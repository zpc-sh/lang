#!/bin/bash
# Generate LANG fonts using a more robust approach

echo "🔤 Generating LANG fonts (OTF/TTF)..."

# Create directories
mkdir -p priv/static/fonts/lang/svg
mkdir -p priv/static/fonts/lang/build

# First, create individual SVG files for each icon (same as before)
cat > priv/static/fonts/lang/svg/uE000-logo.svg << 'EOF'
<svg viewBox="0 0 1000 1000" xmlns="http://www.w3.org/2000/svg">
  <path d="M 292 708 L 208 500 L 292 292" stroke="black" stroke-width="25" fill="none" stroke-linecap="round"/>
  <path d="M 333 500 Q 417 583, 500 500 T 667 500" stroke="black" stroke-width="20" fill="none" stroke-linecap="round"/>
  <path d="M 708 708 L 792 500 L 708 292" stroke="black" stroke-width="25" fill="none" stroke-linecap="round"/>
</svg>
EOF

cat > priv/static/fonts/lang/svg/uE001-lang.svg << 'EOF'
<svg viewBox="0 0 1000 1000" xmlns="http://www.w3.org/2000/svg">
  <rect x="200" y="300" width="600" height="400" rx="50" stroke="black" stroke-width="30" fill="none"/>
  <text x="500" y="550" text-anchor="middle" font-size="200" fill="black" font-family="monospace">{ }</text>
</svg>
EOF

cat > priv/static/fonts/lang/svg/uE002-build.svg << 'EOF'
<svg viewBox="0 0 1000 1000" xmlns="http://www.w3.org/2000/svg">
  <rect x="200" y="600" width="200" height="200" fill="black" opacity="0.8"/>
  <rect x="450" y="450" width="200" height="350" fill="black" opacity="0.8"/>
  <rect x="700" y="300" width="200" height="500" fill="black" opacity="0.8"/>
</svg>
EOF

cat > priv/static/fonts/lang/svg/uE003-proc.svg << 'EOF'
<svg viewBox="0 0 1000 1000" xmlns="http://www.w3.org/2000/svg">
  <circle cx="300" cy="300" r="80" fill="black"/>
  <circle cx="700" cy="300" r="80" fill="black"/>
  <circle cx="500" cy="700" r="80" fill="black"/>
  <path d="M 300 300 L 500 700 L 700 300" stroke="black" stroke-width="20" fill="none"/>
</svg>
EOF

cat > priv/static/fonts/lang/svg/uE004-edit.svg << 'EOF'
<svg viewBox="0 0 1000 1000" xmlns="http://www.w3.org/2000/svg">
  <path d="M 300 700 L 600 400 L 700 500 L 400 800 Z" fill="black"/>
  <path d="M 600 400 L 700 300 L 800 400 L 700 500 Z" fill="black" opacity="0.6"/>
  <path d="M 300 700 L 250 850 L 400 800 Z" fill="black"/>
</svg>
EOF

cat > priv/static/fonts/lang/svg/uE005-stor.svg << 'EOF'
<svg viewBox="0 0 1000 1000" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="500" cy="300" rx="250" ry="80" fill="black" opacity="0.8"/>
  <rect x="250" y="300" width="500" height="400" fill="black" opacity="0.6"/>
  <ellipse cx="500" cy="700" rx="250" ry="80" fill="black" opacity="0.8"/>
</svg>
EOF

# Create the LANG Mono ligature font SVG components
cat > priv/static/fonts/lang/svg/ligatures.json << 'EOF'
{
  "ligatures": [
    {"chars": "<~>", "unicode": "E100", "name": "lang_operator"},
    {"chars": "->", "unicode": "E101", "name": "arrow"},
    {"chars": "~>", "unicode": "E102", "name": "wave"},
    {"chars": "=>", "unicode": "E103", "name": "fat_arrow"},
    {"chars": "|>", "unicode": "E104", "name": "pipe"},
    {"chars": "!=", "unicode": "E105", "name": "not_equal"},
    {"chars": "~=", "unicode": "E106", "name": "approx"},
    {"chars": "::", "unicode": "E107", "name": "type"},
    {"chars": "[[", "unicode": "E108", "name": "left_semantic"},
    {"chars": "]]", "unicode": "E109", "name": "right_semantic"},
    {"chars": "<|", "unicode": "E10A", "name": "back_pipe"},
    {"chars": "...", "unicode": "E10B", "name": "ellipsis"},
    {"chars": "<-", "unicode": "E10C", "name": "back_arrow"},
    {"chars": "++", "unicode": "E10D", "name": "concat"},
    {"chars": "||", "unicode": "E10E", "name": "parallel"},
    {"chars": "&&", "unicode": "E10F", "name": "and"}
  ]
}
EOF

