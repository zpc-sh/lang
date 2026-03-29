# Kyozo Visual Identity Specification
## Icon and Font Standards v1.0

### Core Logo

The LANG logo represents universal text flow and intelligence:

```svg
<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  <!-- Left bracket: Input -->
  <path d="M 35 35 L 25 60 L 35 85"
        stroke="currentColor"
        stroke-width="3"
        fill="none"
        stroke-linecap="round"/>

  <!-- Center wave: Transformation/Intelligence -->
  <path d="M 40 60 Q 50 52, 60 60 T 80 60"
        stroke="currentColor"
        stroke-width="2.5"
        fill="none"
        stroke-linecap="round"/>

  <!-- Right bracket: Output -->
  <path d="M 85 35 L 95 60 L 85 85"
        stroke="currentColor"
        stroke-width="3"
        fill="none"
        stroke-linecap="round"/>
</svg>
```

### Service Icons

Each Kyozo service has a distinct icon representing its function:

#### Lang - Universal Text Intelligence
```svg
<svg viewBox="0 0 100 100">
  <!-- Document with braces indicating parsing -->
  <rect x="20" y="30" width="60" height="40" rx="5"
        stroke="currentColor"
        stroke-width="3"
        fill="none"/>
  <text x="50" y="55"
        text-anchor="middle"
        font-size="20"
        fill="currentColor">{ }</text>
</svg>
```

#### Build - Intelligent System Construction
```svg
<svg viewBox="0 0 100 100">
  <!-- Building blocks ascending -->
  <rect x="20" y="60" width="20" height="20" fill="currentColor" opacity="0.8"/>
  <rect x="45" y="45" width="20" height="35" fill="currentColor" opacity="0.8"/>
  <rect x="70" y="30" width="20" height="50" fill="currentColor" opacity="0.8"/>
</svg>
```

#### Proc - Cognitive Process Orchestration
```svg
<svg viewBox="0 0 100 100">
  <!-- Network of connected nodes -->
  <circle cx="30" cy="30" r="8" fill="currentColor"/>
  <circle cx="70" cy="30" r="8" fill="currentColor"/>
  <circle cx="50" cy="70" r="8" fill="currentColor"/>
  <path d="M 30 30 L 50 70 L 70 30"
        stroke="currentColor"
        stroke-width="2"
        fill="none"/>
</svg>
```

#### Edit - Semantic Content Manipulation
```svg
<svg viewBox="0 0 100 100">
  <!-- Pencil/edit tool -->
  <path d="M 30 70 L 60 40 L 70 50 L 40 80 Z" fill="currentColor"/>
  <path d="M 60 40 L 70 30 L 80 40 L 70 50 Z" fill="currentColor" opacity="0.6"/>
  <path d="M 30 70 L 25 85 L 40 80 Z" fill="currentColor"/>
</svg>
```

#### Stor - Knowledge Persistence & Retrieval
```svg
<svg viewBox="0 0 100 100">
  <!-- Database cylinder -->
  <ellipse cx="50" cy="30" rx="25" ry="8" fill="currentColor" opacity="0.8"/>
  <rect x="25" y="30" width="50" height="40" fill="currentColor" opacity="0.6"/>
  <ellipse cx="50" cy="70" rx="25" ry="8" fill="currentColor" opacity="0.8"/>
</svg>
```

### Intelligence Elements

#### Intelligence Node
```svg
<svg viewBox="0 0 100 100">
  <!-- Radiating intelligence -->
  <circle cx="50" cy="50" r="8" fill="currentColor"/>
  <circle cx="50" cy="50" r="15" fill="none" stroke="currentColor" stroke-width="2" opacity="0.6"/>
  <circle cx="50" cy="50" r="22" fill="none" stroke="currentColor" stroke-width="1" opacity="0.3"/>
</svg>
```

#### Connection
```svg
<svg viewBox="0 0 100 100">
  <!-- Curved connection between nodes -->
  <path d="M 20 50 Q 50 30, 80 50"
        stroke="currentColor"
        stroke-width="3"
        fill="none"
        stroke-linecap="round"
        opacity="0.8"/>
  <circle cx="20" cy="50" r="4" fill="currentColor"/>
  <circle cx="80" cy="50" r="4" fill="currentColor"/>
</svg>
```

#### Data Flow
```svg
<svg viewBox="0 0 100 100">
  <!-- Directional data movement -->
  <path d="M 20 50 L 80 50"
        stroke="currentColor"
        stroke-width="2"
        fill="none"
        stroke-dasharray="5,5"/>
  <path d="M 70 45 L 80 50 L 70 55"
        stroke="currentColor"
        stroke-width="2"
        fill="none"/>
</svg>
```

### Color Specifications

Primary colors for icons:
-
 Default: `currentColor` (inherits from context)
-
 Primary Blue: `#4a9eff`
-
 Deep Blue: `#0066ff`
-
 Gradient: `linear-gradient(45deg, #4a9eff, #0066ff)`

### Usage Guidelines

1.
 **Scalability**: All icons must work from 16px to 512px
2.
 **Contrast**: Ensure sufficient contrast in both light and dark modes
3.
 **Animation**: Intelligence nodes may pulse, connections may animate
4.
 **Consistency**: Always use the official SVG paths from this spec

### Implementation

Generate fonts from this spec using:
```bash
docker run --rm -v $(pwd)/docs/specifications:/specs -v $(pwd)/priv/static/fonts:/output node:alpine node -e "
  const fs = require('fs');
  const spec = fs.readFileSync('/specs/kyozo-visual-identity-spec.md', 'utf8');
  // Extract SVG definitions from spec
  const icons = {};
  const svgPattern = /#### ([\w\s-]+)\n```svg\n([\s\S]*?)```/g;
  let match;
  while (match = svgPattern.exec(spec)) {
    const name = match[1].toLowerCase().replace(/\s+/g, '-');
    const svg = match[2].trim();
    icons[name] = svg;
  }
  // Generate files
  fs.writeFileSync('/output/lang-icons-spec.json', JSON.stringify(icons, null, 2));
  console.log('Generated icons from spec:', Object.keys(icons));
"
```

---

*This specification is the authoritative source for all Kyozo visual elements.*
