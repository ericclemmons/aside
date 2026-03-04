#!/bin/bash
# watch.sh — rebuild and relaunch Aside on source changes
cd "$(dirname "$0")"
BUNDLE="$(pwd)/Aside.app"
BINARY="$BUNDLE/Contents/MacOS/Aside"
export BUNDLE

rebuild() {
    echo ""
    echo "⟳  Building…"
    if swift build 2>&1; then
        pkill -x Aside 2>/dev/null || true
        sleep 0.3
        cp .build/arm64-apple-macosx/debug/Aside "$BINARY"
        codesign --force --deep --sign "Developer ID Application: Eric Clemmons (D3TJHQZD9N)" --identifier com.ericclemmons.aside.app "$BUNDLE"
        open "$BUNDLE"
        echo "✓  Done"
    else
        echo "✗  Build failed — waiting for next change"
    fi
}

# --once: called by entr on each file change
if [[ "${1:-}" == "--once" ]]; then
    rebuild
    exit 0
fi

echo "Watching Sources/ and Package.swift  (Ctrl-C to stop)"
rebuild  # build on start

find Sources \( -name "*.swift" -o -name "*.xcassets" \) \
    | cat - <(echo Package.swift) \
    | entr -ns 'bash "'"$(pwd)/watch.sh"'" --once'
