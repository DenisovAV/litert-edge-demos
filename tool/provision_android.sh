#!/usr/bin/env bash
# Pushes the demo models into the Android app's external files directory.
#
#   adb devices                          # find the serial (optional with one device)
#   tool/provision_android.sh [<serial>]
#
# The app must be installed once first, so /sdcard/Android/data/<package>/ exists:
#   fvm flutter run -d <serial> --release ...   (setup then fails with "Model file not
#   found" until this script has run: expected; tap Retry afterwards)
# adb cannot write the documents directory (app_flutter/), so the app gets absolute
# paths into its external files directory instead.
#
# Source files on this Mac (environment overrides, same defaults as run_macos.sh):
#   GEMMA_MODEL_PATH     ~/Work/gemma-4-E2B-it.litertlm
#   DETECTOR_MODEL_PATH  ~/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite
#   EMBEDDING_MODEL_DIR  ~/Work/models/embeddinggemma
# Layout on the phone:
#   /sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/gemma-4-E2B-it.litertlm
#   .../files/yolo26n_fp16_rawhead.tflite
#   .../files/embeddinggemma/{embeddinggemma-300M_seq512_mixed-precision.tflite,sentencepiece.model}
# `adb push --sync` skips files that are already up to date, so re-runs are cheap.
#
# Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

readonly PACKAGE=dev.fluttergemma.litert_hackathon
readonly APP_DATA="/sdcard/Android/data/$PACKAGE"
readonly REMOTE="$APP_DATA/files"
readonly DETECTOR_BYTES=10361332      # yolo26n_fp16_rawhead.tflite (lib/domain/models/detector_spec.dart)
readonly EMBEDDER_MODEL=embeddinggemma-300M_seq512_mixed-precision.tflite
readonly EMBEDDER_TOKENIZER=sentencepiece.model
readonly EMBEDDER_SUBDIR=embeddinggemma

die() {
  printf 'provision_android: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
}

serial=""
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *) serial="$1" ;;
esac
[[ $# -le 1 ]] || die "expected at most one argument, <serial>"

command -v adb >/dev/null || die "adb not found (Android SDK platform-tools)"
adb_cmd=(adb)
[[ -n "$serial" ]] && adb_cmd+=(-s "$serial")
adb_() { "${adb_cmd[@]}" "$@"; }

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
  printf 'provision_android: cannot provision, %d problem(s):\n' "${#problems[@]}" >&2
  for p in "${problems[@]}"; do
    printf '  - %s\n' "$p" >&2
  done
  exit 1
fi

# 1. One reachable device with the app installed.
state="$(adb_ get-state 2>&1 || true)"
[[ "$state" == device ]] ||
  die "no usable device${serial:+ \"$serial\"}: $state (see: adb devices; pass the serial when several are attached)"
case "$(adb_ shell pm path "$PACKAGE" 2>/dev/null | tr -d '\r')" in
  package:*) ;;
  *) die "$PACKAGE is not installed. Install it once first (fvm flutter run -d <serial> --release ...), then re-run." ;;
esac
adb_ shell ls -d "$APP_DATA" >/dev/null 2>&1 ||
  die "$APP_DATA does not exist yet. Launch the app once, then re-run."
adb_ shell mkdir -p "$REMOTE/$EMBEDDER_SUBDIR" ||
  die "cannot create $REMOTE/$EMBEDDER_SUBDIR. Launch the app once (it creates files/), then re-run."

# 2. Push.
push() { # <local file> <remote file>
  printf '\n==> %s -> %s\n' "$1" "$2"
  adb_ push --sync "$1" "$2"
}
push "$gemma" "$REMOTE/$(basename "$gemma")"
push "$detector" "$REMOTE/$(basename "$detector")"
push "$embedding/$EMBEDDER_MODEL" "$REMOTE/$EMBEDDER_SUBDIR/$EMBEDDER_MODEL"
push "$embedding/$EMBEDDER_TOKENIZER" "$REMOTE/$EMBEDDER_SUBDIR/$EMBEDDER_TOKENIZER"

# 3. Read back the sizes.
printf '\n'
bad=0
verify() { # <local file> <remote file>
  local want got
  want="$(stat -f%z "$1")"
  got="$(adb_ shell stat -c %s "$2" 2>/dev/null | tr -d '\r' || true)"
  if [[ "$got" == "$want" ]]; then
    printf '  ok        %s (%s bytes)\n' "$2" "$want"
  else
    printf '  MISMATCH  %s device=%s local=%s\n' "$2" "${got:-missing}" "$want"
    bad=1
  fi
}
verify "$gemma" "$REMOTE/$(basename "$gemma")"
verify "$detector" "$REMOTE/$(basename "$detector")"
verify "$embedding/$EMBEDDER_MODEL" "$REMOTE/$EMBEDDER_SUBDIR/$EMBEDDER_MODEL"
verify "$embedding/$EMBEDDER_TOKENIZER" "$REMOTE/$EMBEDDER_SUBDIR/$EMBEDDER_TOKENIZER"
[[ "$bad" == 0 ]] || die "some files did not arrive intact; re-run the script"

cat <<EOF

Provisioned. Build and run with these absolute paths (dart-defines are compiled in,
so rebuild after changing them):

  fvm flutter run -d ${serial:-<serial>} --release \\
    --dart-define=GEMMA_MODEL_PATH=$REMOTE/$(basename "$gemma") \\
    --dart-define=DETECTOR_MODEL_PATH=$REMOTE/$(basename "$detector") \\
    --dart-define=EMBEDDING_MODEL_DIR=$REMOTE/$EMBEDDER_SUBDIR

No .env or token: no model needs one (EmbeddingGemma is built in). If the app is already open on the setup
error, tap Retry instead. Every other model is built into the app; nothing is downloaded.
Uninstalling the app deletes these files.
EOF
