#!/usr/bin/env python3
"""Build the App Store screenshots from the real-device player captures in source/.

source/NN-name.jpg  ->  iphone-69-NN-name.png  (1320x2868, APP_IPHONE_67)
                        ipad-13-NN-name.png    (2064x2752, APP_IPAD_PRO_3GEN_129)
Leading rows holding a half-cropped status bar (source 01 was captured with the clock cut off)
are trimmed first (<= 40 px, background only below). No captions, no stretching: Lanczos resample keeping aspect ratio, then pad with the
capture's own edge/background colour (iPhone: top/bottom; iPad: left/right, per-row edge colour).
Usage: python3 docs/asc/screenshots/en-US/make_store_screenshots.py   (needs Pillow)
"""
from pathlib import Path
from statistics import median
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent
IPHONE = (1320, 2868)
IPAD = (2064, 2752)


def row_color(im, y):
    w = im.width
    px = [im.getpixel((x, y)) for x in range(w)]
    return tuple(int(median(p[c] for p in px)) for c in range(3))


def trim_clipped_status_bar(src):
    g = src.convert("L")
    top = 0
    while top < 40 and sum(1 for x in range(g.width) if g.getpixel((x, top)) < 200) > 20:
        top += 1
    if top:
        top += 2  # JPEG ringing below the glyph remnants
    return src.crop((0, top, src.width, src.height)) if top else src


def iphone(src):
    W, H = IPHONE
    h = round(src.height * W / src.width)
    assert h <= H, (src.size, h)
    scaled = src.resize((W, h), Image.LANCZOS)
    top = (H - h) // 2
    out = Image.new("RGB", (W, H))
    out.paste(Image.new("RGB", (W, top), row_color(src, 0)), (0, 0))
    out.paste(Image.new("RGB", (W, H - h - top), row_color(src, src.height - 1)), (0, top + h))
    out.paste(scaled, (0, top))
    return out


def ipad(src):
    W, H = IPAD
    w = round(src.width * H / src.height)
    scaled = src.resize((w, H), Image.LANCZOS)
    # per-row background = median of the outer 4 px columns on both sides, smoothed vertically
    edge = Image.new("RGB", (1, H))
    for y in range(H):
        px = [scaled.getpixel((x, y)) for x in (1, 2, 3, 4, w - 5, w - 4, w - 3, w - 2)]
        edge.putpixel((0, y), tuple(int(median(p[c] for p in px)) for c in range(3)))
    edge = edge.filter(ImageFilter.BoxBlur(12))
    out = edge.resize((W, H), Image.NEAREST)
    out.paste(scaled, ((W - w) // 2, 0))
    return out


def main():
    for f in sorted((HERE / "source").glob("*.jpg")):
        src = trim_clipped_status_bar(Image.open(f).convert("RGB"))
        for prefix, fn, size in (("iphone-69", iphone, IPHONE), ("ipad-13", ipad, IPAD)):
            img = fn(src)
            assert img.size == size
            dst = HERE / f"{prefix}-{f.stem}.png"
            img.save(dst, optimize=True)
            print(dst.name, img.size)


if __name__ == "__main__":
    main()
