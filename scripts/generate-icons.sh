#!/bin/bash
# Generate LANG icons from specification

# Extract icons from the visual identity spec
docker run --rm \
  -v $(pwd)/docs/specifications:/specs:ro \
  -v $(pwd)/priv/static/fonts:/output \
  node:alpine sh -c '
cat > /tmp/generate-from-spec.js << "EOF"
const fs = require("fs");

// Read the specification
const spec = fs.readFileSync("/specs/kyozo-visual-identity-spec.md", "utf8");

// Extract SVG definitions from the spec markdown
const icons = {};
const svgPattern = /####\s+([\w\s-]+)\n```svg\n([\s\S]*?)```/g;
let match;

while (match = svgPattern.exec(spec)) {
  const name = match[1].trim()
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/---/g, "-");
  const svgContent = match[2].trim();

  // Extract just the inner content (remove outer svg tag if present)
  const innerContent = svgContent
    .replace(/<svg[^>]*>/, "")
    .replace(/<\/svg>/, "")
    .trim();

  icons[name] = innerContent;
}

// Generate CSS with embedded SVGs
const css = `/* LANG Icons - Generated from Kyozo Visual Identity Specification */

.lang-icon {
  display: inline-block;
  width: 1em;
  height: 1em;
  vertical-align: -0.125em;
}

${Object.entries(icons).map(([name, svg]) => {
  const encoded = encodeURIComponent(svg);
  return `.lang-icon-${name} {
  background: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E${encoded}%3C/svg%3E") no-repeat center;
  background-size: contain;
}`;
}).join("\n\n")}

/* Size utilities */
.lang-icon-xs { width: 0.75rem; height: 0.75rem; }
.lang-icon-sm { width: 0.875rem; height: 0.875rem; }
.lang-icon-lg { width: 1.25rem; height: 1.25rem; }
.lang-icon-xl { width: 1.5rem; height: 1.5rem; }
.lang-icon-2xl { width: 2rem; height: 2rem; }
.lang-icon-3xl { width: 3rem; height: 3rem; }

/* Animations */
@keyframes lang-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.lang-animate-pulse {
  animation: lang-pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
`;

// Generate SVG sprite
const sprite = `<svg xmlns="http://www.w3.org/2000/svg" style="display: none;">
  <defs>
${Object.entries(icons).map(([name, svg]) =>
  `    <symbol id="lang-${name}" viewBox="0 0 100 100">
      ${svg}
    </symbol>`
).join("\n")}
  </defs>
</svg>`;

// Generate JSON map
const jsonMap = {
  generated: new Date().toISOString(),
  source: "kyozo-visual-identity-spec.md",
  icons: Object.keys(icons).reduce((acc, name) => {
    acc[name] = {
      name: name,
      className: `lang-icon-${name}`,
      symbolId: `lang-${name}`
    };
    return acc;
  }, {})
};

// Write files
fs.writeFileSync("/output/lang-icons.css", css);
fs.writeFileSync("/output/lang-icons.svg", sprite);
fs.writeFileSync("/output/lang-icons.json", JSON.stringify(jsonMap, null, 2));

console.log("✅ Generated LANG icons from specification:");
console.log("   Found icons:", Object.keys(icons).join(", "));
console.log("   Output files: lang-icons.css, lang-icons.svg, lang-icons.json");

EOF

node /tmp/generate-from-spec.js
'

echo "✅ LANG icons generated from specification"
