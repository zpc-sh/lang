#!/bin/bash
# 🧪 JULES POST-MORTEM: BINARY OSCILLATION TEST
# Run this inside lang_turd to audit the Copilot "Seepage"

echo "📂 Analyzing libtree_parser.so variants..."

# Extract all unique blobs of the tree parser
BLOBS=$(git rev-list --objects --all | grep 'libtree_parser.so' | awk '{print $1}')

if [ -z "$BLOBS" ]; then
  echo "🚫 RESULT: NO BLOBS FOUND. libtree_parser.so is not in the git history of this repository."
else
  mkdir -p ./autopsy

  for sha in $BLOBS; do
    echo "🔪 Extracting $sha..."
    git cat-file -p "$sha" > "./autopsy/$sha.so"

    # Check if 'nm' is available to look at the symbols (The 'Matrix' view)
    if command -v nm &> /dev/null; then
      nm -D "./autopsy/$sha.so" > "./autopsy/$sha.symbols"
    fi
  done

  echo "📊 COMPARING DIFFS..."
  # Compare the first one to the last one to see 'Evolution' vs 'Looping'
  FIRST=$(echo "$BLOBS" | head -n 1)
  LAST=$(echo "$BLOBS" | tail -n 1)

  if diff "./autopsy/$FIRST.so" "./autopsy/$LAST.so" > /dev/null; then
    echo "🚫 RESULT: STATIC LOOP. The binaries are identical despite different commits."
  else
    echo "📈 RESULT: EVOLVING SEEPAGE. The binaries are actually changing."
    # If symbols exist, see what functions were added/removed
    if [[ -f "./autopsy/$FIRST.symbols" && -f "./autopsy/$LAST.symbols" ]]; then
        diff -u "./autopsy/$FIRST.symbols" "./autopsy/$LAST.symbols" || true
    fi
  fi
fi
