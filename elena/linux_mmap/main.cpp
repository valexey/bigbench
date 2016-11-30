#include <iostream>
#include <algorithm>
#include <fcntl.h> 
#include <sys/mman.h>
#include <sys/stat.h>
#include <cstdio>
#include <cstring>
#include <unistd.h>

int main() {

    int input, output;
    uint32_t *src, *dst;

    // open files
    input = open("input", O_RDONLY, 0666);
    if (input < 0) {
        std::cout << "Unable to open input file" << std::endl;
    }
    output = open("output", O_RDWR | O_CREAT | O_TRUNC, 0666);
    if (output < 0) {
        std::cout << "Unable to open output file" << std::endl;
    }

    // calc input size and set output size
    struct stat buff;
    fstat(input, &buff);
    lseek(output, buff.st_size - 1, SEEK_SET);
    if (write(output, "", 1) != 1)
        std::cout << "Function 'write' return error" << std::endl;

    // copy file
    src = (uint32_t*)mmap(0, buff.st_size, PROT_READ, MAP_SHARED, input, 0);
    if (src == MAP_FAILED ) 
        std::cout << "Mmap error for input file" << std::endl;
    dst = (uint32_t*)mmap(0, buff.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, output, 0);
    if (dst == MAP_FAILED ) 
        std::cout << "Mmap error for output file" << std::endl; 
    memcpy(dst, src, buff.st_size);

    // sort
    std::sort(dst, dst + buff.st_size/sizeof(uint32_t));

    return 0;
}
