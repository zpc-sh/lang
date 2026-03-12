#!/bin/bash
# Generate LANG fonts using pre-built font tools

echo "🔤 Generating LANG fonts (OTF/TTF) with simplified approach..."

# Create directories
mkdir -p priv/static/fonts/lang

# Use a pre-built image with fonttools
docker run --rm \
  -v $(pwd)/priv/static/fonts/lang:/output \
  alpine:latest sh -c '
# Install Python and fonttools from Alpine packages
apk add --no-cache python3 py3-pip py3-fonttools

# Create font generation script
cat > /tmp/generate_font.py << "SCRIPT"
#!/usr/bin/env python3
import os
import sys

try:
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.t2CharStringPen import T2CharStringPen
except ImportError:
    print("Installing fonttools...")
    os.system("pip3 install --break-system-packages fonttools")
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.t2CharStringPen import T2CharStringPen

print("Creating LANG Icon font...")

# Font metadata
familyName = "LANG Icons"
styleName = "Regular"
version = "1.0"
unitsPerEm = 1000

# Create font builder
fb = FontBuilder(unitsPerEm, isTTF=True)

# Set up glyphs
glyph_order = [".notdef", ".null", "space", "logo", "lang", "build", "proc", "edit", "stor"]
char_map = {
    32: "space",
    0xE000: "logo",
    0xE001: "lang",
    0xE002: "build",
    0xE003: "proc",
    0xE004: "edit",
    0xE005: "stor",
}

fb.setupGlyphOrder(glyph_order)
fb.setupCharacterMap(char_map)

# Create glyphs
glyphs = {}

