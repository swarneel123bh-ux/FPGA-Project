#!/usr/bin/env python3
# Not team code. Blind preference test: plain vs enhanced, presented as "1" and "2" in random order.
# Usage (macOS, uses afplay):  python3 pref.py [folder]     e.g.  python3 pref.py short_2s
import glob, math, os, random, subprocess, sys

def play(path):
    subprocess.run(["afplay", path], check=True)

def p_value(k, n):
    # one-sided probability of at least k preferences for enhanced out of n by pure chance
    return sum(math.comb(n, i) for i in range(k, n + 1)) / 2**n

def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    plain = sorted(glob.glob(os.path.join(folder, "excerpt_*_plain.wav")))
    enh = sorted(glob.glob(os.path.join(folder, "excerpt_*_enhanced.wav")))
    if len(plain) != len(enh) or not plain:
        sys.exit("expected matching excerpt_*_plain.wav and excerpt_*_enhanced.wav files")
    rng = random.SystemRandom()
    order = list(range(len(plain)))
    rng.shuffle(order)
    prefer_enh, answered = 0, 0
    for trial, idx in enumerate(order, 1):
        enh_first = rng.random() < 0.5          # hidden, kept only in memory
        one, two = (enh[idx], plain[idx]) if enh_first else (plain[idx], enh[idx])
        print(f"\nTrial {trial} of {len(order)}")
        while True:
            cmd = input("[1] play 1  [2] play 2  [p] choose preferred (1/2)  [q] quit > ").strip().lower()
            if cmd == "1": play(one)
            elif cmd == "2": play(two)
            elif cmd == "q":
                print(f"\nStopped after {answered} trials. Enhanced preferred {prefer_enh}/{answered}.")
                return
            elif cmd == "p":
                ans = input("Which do you prefer? (1/2) > ").strip()
                if ans not in ("1", "2"):
                    print("Enter 1 or 2."); continue
                answered += 1
                prefer_enh += (ans == "1") == enh_first
                break
    print(f"\nEnhanced preferred {prefer_enh}/{answered}. "
          f"Probability of this many or more by chance: {p_value(prefer_enh, answered):.4f}")
    print("Below 0.05 means the enhanced version is preferred more often than chance.")

if __name__ == "__main__":
    main()
