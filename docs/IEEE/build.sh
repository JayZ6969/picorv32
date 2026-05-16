#!/bin/sh
# Build IEEE PicoRV32 paper (artifacts in build/, PDF at project root).
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p build

pdflatex -interaction=nonstopmode -file-line-error -output-directory=build main.tex
BIBINPUTS="$ROOT:" bibtex build/main
pdflatex -interaction=nonstopmode -file-line-error -output-directory=build main.tex
pdflatex -interaction=nonstopmode -file-line-error -output-directory=build main.tex

cp -f build/main.pdf main.pdf
echo "Build finished. Output: $ROOT/main.pdf"
