#!/bin/bash
# Generate LANG fonts using svg2ttf approach

echo "🔤 Generating LANG fonts (OTF/TTF)..."

# Create directories
mkdir -p priv/static/fonts/lang/svg
mkdir -p priv/static/fonts/lang/build

# First, create individual SVG files for each icon
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

# Now use Docker with a more reliable font generation approach
docker run --rm \
  -v $(pwd)/priv/static/fonts/lang:/work \
  python:3.11-slim bash -c '
pip install fonttools svgpathtools defcon ufo2ft

cat > /tmp/generate_font.py << "SCRIPT"
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.misc.psCharStrings import T2CharString
from pathlib import Path
import xml.etree.ElementTree as ET
import re

# Font metadata
familyName = "LANG Icons"
styleName = "Regular"
version = "1.0"
unitsPerEm = 1000

# Create font builder
fb = FontBuilder(unitsPerEm, isTTF=True)

# Set font metadata
fb.setupGlyphOrder([".notdef", ".null", "logo", "lang", "build", "proc", "edit", "stor"])
fb.setupCharacterMap({
    0xE000: "logo",
    0xE001: "lang",
    0xE002: "build", 
    0xE003: "proc",
    0xE004: "edit",
    0xE005: "stor",
})

# Parse SVG paths to font outlines
def parse_svg_path(path_d):
    """Convert SVG path to coordinate list"""
    coords = []
    if not path_d:
        return coords
    
    # Simple SVG path parser for basic commands
    commands = re.findall(r"([MLQTCZz])([^MLQTCZz]*)", path_d)
    current_x, current_y = 0, 0
    
    for cmd, args in commands:
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*", args)]
        
        if cmd == "M":  # moveTo
            if len(nums) >= 2:
                current_x, current_y = nums[0], nums[1]
                coords.append(("moveTo", [(current_x, current_y)]))
        elif cmd == "L":  # lineTo
            if len(nums) >= 2:
                current_x, current_y = nums[0], nums[1]
                coords.append(("lineTo", [(current_x, current_y)]))
        elif cmd == "Q":  # quadratic curve
            if len(nums) >= 4:
                coords.append(("qCurveTo", [(nums[0], nums[1]), (nums[2], nums[3])]))
                current_x, current_y = nums[2], nums[3]
        elif cmd == "T":  # smooth quadratic curve
            if len(nums) >= 2:
                coords.append(("qCurveTo", [(nums[0], nums[1])]))
                current_x, current_y = nums[0], nums[1]
        elif cmd == "Z" or cmd == "z":  # closePath
            coords.append(("closePath", []))
    
    return coords

# Load glyphs from SVG files
glyphs = {}
svg_dir = Path("/work/svg")

