#!/usr/bin/env python3
"""Convert a boot ROM binary into a $readmemh file of 32-bit little-endian
words, padded with zeros to the ROM size.

  gen-romhex.py <image.bin> <out.hex> [words]   (default 16384 = 64 KiB)
"""
import sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    words = int(sys.argv[3]) if len(sys.argv) > 3 else 16384
    data = open(src, "rb").read()
    if len(data) > words * 4:
        sys.exit(f"{src}: {len(data)} bytes does not fit in {words * 4}")
    data += b"\0" * (words * 4 - len(data))
    with open(dst, "w") as f:
        for i in range(words):
            f.write("%08x\n" % int.from_bytes(data[4 * i:4 * i + 4], "little"))


if __name__ == "__main__":
    main()
