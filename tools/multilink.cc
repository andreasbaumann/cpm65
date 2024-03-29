/* CP/M-65 Copyright © 2022 David Given
 * This file is licensed under the terms of the 2-clause BSD license. Please
 * see the COPYING file in the root project directory for the full text.
 */

#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <fmt/format.h>
#include <filesystem>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>

static std::string outfilename;
static std::string corefilename;
static std::string zpfilename;
static std::string memfilename;
static bool verbose = false;

template <typename... T>
void error(fmt::format_string<T...> fmt, T&&... args)
{
    fmt::print(stderr, fmt, args...);
    fputc('\n', stderr);
    exit(1);
}

std::pair<std::vector<uint16_t>, uint8_t> compare(
    const std::string& f1, const std::string& f2)
{
    if (std::filesystem::file_size(f1) != std::filesystem::file_size(f2))
        error("files {} and {} are not the same size!", f1, f2);

    std::vector<uint16_t> results;
    std::ifstream s1(f1);
    std::ifstream s2(f2);

    unsigned pos = 0;
    uint8_t max = 0;
    while (!s1.eof())
    {
        uint8_t b1 = s1.get();
        uint8_t b2 = s2.get();

        if (b1 != b2)
        {
            results.push_back(pos);
            max = std::max(max, b1);
        }
        pos++;
    }

    return std::make_pair(results, max);
}

std::vector<uint8_t> toBytestream(const std::vector<uint16_t>& differences)
{
    std::vector<uint8_t> bytes;
    uint16_t pos = 0;

    for (uint16_t diff : differences)
    {
        uint16_t delta = diff - pos;
        while (delta >= 0xe)
        {
            bytes.push_back(0xe);
            delta -= 0xe;
        }
        bytes.push_back(delta);

        pos = diff;
    }
    bytes.push_back(0xf);

    std::vector<uint8_t> results;
    for (int i = 0; i < bytes.size(); i += 2)
    {
        uint8_t left = bytes[i];
        uint8_t right = ((i + 1) < bytes.size()) ? bytes[i + 1] : 0x00;
        results.push_back((left << 4) | right);
    }
    return results;
}

void emitw(std::ostream& s, uint16_t w)
{
    s.put(w & 0xff);
    s.put(w >> 8);
}

void align(std::ostream& s, uint32_t pow2)
{
    while (s.tellp() & (pow2 - 1))
        s.put(0);
}

unsigned roundup(unsigned value)
{
    return (value + 127) & ~127;
}

static void syntaxError()
{
    fmt::print(stderr,
        "Usage: multilink -o <outfile> <corefile> <zpfile> <memfile>\n");
    exit(1);
}

static void parseArguments(int argc, char* const* argv)
{
    for (;;)
    {
        switch (getopt(argc, argv, "vo:"))
        {
            case -1:
                if (!argv[optind + 0] || !argv[optind + 1] || !argv[optind + 2])
                    syntaxError();

                corefilename = argv[optind + 0];
                zpfilename = argv[optind + 1];
                memfilename = argv[optind + 2];
                return;

            case 'o':
                outfilename = optarg;
                break;

            case 'v':
                verbose = true;
                break;

            default:
                syntaxError();
        }
    }
}

int main(int argc, char* const* argv)
{
    parseArguments(argc, argv);

    if (verbose)
    {
        fmt::print("core file: {}\n", corefilename);
        fmt::print("zp file:   {}\n", zpfilename);
        fmt::print("mem file:  {}\n", memfilename);
    }

    auto coreSize = std::filesystem::file_size(corefilename);

    auto [zpDifferences, zpMax] = compare(corefilename, zpfilename);
    auto zpBytes = toBytestream(zpDifferences);
    auto [memDifferences, memMax] = compare(corefilename, memfilename);
    auto memBytes = toBytestream(memDifferences);

    unsigned reloBytesSize = zpBytes.size() + 1 + memBytes.size();

    std::fstream outs(outfilename,
        std::fstream::in | std::fstream::out | std::fstream::trunc |
            std::fstream::binary);
    if (verbose)
        fmt::print("{} code bytes, {} zprelo bytes, {} memrelo bytes\n",
            coreSize,
            zpBytes.size(),
            memBytes.size());

    /* Write the actual code body. */

    {
        auto memi = memDifferences.begin();
        std::ifstream is(corefilename);
        unsigned pos = 0;
        for (;;)
        {
            int b = is.get();
            if (b == -1)
                break;
            if (pos == *memi)
            {
                b -= 2;
                memi++;
            }
            outs.put(b);
            pos++;
        }
    }

    /* Patch the TPA byte to include the relocation data. */

    {
        outs.seekg(1);
        uint16_t tpaRequired = outs.get();
        uint16_t relOffset = outs.get();
        relOffset |= outs.get() << 8;
        tpaRequired = std::max<uint8_t>(
            tpaRequired, (relOffset + reloBytesSize + 255) / 256);
        outs.seekp(1);
        outs.put(tpaRequired);
        outs.seekp(0, std::fstream::end);
    }

    /* Write the relocation bytes. */

    for (uint8_t b : zpBytes)
        outs.put(b);
    for (uint8_t b : memBytes)
        outs.put(b);

    return 0;
}
