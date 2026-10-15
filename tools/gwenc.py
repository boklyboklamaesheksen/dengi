#!/usr/bin/env python3
"""gwenc1 codec for Remote Config values (same as the GW and VLESS apps).

    python3 tools/gwenc.py encode "https://api.example.com"
    python3 tools/gwenc.py decode "gwenc1:..."
"""
import base64
import sys

PREFIX = "gwenc1:"
KEY = bytes([0x37, 0x5B, 0x71, 0x2E, 0x49, 0x6D, 0x23, 0x58,
             0x0F, 0x66, 0x3C, 0x7A, 0x11, 0x44, 0x69, 0x05])
OFFSET = 0x5D


def encode(plain: str) -> str:
    data = bytearray(plain.encode("utf-8"))
    for i in range(len(data)):
        data[i] = ((data[i] ^ KEY[i % 16]) + OFFSET) & 0xFF
    data.reverse()
    return PREFIX + base64.b64encode(bytes(data)).decode()


def decode(value: str) -> str:
    value = value.strip()
    if not value.startswith(PREFIX):
        raise ValueError("value has no gwenc1: prefix")
    data = bytearray(base64.b64decode(value[len(PREFIX):]))
    data.reverse()
    return bytes(((b - OFFSET) & 0xFF) ^ KEY[i % 16]
                 for i, b in enumerate(data)).decode("utf-8")


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("encode", "decode"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    op, value = sys.argv[1], sys.argv[2]
    print(encode(value) if op == "encode" else decode(value))
    return 0


if __name__ == "__main__":
    sys.exit(main())
