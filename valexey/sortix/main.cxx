#include <iostream>
#include <thread>
#include <cstdint>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sendfile.h>
#include <fcntl.h>
#include <algorithm>
#include <unistd.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <array>
#include <vector>

const size_t bits_a = 9;
const size_t length_a = (1 << bits_a);       // msb
const size_t length_b = (1 << (32-bits_a));  // lsb

const uint32_t mask_a = ((uint32_t)length_a - 1) << (32-bits_a);
const uint32_t mask_b = (uint32_t)length_b - 1;

using namespace std;
array<uint64_t,length_b> count_b;

int main() 
{
    cout << length_a << endl;
    cout << "hello!\n" << endl;
    int fd = open("./input", /*O_RDONLY*/O_RDWR , 0666);
    int fd_out = open("./output", O_RDWR | O_CREAT | O_TRUNC, 0666);
    struct stat fd_stat;
    fstat(fd, &fd_stat);
    ftruncate(fd_out, fd_stat.st_size);

    int fd_tmp = fd;
    fd = fd_out;

    cout << fd << "!!\n"; cout.flush();

    uint32_t* buf = (uint32_t*)mmap(0, fd_stat.st_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    uint32_t* in  = (uint32_t*)mmap(0, fd_stat.st_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd_tmp, 0);
    size_t len = fd_stat.st_size/sizeof(uint32_t);

	cout << (long)buf <<  "!!!\n"; cout.flush();

    { // pass 0
        array<uint64_t, length_a> count_a;
        fill(count_a.begin(), count_a.end(), 0);
        
        for (size_t i=0; i<len; ++i)
            count_a[ (in[i]&mask_a) >> (32-bits_a) ]++;

        array<uint64_t,length_a> offsets_a;
        fill(offsets_a.begin(), offsets_a.end(), 0);

        for (size_t i=1; i<length_a; ++i)
            offsets_a[i] = offsets_a[i-1]+count_a[i-1];

        // let's write it all to buf
        for (size_t i=0; i<len; ++i)
            buf[ offsets_a[(in[i]&mask_a) >> (32-bits_a)]++ ] = in[i];

        cout << "done\n";

        fill(offsets_a.begin(), offsets_a.end(),0);

        for (size_t i=1; i<length_a; ++i)
            offsets_a[i] = offsets_a[i-1]+count_a[i-1];

        int64_t total = 0;

        for (size_t j=0; j<length_a; j++) { // pass 1
            if (count_a[j]==0) continue;
            //vector<uint64_t> count_b(length_b);
            fill(count_b.begin(), count_b.end(), 0);

            for (uint64_t off=offsets_a[j]; off<offsets_a[j]+count_a[j]; ++off)
                count_b[ (buf[off] & mask_b) ]++;

            uint64_t off = offsets_a[j];

            for (size_t k=0; k<length_b; k++)
                while (count_b[k]!=0) {
                    buf[off] = ((buf[off]&mask_a) + k);
                    off++;
                    count_b[k]--;
                }            
        }        
    }
        
	return 0;
}
