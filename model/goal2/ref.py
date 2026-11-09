# Reference model for goal2
import sys
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

FILTER_ORDER = 8
FS = 48000				 # Samplign rate
FC = None          # Cutoff, to be measured from the bitrate of the file sent over
FC_BY_BITRATE = {	 # Table of bitrate vs FC
	32: 7200,
	40: 8700,
	48: 11300,
	56: 13600,
	64: 13700
}
GAIN = 1        	 # fixed gain for the added treble
LIMIT_HZ = 20000   # output low-pass


# 8th order butterworth BANDPASS filter
# with filtering range as (fc/2, fc). One octave starts at f and ends at 2*f
# Returns the filtered signal
def bandpass_octave(x, fc):
	sos = butter(FILTER_ORDER//2, [fc/2, fc], btype="bandpass", fs=FS, output="sos") # BANDPASS gets 2*order so half it
	after_filter = sosfilt(sos, x)
	return after_filter

# rectifier or similar; sets the harmonics
def nonlinearity(x):
	return np.abs(x)

# keep only the new content above fc
def highpass(x, fc):
	sos = butter(FILTER_ORDER, fc, btype="highpass", fs=FS, output="sos")
	after_filter = sosfilt(sos, x)
	return after_filter

# limit the output
def lowpass(x, fc):
	sos = butter(FILTER_ORDER, fc, btype="lowpass", fs=FS, output="sos")
	after_filter = sosfilt(sos, x)
	return after_filter


# chain the stages
def enhance(x_int16, fc, gain):
	enhanced = lowpass(
		highpass(
			nonlinearity(
				bandpass_octave(x_int16, fc)
			),
			fc
		),
		LIMIT_HZ	# 20kHz is the highest humans can hear
	)

	return x_int16 + gain * enhanced


if __name__ == "__main__":
	if len(sys.argv) < 3:
		print(f"usage: {sys.argv[0]} <filename>.mp3 <bitrate>")
		sys.exit(1)

	x = np.fromfile(sys.argv[1], dtype="<i2")
	FC = FC_BY_BITRATE[int(sys.argv[2])]
	print(len(x), len(x)/FS)

	enhanced = enhance(x, FC, GAIN)

	# Write enhanced to file for testing
	print("clipped samples:", np.sum(np.abs(enhanced) > 32767))
	out16 = np.clip(enhanced, -32768, 32767).astype("<i2")
	out16.tofile(f"build/enhanced_{int(sys.argv[2])}k.raw")
	wavfile.write(f"build/enhanced_{int(sys.argv[2])}k.wav", FS, out16)
