/* Bare-metal CoreMark port: mcycle timing, board UART at 0x60010000.
 * Apache-2.0 (derived from the EEMBC barebones port). */
#include <stdarg.h>
#include "coremark.h"

#ifndef CLK_MHZ
#define CLK_MHZ 50
#endif

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* ---- UART (repository axi-uart) ---- */
struct uart_regs {
    volatile uint32_t rx_fifo, tx_fifo, status, control;
};
#define UART ((struct uart_regs *)0x60010000)

static void kputc(char c) {
    while (UART->status & (1 << 3)) {}
    UART->tx_fifo = (uint8_t)c;
}
void kputs(const char *s) {
    while (*s) kputc(*s++);
    kputc('\r');
    kputc('\n');
}

static void put_num(unsigned long long v, int base, int width, char pad) {
    char buf[24];
    int n = 0;
    do {
        int d = v % base;
        buf[n++] = d < 10 ? '0' + d : 'a' + d - 10;
        v /= base;
    } while (v);
    while (n < width) buf[n++] = pad;
    while (n) kputc(buf[--n]);
}

int ee_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            if (*fmt == '\n') kputc('\r');
            kputc(*fmt);
            continue;
        }
        fmt++;
        char pad = ' ';
        int width = 0, lng = 0;
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        while (*fmt == 'l') { lng++; fmt++; }
        switch (*fmt) {
        case 'd': {
            long long v = lng ? va_arg(ap, long) : va_arg(ap, int);
            if (v < 0) { kputc('-'); v = -v; }
            put_num(v, 10, width, pad);
            break;
        }
        case 'u': put_num(lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned), 10, width, pad); break;
        case 'x': put_num(lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned), 16, width, pad); break;
        case 's': { const char *s = va_arg(ap, const char *); while (*s) kputc(*s++); break; }
        case 'c': kputc((char)va_arg(ap, int)); break;
        case '%': kputc('%'); break;
        default: kputc('?'); break;
        }
    }
    va_end(ap);
    return 0;
}

void report_trap(unsigned long cause, unsigned long epc, unsigned long tval) {
    ee_printf("COREMARK_TRAP mcause=0x%lx mepc=0x%lx mtval=0x%lx\n", cause, epc, tval);
}

/* ---- timing ---- */
static inline uint64_t rdmcycle(void) {
    uint64_t c;
#ifdef SMODE
    asm volatile("rdcycle %0" : "=r"(c));   /* S-mode: cycle (mcounteren.CY) */
#else
    asm volatile("csrr %0, mcycle" : "=r"(c));
#endif
    return c;
}
static CORE_TICKS start_time_val, stop_time_val;
void start_time(void) { start_time_val = rdmcycle(); }
void stop_time(void) { stop_time_val = rdmcycle(); }
CORE_TICKS get_time(void) { return stop_time_val - start_time_val; }
secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)(ticks / ((CORE_TICKS)CLK_MHZ * 1000000u));
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    ee_printf("COREMARK_START core=%s mode=%s iterations=%d\n", CORE_NAME, MODE_NAME, ITERATIONS);
    p->portable_id = 1;
}

void portable_fini(core_portable *p) {
    uint64_t cycles = stop_time_val - start_time_val;
    /* CoreMark/MHz = iterations / (cycles / 1e6), printed with 3 decimals. */
    uint64_t x1000 = (uint64_t)ITERATIONS * 1000000000ull / cycles;
    ee_printf("COREMARK_RESULT core=%s mode=%s iterations=%d cycles=%lu coremark_per_mhz=%lu.%03lu\n",
              CORE_NAME, MODE_NAME, ITERATIONS, (unsigned long)cycles,
              (unsigned long)(x1000 / 1000), (unsigned long)(x1000 % 1000));
    p->portable_id = 0;
}
