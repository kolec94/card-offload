#!/usr/bin/env python3
"""Generates the app icon.

App Store icons must be 1024x1024 with no alpha channel, so this renders at 4x and
downsamples for clean edges, then saves as flat RGB.

    python Tools/make_icon.py

Writes CardOffload/Assets.xcassets/AppIcon.appiconset/AppIcon.png.
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # supersample, then downsample with Lanczos for anti-aliasing
S = SIZE * SCALE

TOP = (27, 60, 156)      # deep indigo
BOTTOM = (13, 165, 200)  # cyan
WHITE = (255, 255, 255)

OUT = Path("CardOffload/Assets.xcassets/AppIcon.appiconset/AppIcon.png")


def px(value: float) -> float:
    """Scale a coordinate expressed in 1024-space up to the supersampled canvas."""
    return value * SCALE


def gradient() -> Image.Image:
    """Vertical indigo-to-cyan wash."""
    base = Image.new("RGB", (1, SIZE), TOP)
    pixels = base.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        pixels[0, y] = (
            round(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
            round(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
            round(TOP[2] + (BOTTOM[2] - TOP[2]) * t),
        )
    return base.resize((S, S), Image.Resampling.BILINEAR)


def draw_card(draw: ImageDraw.ImageDraw) -> None:
    """An SD card, chamfered on the top-left corner the way the real ones are."""
    left, right, top, bottom, chamfer = 412, 612, 118, 330, 58
    draw.polygon(
        [
            (px(left + chamfer), px(top)),
            (px(right), px(top)),
            (px(right), px(bottom)),
            (px(left), px(bottom)),
            (px(left), px(top + chamfer)),
        ],
        fill=WHITE,
    )
    # Contact strip, punched back out to the gradient so it reads at small sizes.
    for i in range(3):
        x = 448 + i * 42
        draw.rounded_rectangle(
            [px(x), px(150), px(x + 22), px(216)],
            radius=px(11),
            fill=TOP,
        )


def draw_arrow(draw: ImageDraw.ImageDraw) -> None:
    """The offload direction: down."""
    draw.rounded_rectangle(
        [px(472), px(378), px(552), px(566)],
        radius=px(18),
        fill=WHITE,
    )
    draw.polygon(
        [(px(388), px(540)), (px(636), px(540)), (px(512), px(690))],
        fill=WHITE,
    )


def draw_drive(draw: ImageDraw.ImageDraw) -> None:
    """The SSD, with vents cut back to the gradient."""
    draw.rounded_rectangle(
        [px(258), px(752), px(766), px(910)],
        radius=px(44),
        fill=WHITE,
    )
    for i in range(3):
        y = 800 + i * 32
        draw.rounded_rectangle(
            [px(560), px(y), px(700), px(y + 14)],
            radius=px(7),
            fill=BOTTOM,
        )
    # Status light.
    draw.ellipse([px(322), px(806), px(384), px(868)], fill=BOTTOM)


def main() -> None:
    canvas = gradient()
    draw = ImageDraw.Draw(canvas)
    draw_card(draw)
    draw_arrow(draw)
    draw_drive(draw)

    icon = canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, mode={icon.mode})")


if __name__ == "__main__":
    main()
