#!/usr/bin/env bash
# Regenerate every diagram (.svg + .png) from its .dot source, and the logo PNG
# from logo.svg. Reproducible: edit the .dot / .svg sources, re-run this.
#   deps: graphviz (dot), librsvg (rsvg-convert)  — fallbacks: inkscape / ImageMagick
set -euo pipefail
cd "$(dirname "$0")/.."

DIAGRAMS="assets/diagrams"
DPI=150

svg2png() {  # $1=in.svg  $2=out.png  [width]
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert ${3:+-w "$3"} -o "$2" "$1"
  elif command -v inkscape >/dev/null 2>&1; then
    inkscape "$1" --export-type=png --export-filename="$2" ${3:+-w "$3"} >/dev/null 2>&1
  else
    convert -density "$DPI" -background none "$1" "$2"
  fi
}

echo "==> diagrams"
for dot in "$DIAGRAMS"/*.dot; do
  base="${dot%.dot}"
  dot -Tsvg "$dot" -o "$base.svg"
  dot -Tpng -Gdpi="$DPI" "$dot" -o "$base.png"
  echo "    $(basename "$base").{svg,png}"
done

echo "==> logo"
svg2png assets/logo.svg assets/logo.png 1200
echo "    logo.png"

echo "done."
