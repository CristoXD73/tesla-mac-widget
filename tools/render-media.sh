#!/bin/bash
# Renders docs/images/widget-{small,medium,large}.png and hero.png from the widget's own SwiftUI views,
# with made-up sample data (Palo Alto address, Ultra Red Model Y). Needs network for the car photo and map.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -parse-as-library -D RENDER_TOOL -O -target arm64-apple-macos15.0 \
  Shared/*.swift Widget/*.swift App/CarRender.swift App/TeslaAuth.swift tools/render-widgets.swift \
  -o build/render-widgets
build/render-widgets docs/images
