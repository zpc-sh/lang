#!/usr/bin/env python3
"""
Generate LANG fonts (TTF/OTF) - Simplified version
Creates icon fonts that can be used in web applications
"""

import os
import sys
import subprocess

# Install dependencies if needed
try:
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    from fontTools.ttLib import TTFont
    print("✅ fonttools already installed")
except ImportError:
    print("📦 Installing fonttools...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "fonttools", "brotli"])
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    from fontTools.ttLib import TTFont

def create_simple_icon_font():
    """Create a simple icon font with basic shapes"""
    print("\n🎨 Creating LANG Icons font (simplified)...")
    
    # Font metadata
    familyName = "LANG Icons"
    styleName = "Regular"
    version = "1.0"
    unitsPerEm = 1000
    
    # Create font builder for TTF
    fb = FontBuilder(unitsPerEm, isTTF=True)
    
    # Set up glyphs
    glyph_order = [".notdef", ".null", "space", "logo", "lang", "build", "proc", "edit", "stor"]
    char_map = {
        32: "space",
        0xE000: "logo",     # <~>
        0xE001: "lang",     # { }
        0xE002: "build",    # bars
        0xE003: "proc",     # triangle
        0xE004: "edit",     # pencil
        0xE005: "stor",     # cylinder
    }
    
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(char_map)
    
    # Create glyphs using TTGlyphPen
    glyphs = {}
    
    # Default glyph (.notdef)
    pen = TTGlyphPen(None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((900, 700))
    pen.lineTo((900, 0))
    pen.closePath()
    glyphs[".notdef"] = pen.glyph()
    
    # Null glyph
    pen = TTGlyphPen(None)
    glyphs[".null"] = pen.glyph()
    
    # Space glyph
    pen = TTGlyphPen(None)
    glyphs["space"] = pen.glyph()
    
    # Logo <~> - simplified
    pen = TTGlyphPen(None)
    # Left angle
    pen.moveTo((250, 650))
    pen.lineTo((150, 500))
    pen.lineTo((250, 350))
    pen.lineTo((300, 400))
    pen.lineTo((225, 500))
    pen.lineTo((300, 600))
    pen.closePath()
    # Wave
    pen.moveTo((350, 500))
    pen.qCurveTo((450, 600), (550, 500))
    pen.qCurveTo((650, 400), (750, 500))
    pen.lineTo((750, 450))
    pen.qCurveTo((650, 350), (550, 450))
    pen.qCurveTo((450, 550), (350, 450))
    pen.closePath()
    # Right angle
    pen.moveTo((750, 350))
    pen.lineTo((850, 500))
    pen.lineTo((750, 650))
    pen.lineTo((700, 600))
    pen.lineTo((775, 500))
    pen.lineTo((700, 400))
    pen.closePath()
    glyphs["logo"] = pen.glyph()
    
    # Lang { } - curly braces
    pen = TTGlyphPen(None)
    # Left brace
    pen.moveTo((300, 300))
    pen.lineTo((250, 350))
    pen.lineTo((250, 450))
    pen.lineTo((200, 500))
    pen.lineTo((250, 550))
    pen.lineTo((250, 650))
    pen.lineTo((300, 700))
    pen.lineTo((350, 650))
    pen.lineTo((350, 550))
    pen.lineTo((300, 500))
    pen.lineTo((350, 450))
    pen.lineTo((350, 350))
    pen.closePath()
    # Right brace
    pen.moveTo((700, 300))
    pen.lineTo((750, 350))
    pen.lineTo((750, 450))
    pen.lineTo((800, 500))
    pen.lineTo((750, 550))
    pen.lineTo((750, 650))
    pen.lineTo((700, 700))
    pen.lineTo((650, 650))
    pen.lineTo((650, 550))
    pen.lineTo((700, 500))
    pen.lineTo((650, 450))
    pen.lineTo((650, 350))
    pen.closePath()
    glyphs["lang"] = pen.glyph()
    
    # Build - bar chart
    pen = TTGlyphPen(None)
    # Bar 1
    pen.moveTo((200, 600))
    pen.lineTo((350, 600))
    pen.lineTo((350, 800))
    pen.lineTo((200, 800))
    pen.closePath()
    # Bar 2
    pen.moveTo((425, 450))
    pen.lineTo((575, 450))
    pen.lineTo((575, 800))
    pen.lineTo((425, 800))
    pen.closePath()
    # Bar 3
    pen.moveTo((650, 300))
    pen.lineTo((800, 300))
    pen.lineTo((800, 800))
    pen.lineTo((650, 800))
    pen.closePath()
    glyphs["build"] = pen.glyph()
    
    # Proc - network nodes
    pen = TTGlyphPen(None)
    # Three circles as squares for simplicity
    # Top left
    pen.moveTo((250, 250))
    pen.lineTo((350, 250))
    pen.lineTo((350, 350))
    pen.lineTo((250, 350))
    pen.closePath()
    # Top right
    pen.moveTo((650, 250))
    pen.lineTo((750, 250))
    pen.lineTo((750, 350))
    pen.lineTo((650, 350))
    pen.closePath()
    # Bottom
    pen.moveTo((450, 650))
    pen.lineTo((550, 650))
    pen.lineTo((550, 750))
    pen.lineTo((450, 750))
    pen.closePath()
    # Connect with lines
    pen.moveTo((300, 350))
    pen.lineTo((500, 650))
    pen.lineTo((520, 640))
    pen.lineTo((320, 340))
    pen.closePath()
    pen.moveTo((700, 350))
    pen.lineTo((500, 650))
    pen.lineTo((480, 640))
    pen.lineTo((680, 340))
    pen.closePath()
    glyphs["proc"] = pen.glyph()
    
    # Edit - pencil shape
    pen = TTGlyphPen(None)
    pen.moveTo((300, 700))
    pen.lineTo((600, 400))
    pen.lineTo((700, 500))
    pen.lineTo((400, 800))
    pen.closePath()
    # Tip
    pen.moveTo((600, 400))
    pen.lineTo((650, 350))
    pen.lineTo((750, 450))
    pen.lineTo((700, 500))
    pen.closePath()
    glyphs["edit"] = pen.glyph()
    
    # Stor - database cylinder
    pen = TTGlyphPen(None)
    # Top oval as polygon
    pen.moveTo((250, 300))
    pen.lineTo((350, 250))
    pen.lineTo((650, 250))
    pen.lineTo((750, 300))
    pen.lineTo((650, 350))
    pen.lineTo((350, 350))
    pen.closePath()
    # Body
    pen.moveTo((250, 300))
    pen.lineTo((250, 700))
    pen.lineTo((350, 750))
    pen.lineTo((650, 750))
    pen.lineTo((750, 700))
    pen.lineTo((750, 300))
    pen.closePath()  # Added missing closePath
    glyphs["stor"] = pen.glyph()
    
    # Set up the glyf table
    fb.setupGlyf(glyphs)
    
    # Set up metrics
    metrics = {name: (1000, 100) for name in glyph_order}
    metrics["space"] = (500, 0)
    fb.setupHorizontalMetrics(metrics)
    
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    
    # Name table (only standard fields)
    fb.setupNameTable({
        "familyName": familyName,
        "styleName": styleName,
        "fullName": f"{familyName} {styleName}",
        "psName": f"{familyName.replace(' ', '')}-{styleName}",
        "version": f"Version {version}",
        "copyright": "Copyright (c) 2025 LANG Platform",
        "manufacturer": "LANG",
    })
    
    # OS/2 table
    fb.setupOS2(
        sTypoAscender=800,
        sTypoDescender=-200,
        usWinAscent=800,
        usWinDescent=200,
        sCapHeight=700,
        sxHeight=500,
    )
    
    # Post table
    fb.setupPost()
    
    # Build the font
    font = fb.font
    
    # Save files
    output_dir = "priv/static/fonts/lang"
    os.makedirs(output_dir, exist_ok=True)
    
    print("💾 Saving TTF...")
    ttf_path = os.path.join(output_dir, "LANGIcons.ttf")
    font.save(ttf_path)
    
    print("💾 Converting to OTF...")
    # For OTF, we need to convert to CFF outline
    otf = TTFont(ttf_path)
    otf_path = os.path.join(output_dir, "LANGIcons.otf")
    otf.save(otf_path)
    
    print("💾 Generating WOFF...")
    otf.flavor = "woff"
    woff_path = os.path.join(output_dir, "LANGIcons.woff")
    otf.save(woff_path)
    
    print("💾 Generating WOFF2...")
    otf.flavor = "woff2"
    woff2_path = os.path.join(output_dir, "LANGIcons.woff2")
    otf.save(woff2_path)
    
    print("✅ LANG Icons font complete!")
    
    # Also create CSS file
    css_content = """/* LANG Icons Font */
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
.lang-icon-logo:before { content: "\\E000"; }
.lang-icon-lang:before { content: "\\E001"; }
.lang-icon-build:before { content: "\\E002"; }
.lang-icon-proc:before { content: "\\E003"; }
.lang-icon-edit:before { content: "\\E004"; }
.lang-icon-stor:before { content: "\\E005"; }

/* Sizes */
.lang-icon-xs { font-size: 0.75rem; }
.lang-icon-sm { font-size: 0.875rem; }
.lang-icon-base { font-size: 1rem; }
.lang-icon-lg { font-size: 1.25rem; }
.lang-icon-xl { font-size: 1.5rem; }
.lang-icon-2xl { font-size: 2rem; }
.lang-icon-3xl { font-size: 3rem; }
"""
    
    css_path = os.path.join(output_dir, "lang-icons.css")
    with open(css_path, 'w') as f:
        f.write(css_content)
    print("✅ CSS file created!")
    
    return True

def main():
    """Main function"""
    print("🚀 LANG Font Generator (Simplified)")
    print("=" * 50)
    
    try:
        # Create icon font
        if not create_simple_icon_font():
            print("❌ Failed to create icon font")
            return 1
        
        # List generated files
        output_dir = "priv/static/fonts/lang"
        print(f"\n📁 Generated files in {output_dir}:")
        for file in sorted(os.listdir(output_dir)):
            if file.endswith(('.ttf', '.otf', '.woff', '.woff2', '.css')):
                size = os.path.getsize(os.path.join(output_dir, file))
                print(f"   ✅ {file} ({size:,} bytes)")
        
        print("\n🎉 Font generation complete!")
        print("\n💡 To use the fonts:")
        print("   1. Include the CSS: <link href='/fonts/lang/lang-icons.css' rel='stylesheet'>")
        print("   2. Use icon classes: <i class='lang-icon lang-icon-logo'></i>")
        print("\n📝 Note: For the LANG Mono font with ligatures, use existing fonts like")
        print("   Fira Code or JetBrains Mono with custom CSS for ligature mappings.")
        
        return 0
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())