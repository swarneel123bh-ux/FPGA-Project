import sys
import numpy as np
from matplotlib import pyplot as plt
from scipy import signal

# Returns the spectrogram of the given signal
def spectrum_db(x):
	f_s, t_s, S = signal.spectrogram(x, fs=fs, nperseg=4096) # Returns S[Freq, Tim], Power
	avg_dB = 10 * np.log10(S.mean(axis=1) + 1e-12)	# Add tiny bit to ensure no log10(0) happens
	return f_s, t_s, avg_dB, S


if __name__ == "__main__":

	if len(sys.argv) < 2:
		print(f"usage: {sys.argv[0]} <filename>.mp3")

	fs = 48000
	x = np.fromfile(sys.argv[1], dtype="<i2")
	assert len(x) == 963072, f"got {len(x)} samples: wrong file?"
	print(len(x), len(x)/fs)

	t = np.arange(len(x)) / fs
	assert t.shape == x.shape, f"t.shape({t.shape}) != x.shape, "
	plt.plot(t, x);
	plt.title("Waveform")
	plt.xlabel("time")
	plt.ylabel("amplitude")
	plt.show()

	_fft_dB = 20*np.log10(np.abs(np.fft.rfft(x)) + 1e-12)
	_freqs_ = np.fft.rfftfreq(len(x), 1/fs)
	f_s, t_s, S = signal.spectrogram(x, fs=fs, nperseg=4096) # Returns S[Freq, Tim], Power
	avg_dB = 10 * np.log10(S.mean(axis=1) + 1e-12)	# Add tiny bit to ensure no log10(0) happens
	plt.plot(_freqs_, _fft_dB, label="FFT (Step 3)")
	plt.plot(f_s, avg_dB, label="spectrogram, time-averaged")
	plt.xlim(0, 16000)
	plt.legend()
	plt.show()

	plt.pcolormesh(t_s, f_s, 10 * np.log10(S + 1e-12), shading="auto")
	plt.ylim(0, 24000)
	plt.xlabel("time (s)")
	plt.ylabel("frequency (Hz)")
	plt.colorbar(label="dB")
	plt.show()
