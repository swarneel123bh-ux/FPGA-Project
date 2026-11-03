#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include "minimp3.h"
#include "decode.h"

#define ERR_FILE_LEN_MISMATCH 1
#define ERR_FOPEN_NULL 2
#define ERR_MALLOC_RETURNED_NULL 3
#define ERR_SIG_DECODE_FAIL 4

#define MP3_LEN 140627

// Macos_main
int main(int argc, char **argv) {

#ifdef BOARD
#else
	if (!(argc == 3)) {
		fprintf(stderr, "usage: %s <in.mp3> <out.raw>\n", argv[0]);
		return 1;
	}
#endif

	int16_t *pcm_buffer;
	uint8_t *mp3;
	size_t pcm_cap;
	long len = MP3_LEN;

	// Read the file into the correct buffer
#ifdef BOARD
	mp3				=  (uint8_t*)0x10000000;
	pcm_buffer = (int16_t*)0x11000000;
	pcm_cap = (size_t)len * 48 + MINIMP3_MAX_SAMPLES_PER_FRAME;
#else
	// Get file name and open file
	char *filename = argv[1];
	FILE *f = fopen(filename, "rb");
	if (!f) {
		fprintf(stderr, "[FAIL] fopen returned NULL\n");
		return ERR_FOPEN_NULL;
	}

	// Get file size
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);

	mp3 = (uint8_t*) malloc(len);
	if (!mp3) {
		fprintf(stderr, "[FAIL] mp3 got NULL from malloc\n");
		return ERR_MALLOC_RETURNED_NULL;
	}

	if ((size_t)len != fread(mp3, 1, (size_t)len, f)) {
		fprintf(stderr, "[FAIL] mp3 file read unexpected number of bytes\n");
		return ERR_FILE_LEN_MISMATCH;
	}
	fclose(f);

#endif


	/*
		The smallest standard frame is MPEG-2 Layer III at 8 kbps and 24 kHz.
		Frame size = 72 × bitrate ÷ sample rate = 72 × 8000 ÷ 24000 = 24 bytes.
		That frame decodes to 576 samples per channel × up to 2 channels = 1,152 int16 values.
		So, worst case, 1,152 ÷ 24 = 48 int16 values per input byte.
	 */
	pcm_cap = (size_t)len * 48 + MINIMP3_MAX_SAMPLES_PER_FRAME;
#ifdef BOARD
#else
	pcm_buffer = (int16_t*) malloc(pcm_cap * sizeof(int16_t));
	if (!pcm_buffer) {
		fprintf(stderr, "[FAIL] pcm_buffer got NULL from malloc\n");
		return ERR_MALLOC_RETURNED_NULL;
	}
#endif

	// Decode and show results
	DecodeResult_t res;
	if (decode(mp3, len, pcm_buffer, pcm_cap, &res) == SIG_DECODE_FAIL) {
		fprintf(stderr, "[FAIL] decode() returned SIG_DECODE_FAIL\n");
#ifdef BOARD
#else
		free(mp3);
		free(pcm_buffer);
#endif
		return ERR_SIG_DECODE_FAIL;
	};

	printf("res.channel_count = %lu\n", 			(unsigned long)res.channel_count);
	printf("res.frame_count = %lu\n", 				(unsigned long)res.frame_count);
	printf("res.sample_rate = %lu\n", 				(unsigned long)res.sample_rate);
	printf("res.samples_per_channel = %lu\n", (unsigned long)res.samples_per_channel);
	printf("res.checksum = 0x%08x\n", 				res.checksum);

	// Write to the target file
#ifdef BOARD
#else
	char *target_filename = argv[2];
	FILE* tf = fopen(target_filename, "wb");
	if (!tf) {
		fprintf(stderr, "[FAIL] fopen returned null to tf\n");
		free(pcm_buffer);
		free(mp3);
		return ERR_FOPEN_NULL;
	}
	fwrite(pcm_buffer, sizeof(int16_t), res.samples_per_channel * res.channel_count, tf);
	fclose(tf);
	free(mp3);
	free(pcm_buffer);

#endif
	return 0;
}
