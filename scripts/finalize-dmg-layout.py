#!/usr/bin/env python3
"""Finalize existing Finder Iloc records without changing the DS_Store allocation.

Finder can return cached AppleScript positions before persisting them. Run this
after detaching and remounting the image, with no Finder window open.
Iloc format: https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod
"""

import argparse
from pathlib import Path
import struct


def finalize(path: Path, verify: bool) -> None:
    data = bytearray(path.read_bytes())
    if data[:8] != b"\x00\x00\x00\x01Bud1":
        raise ValueError("Unrecognized Finder DS_Store format")
    for name, position in {"Rsyncer.app": (170, 245), "Applications": (470, 245)}.items():
        # Match the complete record header, including UTF-16 filename and the
        # fixed 16-byte Iloc payload length. No records are added or resized.
        key = struct.pack(">I", len(name)) + name.encode("utf-16be")
        key += b"Ilocblob" + struct.pack(">I", 16)
        offsets = []
        start = 0
        while (index := data.find(key, start)) != -1:
            start = index + len(key)
            if start + 16 > len(data):
                raise ValueError(f"Truncated icon record: {name}")
            offsets.append(start)
        if not offsets:
            raise ValueError(f"Finder did not create an icon record for {name}")
        for offset in offsets:
            if verify:
                actual = struct.unpack_from(">II", data, offset)
                if actual != position:
                    raise ValueError(f"{name}: saved position {actual}, expected {position}")
            else:
                struct.pack_into(">II", data, offset, *position)
        print(f"{name}: saved icon position {position}")
    if not verify:
        path.write_bytes(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("store", type=Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    finalize(args.store, args.verify)
