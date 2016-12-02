#include <boost/format.hpp>
#include <boost/iterator/transform_iterator.hpp>
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

int const k_io_buffer_size = 1024 * 256 / sizeof(block_t::value_type); // 256kb

class swap_t
    {
    public:
        swap_t(std::string const& name)
            : name(name)
            , in(name, std::ios::in | std::ios::binary)
            , in_buffer(k_io_buffer_size)
            {
            this->bufferize();
            }

        std::uint32_t get() const { return *this->it; }
        
        bool eof() const { return this->it == this->in_buffer.end(); }
        
        void next() 
            { 
            if (++this->it == this->in_buffer.end())
                this->bufferize();
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

std::uint32_t swap_get(swap_t const& s){ return s.get(); }

bool swap_eof(swap_t const& s){return s.eof();}

typedef boost::ptr_vector<swap_t> swaps_t;

std::auto_ptr<swap_t>
make_swap(std::istream& in, block_t& block, int counter)
    {
    read_block(in, block);
    std::sort(block.begin(), block.end());

    auto name = str(boost::format("swap.%1%") % counter);
        {
        std::ofstream out(name, std::ios::out | std::ios::binary);
        write_block(out, block);
        }
    return std::auto_ptr<swap_t>(new swap_t(name));
    }

void merge(swaps_t& swaps, std::ostream& out)
    {
    swaps.erase_if(&swap_eof);
    
    if (swaps.empty())
        return;

    block_t out_buffer;
    out_buffer.reserve(k_io_buffer_size);
    while (swaps.size() > 1)
        {
        auto min_it = std::min_element(boost::make_transform_iterator(swaps.begin(), &swap_get)
                                     , boost::make_transform_iterator(swaps.end(), &swap_get));
        out_buffer.push_back(*min_it);
        if (out_buffer.size() == out_buffer.capacity())
            {
            write_block(out, out_buffer);
            out_buffer.clear();
            }

        auto it = min_it.base();
        it->next();
        if (it->eof())
            swaps.erase(it);
        }
    
    write_block(out, out_buffer);
    swaps.front().copy_to(out);
    }

int main()
    {
    char const k_output[] = "output";
    std::ifstream in("input", std::ios::in | std::ios::binary);
    
    block_t block(1024 * 1024 * 100 / sizeof(block_t::value_type)); //100Mb 
    swaps_t swaps;
    while (in)
        swaps.push_back(make_swap(in, block, swaps.size()));

    if (swaps.size() == 1) // optimize the case when the input was fit in a single swap
        std::rename(swaps.front().name.c_str(), k_output);
    else
        {
        std::ofstream out(k_output, std::ios::out | std::ios::binary);
        merge(swaps, out);
        }
    }