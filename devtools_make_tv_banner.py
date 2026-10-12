"""Generate the Android TV / Google TV launcher banner for Kazumi.

Google TV renders a 320x180 banner next to the app in the launcher row.
The stock launcher icon is a square character portrait on a white field, so
the banner keeps that white field as the art direction instead of fighting it:
a warm cream-to-green gradient with the character on the right and a wordmark
on the left. Densities follow the xhdpi reference (320x180).
"""

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RES = "/Volumes/Samsung_T5/ai/Kazumi/android/app/src/main/res"
ICON = os.path.join(RES, "mipmap-xxxhdpi/ic_launcher.png")
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# xhdpi is the TV reference density; the others are supplied for completeness.
DENSITIES = {
    "drawable-mdpi": (160, 90),
    "drawable-hdpi": (240, 135),
    "drawable-xhdpi": (320, 180),
    "drawable-xxhdpi": (480, 270),
    "drawable-xxxhdpi": (640, 360),
}

INK = (58, 72, 40)          # deep olive, readable on the cream field
CREAM_TOP = (253, 248, 238)
GREEN_BOTTOM = (214, 233, 186)
ACCENT = (140, 183, 74)     # sampled from the character's hair


def gradient(w, h, top, bottom):
    """Vertical gradient, built by interpolation rather than a tiled 1px strip."""
    grad = Image.new("RGB", (1, h))
    px = grad.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return grad.resize((w, h), Image.BILINEAR)


def fit_height(img, target_h):
    ratio = target_h / img.height
    return img.resize((max(1, round(img.width * ratio)), target_h), Image.LANCZOS)


def render(w, h):
    canvas = gradient(w, h, CREAM_TOP, GREEN_BOTTOM)
    draw = ImageDraw.Draw(canvas)

    # Character sits on the right. Kept fully on-canvas and clear of the
    # wordmark column; bleeding it off the edge makes it collide with text.
    char_h = round(h * 0.98)
    char = fit_height(Image.open(ICON).convert("RGB"), char_h)
    # Feather the top edge: a hard horizontal line gives the paste away.
    mask = Image.new("L", char.size, 255)
    fade = Image.new("L", (1, char.size[1]))
    fp = fade.load()
    feather = round(char_h * 0.30)
    for y in range(char.size[1]):
        fp[0, y] = 0 if y < feather else min(255, round((y - feather) / feather * 255))
    mask.paste(fade.resize(char.size, Image.BILINEAR), (0, 0))
    canvas.paste(char, (w - char.width - round(w * 0.02), h - char_h), mask)

    # Wordmark block, optically centred in the left half.
    title = "Kazumi"
    size = round(h * 0.20)
    font = ImageFont.truetype(FONT, size)
    sub_size = round(h * 0.072)
    sub_font = ImageFont.truetype(FONT, sub_size)

    left = round(w * 0.075)
    band_top = round(h * 0.36)

    # Accent bar above the wordmark, kept short so it frames rather than shouts.
    bar_w = round(w * 0.22)
    draw.rounded_rectangle(
        [left, band_top - round(size * 0.52), left + bar_w, band_top - round(size * 0.38)],
        radius=round(size * 0.07),
        fill=ACCENT,
    )

    draw.text((left, band_top), title, font=font, fill=INK)
    draw.text(
        (left + 2, band_top + round(size * 1.16)),
        "OPEN  SOURCE",
        font=sub_font,
        fill=(INK[0] + 40, INK[1] + 40, INK[2] + 30),
    )

    return canvas


def main():
    for folder, (w, h) in DENSITIES.items():
        out_dir = os.path.join(RES, folder)
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, "tv_banner.png")
        render(w, h).save(out, "PNG", optimize=True)
        print(f"{out}  {w}x{h}  {os.path.getsize(out)} bytes")


if __name__ == "__main__":
    main()
