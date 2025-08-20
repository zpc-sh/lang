#!/bin/bash

# Clean build artifacts for LANG Universal Text Intelligence Platform
# This script removes all build artifacts, compiled files, and temporary files

set -e

echo "🧹 Cleaning LANG build artifacts..."

# Change to project root
cd "$(dirname "$0")/.."

# Clean Mix build artifacts
echo "  • Cleaning Mix artifacts..."
rm -rf _build/
rm -rf cover/
rm -rf deps/
rm -rf doc/
rm -rf tmp/
rm -f *.ez
rm -f lang-*.tar
rm -f erl_crash.dump

# Clean Phoenix assets
echo "  • Cleaning Phoenix assets..."
rm -rf priv/static/assets/
rm -rf priv/static/cache_manifest.json

# Clean Node.js artifacts
echo "  • Cleaning Node.js artifacts..."
rm -rf assets/node_modules/
rm -f assets/package-lock.json
rm -f assets/yarn.lock
rm -f npm-debug.log

# Clean Rust native artifacts
echo "  • Cleaning Rust native artifacts..."
find native -name "target" -type d -exec rm -rf {} + 2>/dev/null || true
find native -name "Cargo.lock" -type f -delete 2>/dev/null || true
rm -rf priv/native/
rm -rf priv/crates/
rm -rf priv/precompiled_nifs/
rm -f checksum-*.exs

# Clean compiled native libraries
echo "  • Cleaning compiled libraries..."
find . -name "*.so" -delete 2>/dev/null || true
find . -name "*.dll" -delete 2>/dev/null || true
find . -name "*.dylib" -delete 2>/dev/null || true

# Clean IDE and editor files
echo "  • Cleaning IDE files..."
rm -rf .vscode/
rm -rf .idea/
find . -name "*.swp" -delete 2>/dev/null || true
find . -name "*.swo" -delete 2>/dev/null || true
find . -name "*~" -delete 2>/dev/null || true

# Clean OS files
echo "  • Cleaning OS files..."
find . -name ".DS_Store" -delete 2>/dev/null || true
find . -name "Thumbs.db" -delete 2>/dev/null || true

# Clean logs
echo "  • Cleaning logs..."
rm -rf logs/
rm -rf log/
find . -name "*.log" -delete 2>/dev/null || true

# Clean temporary files
echo "  • Cleaning temporary files..."
find . -name "*.tmp" -delete 2>/dev/null || true
find . -name "*.temp" -delete 2>/dev/null || true
find . -name "*.bak" -delete 2>/dev/null || true
find . -name "*.backup" -delete 2>/dev/null || true

# Clean test artifacts
echo "  • Cleaning test artifacts..."
rm -rf coverage/
rm -f lcov.info

# Clean development artifacts
echo "  • Cleaning development artifacts..."
rm -rf .elixir_ls/
rm -rf .lexical/

# Clean release artifacts
echo "  • Cleaning release artifacts..."
rm -rf _rel/
rm -rf rel/
find . -name "*.tar.gz" -delete 2>/dev/null || true

# Clean documentation
echo "  • Cleaning documentation..."
rm -rf docs/
rm -rf documentation/

# Clean benchmarking and profiling
echo "  • Cleaning benchmarking and profiling data..."
rm -rf benchmarks/results/
find . -name "*.bench" -delete 2>/dev/null || true
find . -name "*.prof" -delete 2>/dev/null || true

echo "✅ Clean complete!"
echo ""
echo "To rebuild everything:"
echo "  mix deps.get"
echo "  cd assets && npm install"
echo "  mix compile"
echo ""
echo "To rebuild native extensions:"
echo "  mix deps.compile --force"
echo ""