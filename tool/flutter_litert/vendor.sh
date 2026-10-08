#!/bin/sh
# Recreates third_party/flutter_litert: flutter_litert 3.9.3 from pub.dev plus
# flutter_litert-3.9.3.patch (pubspec.yaml points dependency_overrides there).
# Run once per checkout, before `fvm flutter pub get`; CI runs it too.
#
# Why the patch (docs/design/detector-linux.md): on Linux the app's LiteRT
# runtime is flutter_gemma's libLiteRt.so (x86_64 + arm64, glibc 2.35), whose
# model-loading ABI is newer than the one flutter_litert 3.9.3 assumes on
# desktop. Unpatched, YOLO26n crashes the process on Linux.
set -eu

VERSION=3.9.3
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PATCH="$ROOT/tool/flutter_litert/flutter_litert-$VERSION.patch"
DEST="$ROOT/third_party/flutter_litert"
STAMP="$DEST/.vendored"
WANT="$VERSION $(shasum -a 256 "$PATCH" 2>/dev/null || sha256sum "$PATCH")"
WANT=$(printf '%s' "$WANT" | awk '{print $1, $2}')

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANT" ]; then
  echo "third_party/flutter_litert is up to date ($VERSION + patch)"
  exit 0
fi
if [ -e "$DEST" ]; then
  echo "error: $DEST is stale or hand-edited; delete it and rerun" >&2
  exit 1
fi

DART="dart"
command -v fvm >/dev/null 2>&1 && DART="fvm dart"
(cd "$ROOT" && $DART pub cache add flutter_litert --version "$VERSION")

PUB_CACHE_DIR=${PUB_CACHE:-$HOME/.pub-cache}
SRC="$PUB_CACHE_DIR/hosted/pub.dev/flutter_litert-$VERSION"
[ -d "$SRC" ] || { echo "error: $SRC not found after pub cache add" >&2; exit 1; }

TMP="$DEST.tmp.$$"
mkdir -p "$TMP"
# example/ is not needed for a path dependency.
(cd "$SRC" && tar cf - --exclude ./example .) | (cd "$TMP" && tar xf -)
(cd "$TMP" && patch -p1 --forward --quiet < "$PATCH")
printf '%s\n' "$WANT" > "$TMP/.vendored"

mkdir -p "$(dirname "$DEST")"
mv "$TMP" "$DEST"
echo "third_party/flutter_litert: flutter_litert $VERSION + patch"
