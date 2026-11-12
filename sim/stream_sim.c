/* PC timing simulation of the streaming player (sw/app/stream_play.c).
   NOT TEAM CODE - test scaffolding written by Claude (Swarneel's agent), 12 Nov 2026.

   Runs the real stream_play() against a simulated board:
     UART      bytes arrive at baud/10 bytes per second from t = 0 (header already in)
     ARM       each mp3dec_decode_frame call costs FRAME_US (measured on the board, 12 Nov:
               9338 ms for 20121 frames = 464 us), each FIFO write WRITE_US, each poll POLL_US
     PL FIFO   4096 deep, drains one sample per 48 kHz tick once anything has been written
   After stream_play() returns it keeps looping like pl_play_loop_from() for 3 s of audio.

   Checks:
     1. PCM and DecodeResult_t identical to decode() on the whole file (decode.c)
     2. no FIFO underrun from the first sample until the end of the run (including the wrap
        from the end of the song to the start), no FIFO overflow
   Prints the start-up delay (header -> first sample in the FIFO) and the receive time.

   Usage: build/stream_sim <file.mp3> [baud [claimed_baud]]        (sim/run_stream.sh runs the set) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "decode.h"
#include "stream_play.h"

#define FRAME_US  464.0
#define WRITE_US  0.25
#define POLL_US   0.5
#define FS        48000.0

static double t_us;           /* simulated time */
static double rx_rate;        /* bytes per microsecond */
static uint32_t rx_total;     /* payload + trailer */
static uint32_t level;        /* FIFO fill */
static double tick_next_us;   /* next 48 kHz drain tick */
static int draining;          /* first sample has been written */
static uint64_t underruns, overflows, written, drained;

static void advance(double dt) {
	t_us += dt;
	while (draining && tick_next_us <= t_us) {
		if (level) { level--; drained++; }
		else underruns++;
		tick_next_us += 1e6 / FS;
	}
}

static uint32_t sim_rx_bytes(void) {
	advance(POLL_US);
	double b = t_us * rx_rate;
	return b >= rx_total ? rx_total : (uint32_t)b;
}
static uint32_t sim_fifo_level(void) { advance(POLL_US); return level; }
static void sim_fifo_write(int16_t s) {
	(void)s;
	advance(WRITE_US);
	if (!draining) { draining = 1; tick_next_us = t_us + 1e6 / FS; }
	if (level >= STREAM_FIFO_DEPTH) overflows++; else level++;
	written++;
}
static uint32_t sim_now_us(void) { return (uint32_t)(uint64_t)t_us; }
static void sim_frame_cost(void) { advance(FRAME_US); }

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage: %s file.mp3 [baud]\n", argv[0]); return 2; }
	uint32_t baud = argc > 2 ? (uint32_t)atoi(argv[2]) : 230400u;
	/* rate stream_play() is told; a wrong one must make the check fail (negative control) */
	uint32_t claimed = argc > 3 ? (uint32_t)atoi(argv[3]) : baud;
	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror(argv[1]); return 2; }
	fseek(f, 0, SEEK_END);
	uint32_t len = (uint32_t)ftell(f);
	fseek(f, 0, SEEK_SET);
	uint8_t *buf = malloc(len + 4);
	if (fread(buf, 1, len, f) != len) { fprintf(stderr, "read error\n"); return 2; }
	fclose(f);
	memset(buf + len, 0, 4);

	size_t cap = (size_t)len * 48 + 1152 * 2;
	int16_t *ref = malloc(cap * 2), *pcm = malloc(cap * 2);
	DecodeResult_t rres;
	if (decode(buf, len, ref, cap, &rres) != SIG_DECODE_OK) { fprintf(stderr, "decode failed\n"); return 2; }

	rx_rate = (double)baud / 10.0 / 1e6;
	rx_total = len + 4;
	stream_io_t io = { sim_rx_bytes, sim_fifo_level, sim_fifo_write, sim_now_us, sim_frame_cost };
	stream_result_t sr;
	int st = stream_play(&io, buf, len, pcm, cap, claimed / 10u, 5000u, &sr);
	double rx_done_s = t_us / 1e6;

	/* pl_play_loop_from(): keep the FIFO topped up, wrapping at the end, for 3 s of audio */
	uint32_t n = (uint32_t)sr.res.samples_per_channel, i = sr.play_pos;
	double t_end = t_us + 3e6;
	int playable = (sr.res.sample_rate == 48000 && sr.res.channel_count == 1);
	if (playable && n) {
		while (t_us < t_end) {
			uint32_t room = STREAM_FIFO_DEPTH - sim_fifo_level();
			while (room--) { sim_fifo_write(pcm[i]); if (++i == n) i = 0; }
		}
	}

	int same_res = rres.checksum == sr.res.checksum && rres.frame_count == sr.res.frame_count &&
		rres.samples_per_channel == sr.res.samples_per_channel &&
		rres.sample_rate == sr.res.sample_rate && rres.channel_count == sr.res.channel_count &&
		rres.bitrate == sr.res.bitrate;
	int same_pcm = memcmp(ref, pcm, rres.samples_per_channel * rres.channel_count * 2) == 0;
	double song_s = rres.samples_per_channel / (double)(rres.sample_rate ? rres.sample_rate : 1);
	int pass = st == STREAM_OK && same_res && same_pcm && underruns == 0 && overflows == 0 &&
		(playable ? sr.first_audio_us > 0 : written == 0);

	printf("%-40s %6u baud %4u kbit/s %6.1f s song | first audio %6.2f s (was %6.1f s) | "
	       "rx done %6.1f s | underruns %llu overflows %llu | pcm %s res %s | %s\n",
	       strrchr(argv[1], '/') ? strrchr(argv[1], '/') + 1 : argv[1], baud,
	       (unsigned)rres.bitrate, song_s, sr.first_audio_us / 1e6,
	       (len + 12) / (baud / 10.0) + song_s / 51.0, rx_done_s,
	       (unsigned long long)underruns, (unsigned long long)overflows,
	       same_pcm ? "same" : "DIFF", same_res ? "same" : "DIFF", pass ? "PASS" : "FAIL");
	return pass ? 0 : 1;
}
