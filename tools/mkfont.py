"""Builds the field's big text font (BMFont text format + PNG) from a TTF, only with the glyphs it needs.

Connect IQ's system text fonts stop at FONT_LARGE, smaller than the number fonts, so words like REC
looked small next to the battery and storage numbers.

Usage: python mkfont.py <font.ttf> <output dir>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GLYPHS = "RECSTOPBUSYAMI."  # REC, STOP, BUSY, CAM, PAIR and the dots of "REC..."
SIZES = [150, 104, 80, 60]  # 150 for the large screens (Edge 550, 850, 1050)


def build(ttf, out, size):
    """Tight font box: the line is only as tall as the glyphs, so the field can draw the word bigger
    in the same space (the TTF metrics add a lot of empty room above and below capitals)."""
    font = ImageFont.truetype(str(ttf), size)
    boxes = {ch: font.getbbox(ch) for ch in GLYPHS}
    top = min(b[1] for b in boxes.values())
    bottom = max(b[3] for b in boxes.values())
    line = bottom - top
    chars = []
    x = 1
    for ch in GLYPHS:
        left, gtop, right, gbottom = boxes[ch]
        w, h = max(right - left, 1), max(gbottom - gtop, 1)
        chars.append((ch, x, left, gtop - top, w, h, round(font.getlength(ch)), gtop))
        x += w + 2
    width, height = x, line + 2
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for ch, cx, left, yoff, w, h, adv, gtop in chars:
        # Glyph top lands at 1 + yoff, its row in the atlas
        draw.text((cx - left, 1 - top), ch, font=font, fill=(255, 255, 255, 255))
    name = "bigtext_%d" % size
    img.save(out / (name + ".png"))
    lines = [
        'info face="Barlow Condensed Bold" size=%d bold=1 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1' % size,
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % (line, line, width, height),
        'page id=0 file="%s.png"' % name,
        "chars count=%d" % len(chars),
    ]
    for ch, cx, left, yoff, w, h, adv, gtop in chars:
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                     % (ord(ch), cx, 1 + yoff, w, h, left, yoff, adv))
    (out / (name + ".fnt")).write_text("\n".join(lines) + "\n")
    return name


if __name__ == "__main__":
    ttf, out = Path(sys.argv[1]), Path(sys.argv[2])
    names = [build(ttf, out, s) for s in SIZES]
    xml = ["<fonts>"] + ['    <font id="BigText%s" filename="%s.fnt" antialias="true" />' % (n.split("_")[1], n) for n in names] + ["</fonts>"]
    (out / "fonts.xml").write_text("\n".join(xml) + "\n")
    print("built", names)
