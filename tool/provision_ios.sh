#!/usr/bin/env bash
# Copies the demo models into the iPhone app's Documents (its data container).
#
#   xcrun devicectl list devices         # find the device
#   tool/provision_ios.sh <device>
#
# <device> is anything devicectl --device takes. Use the device name (e.g. "sashamobile")
# or the UDID from `fvm flutter devices`: both also work for `flutter run -d`, while
# devicectl's own "Identifier" column (a CoreDevice UUID) is not a flutter device id.
#
# The app must be installed once first, so its data container exists:
#   fvm flutter run -d <device> --release ...   (setup then fails with "Model file not
#   found" until this script has run: expected; tap Retry afterwards)
#
# Source files on this Mac (environment overrides, same defaults as run_macos.sh):
#   GEMMA_MODEL_PATH     ~/Work/gemma-4-E2B-it.litertlm
#   DETECTOR_MODEL_PATH  ~/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite
#   EMBEDDING_MODEL_DIR  ~/Work/models/embeddinggemma
# Layout on the phone (documents-relative, which is what the app's --dart-defines take):
#   Documents/gemma-4-E2B-it.litertlm
#   Documents/yolo26n_fp16_rawhead.tflite
#   Documents/embeddinggemma/{embeddinggemma-300M_seq512_mixed-precision.tflite,sentencepiece.model}
# devicectl skips files that have not changed, so re-runs are cheap. The first Gemma
# copy (2.5 GB) takes minutes; keep the phone unlocked and on the cable.
#
# Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

readonly BUNDLE_ID=dev.fluttergemma.litertHackathon
readonly DETECTOR_BYTES=10361332      # yolo26n_fp16_rawhead.tflite (lib/domain/models/detector_spec.dart)
readonly EMBEDDER_MODEL=embeddinggemma-300M_seq512_mixed-precision.tflite
readonly EMBEDDER_TOKENIZER=sentencepiece.model
readonly EMBEDDER_SUBDIR=embeddinggemma
readonly COPY_TIMEOUT_S=3600

die() {
  printf 'provision_ios: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") die "missing <device> (see: xcrun devicectl list devices)" ;;
esac
[[ $# -eq 1 ]] || die "expected exactly one argument, <device>"
readonly DEVICE="$1"

command -v xcrun >/dev/null || die "xcrun not found (install Xcode)"

gemma="${GEMMA_MODEL_PATH:-$HOME/Work/gemma-4-E2B-it.litertlm}"
detector="${DETECTOR_MODEL_PATH:-$HOME/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite}"
embedding="${EMBEDDING_MODEL_DIR:-$HOME/Work/models/embeddinggemma}"

problems=()
[[ -f "$gemma" ]] || problems+=("Gemma: no file at $gemma (set GEMMA_MODEL_PATH)")
if [[ ! -f "$detector" ]]; then
  problems+=("Detector: no file at $detector (derive it with tool/prune_yolo26n_head.py, docs/design/detector-yolo26n.md §2.2; or set DETECTOR_MODEL_PATH)")
elif [[ "$(stat -f%z "$detector")" != "$DETECTOR_BYTES" ]]; then
  problems+=("Detector: $detector is not yolo26n_fp16_rawhead.tflite ($DETECTOR_BYTES bytes); the app rejects any other file")
fi
for name in "$EMBEDDER_MODEL" "$EMBEDDER_TOKENIZER"; do
  [[ -f "$embedding/$name" ]] || problems+=("EmbeddingGemma: no file at $embedding/$name (set EMBEDDING_MODEL_DIR)")
done
if [[ ${#problems[@]} -gt 0 ]]; then
  printf 'provision_ios: cannot provision, %d problem(s):\n' "${#problems[@]}" >&2
  for p in "${problems[@]}"; do
    printf '  - %s\n' "$p" >&2
  done
  exit 1
fi

apps_json="$(mktemp -t provision_ios_apps)"
files_json="$(mktemp -t provision_ios_files)"
trap 'rm -f "$apps_json" "$files_json"' EXIT

# 1. The app is installed (its container exists). JSON output is devicectl's only
#    stable interface for scripts; result.apps is empty when the app is missing.
xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$BUNDLE_ID" \
  --quiet --json-output "$apps_json" --timeout 60 >/dev/null ||
  die "devicectl cannot reach \"$DEVICE\" (unlocked, paired, Developer Mode on? see: xcrun devicectl list devices)"
installed="$(plutil -extract result.apps.0.bundleIdentifier raw -o - "$apps_json" 2>/dev/null || true)"
[[ "$installed" == "$BUNDLE_ID" ]] ||
  die "$BUNDLE_ID is not installed on \"$DEVICE\". Install it once first (fvm flutter run -d <device> --release ...), then re-run."

# 2. Copy. --destination is relative to the container root; devicectl creates
#    missing directories (checked with the temporary domain on iOS 26, Xcode 26.5).
copy() { # <local file> <path under the container root>
  printf '\n==> %s -> %s\n' "$1" "$2"
  xcrun devicectl device copy to --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "$1" --destination "$2" --timeout "$COPY_TIMEOUT_S"
}
copy "$gemma" "Documents/$(basename "$gemma")"
copy "$detector" "Documents/$(basename "$detector")"
copy "$embedding/$EMBEDDER_MODEL" "Documents/$EMBEDDER_SUBDIR/$EMBEDDER_MODEL"
copy "$embedding/$EMBEDDER_TOKENIZER" "Documents/$EMBEDDER_SUBDIR/$EMBEDDER_TOKENIZER"

# 3. Read back: every file is in Documents with the local size.
xcrun devicectl device info files --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --subdirectory Documents --quiet --json-output "$files_json" --timeout 120 >/dev/null ||
  die "could not list the app's Documents to verify the copy"
python3 - "$files_json" \
  "$(basename "$gemma")=$(stat -f%z "$gemma")" \
  "$(basename "$detector")=$(stat -f%z "$detector")" \
  "$EMBEDDER_SUBDIR/$EMBEDDER_MODEL=$(stat -f%z "$embedding/$EMBEDDER_MODEL")" \
  "$EMBEDDER_SUBDIR/$EMBEDDER_TOKENIZER=$(stat -f%z "$embedding/$EMBEDDER_TOKENIZER")" <<'PY'
import json, sys
files = json.load(open(sys.argv[1]))["result"]["files"]
sizes = {f["relativePath"]: f.get("metadata", {}).get("size") for f in files}
bad = []
for spec in sys.argv[2:]:
    path, want = spec.rsplit("=", 1)
    got = sizes.get(path)
    status = "ok" if got == int(want) else "MISMATCH"
    print(f"  {status:8} Documents/{path}  device={got} local={want}")
    if status != "ok":
        bad.append(path)
sys.exit(1 if bad else 0)
PY

cat <<EOF

Provisioned. Build and run with these documents-relative paths (dart-defines are
compiled in, so rebuild after changing them):

  fvm flutter run -d $DEVICE --release \\
    --dart-define=GEMMA_MODEL_PATH=$(basename "$gemma") \\
    --dart-define=DETECTOR_MODEL_PATH=$(basename "$detector") \\
    --dart-define=EMBEDDING_MODEL_DIR=$EMBEDDER_SUBDIR

No .env or token: no model needs one (EmbeddingGemma is built in). If the app is already open on the setup
error, tap Retry instead. Every other model is built into the app; nothing is downloaded.
EOF
