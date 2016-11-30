#include <fstream>
#include <iostream>
#include <algorithm>
#include <iterator>
#include <vector>
#include <cstdint>
#include <string>
#include <queue>
#include <map>

const unsigned int chunk_size = 28*1024*1024;
//const unsigned int chunk_size = 2;

void sort_chunk(std::vector<uint32_t> *chunk) {
    std::sort(chunk->begin(), chunk->end());
    return;
}

int merge_files(
    std::fstream *temp1, 
    std::fstream *temp2, 
    std::fstream *output, 
    const unsigned long long in1,
    const unsigned long long len1,
    const unsigned long long in2,
    const unsigned long long len2) 
{
    if (!temp1->is_open())
        return 1;
    if (!temp2->is_open())
        return 1;
    if (!output->is_open())
        return 1;

    uint32_t t1, t2;
    unsigned long long i1 = 0, i2 = 0, n3 = 0, i = 0;
    const size_t size = sizeof(uint32_t);
    temp1->seekg(in1);
    temp2->seekg(in2);
    output->seekp(0);
    temp1->read((char*)&t1, size);
    temp2->read((char*)&t2, size);

    bool t1_good = temp1->good();
    bool t2_good = temp2->good();
    while ((temp1->good() && i1 < len1) || (temp2->good() && i2 < len2)) {
        if ((!temp2->good() || i2 >= len2) || (temp1->good() && i1 < len1 && t1 < t2)) {
            output->write((char*)&t1, size);
            i1++;
            temp1->read((char*)&t1, size);
            n3++;
        }
        else {
            output->write((char*)&t2, size);
            i2++;
            temp2->read((char*)&t2, size);
            n3++;
        }
        t1_good = temp1->good();
        t2_good = temp2->good();
    }

    temp1->clear();
    temp2->clear();
    temp1->seekp(in1);
    temp2->seekp(in1);

    output->seekg(0);
    while (output->good() && i < len1 + len2) {
        output->read((char*)&t1, size);
        i++;
        if (output->good()) {
            temp1->write((char*)&t1, size);
            temp2->write((char*)&t1, size);
        }
    }

    return 0;
}

int main() {

    // open file
    std::ifstream input;
    input.open("input", std::ios::binary);
    if (!input.is_open()) {
        return 1;
    }

    // create temp file
    std::fstream temp1("temp1", std::fstream::in | std::fstream::out | std::fstream::trunc | std::ios::binary);
    if (!temp1.is_open()) {
        std::cout << "Unable to create temp file" << std::endl;
        input.close();
        return 1;
    }
    std::fstream temp2("temp2", std::fstream::in | std::fstream::out | std::fstream::trunc | std::ios::binary);
    if (!temp2.is_open()) {
        std::cout << "Unable to create temp file" << std::endl;
        input.close();
        temp1.close();
        return 1;
    }

    // output file
    std::fstream output;
    output.open("output", std::fstream::in | std::fstream::out | std::fstream::trunc | std::ios::binary);
    if (!output.is_open()) {
        std::cout << "Unable to create output file" << std::endl;
        input.close();
        temp1.close();
        temp2.close();
        return 1;
    }

    unsigned long long pos = 0;
    std::map<unsigned long long, unsigned long long> index;

    // read input file
    while (!input.eof()) {
        unsigned int size = 0;

        // read chunk
        std::vector<uint32_t> chunk(chunk_size);
        input.read((char*)&chunk[0], sizeof(uint32_t) * chunk_size);
        if (input.eof()) {
            chunk.resize(input.gcount() / sizeof(uint32_t));
        }

        // check chunk size
        if (0 == chunk.size())
            break;

        // sort chunk
        sort_chunk(&chunk);
        
        // write to temp file
        temp1.seekp(pos);
        temp2.seekp(pos);
        temp1.write((char*)&chunk[0], sizeof(uint32_t) * chunk.size());
        temp2.write((char*)&chunk[0], sizeof(uint32_t) * chunk.size());
        index[pos] = chunk.size();

        // increment pos
        pos += chunk.size() * sizeof(uint32_t);
    }

    // close input file
    input.close();

    // merge
    while (index.size() > 1) {
        for (auto it = index.begin(); it != index.end() && std::next(it) != index.end(); it ++) {
            merge_files(&temp1, &temp2, &output, (*it).first, (*it).second, (*std::next(it)).first, (*std::next(it)).second);
            (*it).second += (*std::next(it)).second;
            index.erase(std::next(it));

        }
    }

    // copy result
    temp1.seekg(0);
    output.seekp(0);
    uint32_t t;
    temp1.read((char*)&t, sizeof(uint32_t));
    while (temp1.good()) {
        output.write((char*)&t, sizeof(uint32_t));
        temp1.read((char*)&t, sizeof(uint32_t));
    }

    // close files
    output.close();
    temp1.close();
    temp2.close();

    return 0;
}