# Default empty glyphs
for name in [".notdef", ".null"]:
    pen = T2CharStringPen(1000, None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((900, 700))
    pen.lineTo((900, 0))
    pen.closePath()
    glyphs[name] = pen.getCharString()

# Load icon glyphs from SVG files
icon_map = {
    "logo": "uE000-logo.svg",
    "lang": "uE001-lang.svg",
    "build": "uE002-build.svg",
    "proc": "uE003-proc.svg",
    "edit": "uE004-edit.svg",
    "stor": "uE005-stor.svg"
}

for glyph_name, svg_file in icon_map.items():
    svg_path = svg_dir / svg_file
    if svg_path.exists():
        tree = ET.parse(svg_path)
        root = tree.getroot()
        
        pen = T2CharStringPen(1000, None)
        
        # Process all paths and shapes in the SVG
        for elem in root.iter():
            if elem.tag.endswith("path"):
                d = elem.get("d", "")
                coords = parse_svg_path(d)
                for cmd, points in coords:
                    if cmd == "moveTo":
                        pen.moveTo(points[0])
                    elif cmd == "lineTo":
                        pen.lineTo(points[0])
                    elif cmd == "qCurveTo":
                        pen.qCurveTo(*points)
                    elif cmd == "closePath":
                        pen.closePath()
            elif elem.tag.endswith("rect"):
                x = float(elem.get("x", 0))
                y = float(elem.get("y", 0))
                w = float(elem.get("width", 0))
                h = float(elem.get("height", 0))
                pen.moveTo((x, y))
                pen.lineTo((x + w, y))
                pen.lineTo((x + w, y + h))
                pen.lineTo((x, y + h))
                pen.closePath()
            elif elem.tag.endswith("circle"):
                cx = float(elem.get("cx", 0))
                cy = float(elem.get("cy", 0))
                r = float(elem.get("r", 0))
                # Approximate circle with bezier curves
                k = 0.5522847498 * r
                pen.moveTo((cx + r, cy))
                pen.curveTo((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r))
                pen.curveTo((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy))
                pen.curveTo((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r))
                pen.curveTo((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy))
                pen.closePath()
            elif elem.tag.endswith("ellipse"):
                cx = float(elem.get("cx", 0))
                cy = float(elem.get("cy", 0))
                rx = float(elem.get("rx", 0))
                ry = float(elem.get("ry", 0))
                # Approximate ellipse
                kx = 0.5522847498 * rx
                ky = 0.5522847498 * ry
                pen.moveTo((cx + rx, cy))
                pen.curveTo((cx + rx, cy + ky), (cx + kx, cy + ry), (cx, cy + ry))
                pen.curveTo((cx - kx, cy + ry), (cx - rx, cy + ky), (cx - rx, cy))
                pen.curveTo((cx - rx, cy - ky), (cx - kx, cy - ry), (cx, cy - ry))
                pen.curveTo((cx + kx, cy - ry), (cx + rx, cy - ky), (cx + rx, cy))
                pen.closePath()
        
        glyphs[glyph_name] = pen.getCharString()
    else:
        # Fallback empty glyph
        pen = T2CharStringPen(1000, None)
        pen.moveTo((100, 100))
        pen.lineTo((900, 100))
        pen.lineTo((900, 900))
        pen.lineTo((100, 900))
        pen.closePath()
        glyphs[glyph_name] = pen.getCharString()

# Build the font
fb.setupCFF(
    psName=familyName.replace(" ", ""),
    charStrings=glyphs,
    fontInfo={"FullName": familyName}
)

fb.setupHorizontalMetrics({
    ".notdef": (1000, 100),
    ".null": (0, 0),
    "logo": (1000, 100),
    "lang": (1000, 100),
    "build": (1000, 100),
    "proc": (1000, 100),
    "edit": (1000, 100),
    "stor": (1000, 100),
})

fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({
    "familyName": familyName,
    "styleName": styleName,
    "psName": familyName.replace(" ", "") + "-" + styleName,
    "uniqueFontIdentifier": f"{familyName} {version}",
    "fullName": familyName,
    "version": f"Version {version}",
    "copyright": "Copyright (c) 2025 Kyozo Platform",
    "manufacturer": "Kyozo",
})

fb.setupOS2(
    sTypoAscender=800,
    sTypoDescender=-200,
    usWinAscent=800,
    usWinDescent=200,
)

fb.setupPost()

# Save fonts
font = fb.font
font.save("/work/LANGIcons.ttf")

# Convert to OTF
from fontTools.ttLib import TTFont
ttf = TTFont("/work/LANGIcons.ttf")
ttf.flavor = None
ttf.save("/work/LANGIcons.otf")

# Generate WOFF
ttf.flavor = "woff"
ttf.save("/work/LANGIcons.woff")

# Generate WOFF2
ttf.flavor = "woff2"
ttf.save("/work/LANGIcons.woff2")

print("✅ Font files generated successfully!")
SCRIPT

python /tmp/generate_font.py
'

echo "✅ LANG fonts generated!"
echo "📁 Output files:"
ls -la priv/static/fonts/lang/*.{ttf,otf,woff,woff2} 2>/dev/null || echo "Font generation may have failed"

# Update CSS to use the proper fonts
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

/* Sizes */
.lang-icon-xs { font-size: 0.75rem; }
.lang-icon-sm { font-size: 0.875rem; }
.lang-icon-base { font-size: 1rem; }
.lang-icon-lg { font-size: 1.25rem; }
.lang-icon-xl { font-size: 1.5rem; }
.lang-icon-2xl { font-size: 2rem; }
.lang-icon-3xl { font-size: 3rem; }

/* Colors */
.lang-icon-primary { color: #4a9eff; }
.lang-icon-secondary { color: #0066ff; }
.lang-icon-gradient {
  background: linear-gradient(45deg, #4a9eff, #0066ff);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
EOF