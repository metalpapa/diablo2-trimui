"""Encode a transparent-background RGBA PNG into a D2 DC6 sprite (one frame,
one direction), matching the exact layout components/dc6/dc6.hpp parses.
Colours are mapped to the nearest entry in a given D2 palette (index 0 stays
reserved for transparency, as D2 itself does).
"""
import struct
import sys
from PIL import Image


def load_palette(path):
    with open(path, "rb") as f:
        data = f.read()
    return [tuple(data[i:i + 3]) for i in range(0, 768, 3)]


def nearest_index(rgb, palette):
    best_i, best_d = 1, None
    r, g, b = rgb
    for i in range(1, 256):  # skip index 0: reserved for transparency
        pr, pg, pb = palette[i]
        d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
        if best_d is None or d < best_d:
            best_d, best_i = d, i
    return best_i


def rle_encode_row(indices):
    """One scanline of palette indices (0 = transparent) -> DC6 RLE tokens."""
    out = bytearray()
    i = 0
    n = len(indices)
    while i < n:
        if indices[i] == 0:
            j = i
            while j < n and indices[j] == 0 and (j - i) < 0x7f:
                j += 1
            out.append(0x80 | (j - i))
            i = j
        else:
            j = i
            while j < n and indices[j] != 0 and (j - i) < 0x7f:
                j += 1
            out.append(j - i)
            out.extend(indices[i:j])
            i = j
    out.append(0x80)  # end of scanline
    return bytes(out)


def encode_dc6(png_path, palette):
    img = Image.open(png_path).convert("RGBA")
    w, h = img.size
    px = img.load()
    rle = bytearray()
    for y in range(h):  # top-down (flip=1): simplest to generate and to read back
        row = []
        for x in range(w):
            r, g, b, a = px[x, y]
            row.append(0 if a < 128 else nearest_index((r, g, b), palette))
        rle.extend(rle_encode_row(row))

    frame_header = struct.pack("<8i", 1, w, h, 0, 0, 0, 0, len(rle))  # flip=1: top-down
    frame = frame_header + bytes(rle)

    file_header = struct.pack("<6I", 6, 1, 1, 0xCDCDCDCD & 0xffffffff, 1, 1)  # version, subver, enc, term, dirs=1, frames=1
    pointer_table = struct.pack("<I", len(file_header) + 4)  # one frame, right after this 4-byte pointer
    return file_header + pointer_table + frame


def main():
    png_path, pal_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    palette = load_palette(pal_path)
    data = encode_dc6(png_path, palette)
    with open(out_path, "wb") as f:
        f.write(data)
    print(f"wrote {out_path} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
