#ifndef DECODE_H
#define DECODE_H

#include <stdint.h>
#include <stdlib.h>

typedef struct DecodeResult_t {
	uint32_t checksum;
	size_t frame_count;
	size_t samples_per_channel;
	size_t sample_rate;
	size_t channel_count;
} DecodeResult_t;

#define SIG_DECODE_OK		0
#define SIG_DECODE_FAIL	1

int decode(
	const uint8_t *mp3, size_t mp3_len,
	int16_t *pcm, size_t pcm_cap, /* caller's buffer, in 16-bit signed integer PCM values */
	DecodeResult_t *res); /* returns OK or FAIL if pcm is too small */

#endif // DECODE_H
