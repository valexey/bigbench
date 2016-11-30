#include <algorithm>
#include <fstream>
#include <iterator>
#include <vector>

struct int_t
    {
    std::uint32_t i;
    };

bool operator < (int_t i1, int_t i2){ return i1.i < i2.i; }

std::ostream&
operator << (std::ostream& s, int_t i )
    {
    s.write(reinterpret_cast<char*>(&i.i), sizeof(i.i));
    return s;
    }

std::istream&
operator >> (std::istream& s, int_t& i )
    {
    s.read(reinterpret_cast<char*>(&i.i), sizeof(i.i));
    return s;
    }

char const k_output[] = "output";
char const k_swap[] = "output.temp";

int main()
{
    std::ifstream in("input");
    (std::ofstream(k_output));
    
    std::vector<int_t> block;
    block.reserve(1024 * 1024 * 100 / sizeof(std::uint32_t)); //100Mb 
    while (in)
    {
        int_t i;
        block.clear();
        while (block.size() < block.capacity() && in >> i)
            block.push_back(i);
        std::sort(block.begin(), block.end());

        std::rename(k_output, k_swap);
        std::ofstream out(k_output);
        std::ifstream swap(k_swap);
        std::merge(block.begin(), block.end()
                 , std::istream_iterator<int_t>(swap), std::istream_iterator<int_t>()
                 , std::ostream_iterator<int_t>(out));
    }
}