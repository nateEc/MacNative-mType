"""Emit table templates for an original, two-glyph test font (fontTools 4.51).

No input fonts or external assets. The only drawn glyph is our own rectangle.
The Swift test assembles these tables with a fresh name and valid checksums.
Run manually to reproduce the embedded templates; not a test dependency.
"""
import base64
import io
import json

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

builder = FontBuilder(1000, isTTF=True)
builder.setupGlyphOrder([".notdef", "x"])
builder.setupCharacterMap({120: "x"})
empty = TTGlyphPen(None)
rectangle = TTGlyphPen(None)
rectangle.moveTo((100, 0))
rectangle.lineTo((500, 0))
rectangle.lineTo((500, 700))
rectangle.lineTo((100, 700))
rectangle.closePath()
builder.setupGlyf({".notdef": empty.glyph(), "x": rectangle.glyph()})
builder.setupHorizontalMetrics({".notdef": (600, 0), "x": (600, 100)})
builder.setupHorizontalHeader(ascent=800, descent=-200)
builder.setupNameTable({"familyName": "Owned Fixture", "styleName": "Regular",
                       "psName": "OwnedFixture", "fullName": "Owned Fixture"})
builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
builder.setupPost()
builder.setupMaxp()
builder.font["head"].created = builder.font["head"].modified = 0
buffer = io.BytesIO()
builder.save(buffer)
font = TTFont(io.BytesIO(buffer.getvalue()))
tables = {}
for tag in sorted(font.reader.keys()):
    if tag == "name":
        continue
    payload = bytearray(font.reader[tag])
    if tag == "head":
        payload[8:12] = bytes(4)  # Swift assembler computes checkSumAdjustment.
    tables[tag] = base64.b64encode(payload).decode("ascii")
print(json.dumps(tables, indent=2, sort_keys=True))
