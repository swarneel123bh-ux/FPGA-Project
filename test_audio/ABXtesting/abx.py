#!/usr/bin/env python3
# Not team code. Blind ABX test for plain vs enhanced 32 kbit/s audio (macOS: uses afplay).
# A = plain, B = enhanced (known). X = A or B, chosen at random for each trial and kept hidden.
import glob, math, random, subprocess, sys

def play(path):
    subprocess.run(["afplay", path], check=True)

def p_value(correct, trials):
    # one-sided probability of at least `correct` right out of `trials` by pure guessing
    return sum(math.comb(trials, k) for k in range(correct, trials + 1)) / 2**trials

def main():
    rng = random.SystemRandom()
    plain = sorted(glob.glob("excerpt_*_plain.wav"))
    enh = sorted(glob.glob("excerpt_*_enhanced.wav"))
    if len(plain) != len(enh) or not plain:
        sys.exit("expected matching excerpt_*_plain.wav and excerpt_*_enhanced.wav files")
    order = list(range(len(plain)))
    rng.shuffle(order)
    score, answered = 0, 0
    for trial, idx in enumerate(order, 1):
        A, B = plain[idx], enh[idx]
        x_is_a = rng.random() < 0.5          # hidden key, kept only in memory
        X = A if x_is_a else B
        print(f"\nTrial {trial} of {len(order)}  ({A.split('_')[1]})")
        while True:
            cmd = input("[a] play A  [b] play B  [x] play X  [g] guess (a/b)  [q] quit > ").strip().lower()
            if cmd == "a": play(A)
            elif cmd == "b": play(B)
            elif cmd == "x": play(X)
            elif cmd == "q":
                print(f"\nStopped after {answered} trials. Score {score}/{answered}.")
                return
            elif cmd in ("g", "guess"):
                ans = input("Is X the same as A or B? (a/b) > ").strip().lower()
                if ans not in ("a", "b"):
                    print("Enter a or b."); continue
                answered += 1
                correct = (ans == "a") == x_is_a
                score += correct
                print("Correct" if correct else "Wrong")
                break
    print(f"\nScore {score}/{answered}. Probability of this by guessing: {p_value(score, answered):.4f}")
    print("Below 0.05 suggests a real difference; near 0.5 suggests guessing.")

if __name__ == "__main__":
    main()
