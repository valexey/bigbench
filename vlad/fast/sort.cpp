#include <boost/format.hpp>
#include <boost/ptr_container/ptr_vector.hpp>
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
            return this->it != this->in_buffer.end();;
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

bool
make_swap(std::istream& in, block_t& block, std::string const& name)
    {
    read_block(in, block);
    if (block.empty())
        return false;

    std::sort(block.begin(), block.end());

    std::ofstream out(name, std::ios::out | std::ios::binary);
    write_block(out, block);
    return true;
    }

int const k_max_buffer_size = 1024 * 1024 * 100 / sizeof(block_t::value_type); //100Mb

int
divide(std::istream& in)
    {
    int counter = 0;
    block_t block(k_max_buffer_size); 
    while (make_swap(in, block, swap_name(counter)))
        ++counter;
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