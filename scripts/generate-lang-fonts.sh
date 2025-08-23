#!/bin/bash
# Generate LANG fonts in OTF and TTF formats

echo "🔤 Generating LANG fonts (OTF/TTF)..."

# Create output directory
mkdir -p priv/static/fonts/lang

# Run FontForge in Docker to create the fonts
docker run --rm \
  -v $(pwd)/priv/static/fonts:/output \
  nfqlt/fontforge sh -c '
cat > /tmp/create-lang-font.py << "EOF"
import fontforge
import psMat

# Create a new font
font = fontforge.font()
font.fontname = "LANGIcons"
font.fullname = "LANG Icons"
font.familyname = "LANG Icons"
font.copyright = "Copyright (c) 2025 Kyozo Platform"
font.version = "1.0"

# Set font metrics
font.ascent = 800
font.descent = 200
font.em = 1000

# Create glyphs for each icon
# Unicode private use area starts at E000

# LANG Logo (E000)
glyph = font.createChar(0xE000, "lang-logo")
pen = glyph.glyphPen()
# Left bracket
pen.moveTo((350, 650))
pen.lineTo((250, 400))
pen.lineTo((350, 150))
# Center wave
pen.moveTo((400, 400))
pen.qCurveTo((500, 480), (600, 400))
pen.qCurveTo((700, 320), (800, 400))
# Right bracket
pen.moveTo((850, 650))
pen.lineTo((950, 400))
pen.lineTo((850, 150))
pen = None
glyph.width = 1200

# Lang Service Icon (E001)
glyph = font.createChar(0xE001, "lang-service")
pen = glyph.glyphPen()
# Document rectangle
pen.moveTo((200, 300))
pen.lineTo((200, 700))
pen.lineTo((800, 700))
pen.lineTo((800, 300))
pen.lineTo((200, 300))
pen.closePath()
# Braces inside
pen.moveTo((400, 500))
pen.lineTo((350, 500))
pen.qCurveTo((300, 500), (300, 450))
pen.qCurveTo((300, 400), (350, 400))
pen.moveTo((600, 500))
pen.lineTo((650, 500))
pen.qCurveTo((700, 500), (700, 450))
pen.qCurveTo((700, 400), (650, 400))
pen = None
glyph.width = 1000

# Build Service Icon (E002)
glyph = font.createChar(0xE002, "build-service")
pen = glyph.glyphPen()
# First block
pen.moveTo((200, 200))
pen.lineTo((200, 400))
pen.lineTo((400, 400))
pen.lineTo((400, 200))
pen.closePath()
# Second block
pen.moveTo((450, 350))
pen.lineTo((450, 700))
pen.lineTo((650, 700))
pen.lineTo((650, 350))
pen.closePath()
# Third block
pen.moveTo((700, 500))
pen.lineTo((700, 1000))
pen.lineTo((900, 1000))
pen.lineTo((900, 500))
pen.closePath()
pen = None
glyph.width = 1100

# Proc Service Icon (E003)
glyph = font.createChar(0xE003, "proc-service")
pen = glyph.glyphPen()
# Top left node
pen.moveTo((300, 700))
pen.curveTo((380, 700), (380, 700), (380, 620))
pen.curveTo((380, 540), (380, 540), (300, 540))
pen.curveTo((220, 540), (220, 540), (220, 620))
pen.curveTo((220, 700), (220, 700), (300, 700))
pen.closePath()
# Top right node
pen.moveTo((700, 700))
pen.curveTo((780, 700), (780, 700), (780, 620))
pen.curveTo((780, 540), (780, 540), (700, 540))
pen.curveTo((620, 540), (620, 540), (620, 620))
pen.curveTo((620, 700), (620, 700), (700, 700))
pen.closePath()
# Bottom node
pen.moveTo((500, 300))
pen.curveTo((580, 300), (580, 300), (580, 220))
pen.curveTo((580, 140), (580, 140), (500, 140))
pen.curveTo((420, 140), (420, 140), (420, 220))
pen.curveTo((420, 300), (420, 300), (500, 300))
pen.closePath()
# Connections
pen.moveTo((300, 620))
pen.lineTo((500, 220))
pen.moveTo((500, 220))
pen.lineTo((700, 620))
pen = None
glyph.width = 1000

# Edit Service Icon (E004)
glyph = font.createChar(0xE004, "edit-service")
pen = glyph.glyphPen()
# Pencil body
pen.moveTo((300, 300))
pen.lineTo((600, 600))
pen.lineTo((700, 500))
pen.lineTo((400, 200))
pen.closePath()
# Pencil tip
pen.moveTo((600, 600))
pen.lineTo((800, 800))
pen.lineTo((700, 700))
pen.lineTo((700, 500))
pen.closePath()
# Pencil point
pen.moveTo((300, 300))
pen.lineTo((250, 150))
pen.lineTo((400, 200))
pen.closePath()
pen = None
glyph.width = 1000

# Stor Service Icon (E005)
glyph = font.createChar(0xE005, "stor-service")
pen = glyph.glyphPen()
# Top ellipse
pen.moveTo((250, 700))
pen.curveTo((250, 780), (370, 820), (500, 820))
pen.curveTo((630, 820), (750, 780), (750, 700))
pen.curveTo((750, 620), (630, 580), (500, 580))
pen.curveTo((370, 580), (250, 620), (250, 700))
pen.closePath()
# Cylinder body
pen.moveTo((250, 700))
pen.lineTo((250, 300))
pen.moveTo((750, 700))
pen.lineTo((750, 300))
# Bottom ellipse
pen.moveTo((250, 300))
pen.curveTo((250, 380), (370, 420), (500, 420))
pen.curveTo((630, 420), (750, 380), (750, 300))
pen.curveTo((750, 220), (630, 180), (500, 180))
pen.curveTo((370, 180), (250, 220), (250, 300))
pen.closePath()
pen = None
glyph.width = 1000

