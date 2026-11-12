/* Decode the MP3 while it is still arriving over the UART and start playing before the end.
   Written by Claude (Swarneel's agent), 12 Nov 2026, at Swarneel's request. Not team code.

   Portable C (no Xilinx headers), so the same file runs on the board (io from pl_feed.c) and in
   the PC timing simulation (sim/stream_sim.c, io from a simulated clock).

   Frame loop: same bookkeeping as decode() in decode.c (checksum, frame count, bitrate), so the
   result and the PCM are identical to decoding the whole buffer at once. A frame is decoded
   only when STREAM_LOOKAHEAD bytes past it have arrived (or the whole file is in), so
   minimp3 always sees as much data as the batch decode would (its first-frame sync looks up to
   10 frames ahead: 10 x 1441 bytes at 320 kbit/s). */
#ifndef STREAM_PLAY_H
#define STREAM_PLAY_H

#include <stdint.h>
#include <stddef.h>
#include "decode.h"

#define STREAM_LOOKAHEAD   16384u   /* bytes; 0.7 s of UART at 230,400 baud */
#define STREAM_MIN_START   4800u    /* decoded samples (0.1 s) before the FIFO is fed */
#define STREAM_FIFO_DEPTH  4096u    /* rtl/music_fifo_axi.v */

typedef struct {
	uint32_t (*rx_bytes)(void);        /* bytes of payload + trailer received so far */
	uint32_t (*fifo_level)(void);      /* samples in the PL FIFO */
	void     (*fifo_write)(int16_t s); /* push one sample */
	uint32_t (*now_us)(void);          /* free-running microseconds (wraps; differences only) */
	void     (*frame_cost)(void);      /* sim only: charge one frame's decode time; NULL on board */
} stream_io_t;

#define STREAM_OK          0
#define STREAM_RX_TIMEOUT  1
#define STREAM_PCM_FULL    2

typedef struct {
	DecodeResult_t res;
	uint32_t play_pos;        /* next sample to write to the FIFO (continue from here) */
	uint32_t first_audio_us;  /* time from the call to the first FIFO write */
	uint32_t decode_us;       /* time spent inside mp3dec_decode_frame */
	uint32_t rx_bytes;        /* bytes received when it returned */
} stream_result_t;

/* buf: receive buffer the UART is filling (len payload bytes, then the 4-byte trailer).
   rx_bytes_per_s: expected UART rate (230400 baud -> 23040), used to decide when playback can
   start without running out. Returns once the file is fully received and decoded; playback is
   kept going all along and continues from out->play_pos (pl_play_loop_from). */
int stream_play(const stream_io_t *io, const uint8_t *buf, uint32_t len,
	int16_t *pcm, size_t pcm_cap, uint32_t rx_bytes_per_s, uint32_t timeout_ms,
	stream_result_t *out);

#endif
