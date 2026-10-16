#!/usr/bin/env bash
# Rebuilds the picture manual in docs/manual/ from the app (see README.md).
#   bash test/manual/make_manual.sh [chapter ...]
set -euo pipefail
cd "$(dirname "$0")/../.."
out=build/manual
rm -rf "$out"
mkdir -p "$out"
if [ $# -gt 0 ]; then
  files=$(for c in "$@"; do echo "test/manual/${c}_manual.dart"; done)
else
  files=$(ls test/manual/*_manual.dart)
fi
# One chapter at a time keeps memory low; each runs in English and Thai.
for f in $files; do
  MANUAL_OUT="$out" flutter test "$f" --reporter compact
done
python3 test/manual/annotate.py "$out" ../docs/manual/img
version=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
python3 test/manual/build_manual.py ../docs/manual "$version"