# Add regular ASCII mappings for convenience
# Map L to LANG logo
glyph = font.createChar(ord("L"), "L")
glyph.addReference("lang-logo", psMat.identity())
glyph.width = 1200

# Generate the fonts
font.generate("/output/LANGIcons.otf")
font.generate("/output/LANGIcons.ttf")
font.generate("/output/LANGIcons.woff")
font.generate("/output/LANGIcons.woff2")

# Also generate an SVG font for reference
font.generate("/output/LANGIcons.svg")

print("✅ Font files generated successfully!")
EOF

python /tmp/create-lang-font.py
'

# Create CSS file for the font
cat > priv/static/fonts/lang/lang-icons-font.css << 'EOF'
@font-face {
  font-family: 'LANG Icons';
  src: url('LANGIcons.woff2') format('woff2'),
       url('LANGIcons.woff') format('woff'),
       url('LANGIcons.ttf') format('truetype'),
       url('LANGIcons.otf') format('opentype'),
       url('LANGIcons.svg#LANGIcons') format('svg');
  font-weight: normal;
  font-style: normal;
}

.lang-font {
  font-family: 'LANG Icons' !important;
  speak: none;
  font-style: normal;
  font-weight: normal;
  font-variant: normal;
  text-transform: none;
  line-height: 1;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

/* Icon mappings */
.lang-font-logo:before { content: "\E000"; }
.lang-font-lang:before { content: "\E001"; }
.lang-font-build:before { content: "\E002"; }
.lang-font-proc:before { content: "\E003"; }
.lang-font-edit:before { content: "\E004"; }
.lang-font-stor:before { content: "\E005"; }

/* Convenience: type "L" to get logo */
.lang-font-L:before { content: "L"; }

/* Sizes */
.lang-font-xs { font-size: 0.75rem; }
.lang-font-sm { font-size: 0.875rem; }
.lang-font-base { font-size: 1rem; }
.lang-font-lg { font-size: 1.25rem; }
.lang-font-xl { font-size: 1.5rem; }
.lang-font-2xl { font-size: 2rem; }
.lang-font-3xl { font-size: 3rem; }
EOF

# Create demo HTML
cat > priv/static/fonts/lang/demo.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>LANG Icons Font Demo</title>
  <link rel="stylesheet" href="lang-icons-font.css">
  <style>
    body {
      font-family: system-ui, sans-serif;
      background: #0a0a0a;
      color: white;
      padding: 2rem;
    }
    .demo-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 2rem;
      margin: 2rem 0;
    }
    .icon-demo {
      text-align: center;
      padding: 1rem;
      background: #1a1a1a;
      border-radius: 8px;
    }
    .icon-preview {
      font-size: 3rem;
      background: linear-gradient(45deg, #4a9eff, #0066ff);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 0.5rem;
    }
    .icon-code {
      font-family: monospace;
      font-size: 0.875rem;
      color: #666;
    }
  </style>
</head>
<body>
  <h1>LANG Icons Font</h1>
  <p>True font files (OTF/TTF/WOFF/WOFF2) for the Kyozo platform</p>

  <div class="demo-grid">
    <div class="icon-demo">
      <div class="icon-preview">
        <i class="lang-font lang-font-logo"></i>
      </div>
      <div>LANG Logo</div>
      <div class="icon-code">\E000</div>
    </div>

    <div class="icon-demo">
      <div class="icon-preview">
        <i class="lang-font lang-font-lang"></i>
      </div>
      <div>Lang Service</div>
      <div class="icon-code">\E001</div>
    </div>

    <div class="icon-demo">
      <div class="icon-preview">
        <i class="lang-font lang-font-build"></i>
      </div>
      <div>Build Service</div>
      <div class="icon-code">\E002</div>
    </div>

    <div class="icon-demo">
      <div class="icon-preview">
        <i class="lang-font lang-font-proc"></i>
      </div>
      <div>Proc Service</div>
      <div class="icon-code">\E003</div>
    </div>

    <div class="icon-demo">
      <div class="icon-preview">
        <i class="lang-font lang-font-edit"></i>
      </div>
      <div>Edit Service</div>
      <div class="icon-code">\E004</div>
    </div>

    <div class="icon-demo">
      <div class="icon-preview">
        <i class="lang-font lang-font-stor"></i>
      </div>
      <div>Stor Service</div>
      <div class="icon-code">\E005</div>
    </div>
  </div>

  <h2>Usage</h2>
  <pre style="background: #1a1a1a; padding: 1rem; border-radius: 4px;">
&lt;!-- Include the CSS --&gt;
&lt;link rel="stylesheet" href="lang-icons-font.css"&gt;

&lt;!-- Use the icons --&gt;
&lt;i class="lang-font lang-font-logo lang-font-2xl"&gt;&lt;/i&gt;
&lt;i class="lang-font lang-font-proc"&gt;&lt;/i&gt;

&lt;!-- Or type "L" for the logo --&gt;
&lt;span class="lang-font lang-font-3xl"&gt;L&lt;/span&gt;
  </pre>
</body>
</html>
EOF

echo "✅ LANG fonts generated!"
echo "📁 Output files:"
ls -la priv/static/fonts/lang/