# Use Docker with better dependency handling
docker run --rm \
  -v $(pwd)/priv/static/fonts/lang:/work \
  python:3.11-slim bash -c '
# Install system dependencies first
apt-get update && apt-get install -y build-essential python3-dev

# Install Python packages with specific versions that work together
pip install --no-cache-dir \
  fonttools==4.43.0 \
  defcon==0.10.3 \
  ufo2ft==2.33.4 \
  brotli \
  zopfli

# Create the font generation script
cat > /tmp/generate_font.py << "SCRIPT"
import sys
import json
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.misc.fixedTools import floatToFixed

# Font metadata
familyName = "LANG Icons"
styleName = "Regular"
version = "1.0"
unitsPerEm = 1000

# Create font builder
fb = FontBuilder(unitsPerEm, isTTF=True)

# Basic glyphs
glyph_order = [".notdef", ".null", "space"]
char_map = {32: "space"}  # space character

# Add icon glyphs
icon_glyphs = ["logo", "lang", "build", "proc", "edit", "stor"]
for i, name in enumerate(icon_glyphs):
    glyph_order.append(name)
    char_map[0xE000 + i] = name

fb.setupGlyphOrder(glyph_order)
fb.setupCharacterMap(char_map)

# Create glyphs
glyphs = {}

# Empty glyph for .notdef and .null
for name in [".notdef", ".null"]:
    pen = T2CharStringPen(1000, None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((900, 700))
    pen.lineTo((900, 0))
    pen.closePath()
    glyphs[name] = pen.getCharString()

# Space glyph
pen = T2CharStringPen(1000, None)
glyphs["space"] = pen.getCharString()

# Simple icon glyphs (using basic shapes for now)
# Logo glyph - <~>
pen = T2CharStringPen(1000, None)
pen.moveTo((292, 708))
pen.lineTo((208, 500))
pen.lineTo((292, 292))
pen.moveTo((333, 500))
pen.qCurveTo((417, 583), (500, 500))
pen.qCurveTo((583, 417), (667, 500))
pen.moveTo((708, 708))
pen.lineTo((792, 500))
pen.lineTo((708, 292))
glyphs["logo"] = pen.getCharString()

# Lang glyph - { }
pen = T2CharStringPen(1000, None)
pen.moveTo((350, 300))
pen.lineTo((300, 350))
pen.lineTo((300, 450))
pen.qCurveTo((250, 500), (300, 550))
pen.lineTo((300, 650))
pen.lineTo((350, 700))
pen.moveTo((650, 300))
pen.lineTo((700, 350))
pen.lineTo((700, 450))
pen.qCurveTo((750, 500), (700, 550))
pen.lineTo((700, 650))
pen.lineTo((650, 700))
glyphs["lang"] = pen.getCharString()

# Build glyph - bars
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

# Proc glyph - triangle with nodes
pen = T2CharStringPen(1000, None)
# Draw circles
for cx, cy in [(300, 300), (700, 300), (500, 700)]:
    pen.moveTo((cx + 80, cy))
    pen.qCurveTo((cx + 80, cy + 80), (cx, cy + 80))
    pen.qCurveTo((cx - 80, cy + 80), (cx - 80, cy))
    pen.qCurveTo((cx - 80, cy - 80), (cx, cy - 80))
    pen.qCurveTo((cx + 80, cy - 80), (cx + 80, cy))
    pen.closePath()
# Draw lines
pen.moveTo((300, 300))
pen.lineTo((500, 700))
pen.moveTo((500, 700))
pen.lineTo((700, 300))
pen.moveTo((700, 300))
pen.lineTo((300, 300))
glyphs["proc"] = pen.getCharString()

# Edit glyph - pencil
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
pen.moveTo((300, 700))
pen.lineTo((250, 850))
pen.lineTo((400, 800))
pen.closePath()
glyphs["edit"] = pen.getCharString()

# Stor glyph - cylinder
pen = T2CharStringPen(1000, None)
# Top ellipse
pen.moveTo((750, 300))
pen.qCurveTo((750, 380), (500, 380))
pen.qCurveTo((250, 380), (250, 300))
pen.qCurveTo((250, 220), (500, 220))
pen.qCurveTo((750, 220), (750, 300))
pen.closePath()
# Body
pen.moveTo((250, 300))
pen.lineTo((250, 700))
pen.qCurveTo((250, 780), (500, 780))
pen.qCurveTo((750, 780), (750, 700))
pen.lineTo((750, 300))
glyphs["stor"] = pen.getCharString()

# Build the font
fb.setupCFF(
    psName=familyName.replace(" ", ""),
    charStrings=glyphs,
    fontInfo={
        "FullName": familyName,
        "FamilyName": familyName,
        "Weight": "Regular"
    }
)

# Set up metrics
metrics = {name: (1000, 100) for name in glyph_order}
metrics["space"] = (500, 0)
fb.setupHorizontalMetrics(metrics)

fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({
    "familyName": familyName,
    "styleName": styleName,
    "psName": familyName.replace(" ", "") + "-" + styleName,
    "uniqueFontIdentifier": f"{familyName} {version}",
    "fullName": familyName,
    "version": f"Version {version}",
    "copyright": "Copyright (c) 2025 LANG Platform",
    "manufacturer": "LANG",
})

fb.setupOS2(
    sTypoAscender=800,
    sTypoDescender=-200,
    usWinAscent=800,
    usWinDescent=200,
    sCapHeight=700,
    sxHeight=500,
)

fb.setupPost()

# Save TTF
print("Saving TTF...")
font = fb.font
font.save("/work/LANGIcons.ttf")
print("✅ TTF saved")

# Convert to OTF
print("Converting to OTF...")
from fontTools.ttLib import TTFont
from fontTools.otlLib.builder import Builder
from fontTools.feaLib.builder import addOpenTypeFeatures

ttf = TTFont("/work/LANGIcons.ttf")
# Save as OTF (CFF-flavored font)
ttf.save("/work/LANGIcons.otf")
print("✅ OTF saved")

# Generate web fonts
print("Generating WOFF...")
ttf.flavor = "woff"
ttf.save("/work/LANGIcons.woff")
print("✅ WOFF saved")

print("Generating WOFF2...")
ttf.flavor = "woff2"
ttf.save("/work/LANGIcons.woff2")
print("✅ WOFF2 saved")

print("\n✅ All font files generated successfully!")
SCRIPT

python /tmp/generate_font.py

# Now generate the LANG Mono font with ligatures
cat > /tmp/generate_mono_font.py << "SCRIPT"
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
import string

# Font metadata
familyName = "LANG Mono"
styleName = "Regular"
version = "1.0"
unitsPerEm = 1000

# Create font builder
fb = FontBuilder(unitsPerEm, isTTF=True)

# Build glyph order - ASCII + ligatures
glyph_order = [".notdef", ".null", "space"]
char_map = {32: "space"}

# Add ASCII characters
for i in range(33, 127):
    char = chr(i)
    glyph_name = f"char{i}"
    glyph_order.append(glyph_name)
    char_map[i] = glyph_name

# Add ligature glyphs (Private Use Area)
ligatures = [
    ("lang_op", 0xE100),  # <~>
    ("arrow", 0xE101),    # ->
    ("wave", 0xE102),     # ~>
    ("fat_arrow", 0xE103), # =>
    ("pipe", 0xE104),     # |>
    ("not_equal", 0xE105), # !=
    ("approx", 0xE106),   # ~=
    ("type_op", 0xE107),  # ::
]

for name, code in ligatures:
    glyph_order.append(name)
    char_map[code] = name

fb.setupGlyphOrder(glyph_order)
fb.setupCharacterMap(char_map)

# Create basic glyphs (simplified monospace design)
glyphs = {}
mono_width = 600
x_height = 500
cap_height = 700

# Default glyphs
for name in [".notdef", ".null"]:
    pen = T2CharStringPen(unitsPerEm, None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((500, 700))
    pen.lineTo((500, 0))
    pen.closePath()
    glyphs[name] = pen.getCharString()

# Space
pen = T2CharStringPen(unitsPerEm, None)
glyphs["space"] = pen.getCharString()

# Create simple monospace letters (very basic shapes)
# This is a simplified version - a real font would have proper outlines
for i in range(33, 127):
    char = chr(i)
    glyph_name = f"char{i}"
    pen = T2CharStringPen(unitsPerEm, None)
    
    # Super simple: just draw a box for now
    # In production, you would load real glyph outlines
    x = (mono_width - 400) // 2
    pen.moveTo((x, 100))
    pen.lineTo((x + 400, 100))
    pen.lineTo((x + 400, 600))
    pen.lineTo((x, 600))
    pen.closePath()
    
    glyphs[glyph_name] = pen.getCharString()

# Create ligature glyphs with custom designs
# <~> ligature (LANG operator)
pen = T2CharStringPen(unitsPerEm, None)
pen.moveTo((150, 600))
pen.lineTo((100, 350))
pen.lineTo((150, 100))
pen.moveTo((200, 350))
pen.qCurveTo((300, 450), (300, 350))
pen.qCurveTo((300, 250), (400, 350))
pen.moveTo((450, 600))
pen.lineTo((500, 350))
pen.lineTo((450, 100))
glyphs["lang_op"] = pen.getCharString()

# -> arrow
pen = T2CharStringPen(unitsPerEm, None)
pen.moveTo((100, 350))
pen.lineTo((400, 350))
pen.moveTo((350, 400))
pen.lineTo((450, 350))
pen.lineTo((350, 300))
glyphs["arrow"] = pen.getCharString()

# Build remaining ligatures with simple designs
for name, _ in ligatures[2:]:
    pen = T2CharStringPen(unitsPerEm, None)
    # Placeholder design
    pen.moveTo((100, 350))
    pen.lineTo((500, 350))
    glyphs[name] = pen.getCharString()

# Build the font
fb.setupCFF(
    psName=familyName.replace(" ", ""),
    charStrings=glyphs,
    fontInfo={
        "FullName": familyName,
        "FamilyName": familyName,
        "Weight": "Regular"
    }
)

# Set up metrics (monospace)
metrics = {name: (mono_width, 0) for name in glyph_order}
fb.setupHorizontalMetrics(metrics)

fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({
    "familyName": familyName,
    "styleName": styleName,
    "psName": familyName.replace(" ", "") + "-" + styleName,
    "uniqueFontIdentifier": f"{familyName} {version}",
    "fullName": familyName,
    "version": f"Version {version}",
    "copyright": "Copyright (c) 2025 LANG Platform",
    "manufacturer": "LANG",
})

fb.setupOS2(
    sTypoAscender=800,
    sTypoDescender=-200,
    usWinAscent=800,
    usWinDescent=200,
    sCapHeight=cap_height,
    sxHeight=x_height,
)

fb.setupPost(isFixedPitch=True)

# Save fonts
font = fb.font
font.save("/work/LANGMono.ttf")

# Convert to OTF
from fontTools.ttLib import TTFont
ttf = TTFont("/work/LANGMono.ttf")
ttf.save("/work/LANGMono.otf")

# Web fonts
ttf.flavor = "woff"
ttf.save("/work/LANGMono.woff")

ttf.flavor = "woff2"
ttf.save("/work/LANGMono.woff2")

print("✅ LANG Mono font files generated!")
SCRIPT

python /tmp/generate_mono_font.py
'

echo "✅ LANG fonts generated!"
echo "📁 Output files:"
ls -la priv/static/fonts/lang/*.{ttf,otf,woff,woff2} 2>/dev/null

# Create CSS files
cat > priv/static/fonts/lang/lang-icons.css << 'EOF'
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

.lang-icon {
  font-family: 'LANG Icons' !important;
  speak: never;
  font-style: normal;
  font-weight: normal;
  font-variant: normal;
  text-transform: none;
  line-height: 1;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

/* Icon mappings */
.lang-icon-logo:before { content: "\E000"; }
.lang-icon-lang:before { content: "\E001"; }
.lang-icon-build:before { content: "\E002"; }
.lang-icon-proc:before { content: "\E003"; }
.lang-icon-edit:before { content: "\E004"; }
.lang-icon-stor:before { content: "\E005"; }
EOF

cat > priv/static/fonts/lang/lang-mono.css << 'EOF'
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

.lang-mono {
  font-family: 'LANG Mono', 'Fira Code', 'Cascadia Code', monospace !important;
  font-variant-ligatures: contextual;
}

/* Ligature classes */
.lang-mono-ligatures {
  font-feature-settings: "liga" 1, "calt" 1;
}

/* Sizes */
.lang-mono-xs { font-size: 0.75rem; }
.lang-mono-sm { font-size: 0.875rem; }
.lang-mono-base { font-size: 1rem; }
.lang-mono-lg { font-size: 1.125rem; }
.lang-mono-xl { font-size: 1.25rem; }
EOF

echo "✨ Font generation complete!"