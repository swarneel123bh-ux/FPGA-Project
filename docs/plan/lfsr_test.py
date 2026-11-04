
# Purpose: learn how the 23-bit LFSR works and check it.

SEED = 0x5A5A5A        # nonzero, with a mix of 1s and 0s
AMP = 2097152          # +0.25 in Q1.23 (0.25 * 2^23)

state = SEED
count = 0
plus = 0
first = []

while True:
    # feedback: XOR of bit 22 and bit 17 (x^23 + x^18 + 1)
    new_bit = ((state >> 22) ^ (state >> 17)) & 1
    # shift left, insert new bit, keep only 23 bits
    state = ((state << 1) | new_bit) & 0x7FFFFF
    count = count + 1

    # output sample: +AMP if the lowest bit is 1, otherwise -AMP
    if state & 1:
        sample = AMP
        plus = plus + 1
    else:
        sample = -AMP
    if len(first) < 10:
        first.append(sample)

    if state == SEED:
        break

print("period:", count, "(expected 8388607)")
print("plus samples:", plus, " minus samples:", count - plus)
print("first 10 samples:", first)