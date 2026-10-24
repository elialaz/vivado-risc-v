#include <common.h>
#include <dm.h>
#include <cpu_func.h>
#include <fdtdec.h>
#include <asm/global_data.h>

DECLARE_GLOBAL_DATA_PTR;

/*
 * Cache maintenance for non-coherent DMA (SD, Ethernet) on native SoCs that
 * cache DDR, e.g. CVA6 with HPDcache. Enabled only when the CPU node carries
 * riscv,cbom-block-size; coherent Rocket/BOOM/NOEL-V systems are unaffected.
 * Raw Zicbom encodings (a0): cbo.flush = 0x0025200f, cbo.inval = 0x0005200f.
 */
static unsigned long cbom_block_size;

static void cbom_op(unsigned long start, unsigned long end, int inval) {
    unsigned long p;
    if (!cbom_block_size) return;
    asm volatile ("fence rw, rw" ::: "memory");
    for (p = start & ~(cbom_block_size - 1); p < end; p += cbom_block_size) {
        if (inval)
            asm volatile ("mv a0, %0; .word 0x0005200f" :: "r"(p) : "a0", "memory");
        else
            asm volatile ("mv a0, %0; .word 0x0025200f" :: "r"(p) : "a0", "memory");
    }
    asm volatile ("fence rw, rw" ::: "memory");
}

void flush_dcache_range(unsigned long start, unsigned long end) {
    cbom_op(start, end, 0);
}

void invalidate_dcache_range(unsigned long start, unsigned long end) {
    cbom_op(start, end, 1);
}

#ifdef CONFIG_MISC_INIT_R

int misc_init_r(void) {
    /* For now nothing to do here. */
    return 0;
}

#endif

void * board_fdt_blob_setup(int * err) {
    /* OpenSBI passes the backend-specific DTB in a1.  Keep the historical
     * address only as a fallback for direct/legacy entry paths. */
    void * fdt_blob = (void *)(uintptr_t)gd->arch.firmware_fdt_addr;
    if (fdt_blob == NULL) fdt_blob = (void *)0x00010080;

    *err = 0;
    if (fdt_magic(fdt_blob) == FDT_MAGIC) return fdt_blob;

    *err = -EINVAL;
    return NULL;
}

int board_init(void) {
    int cpus = fdt_path_offset(gd->fdt_blob, "/cpus");
    int cpu = cpus < 0 ? cpus : fdt_first_subnode(gd->fdt_blob, cpus);
    while (cpu >= 0) {
        unsigned long size = fdtdec_get_uint(gd->fdt_blob, cpu, "riscv,cbom-block-size", 0);
        if (size && (size & (size - 1)) == 0) {
            cbom_block_size = size;
            break;
        }
        cpu = fdt_next_subnode(gd->fdt_blob, cpu);
    }
    return 0;
}
