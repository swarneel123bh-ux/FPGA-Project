/* See stream_play.h. Written by Claude (Swarneel's agent), 12 Nov 2026. Not team code. */
#include "stream_play.h"
#include "minimp3.h"   /* declarations only; the implementation is compiled in decode.c */

/* Feed the FIFO up to its depth from pcm[*play .. used). */
static void top_up(const stream_io_t *io, const int16_t *pcm, uint32_t *play, uint32_t used) {
	uint32_t level = io->fifo_level();
	uint32_t room = (level < STREAM_FIFO_DEPTH) ? STREAM_FIFO_DEPTH - level : 0;
	while (room-- && *play < used) {
		io->fifo_write(pcm[(*play)++]);
	}
}

int stream_play(const stream_io_t *io, const uint8_t *buf, uint32_t len,
	int16_t *pcm, size_t pcm_cap, uint32_t rx_bytes_per_s, uint32_t timeout_ms,
	stream_result_t *out)
{
	static mp3dec_t dec;   /* not on the stack (board stack is small) */
	mp3dec_frame_info_t info;
	mp3dec_init(&dec);

	/* decode() bookkeeping */
	size_t pos = 0, used = 0, frames = 0, total = 0, bitrate = 0;
	uint32_t hash = 2166136261u;
	int hz = 0, channels = 0;

	int decode_done = 0, started = 0;
	uint32_t play = 0;
	uint32_t t_start = io->now_us();
	uint32_t t_last_rx = t_start, last_got = 0;
	uint32_t got = 0;

	out->first_audio_us = 0;
	out->decode_us = 0;

	for (;;) {
		got = io->rx_bytes();
		uint32_t now = io->now_us();
		if (got != last_got) {
			last_got = got;
			t_last_rx = now;
		} else if (got < len + 4u && (now - t_last_rx) / 1000u > timeout_ms) {
			out->rx_bytes = got;
			out->play_pos = play;
			return STREAM_RX_TIMEOUT;
		}
		uint32_t avail = got < len ? got : len;
		int complete = (avail == len);

		/* Decode one frame per pass, so the FIFO is topped up between frames. */
		if (!decode_done && (complete || avail - pos >= STREAM_LOOKAHEAD)) {
			if (pcm_cap - used < MINIMP3_MAX_SAMPLES_PER_FRAME) {
				out->rx_bytes = got;
				out->play_pos = play;
				return STREAM_PCM_FULL;
			}
			uint32_t t0 = io->now_us();
			int samples = mp3dec_decode_frame(&dec, buf + pos, (int)(avail - pos), pcm + used, &info);
			if (io->frame_cost) io->frame_cost();
			out->decode_us += io->now_us() - t0;

			if (info.frame_bytes == 0) {
				/* With the lookahead this only happens at the end of the file */
				if (complete) decode_done = 1;
			} else {
				pos += info.frame_bytes;
				if (samples) {
					bitrate = info.bitrate_kbps;
					if (frames == 0) {
						hz = info.hz;
						channels = info.channels;
					}
					for (int i = 0; i < samples * info.channels; i++) {
						uint16_t u = (uint16_t)pcm[used + i];
						hash ^= (uint8_t)(u & 0xFFu);
						hash *= 16777619u;
						hash ^= (uint8_t)(u >> 8);
						hash *= 16777619u;
					}
					used += samples * info.channels;
					total += samples;
					frames++;
				}
				if (pos >= len) decode_done = 1;
			}
		}

		/* Start once the rest of the file will arrive before the decoded audio runs out:
		   (bytes still to come + lookahead) / UART rate <= song length, with 25 % margin.
		   Song length is estimated from the bitrate of the frames seen so far. */
		/* Never play a format the PL cannot (main_host.c rejects it after the decode) */
		int playable = (hz == 48000 && channels == 1);

		if (!started && playable && used >= STREAM_MIN_START) {
			if (decode_done || complete) {
				started = 1;
			} else if (bitrate) {
				double song_s = (double)len * 8.0 / ((double)bitrate * 1000.0);
				double rest_s = (double)(len - avail + STREAM_LOOKAHEAD) / (double)rx_bytes_per_s;
				if (rest_s * 1.25 <= song_s) started = 1;
			}
			if (started) out->first_audio_us = io->now_us() - t_start;
		} else if (!started && playable && decode_done && used > 0) {
			started = 1;   /* very short file */
			out->first_audio_us = io->now_us() - t_start;
		}

		if (started) top_up(io, pcm, &play, (uint32_t)used);

		if (decode_done && got >= len + 4u) break;
	}

	out->res.checksum = hash;
	out->res.frame_count = frames;
	out->res.samples_per_channel = total;
	out->res.sample_rate = hz;
	out->res.channel_count = channels;
	out->res.bitrate = bitrate;
	out->rx_bytes = got;
	out->play_pos = play;
	return STREAM_OK;
}
