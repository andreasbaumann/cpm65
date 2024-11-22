/* mkfs © 2019 David Given
 * This program is distributable under the terms of the 2-clause BSD license.
 * See COPYING.cpmish in the distribution root directory for more information.
 */

#include <cpm.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

static DPH* dph;
static DPB* dpb;
static uint16_t spt;
static uint16_t reservedsectors;
static uint16_t directoryblocks;
static uint16_t blocksize;
static uint16_t blockcount;

static void print(const char* s) 
{
    for (;;)
    {
        uint8_t b = *s++;
        if (!b)
            return;
        cpm_conout(b);
    }
}

static void crlf(void)
{
    print("\r\n");
}

static void printx(const char* s) 
{
    print(s);
    crlf();
}

void printhex4(uint8_t nibble)
{
	nibble &= 0x0f;
    if (nibble < 10)
        nibble += '0';
    else
        nibble += 'a' - 10;
    cpm_conout(nibble);
}

void printhex8(uint8_t b)
{
    printhex4(b >> 4);
    printhex4(b);
}

void printhex16(uint16_t n)
{
    printhex8(n >> 8);
    printhex8(n);
}

/* 
 * Prints a 32-bit decimal number with optional left padding and configurable
 * precision. *.
 */
void printip(uint32_t v, bool pad, uint32_t precision)
{
    bool zerosup = true;
    while (precision)
    {
        uint8_t d = v / precision;
        v %= precision;
        precision /= 10;
        if (precision && zerosup && !d)
        {
            if (pad)
                cpm_conout(' ');
        }
        else
        {
            zerosup = false;
            cpm_conout('0' + d);
        }
    }
}

void printi(uint32_t v)
{
    printip(v, false, 1000000000LU);
}

void fatal(const char* s) 
{
    print("Error: ");
	printx(s);
	cpm_warmboot();
}

void main(void)
{
    if (!cpm_fcb.dr || (cpm_fcb.f[0] != ' '))
        fatal("syntax: mkfs <drive>");

    dph = cpm_bios_seldsk(cpm_fcb.dr - 1);
    if (!dph)
        fatal("that drive does not exist");
    dpb = (DPB*) dph->dpb;
    blocksize = 1<<(dpb->bsh+7);
    blockcount = dpb->dsm + 1;
    reservedsectors = dpb->off;
    directoryblocks = (dpb->drm+1) * 32 / blocksize;

    print("Drive ");
    cpm_conout(cpm_fcb.dr + '@');
    printx(":");
    print("  Number of reserved sectors: ");
    printi(reservedsectors);
    crlf();
    print("  Number of directory blocks: ");
    printi(directoryblocks);
    crlf();
    print("  Size of block:              ");
    printi(blocksize);
    printx(" bytes");
    print("  Number of blocks:           ");
    printi(blockcount);
    crlf();
    print("  Total disk size:            ");
    printi((uint32_t)blockcount * (uint32_t)blocksize/1024 + reservedsectors/8);
    printx(" kB");
    crlf();

    print("About to create a filesystem on drive ");
    cpm_conout(cpm_fcb.dr + '@');
    printx(",\ndestroying everything on it.");
    print("Press Y to proceed, anything else to cancel: ");
    if (cpm_conin() != 'y')
        fatal("Aborted.");

    printx("\nFormatting now...");

    cpm_bios_setdma(cpm_default_dma);
    memset(cpm_default_dma, 0xe5, 128);

    {
        uint32_t sector = reservedsectors;

        while (directoryblocks--)
        {
            uint8_t i;
            for (i=0; i<blocksize/128; i++)
            {
                cpm_bios_setsec(&sector);
                if (cpm_bios_write(0))
                    fatal("Disk error");

                sector++;
            }
        }

        /* Rewrite the last sector and force it to be flushed to disk. */

        cpm_bios_write(1);
    }

    printx("Done.");
}
