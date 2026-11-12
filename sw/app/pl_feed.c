/* Feed decoded PCM to the PL music FIFO. See pl_feed.h.
   Written by Claude (Swarneel's agent), 11 Nov 2026, at Swarneel's request. Not team code.
   12 Nov: pl_play_loop_from() and the stream_play() io (streaming playback). */
#ifdef BOARD
#include "pl_feed.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "uart_rx.h"
#ifdef SDT
	#include "xiltimer.h"
#else
	#include "xtime_l.h"
#endif

/* int16 -> s24 as the plan fixes it: sample << 8 (multiply, to avoid shifting a negative). */
static inline uint32_t to_s24(int16_t s) {
	return ((uint32_t)((int32_t)s * 256)) & 0x00FFFFFFu;
}

void pl_play_loop(const int16_t *pcm, uint32_t n) {
	pl_play_loop_from(pcm, n, 0);
}

void pl_play_loop_from(const int16_t *pcm, uint32_t n, uint32_t start) {
	uint32_t i = start, pass = 0;

	if (n == 0) return;
	if (i >= n) i = 0;
	xil_printf("play: %d samples (%d ms) to the PL FIFO at 0x%08x, looping\r\n",
		(int)n, (int)(n / 48), PL_FIFO_BASE);
	xil_printf("SW0 up = enhanced, down = plain; SW1 up = test tone\r\n");

	for (;;) {
		uint32_t level = Xil_In32(PL_FIFO_BASE + PL_FIFO_LEVEL) & 0x1FFFu;
		uint32_t room = (level < PL_FIFO_DEPTH) ? PL_FIFO_DEPTH - level : 0;

		while (room--) {
			Xil_Out32(PL_FIFO_BASE + PL_FIFO_DATA, to_s24(pcm[i]));
			if (++i == n) {
				i = 0;
				pass++;
				xil_printf("play: pass %d done, overflow flag %d\r\n", (int)pass,
					(int)((Xil_In32(PL_FIFO_BASE + PL_FIFO_STATUS) >> 1) & 1u));
			}
		}
	}
}

/* [12 Nov] io for stream_play() */
static uint32_t io_rx_bytes(void) { return uart_rx_progress(); }
static uint32_t io_fifo_level(void) { return Xil_In32(PL_FIFO_BASE + PL_FIFO_LEVEL) & 0x1FFFu; }
static void io_fifo_write(int16_t s) { Xil_Out32(PL_FIFO_BASE + PL_FIFO_DATA, to_s24(s)); }
static uint32_t io_now_us(void) {
	XTime t;
	XTime_GetTime(&t);
	return (uint32_t)(t / (COUNTS_PER_SECOND / 1000000u));
}
const stream_io_t pl_stream_io = { io_rx_bytes, io_fifo_level, io_fifo_write, io_now_us, NULL };
#endif
