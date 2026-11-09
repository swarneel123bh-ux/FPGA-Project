#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "decode.h"
#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"

int decode(
	const uint8_t *mp3, size_t mp3_len,
	int16_t *pcm, size_t pcm_cap, /* caller's buffer, in 16-bit signed integer PCM values */
	DecodeResult_t *res /* returns OK or FAIL if pcm is too small */
){

	// dont declare on stack because stack can be small on the board
	static mp3dec_t dec;
	mp3dec_init(&dec);	// initialize

	size_t pos = 0;
	size_t used = 0;
	size_t frames = 0;
	size_t total = 0;
	size_t bitrate = 0;
	uint32_t hash = 2166136261u;
	mp3dec_frame_info_t info;
	int samples;
	int hz = 0;
	int channels = 0;

	while (pos < mp3_len) {
		if (pcm_cap - used < MINIMP3_MAX_SAMPLES_PER_FRAME) { // Too small even for a single frame, fail
			// fprintf(stderr, "[ERR] pcm_cap - used < MINIMP3_MAX_SAMPLES_PER_FRAME");
			return SIG_DECODE_FAIL;
		}

		samples = mp3dec_decode_frame(
			&dec,
			mp3 + pos, 								// From
			(int)(mp3_len - pos), 		// How many bytes
			pcm + used, 							// To
			&info
		);

		if (info.frame_bytes == 0) break;	// Done

		pos += info.frame_bytes;	// Move the pointer by frame_bytes

		if (!samples) continue; // Must be non-music data, continue

		bitrate = info.bitrate_kbps; // We need to record this after every sample because for some reason
		// there is another piece of samples recorded at 64 kbps so
		// we need only the bitrate at the last sample

		// Need to track since info will be wrong after break
		if (frames == 0) {
			hz = info.hz;
			channels = info.channels;
		}

		// Hash every byte into our hash value
		for (int i = 0; i < samples * info.channels; i ++) {
			uint16_t sample_unsigned = (uint16_t)(*(pcm + used + i));
			uint8_t lb = (uint8_t)(sample_unsigned & 0x00FF);
			hash ^= lb;
			hash *= 16777619u;
			uint8_t hb = (uint8_t)((sample_unsigned & 0xFF00) >> 8);
			hash ^= hb;
			hash *= 16777619u;
		}

		used += samples * info.channels;
		total += samples;
		frames ++;
	}

	// Fill return struct and return with OK
	res->checksum = hash;
	res->frame_count = frames;
	res->samples_per_channel = total;
	res->sample_rate = hz;
	res->channel_count = channels;
	res->bitrate = bitrate;
	return SIG_DECODE_OK;
}
