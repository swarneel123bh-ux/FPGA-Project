from matplotlib import pyplot as plt
import numpy as np
from scipy import signal
from scipy.signal import butter, sosfilt

# Returns the spectrogram of the given signal
def spectrum_db(x):
	f_s, t_s, S = signal.spectrogram(x, fs=fs, nperseg=4096) # Returns S[Freq, Tim], Power
	avg_dB = 10 * np.log10(S.mean(axis=1) + 1e-12)	# Add tiny bit to ensure no log10(0) happens
	return f_s, t_s, avg_dB, S


if __name__ == "__main__":
	# Generate test tone 6kHz + 10kHz
	# 6kHz will remain, but lower bitrate will remove 10kHz
	fs = 48000
	t = np.arange(fs) / fs	# 1 second of timestamps
	orig_tone  = 0.5 * np.sin(2 * np.pi * 6000 * t) + 0.5 * np.sin(2 * np.pi * 10000 * t);

	# 8th order butterworth highpass filter with cutoff at 8kHz
	sos = butter(8, 8000, btype="highpass", fs=fs, output="sos") # Butterworth highpass filter with cutoff at 8Khz
	after_filter = sosfilt(sos, orig_tone)

	# Compare
	f_before, t_before, avg_dB_before, S_before = spectrum_db(orig_tone)
	f_after, t_after, avg_dB_after, S_after 		= spectrum_db(after_filter)

	# Plot spectrograms before and after
	# Before
	plt.pcolormesh(t_before, 	f_before, 10 * np.log10(S_before + 1e-12), shading="auto")
	plt.ylim(0, 24000)
	plt.xlabel("time (s)")
	plt.ylabel("frequency (Hz)")
	plt.colorbar(label="dB")
	plt.show()
	# After
	plt.pcolormesh(t_after, 	f_after, 	10 * np.log10(S_after  + 1e-12), shading="auto")
	plt.ylim(0, 24000)
	plt.xlabel("time (s)")
	plt.ylabel("frequency (Hz)")
	plt.colorbar(label="dB")
	plt.show()

	# Numerical differnce
	for f_check in [6000, 10000]:
		i = np.argmin(np.abs(f_before - f_check))
		print(f"{f_check} Hz: before {avg_dB_before[i]:.1f} dB, after {avg_dB_after[i]:.1f} dB, change {avg_dB_after[i] - avg_dB_before[i]:.1f} dB")
