#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include "minimp3.h"
#include "decode.h"

#ifdef BOARD
	#include "xil_printf.h"
	#include "xstatus.h"
	#ifdef SDT
		#include "xiltimer.h"	/* Vitis 2023.2+: XTime moved into xiltimer */
	#else
		#include "xtime_l.h"	/* Vitis 2020.x */
	#endif
	#include "uart_rx.h"
#endif

#define ERR_FILE_LEN_MISMATCH    1
#define ERR_FOPEN_NULL           2
#define ERR_MALLOC_RETURNED_NULL 3
#define ERR_SIG_DECODE_FAIL      4
#define ERR_URXINIT_FAIL         5
#define ERR_BAD_HEADER           6
#define ERR_RX_TIMEOUT           7
#define ERR_CHECKSUM_MISMATCH    8

/*
	Frame sent by the laptop sender (sw/sender/ must match this byte for byte):
		offset 0      4 bytes  magic "MP3!"
		offset 4      4 bytes  payload length N, little-endian u32
		offset 8      N bytes  the MP3 file, unchanged
		offset 8 + N  4 bytes  FNV-1a 32-bit of the payload, little-endian
*/
#define HDRLEN      8
#define TRAILERLEN  4

#ifdef BOARD
	#define RECV_BUF_ADDR  0x10000000u
	#define PCM_BUF_ADDR   0x11000000u
	/* 96 PCM bytes per MP3 byte (see pcm_cap below): 2 MB of MP3 needs 192 MB, which still
	   ends below the top of the ZedBoard's 512 MB DDR (0x20000000). */
	#define MAX_MP3_LEN    (2u * 1024u * 1024u)
	#define RX_TIMEOUT_S   30

	static uint8_t *RecvBuffer = (uint8_t *)RECV_BUF_ADDR;
#endif

/* FNV-1a 32-bit over a byte buffer (same constants as decode.c). [filled in by Claude] */
static uint32_t fnv1a(const uint8_t *p, size_t n) {
	uint32_t h = 2166136261u;
	for (size_t i = 0; i < n; i++) {
		h ^= p[i];
		h *= 16777619u;
	}
	return h;
}

