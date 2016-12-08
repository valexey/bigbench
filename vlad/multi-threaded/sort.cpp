#include <boost/format.hpp>
#include <boost/ptr_container/ptr_vector.hpp>
#include <boost/thread/thread.hpp>

#include <algorithm>
#include <fstream>
#include <vector>

typedef std::vector<std::uint32_t> block_t;

void
write_block(std::ostream& out, block_t::const_iterator from, block_t::const_iterator to)
    {
    if (from != to)
        out.write(reinterpret_cast<char const*>(&*from), (to - from) * sizeof(block_t::value_type));
    }

void
write_block(std::ostream& out, block_t const& b)
    {
    write_block(out, b.begin(), b.end());
    }

void
read_block(std::istream& in, block_t& b)
    {
    in.read(reinterpret_cast<char*>(&b[0]), b.size() * sizeof(block_t::value_type));
    b.resize(in.gcount() / sizeof(block_t::value_type));
    }

class swap_t
    {
    public:
        swap_t(std::string const& name, int buffer_size)
            : name(name)
            , in(name, std::ios::in | std::ios::binary)
            , in_buffer(buffer_size)
            {
            this->bufferize();
            }

        std::uint32_t get() const { return *this->it; }
        
        bool next() 
            { 
            if (++this->it != this->in_buffer.end())
                return true;
            
            this->bufferize();
            return this->it != this->in_buffer.end();
            }
        
        void copy_to(std::ostream& os) 
            { 
            write_block(os, this->it, this->in_buffer.end());
            os << this->in.rdbuf(); 
            }
    public:
        std::string const name;
    private:
        void bufferize()
            {
            read_block(this->in, this->in_buffer);
            this->it = this->in_buffer.begin();
            }
    private:
        std::ifstream in;
        block_t in_buffer;
        block_t::const_iterator it;
    };

typedef boost::ptr_vector<swap_t> swaps_t;

std::string
swap_name(int i)
    {
    return str(boost::format("swap.%1%") % i);
    }

int const k_max_buffer_size = 1024 * 1024 * 50 / sizeof(block_t::value_type); //50Mb
int const k_sorting_threads_count = 2;
int const k_sorting_block_size = k_max_buffer_size / (k_sorting_threads_count + 1);

struct n_block_t : block_t
    {
    n_block_t(int i)
        : block_t(k_sorting_block_size)
        , i(i)
        {
        }

    int i;
    };

class queue_t
    {
    public:
        queue_t();

        bool empty() const;
        void push(std::unique_ptr<n_block_t>);
        std::unique_ptr<n_block_t> pop();
        void close();
    private:
        mutable boost::condition_variable cond;
        mutable boost::mutex mutex;
        boost::ptr_vector<n_block_t> blocks;
        bool closed;
    };

queue_t::queue_t()
    : closed(false)
    {
    }

bool 
queue_t::empty() const
    {
    boost::unique_lock<boost::mutex> lock(this->mutex);
    return this->blocks.empty();
    }

void
queue_t::push(std::unique_ptr<n_block_t> b)
    {
    boost::unique_lock<boost::mutex> lock(this->mutex);
    while (this->blocks.size() == k_sorting_threads_count)
        this->cond.wait(lock);

    this->blocks.push_back(b.release());
    this->cond.notify_one();
    }

std::unique_ptr<n_block_t> 
queue_t::pop()
    {
    boost::unique_lock<boost::mutex> lock(this->mutex);
    while (this->blocks.empty() && !this->closed)
        this->cond.wait(lock);

    if (this->blocks.empty())
        return std::unique_ptr<n_block_t>();
    
    auto result = this->blocks.pop_back();
    this->cond.notify_one();
    return std::unique_ptr<n_block_t>(result.release());
    }

void
queue_t::close()
    {
    boost::unique_lock<boost::mutex> lock(this->mutex);
    this->closed = true;
    this->cond.notify_all();
    }

class sort_threads_t
    {
    public:
        sort_threads_t(queue_t& sort, queue_t& write);
        ~sort_threads_t();
    private:
        void run();
    private:
        queue_t& sort_queue;
        queue_t& write_queue;
        boost::thread threads[k_sorting_threads_count];
        mutable boost::mutex mutex;
        int finished_count;
    };

sort_threads_t::sort_threads_t(queue_t& sort, queue_t& write)
    : sort_queue(sort)
    , write_queue(write)
    , finished_count(0)
    {
    for(auto &t: this->threads)
        t = boost::thread([this](){this->run();});
    }

sort_threads_t::~sort_threads_t()
    {
    for(auto &t: this->threads)
        t.join();
    }

void
sort_threads_t::run()
    {
    while (auto b = this->sort_queue.pop())
        {
        std::sort(b->begin(), b->end());
        this->write_queue.push(std::move(b));
        }

    boost::unique_lock<boost::mutex> lock(this->mutex);
    if (++this->finished_count == k_sorting_threads_count)
        this->write_queue.close();
    }

bool
write_block(n_block_t const& block)
    {
    std::ofstream out(swap_name(block.i), std::ios::out | std::ios::binary);
    write_block(out, block);
    return true;
    }

bool
make_swap(std::istream& in, queue_t& sort_queue, int i)
    {
    std::unique_ptr<n_block_t> block(new n_block_t(i));
    read_block(in, *block);
    if (block->empty())
        return false;

    sort_queue.push(std::move(block));
    return true;
    }

int
divide(std::istream& in)
    {
    int counter = 0;
    queue_t write_queue; 
        {
        queue_t sort_queue;
        sort_threads_t sort_threads(sort_queue, write_queue);
        while (make_swap(in, sort_queue, counter))
            {
            while (!write_queue.empty())
                if (auto block = write_queue.pop())
                    write_block(*block);

            ++counter;
            }

        sort_queue.close();
        while (auto block = write_queue.pop())
            write_block(*block);
        }

    return counter;
    }

void merge(int count, std::ostream& out)
    {
    if (!count)
        return;

    // make sure to not exceed memory limit even in case of memory fragmentation 
    // - divide calculated ideal size by 10
    int const buffer_size = k_max_buffer_size / count / 10; 

    swaps_t swaps;
    std::vector<std::uint32_t> swap_heads;
    for(int i = 0; i < count; ++i)
        {
        swaps.push_back(new swap_t(swap_name(i), buffer_size));
        swap_heads.push_back(swaps.back().get());
        }

    block_t out_buffer;
    out_buffer.reserve(buffer_size);

    while (swaps.size() > 1)
        {
        auto it = std::min_element(swap_heads.begin(), swap_heads.end());
        out_buffer.push_back(*it);
        if (out_buffer.size() == out_buffer.capacity())
            {
            write_block(out, out_buffer);
            out_buffer.clear();
            }

        auto swap_it = swaps.begin() + (it - swap_heads.begin());
        if (swap_it->next())
            *it = swap_it->get();
        else
            {
            swaps.erase(swap_it);
            swap_heads.erase(it);
            }
        }
    
    write_block(out, out_buffer);
    swaps.front().copy_to(out);
    }

int main()
    {
    char const k_output[] = "output";
    std::ifstream in("input", std::ios::in | std::ios::binary);
    
    auto swaps = divide(in);
    if (swaps == 1) // optimize the case when the input was fit in a single swap
        std::rename(swap_name(0).c_str(), k_output);
    else
        {
        std::ofstream out(k_output, std::ios::out | std::ios::binary);
        merge(swaps, out);
        }
    }