"""Builds the field's big text font (BMFont text format + PNG) from a TTF, only with the glyphs it needs.

Connect IQ's system text fonts stop at FONT_LARGE, smaller than the number fonts, so words like REC
looked small next to the battery and storage numbers.

Usage: python mkfont.py <font.ttf> <output dir>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GLYPHS = "RECSTOPBUSYAMI."  # REC, STOP, BUSY, CAM, PAIR and the dots of "REC..."
SIZES = [104, 80, 60]


def build(ttf, out, size):
    font = ImageFont.truetype(str(ttf), size)
    ascent, descent = font.getmetrics()
    chars = []
    x = 1
    for ch in GLYPHS:
        left, top, right, bottom = font.getbbox(ch)
        w, h = max(right - left, 1), max(bottom - top, 1)
        chars.append((ch, x, left, top, w, h, round(font.getlength(ch))))
        x += w + 2
    width, height = x, ascent + descent + 2
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for ch, cx, left, top, w, h, adv in chars:
        draw.text((cx - left, 1 - top), ch, font=font, fill=(255, 255, 255, 255))
    name = "bigtext_%d" % size
    img.save(out / (name + ".png"))
    lines = [
        'info face="Barlow Condensed Bold" size=%d bold=1 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1' % size,
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % (ascent + descent, ascent, width, height),
        'page id=0 file="%s.png"' % name,
        "chars count=%d" % len(chars),
    ]
    for ch, cx, left, top, w, h, adv in chars:
        lines.append("char id=%d x=%d y=1 width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                     % (ord(ch), cx, w, h, left, top, adv))
    (out / (name + ".fnt")).write_text("\n".join(lines) + "\n")
    return name


if __name__ == "__main__":
    ttf, out = Path(sys.argv[1]), Path(sys.argv[2])
    names = [build(ttf, out, s) for s in SIZES]
    xml = ["<fonts>"] + ['    <font id="BigText%s" filename="%s.fnt" antialias="true" />' % (n.split("_")[1], n) for n in names] + ["</fonts>"]
    (out / "fonts.xml").write_text("\n".join(xml) + "\n")
    print("built", names)