#ifdef BOARD
static uint32_t read_le32(const uint8_t *p) {
	return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
#endif

#ifdef BOARD
/* Wait for the current uart_rx_start() to finish; 0 on success, -1 on timeout. [filled in by Claude] */
static int wait_rx(u32 timeout_s) {
	XTime start, now;
	XTime_GetTime(&start);
	while (!uart_rx_done()) {
		XTime_GetTime(&now);
		if ((now - start) > (XTime)timeout_s * COUNTS_PER_SECOND) {
			return -1;
		}
	}
	return 0;
}
#endif

int main(int argc, char **argv) {
	int16_t *pcm_buffer;
	uint8_t *mp3;
	size_t len;
	size_t pcm_cap;

#ifdef BOARD
	(void)argc;
	(void)argv;

	if (uart_rx_init() != XST_SUCCESS) {
		xil_printf("[FAIL] uart_rx_init\r\n");
		return ERR_URXINIT_FAIL;
	}

	// UART1 now runs at 230,400 baud: the serial terminal must be set to that too
	xil_printf("**Ready**\r\n");

	// Get header
	uint8_t hdr[HDRLEN];
	uart_rx_start(hdr, HDRLEN);
	if (wait_rx(RX_TIMEOUT_S) != 0) {
		xil_printf("[FAIL] header timeout, got %d of %d bytes\r\n", (int)uart_rx_count(), HDRLEN);
		return ERR_RX_TIMEOUT;
	}

	// Checks [filled in by Claude]
	if (hdr[0] != 'M' || hdr[1] != 'P' || hdr[2] != '3' || hdr[3] != '!') {
		xil_printf("[FAIL] bad magic %02x %02x %02x %02x\r\n", hdr[0], hdr[1], hdr[2], hdr[3]);
		return ERR_BAD_HEADER;
	}
	len = read_le32(hdr + 4);
	if (len == 0 || len > MAX_MP3_LEN) {
		xil_printf("[FAIL] length %d out of range (max %d)\r\n", (int)len, (int)MAX_MP3_LEN);
		return ERR_BAD_HEADER;
	}

	// Get the rest: payload and trailing checksum in one receive
	uart_rx_start(RecvBuffer, (u32)(len + TRAILERLEN));
	if (wait_rx(RX_TIMEOUT_S) != 0) {
		xil_printf("[FAIL] payload timeout, got %d of %d bytes\r\n",
			(int)uart_rx_count(), (int)(len + TRAILERLEN));
		return ERR_RX_TIMEOUT;
	}

	// Compute FNV-1a and check correctness [filled in by Claude]
	uint32_t expected = read_le32(RecvBuffer + len);
	uint32_t actual = fnv1a(RecvBuffer, len);
	xil_printf("rx: %d bytes, %d uart errors, fnv 0x%08x (sender 0x%08x)\r\n",
		(int)len, (int)uart_rx_errors(), actual, expected);
	if (actual != expected) {
		xil_printf("[FAIL] checksum mismatch\r\n");
		return ERR_CHECKSUM_MISMATCH;
	}

	mp3 = RecvBuffer;
	pcm_buffer = (int16_t *)PCM_BUF_ADDR;
#else
	if (argc != 3) {
		fprintf(stderr, "usage: %s <in.mp3> <out.raw>\n", argv[0]);
		return 1;
	}

	// Get file name and open file
	char *filename = argv[1];
	FILE *f = fopen(filename, "rb");
	if (!f) {
		fprintf(stderr, "[FAIL] fopen returned NULL\n");
		return ERR_FOPEN_NULL;
	}

	// Get file size
	fseek(f, 0, SEEK_END);
	len = (size_t)ftell(f);
	fseek(f, 0, SEEK_SET);

	mp3 = (uint8_t *)malloc(len);
	if (!mp3) {
		fprintf(stderr, "[FAIL] mp3 got NULL from malloc\n");
		fclose(f);
		return ERR_MALLOC_RETURNED_NULL;
	}

	if (len != fread(mp3, 1, len, f)) {
		fprintf(stderr, "[FAIL] mp3 file read unexpected number of bytes\n");
		fclose(f);
		free(mp3);
		return ERR_FILE_LEN_MISMATCH;
	}
	fclose(f);
	printf("fnv1a(mp3) = 0x%08x\n", fnv1a(mp3, len));
#endif

	/*
		The smallest standard frame is MPEG-2 Layer III at 8 kbps and 24 kHz.
		Frame size = 72 × bitrate ÷ sample rate = 72 × 8000 ÷ 24000 = 24 bytes.
		That frame decodes to 576 samples per channel × up to 2 channels = 1,152 int16 values.
		So, worst case, 1,152 ÷ 24 = 48 int16 values per input byte.
	*/
	pcm_cap = len * 48 + MINIMP3_MAX_SAMPLES_PER_FRAME;

#ifndef BOARD
	pcm_buffer = (int16_t *)malloc(pcm_cap * sizeof(int16_t));
	if (!pcm_buffer) {
		fprintf(stderr, "[FAIL] pcm_buffer got NULL from malloc\n");
		free(mp3);
		return ERR_MALLOC_RETURNED_NULL;
	}
#endif

	// Decode and show results
	DecodeResult_t res;
#ifdef BOARD
	XTime t0, t1;
	XTime_GetTime(&t0);
#endif
	if (decode(mp3, len, pcm_buffer, pcm_cap, &res) == SIG_DECODE_FAIL) {
#ifdef BOARD
		xil_printf("[FAIL] decode() returned SIG_DECODE_FAIL\r\n");
#else
		fprintf(stderr, "[FAIL] decode() returned SIG_DECODE_FAIL\n");
		free(mp3);
		free(pcm_buffer);
#endif
		return ERR_SIG_DECODE_FAIL;
	}

#ifdef BOARD
	XTime_GetTime(&t1);
	u32 decode_ms = (u32)((t1 - t0) * 1000 / COUNTS_PER_SECOND);
	u32 audio_ms = res.sample_rate ? (u32)((u64)res.samples_per_channel * 1000 / res.sample_rate) : 0;

	xil_printf("res.channel_count = %d\r\n",       (int)res.channel_count);
	xil_printf("res.frame_count = %d\r\n",         (int)res.frame_count);
	xil_printf("res.sample_rate = %d\r\n",         (int)res.sample_rate);
	xil_printf("res.samples_per_channel = %d\r\n", (int)res.samples_per_channel);
	xil_printf("res.checksum = 0x%08x\r\n",        res.checksum);
	xil_printf("decode %d ms for %d ms of audio (x%d real time)\r\n",
		(int)decode_ms, (int)audio_ms, decode_ms ? (int)(audio_ms / decode_ms) : 0);
#else
	printf("res.channel_count = %lu\n",       (unsigned long)res.channel_count);
	printf("res.frame_count = %lu\n",         (unsigned long)res.frame_count);
	printf("res.sample_rate = %lu\n",         (unsigned long)res.sample_rate);
	printf("res.samples_per_channel = %lu\n", (unsigned long)res.samples_per_channel);
	printf("res.checksum = 0x%08x\n",         res.checksum);

	// Write to the target file
	char *target_filename = argv[2];
	FILE *tf = fopen(target_filename, "wb");
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
