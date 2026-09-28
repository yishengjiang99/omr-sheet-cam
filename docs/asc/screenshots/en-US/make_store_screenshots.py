#!/usr/bin/env python3
"""Build the App Store screenshots (peach marketing style) from source/.

Outputs (PNG, RGB, no alpha):
  iphone-69-NN-*.png  1320x2868  APP_IPHONE_67
  ipad-13-NN-*.png    2064x2752  APP_IPAD_PRO_3GEN_129
Order: 01 hero mockup, 02 Fur Elise player (tempo/instrument chips), 03 "Reading music" progress card,
04 player controls (instrument/tempo chips).
Every frame has a large bold caption at the top. The hero mockup is Lanczos-upscaled with a mild unsharp
mask and its peach gradient is extended (edge-replicate + blur, feathered seam) to fit the canvas; the
phone itself is never cropped. source/reading-*.png are crops of the scanning screen that exclude the
photo preview (it showed third-party sheet music).
Usage: python3 docs/asc/screenshots/en-US/make_store_screenshots.py   (Pillow + numpy; Inter font)
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
SRC = HERE / "source"
FONT = "/usr/share/fonts/truetype/sand-box/google/Inter/Inter-VariableFont_opsz,wght.ttf"
INK = (38, 20, 16)
SUB = (110, 60, 48)
SIZES = {"iphone-69": (1320, 2868), "ipad-13": (2064, 2752)}

SHOTS = [
    ("01-snap-and-play", "Snap sheet music.\nHear it play.", None),
    ("02-slow-it-down", "Slow it down\nto practice", "Tempo from 0.5\u00d7 to 2\u00d7"),
    ("03-reads-on-device", "Reads music right\non your {device}", "A live progress bar while it reads"),
    ("04-pick-a-sound", "Piano, strings,\nchoir and more", "Pick the instrument for playback"),
]


def font(size, weight="ExtraBold"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def peach_bg(W, H):
    """Vertical peach/salmon gradient with a soft light glow, matching the hero mockup."""
    y = np.linspace(0, 1, H)[:, None]
    x = np.linspace(0, 1, W)[None, :]
    top = np.array([250, 214, 196], float)
    bot = np.array([240, 172, 150], float)
    img = top[None, None, :] * (1 - y[..., None]) + bot[None, None, :] * y[..., None]
    d = np.sqrt(((x - 0.5) * W / H) ** 2 + (y - 0.42) ** 2)
    glow = np.clip(1 - d / 0.55, 0, 1) ** 2 * 18
    img = img + glow[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def draw_caption(canvas, text, sub, scale):
    text = text.replace("{device}", "device" if canvas.width > 2000 else "iPhone")
    d = ImageDraw.Draw(canvas)
    W = canvas.width
    f = font(round(126 * scale))
    y = round(150 * scale)
    lh = round(146 * scale)
    for line in text.split("\n"):
        w = d.textlength(line, font=f)
        assert w <= W - 2 * 60 * scale, (line, w)
        d.text(((W - w) / 2, y), line, font=f, fill=INK)
        y += lh
    if sub:
        fs = font(round(58 * scale), "SemiBold")
        y += round(22 * scale)
        w = d.textlength(sub, font=fs)
        d.text(((W - w) / 2, y), sub, font=fs, fill=SUB)
        y += round(70 * scale)
    return y  # bottom of the caption block


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), r, fill=255)
    return m


def drop_shadow(canvas, box, r, blur, offset, alpha):
    x0, y0, x1, y1 = box
    pad = blur * 3
    sh = Image.new("L", (x1 - x0 + 2 * pad, y1 - y0 + 2 * pad), 0)
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad, pad + x1 - x0, pad + y1 - y0), r, fill=alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    dark = Image.new("RGB", sh.size, (120, 50, 35))
    canvas.paste(dark, (x0 - pad, y0 - pad + offset), sh)


def phone(canvas, screen, cx, top, screen_w):
    """Clean rounded graphite phone frame with the real screenshot inside and a soft shadow."""
    sw = screen_w
    sh = round(screen.height * sw / screen.width)
    b = round(sw * 0.036)
    R = round(sw * 0.14)
    pw, ph = sw + 2 * b, sh + 2 * b
    x0 = round(cx - pw / 2)
    drop_shadow(canvas, (x0, top, x0 + pw, top + ph), R, round(sw * 0.05), round(sw * 0.04), 150)
    body = Image.new("RGB", (pw, ph), (58, 58, 62))
    inner = Image.new("RGB", (pw - 6, ph - 6), (22, 22, 24))
    body.paste(inner, (3, 3), rounded_mask(inner.size, R - 3))
    canvas.paste(body, (x0, top), rounded_mask((pw, ph), R))
    scr = screen.resize((sw, sh), Image.LANCZOS)
    canvas.paste(scr, (x0 + b, top + b), rounded_mask((sw, sh), R - b))
    return top + ph


def card(canvas, img, cx, cy, width, r):
    h = round(img.height * width / img.width)
    im = img.resize((width, h), Image.LANCZOS)
    x0, y0 = round(cx - width / 2), round(cy - h / 2)
    drop_shadow(canvas, (x0, y0, x0 + width, y0 + h), r, round(width * 0.04), round(width * 0.03), 140)
    canvas.paste(im, (x0, y0), rounded_mask(im.size, r))
    return y0, y0 + h


# Playback instruments offered by the app (Sources/App/Settings/AppSettings.swift, Instrument.all)
INSTRUMENTS = ["Piano", "Electric piano", "Harpsichord", "Music box", "Vibraphone", "Organ",
               "Guitar", "Violin", "Strings", "Choir", "Flute"]


def check_badges(canvas, labels, top, scale):
    """Stacked white rounded badges with a coral check mark."""
    d = ImageDraw.Draw(canvas)
    f = font(round(58 * scale), "SemiBold")
    h, gap = round(150 * scale), round(36 * scale)
    w = round(min(canvas.width - 160 * scale, 1080 * scale))
    x0 = (canvas.width - w) // 2
    y = top
    for lab in labels:
        pill = Image.new("RGB", (w, h), (255, 247, 242))
        drop_shadow(canvas, (x0, y, x0 + w, y + h), h // 2, round(18 * scale), round(10 * scale), 70)
        canvas.paste(pill, (x0, y), rounded_mask((w, h), h // 2))
        r = round(40 * scale)
        cx, cy = x0 + round(40 * scale) + r, y + h // 2
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(226, 96, 70))
        lw = max(3, round(9 * scale))
        d.line([(cx - r * 0.45, cy + r * 0.02), (cx - r * 0.1, cy + r * 0.38), (cx + r * 0.5, cy - r * 0.35)],
               fill="white", width=lw, joint="curve")
        tb = d.textbbox((0, 0), lab, font=f)
        d.text((cx + r + round(36 * scale), cy - (tb[1] + tb[3]) / 2), lab, font=f, fill=INK)
        y += h + gap
    return y


def chip_grid(canvas, labels, top, scale, highlight="Piano"):
    """Wrapped rows of black chips (the app's chip style) naming the real instrument choices."""
    d = ImageDraw.Draw(canvas)
    f = font(round(54 * scale), "SemiBold")
    h, gx, gy = round(118 * scale), round(26 * scale), round(28 * scale)
    padx = round(46 * scale)
    maxw = canvas.width - round(140 * scale)
    rows, row, rw = [], [], 0
    for lab in labels:
        w = int(d.textlength(lab, font=f)) + 2 * padx
        if row and rw + gx + w > maxw:
            rows.append((row, rw)); row, rw = [], 0
        row.append((lab, w)); rw += (gx if rw else 0) + w
    rows.append((row, rw))
    y = top
    for row, rw in rows:
        x = (canvas.width - rw) // 2
        for lab, w in row:
            col = (226, 96, 70) if lab == highlight else (20, 20, 22)
            d.rounded_rectangle((x, y, x + w, y + h), h // 2, fill=col)
            tb = d.textbbox((0, 0), lab, font=f)
            d.text((x + padx, y + h / 2 - (tb[1] + tb[3]) / 2), lab, font=f, fill="white")
            x += w + gx
        y += h + gy
    return y


def fit_width(W, H, y, img, below, scale):
    """Card width: up to 1220 pt-scaled, shrunk so card + gap + extras fit above a bottom margin."""
    width = min(W - round(100 * scale), round(1220 * scale))
    room = H - y - round(60 * scale) - below - round(120 * scale)
    return int(min(width, room * img.width / img.height))


def hero(W, H, scale):
    src = Image.open(SRC / "hero-mockup.jpg").convert("RGB")
    cap_bottom = round(150 * scale) + 2 * round(146 * scale) + round(40 * scale)
    # the mockup's own peach margin above the phone is ~9% of its height: let it sit under the caption
    s = min((H - cap_bottom) / (src.height * 0.91), W / src.width)
    w, h = round(src.width * s), round(src.height * s)
    up = src.resize((w, h), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2, percent=55, threshold=2))
    x0, y0 = (W - w) // 2, H - h
    a = np.asarray(up)
    padded = np.pad(a, ((y0, 0), (x0, W - w - x0), (0, 0)), mode="edge")
    canvas = Image.fromarray(padded).filter(ImageFilter.GaussianBlur(round(40 * scale)))
    feather = round(110 * scale)
    m = np.full((h, w), 255.0)
    ramp = np.linspace(0, 1, feather)
    m[:feather, :] *= ramp[:, None]
    if x0 > 0:
        m[:, :feather] *= ramp[None, :]
        m[:, -feather:] *= ramp[::-1][None, :]
    canvas.paste(up, (x0, y0), Image.fromarray(m.astype(np.uint8), "L"))
    draw_caption(canvas, SHOTS[0][1], SHOTS[0][2], scale)
    return canvas


def fur_elise(W, H, scale):
    c = peach_bg(W, H)
    y = draw_caption(c, SHOTS[1][1], SHOTS[1][2], scale)
    scr = Image.open(SRC / "player-fur-elise.jpg").convert("RGB")
    top = y + round(70 * scale)
    avail = H - top - round(110 * scale)
    # phone height = screen_h + 2*bezel, bezel = 0.036*screen_w
    sw = int(avail / (scr.height / scr.width + 0.072))
    sw = min(sw, W - round(160 * scale))
    phone(c, scr, W / 2, top, sw)
    return c


def reading(W, H, scale):
    c = peach_bg(W, H)
    y = draw_caption(c, SHOTS[2][1], SHOTS[2][2], scale)
    cardimg = Image.open(SRC / "reading-progress-card.png").convert("RGB")
    cancel = Image.open(SRC / "reading-cancel-button.png").convert("RGB")
    bgc = cardimg.getpixel((5, 5))
    gap = 90
    panel = Image.new("RGB", (cardimg.width, cancel.height + gap + cardimg.height + 40), bgc)
    panel.paste(cancel, (0, 20))
    panel.paste(cardimg, (0, cancel.height + gap))
    badges = ["No internet needed", "No account or sign-in", "Photos stay on your device"]
    bh = 3 * round(150 * scale) + 2 * round(36 * scale)
    gap = round(150 * scale)
    width = fit_width(W, H, y, panel, gap + bh, scale)
    ph = panel.height * width / panel.width
    top = y + max(round(60 * scale), (H - y - ph - gap - bh) * 0.42)
    y0, y1 = card(c, panel, W / 2, top + ph / 2, width, round(70 * scale))
    check_badges(c, badges, y1 + gap, scale)
    return c


def controls(W, H, scale):
    c = peach_bg(W, H)
    y = draw_caption(c, SHOTS[3][1], SHOTS[3][2], scale)
    scr = Image.open(SRC / "player-die-letzte-kompanie.jpg").convert("RGB")
    crop = scr.crop((0, 1590, scr.width, scr.height))
    probe = Image.new("RGB", (W, H))
    gh = chip_grid(probe, INSTRUMENTS, 0, scale)
    gap = round(150 * scale)
    width = fit_width(W, H, y, crop, gap + gh, scale)
    ch = crop.height * width / crop.width
    top = y + max(round(60 * scale), (H - y - ch - gap - gh) * 0.42)
    y0, y1 = card(c, crop, W / 2, top + ch / 2, width, round(70 * scale))
    chip_grid(c, INSTRUMENTS, y1 + gap, scale)
    return c


def main():
    for f in HERE.glob("*.png"):
        if f.name.startswith(("iphone-69-", "ipad-13-")):
            f.unlink()
    builders = [hero, fur_elise, reading, controls]
    for prefix, (W, H) in SIZES.items():
        scale = W / 1320 if prefix == "iphone-69" else 1.4
        for (name, _, _), fn in zip(SHOTS, builders):
            img = fn(W, H, scale).convert("RGB")
            assert img.size == (W, H), img.size
            dst = HERE / f"{prefix}-{name}.png"
            img.save(dst, optimize=True)
            print(dst.name, img.size, img.mode)


if __name__ == "__main__":
    main()
