#!/bin/sh
# ocr-find.sh IMAGE [WORD]   read a screenshot as text, with click positions.
#
#   ocr-find.sh shot.png             every word: "X Y CONF WORD"
#   ocr-find.sh shot.png Connect     only words containing "Connect" (any case)
#   ocr-find.sh shot.png --text      the screen as plain text lines
#
# X,Y is the centre of the word in screenshot pixels: pass it straight to
# vm.sh m:click,X,Y (VMs) or xtest.sh c:X,Y (Xvfb). The image is upscaled 2x
# before OCR because UI fonts are small; coordinates are scaled back.
# Exit status 1 when WORD was given and not found.
set -eu
IMG=$1
WORD=${2:-}
command -v tesseract >/dev/null || { echo "ocr-find: tesseract missing" >&2; exit 2; }
TMP=$(mktemp --suffix=.png)
trap 'rm -f "$TMP"' EXIT
magick "$IMG" -resize 200% -colorspace Gray "$TMP" 2>/dev/null \
	|| convert "$IMG" -resize 200% -colorspace Gray "$TMP"

if [ "$WORD" = "--text" ]; then
	tesseract "$TMP" - --psm 11 2>/dev/null | grep -v '^\s*$'
	exit 0
fi

# tsv columns: level page block par line word left top width height conf text
tesseract "$TMP" - --psm 11 tsv 2>/dev/null | awk -F'\t' -v w="$WORD" '
	NR > 1 && $12 != "" && $11 > 30 {
		if (w != "" && index(tolower($12), tolower(w)) == 0) next
		printf "%d %d %d %s\n", ($7 + $9 / 2) / 2, ($8 + $10 / 2) / 2, $11, $12
		found = 1
	}
	END { if (w != "" && !found) exit 1 }'