# Default glyph
for name in [".notdef", ".null"]:
    pen = T2CharStringPen(1000, None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((900, 700))
    pen.lineTo((900, 0))
    pen.closePath()
    glyphs[name] = pen.getCharString()

# Space
pen = T2CharStringPen(1000, None)
glyphs["space"] = pen.getCharString()

# Logo <~>
pen = T2CharStringPen(1000, None)
# Left bracket
pen.moveTo((292, 708))
pen.lineTo((208, 500))
pen.lineTo((292, 292))
# Wave
pen.moveTo((333, 500))
pen.qCurveTo((417, 583), (500, 500))
pen.qCurveTo((583, 417), (667, 500))
# Right bracket
pen.moveTo((708, 292))
pen.lineTo((792, 500))
pen.lineTo((708, 708))
glyphs["logo"] = pen.getCharString()

# Lang { }
pen = T2CharStringPen(1000, None)
# Left brace
pen.moveTo((400, 300))
pen.qCurveTo((350, 300), (350, 350))
pen.lineTo((350, 450))
pen.qCurveTo((300, 450), (300, 500))
pen.qCurveTo((300, 550), (350, 550))
pen.lineTo((350, 650))
pen.qCurveTo((350, 700), (400, 700))
# Right brace
pen.moveTo((600, 300))
pen.qCurveTo((650, 300), (650, 350))
pen.lineTo((650, 450))
pen.qCurveTo((700, 450), (700, 500))
pen.qCurveTo((700, 550), (650, 550))
pen.lineTo((650, 650))
pen.qCurveTo((650, 700), (600, 700))
glyphs["lang"] = pen.getCharString()

# Build (bars)
pen = T2CharStringPen(1000, None)
pen.moveTo((200, 600))
pen.lineTo((400, 600))
pen.lineTo((400, 800))
pen.lineTo((200, 800))
pen.closePath()
pen.moveTo((450, 450))
pen.lineTo((650, 450))
pen.lineTo((650, 800))
pen.lineTo((450, 800))
pen.closePath()
pen.moveTo((700, 300))
pen.lineTo((900, 300))
pen.lineTo((900, 800))
pen.lineTo((700, 800))
pen.closePath()
glyphs["build"] = pen.getCharString()

# Proc (triangle)
pen = T2CharStringPen(1000, None)
# Nodes
for cx, cy in [(300, 300), (700, 300), (500, 700)]:
    pen.moveTo((cx + 80, cy))
    for i in range(8):
        angle = i * 3.14159 * 2 / 8
        x = cx + 80 * (1 if i == 0 else 0.7071 if i % 2 else 0)
        y = cy + 80 * (0 if i == 0 else 0.7071 if i % 2 else 1)
        if i == 0:
            pen.moveTo((x, y))
        else:
            pen.lineTo((x, y))
    pen.closePath()
glyphs["proc"] = pen.getCharString()

# Edit (pencil)
pen = T2CharStringPen(1000, None)
pen.moveTo((300, 700))
pen.lineTo((600, 400))
pen.lineTo((700, 500))
pen.lineTo((400, 800))
pen.closePath()
pen.moveTo((600, 400))
pen.lineTo((700, 300))
pen.lineTo((800, 400))
pen.lineTo((700, 500))
pen.closePath()
glyphs["edit"] = pen.getCharString()

# Stor (cylinder)
pen = T2CharStringPen(1000, None)
# Top
pen.moveTo((750, 300))
pen.qCurveTo((750, 380), (500, 380))
pen.qCurveTo((250, 380), (250, 300))
pen.qCurveTo((250, 220), (500, 220))
pen.qCurveTo((750, 220), (750, 300))
pen.closePath()
# Sides and bottom
pen.moveTo((250, 300))
pen.lineTo((250, 700))
pen.qCurveTo((250, 780), (500, 780))
pen.qCurveTo((750, 780), (750, 700))
pen.lineTo((750, 300))
glyphs["stor"] = pen.getCharString()

# Build font
fb.setupCFF(
    psName=familyName.replace(" ", ""),
    charStrings=glyphs,
    fontInfo={"FullName": familyName}
)

# Metrics
metrics = {name: (1000, 100) for name in glyph_order}
metrics["space"] = (500, 0)
fb.setupHorizontalMetrics(metrics)

fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({
    "familyName": familyName,
    "styleName": styleName,
    "fullName": f"{familyName} {styleName}",
    "psName": f"{familyName.replace(' ', '')}-{styleName}",
    "version": f"Version {version}",
})

fb.setupOS2(sTypoAscender=800, sTypoDescender=-200)
fb.setupPost()

# Save fonts
print("Saving TTF...")
font = fb.font
font.save("/output/LANGIcons.ttf")

print("Converting to OTF...")
from fontTools.ttLib import TTFont
ttf = TTFont("/output/LANGIcons.ttf")
ttf.save("/output/LANGIcons.otf")

print("Generating web fonts...")
ttf.flavor = "woff"
ttf.save("/output/LANGIcons.woff")

ttf.flavor = "woff2" 
ttf.save("/output/LANGIcons.woff2")

print("✅ Font generation complete!")

# Also generate a basic LANG Mono font
print("\nCreating LANG Mono font...")

fb2 = FontBuilder(1000, isTTF=True)

# Basic ASCII glyphs
glyph_order = [".notdef", ".null", "space"]
char_map = {32: "space"}

# Add basic ASCII
for i in range(33, 127):
    name = f"uni{i:04X}"
    glyph_order.append(name)
    char_map[i] = name

# Add ligature glyphs
ligatures = [
    ("langop", 0xE100),   # <~>
    ("arrow", 0xE101),    # ->
    ("wave", 0xE102),     # ~>
    ("fatarrow", 0xE103), # =>
    ("pipe", 0xE104),     # |>
]

for name, code in ligatures:
    glyph_order.append(name)
    char_map[code] = name

fb2.setupGlyphOrder(glyph_order)
fb2.setupCharacterMap(char_map)

# Create glyphs
glyphs2 = {}

# Default glyphs
for name in [".notdef", ".null"]:
    pen = T2CharStringPen(1000, None)
    pen.moveTo((100, 0))
    pen.lineTo((500, 0))
    pen.lineTo((500, 700))
    pen.lineTo((100, 700))
    pen.closePath()
    glyphs2[name] = pen.getCharString()

# Space
pen = T2CharStringPen(1000, None)
glyphs2["space"] = pen.getCharString()

# Basic ASCII glyphs (simple rectangles for demo)
for i in range(33, 127):
    name = f"uni{i:04X}"
    pen = T2CharStringPen(1000, None)
    # Simple rectangle
    pen.moveTo((150, 100))
    pen.lineTo((450, 100))
    pen.lineTo((450, 600))
    pen.lineTo((150, 600))
    pen.closePath()
    glyphs2[name] = pen.getCharString()

# Ligature glyphs
# <~> 
pen = T2CharStringPen(1000, None)
pen.moveTo((100, 500))
pen.lineTo((150, 350))
pen.lineTo((100, 200))
pen.moveTo((200, 350))
pen.qCurveTo((250, 400), (300, 350))
pen.qCurveTo((350, 300), (400, 350))
pen.moveTo((500, 200))
pen.lineTo((450, 350))
pen.lineTo((500, 500))
glyphs2["langop"] = pen.getCharString()

# Simple ligatures
for name, _ in ligatures[1:]:
    pen = T2CharStringPen(1000, None)
    pen.moveTo((100, 350))
    pen.lineTo((500, 350))
    glyphs2[name] = pen.getCharString()

# Build mono font
fb2.setupCFF(
    psName="LANGMono",
    charStrings=glyphs2,
    fontInfo={"FullName": "LANG Mono"}
)

# Monospace metrics
metrics2 = {name: (600, 0) for name in glyph_order}
fb2.setupHorizontalMetrics(metrics2)

fb2.setupHorizontalHeader(ascent=800, descent=-200)
fb2.setupNameTable({
    "familyName": "LANG Mono",
    "styleName": "Regular",
    "fullName": "LANG Mono Regular",
    "psName": "LANGMono-Regular",
    "version": "Version 1.0",
})

fb2.setupOS2(sTypoAscender=800, sTypoDescender=-200)
fb2.setupPost(isFixedPitch=True)

# Save mono fonts
print("Saving Mono TTF...")
font2 = fb2.font
font2.save("/output/LANGMono.ttf")

print("Converting Mono to OTF...")
ttf2 = TTFont("/output/LANGMono.ttf")
ttf2.save("/output/LANGMono.otf")

print("Generating Mono web fonts...")
ttf2.flavor = "woff"
ttf2.save("/output/LANGMono.woff")

ttf2.flavor = "woff2"
ttf2.save("/output/LANGMono.woff2")

print("✅ All fonts generated successfully!")
SCRIPT

python3 /tmp/generate_font.py
'

# Generate CSS files
cat > priv/static/fonts/lang/lang-fonts.css << 'EOF'
/* LANG Icons Font */
@font-face {
  font-family: 'LANG Icons';
  src: url('LANGIcons.woff2') format('woff2'),
       url('LANGIcons.woff') format('woff'),
       url('LANGIcons.ttf') format('truetype'),
       url('LANGIcons.otf') format('opentype');
  font-weight: normal;
  font-style: normal;
  font-display: block;
}

/* LANG Mono Font */
@font-face {
  font-family: 'LANG Mono';
  src: url('LANGMono.woff2') format('woff2'),
       url('LANGMono.woff') format('woff'),
       url('LANGMono.ttf') format('truetype'),
       url('LANGMono.otf') format('opentype');
  font-weight: normal;
  font-style: normal;
  font-display: swap;
}

/* Icon classes */
.lang-icon {
  font-family: 'LANG Icons' !important;
  font-style: normal;
  font-weight: normal;
  font-variant: normal;
  text-transform: none;
  line-height: 1;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

.lang-icon-logo:before { content: "\E000"; }
.lang-icon-lang:before { content: "\E001"; }
.lang-icon-build:before { content: "\E002"; }
.lang-icon-proc:before { content: "\E003"; }
.lang-icon-edit:before { content: "\E004"; }
.lang-icon-stor:before { content: "\E005"; }

/* Mono font classes */
.lang-mono {
  font-family: 'LANG Mono', 'Fira Code', monospace !important;
  font-variant-ligatures: contextual;
  font-feature-settings: "liga" 1, "calt" 1;
}

/* Ligature mapping for fallback */
.lang-ligature-langop:before { content: "\E100"; font-family: 'LANG Mono'; }
.lang-ligature-arrow:before { content: "\E101"; font-family: 'LANG Mono'; }
.lang-ligature-wave:before { content: "\E102"; font-family: 'LANG Mono'; }
.lang-ligature-fatarrow:before { content: "\E103"; font-family: 'LANG Mono'; }
.lang-ligature-pipe:before { content: "\E104"; font-family: 'LANG Mono'; }
EOF

echo "✅ Font generation script complete!"
echo "📁 Generated fonts should be in: priv/static/fonts/lang/"
ls -la priv/static/fonts/lang/*.{ttf,otf,woff,woff2} 2>/dev/null || echo "⚠️  No font files found yet"