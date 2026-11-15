"""Decode a D2 DC6 sprite (palette-indexed, RLE) into PNG frames, using the
format exactly as documented in components/dc6/dc6.hpp. Read-only, for
previewing an existing UI button as a template -- not a general tool.
"""
import struct
import sys
from PIL import Image

def load_palette(path):
    with open(path, "rb") as f:
        data = f.read()
    return [tuple(data[i:i+3]) for i in range(0, 768, 3)]

def decode_dc6(path):
    with open(path, "rb") as f:
        data = f.read()
    version, subver, encoding, terminator, directions, frames_per_dir = struct.unpack_from("<6I", data, 0)
    assert version == 6, f"bad version {version}"
    total = directions * frames_per_dir
    ptr_table = struct.unpack_from(f"<{total}I", data, 24)
    frames = []
    for off in ptr_table:
        flip, w, h, ox, oy, unk, nxt, length = struct.unpack_from("<8i", data, off)
        pixel_off = off + 32
        pixels = bytearray(w * h)  # 0 = transparent
        x, y = 0, (h - 1) if flip == 0 else 0
        pos = pixel_off
        end = pixel_off + length
        while pos < end:
            token = data[pos]; pos += 1
            if token == 0x80:
                x = 0
                y += -1 if flip == 0 else 1
                continue
            if token & 0x80:
                x += token & 0x7f
                continue
            count = token
            for i in range(count):
                if 0 <= y < h and 0 <= x < w:
                    pixels[y * w + x] = data[pos + i]
                x += 1
            pos += count
        frames.append((w, h, ox, oy, bytes(pixels)))
    return frames

def main():
    dc6_path, pal_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    palette = load_palette(pal_path)
    frames = decode_dc6(dc6_path)
    w, h, ox, oy, pixels = frames[0]
    print(f"frame 0: {w}x{h}, offset ({ox},{oy}), {len(frames)} frame(s) total")
    img = Image.new("RGBA", (w, h))
    out_px = img.load()
    for y in range(h):
        for x in range(w):
            idx = pixels[y * w + x]
            if idx == 0:
                out_px[x, y] = (0, 0, 0, 0)
            else:
                r, g, b = palette[idx]
                out_px[x, y] = (r, g, b, 255)
    img.save(out_path)
    print("saved", out_path)

if __name__ == "__main__":
    main()
