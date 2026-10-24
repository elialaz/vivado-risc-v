// Repository-owned CVA6 first-stage loader for the common vivado-risc-v SD
// image. It uses CVA6's native AXI Quad SPI and UART drivers, while FatFs and
// the BOOT.ELF convention are shared with the other repository backends.

#include <stdint.h>
#include <stddef.h>

#include "ff.h"
#include "diskio.h"
#include "sd.h"
#include "uart.h"

#define PT_LOAD 1
#define BOOT_ENTRY 0x80000000UL
#define LOADER_RAM_START 0x80000000UL
#define LOADER_RAM_END   0x80002000UL
#define LOADER_RAM_ALT   0x83f00000UL

extern unsigned char _BSS_START_[];
extern unsigned char _BSS_END_[];

static FATFS fatfs;
static FIL file;
static DSTATUS disk_state;
static FRESULT file_error;

static void puts_uart(const char *text)
{
    print_uart(text);
    print_uart("\r\n");
}

static void clear_bss(void)
{
    for (unsigned char *p = _BSS_START_; p < _BSS_END_; ++p) {
        *p = 0;
    }
}

DSTATUS disk_status(BYTE drive)
{
    (void)drive;
    return disk_state;
}

DSTATUS disk_initialize(BYTE drive)
{
    (void)drive;
    if (init_sd() == 0) {
        disk_state = 0;
    }
    return disk_state;
}

DRESULT disk_read(BYTE drive, BYTE *buffer, LBA_t sector, UINT count)
{
    (void)drive;
    if (disk_state & STA_NOINIT) {
        return RES_NOTRDY;
    }
    if (count == 0 || sd_copy(buffer, (uint32_t)sector, count) != 0) {
        return RES_ERROR;
    }
    return RES_OK;
}

static uintptr_t read_number(unsigned size)
{
    uint8_t bytes[8];
    uintptr_t value = 0;
    UINT read_count = 0;

    file_error = f_read(&file, bytes, size, &read_count);
    if (file_error != FR_OK || read_count != size) {
        return 0;
    }
    for (unsigned i = 0; i < size; ++i) {
        value |= (uintptr_t)bytes[i] << (i * 8);
    }
    return value;
}

static void *load_destination(uintptr_t address, UINT *size)
{
    if (address >= LOADER_RAM_START && address < LOADER_RAM_END) {
        if (*size > LOADER_RAM_END - address) {
            *size = (UINT)(LOADER_RAM_END - address);
        }
        return (void *)(LOADER_RAM_ALT + address - LOADER_RAM_START);
    }
    return (void *)address;
}

static int load_boot_elf(void)
{
    uint8_t ident[6];
    UINT read_count = 0;

    file_error = f_open(&file, "BOOT.ELF", FA_READ);
    if (file_error != FR_OK) {
        return -1;
    }
    file_error = f_read(&file, ident, sizeof(ident), &read_count);
    if (file_error != FR_OK || read_count != sizeof(ident) ||
        ident[0] != 0x7f || ident[1] != 'E' || ident[2] != 'L' ||
        ident[3] != 'F' || ident[4] != 2 || ident[5] != 1) {
        return -2;
    }

    file_error = f_lseek(&file, 24);
    uintptr_t entry = read_number(8);
    uintptr_t phoff = read_number(8);
    if (file_error != FR_OK || entry != BOOT_ENTRY) {
        return -3;
    }

    file_error = f_lseek(&file, 54);
    uint16_t phentsize = (uint16_t)read_number(2);
    uint16_t phnum = (uint16_t)read_number(2);
    if (file_error != FR_OK) {
        return -4;
    }

    for (uint16_t i = 0; i < phnum; ++i) {
        file_error = f_lseek(&file, phoff + (uintptr_t)i * phentsize);
        uint32_t type = (uint32_t)read_number(4);
        if (file_error != FR_OK) {
            return -5;
        }
        if (type != PT_LOAD) {
            continue;
        }

        file_error = f_lseek(&file, f_tell(&file) + 4);
        uintptr_t offset = read_number(8);
        uintptr_t vaddr = read_number(8);
        (void)read_number(8); // physical address
        uintptr_t filesz = read_number(8);
        uintptr_t memsz = read_number(8);
        if (file_error != FR_OK || filesz > memsz) {
            return -6;
        }

        file_error = f_lseek(&file, offset);
        uintptr_t done = 0;
        while (done < filesz) {
            UINT chunk = (filesz - done > 0x10000) ? 0x10000 : (UINT)(filesz - done);
            void *destination = load_destination(vaddr + done, &chunk);
            file_error = f_read(&file, destination, chunk, &read_count);
            if (file_error != FR_OK || read_count != chunk) {
                return -7;
            }
            done += chunk;
        }
        while (done < memsz) {
            UINT chunk = (memsz - done > 0x10000) ? 0x10000 : (UINT)(memsz - done);
            volatile uint8_t *destination = load_destination(vaddr + done, &chunk);
            for (UINT j = 0; j < chunk; ++j) {
                destination[j] = 0;
            }
            done += chunk;
        }
    }

    file_error = f_close(&file);
    if (file_error != FR_OK) {
        return -8;
    }

    // The loader's BSS occupies the first 8 KiB of DDR while it runs. The
    // corresponding payload bytes were staged near the top of the first
    // 64 MiB and are committed only after FatFs no longer needs its state.
    volatile uint64_t *destination = (volatile uint64_t *)LOADER_RAM_START;
    const uint64_t *source = (const uint64_t *)LOADER_RAM_ALT;
    while (destination < (volatile uint64_t *)LOADER_RAM_END) {
        *destination++ = *source++;
    }
    __asm__ volatile ("fence rw, rw; fence.i" ::: "memory");
    return 0;
}

int main(void)
{
    clear_bss();
    disk_state = STA_NOINIT;
    init_uart(50000000, 115200);
    puts_uart("CVA6 native Boot ROM");
    puts_uart("Loading BOOT.ELF from FAT SD image");

    file_error = f_mount(&fatfs, "", 1);
    if (file_error != FR_OK) {
        puts_uart("FAT mount failed");
        return -1;
    }
    if (load_boot_elf() != 0) {
        puts_uart("BOOT.ELF load failed");
        return -1;
    }
    puts_uart("BOOT.ELF loaded; starting OpenSBI");
    return 0;
}
