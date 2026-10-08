"""Draws the synthetic sign fixture: test_assets/gate42.png.

A 1280x720 (16:9, the camera's 720p) scene: a grey wall, a blue airport-style
sign on a post reading "GATE 42" with an arrow to the right. The text is
asymmetric on purpose: mirrored, it reads backwards, so a correct answer to
"What does the sign say?" through a mirroring source proves the un-mirroring.

    ~/Work/models/yolo26n/.venv/bin/python tool/make_gate42_fixture.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 720
OUT = Path(__file__).resolve().parent.parent / "test_assets" / "gate42.png"
FONT = "/System/Library/Fonts/Helvetica.ttc"


def main() -> None:
    img = Image.new("RGB", (W, H), (178, 176, 170))
    d = ImageDraw.Draw(img)
    # Floor and a skirting line, so it reads as a room, not a flat card.
    d.rectangle([0, 560, W, H], fill=(120, 112, 100))
    d.rectangle([0, 552, W, 560], fill=(90, 85, 78))
    # The post and the sign (left of centre: the scene is asymmetric too).
    d.rectangle([428, 380, 452, 560], fill=(70, 70, 75))
    sign = [200, 150, 860, 400]
    d.rounded_rectangle(sign, radius=18, fill=(18, 52, 120), outline=(240, 240, 240), width=8)
    font = ImageFont.truetype(FONT, 132, index=1)  # Helvetica Bold
    left, top, right, bottom = d.textbbox((0, 0), "GATE 42", font=font)
    x = (sign[0] + sign[2] - (right - left)) // 2 - left
    y = (sign[1] + sign[3] - (bottom - top)) // 2 - top
    d.text((x, y), "GATE 42", font=font, fill=(255, 255, 255))
    # Arrow to the right, after the text.
    d.polygon([(1000, 230), (1100, 275), (1000, 320)], fill=(255, 205, 0))
    d.rectangle([900, 258, 1000, 292], fill=(255, 205, 0))
    img.save(OUT, optimize=True)
    print(f"{OUT} {img.size}")


if __name__ == "__main__":
    main()
