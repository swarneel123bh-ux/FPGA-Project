/* Feed decoded PCM to the PL music FIFO (rtl/music_fifo_axi.v) over AXI GP0.
   Written by Claude (Swarneel's agent), 11 Nov 2026, at Swarneel's request. Not team code.
   Board build only (BOARD defined). */
#ifndef PL_FEED_H
#define PL_FEED_H

#include <stdint.h>

/* Must match scripts/enh_bd.tcl (assign_bd_address) and rtl/music_fifo_axi.v */
#define PL_FIFO_BASE    0x43C00000u
#define PL_FIFO_DATA    0x0u   /* write: sample, s24 in bits 23:0 */
#define PL_FIFO_LEVEL   0x4u   /* read: samples stored (0..4096) */
#define PL_FIFO_STATUS  0x8u   /* read: bit 1 overflow (sticky), bit 0 full */
#define PL_FIFO_DEPTH   4096u

/* Play n mono 48 kHz samples through the PL, then start again from the beginning, forever.
   The PL drains one sample per 48 kHz tick; this keeps the FIFO topped up. */
void pl_play_loop(const int16_t *pcm, uint32_t n);

/* Same, starting at sample `start` (streaming playback has already played up to there). */
void pl_play_loop_from(const int16_t *pcm, uint32_t n, uint32_t start);

/* Board io for stream_play() (sw/app/stream_play.h): UART progress, FIFO level/write, timer. */
#include "stream_play.h"
extern const stream_io_t pl_stream_io;

#endif
