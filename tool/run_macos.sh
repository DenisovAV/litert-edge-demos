#!/usr/bin/env bash
# Runs the demo app on macOS with the locally provisioned models.
#
#   tool/run_macos.sh                    # debug build, live camera (camera_desktop)
#   tool/run_macos.sh --profile          # AOT speed; still reads the models from ~/Work
#   tool/run_macos.sh --release          # clones the models into the sandbox container first
#   tool/run_macos.sh --fixture ~/Work/models/yolo26n/test_images/coco30   # Demo 3 on stills
#   tool/run_macos.sh -- --verbose       # everything after -- goes to `flutter run`
#
# Model paths: environment overrides, otherwise the defaults below. Like the app, a
# relative path means "relative to the app's Documents" (the sandbox container). A
# variable set to an empty value leaves that --dart-define out (the app then shows
# the model as unavailable; with GEMMA_MODEL_PATH empty it asks for a chat model).
#   GEMMA_MODEL_PATH     ~/Work/gemma-4-E2B-it.litertlm
#   DETECTOR_MODEL_PATH  ~/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite
#   EMBEDDING_MODEL_DIR  ~/Work/models/embeddinggemma
# Passed through when set: DETECTOR_BACKEND (gpu|cpu), VOICE_GATE_DBFS (e.g. -40).
# .env is NOT passed to the build: no model needs a Hugging Face token (EmbeddingGemma is
# built in), and anything passed as a define ends up in the binary.
#
# Sandbox: Debug and Profile builds sign with DebugProfile.entitlements, which may
# read ~/Work/ only. Release builds (Release.entitlements) have no such exception,
# so --release clones (APFS clonefile: instant, no extra disk) the models into
# ~/Library/Containers/dev.fluttergemma.litertHackathon/Data/Documents/ and passes
# documents-relative paths.
#
# Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

readonly BUNDLE_ID=dev.fluttergemma.litertHackathon
readonly CONTAINER_DOCS="$HOME/Library/Containers/$BUNDLE_ID/Data/Documents"
readonly SANDBOX_READ_ROOT="$HOME/Work/"
readonly DETECTOR_BYTES=10361332      # yolo26n_fp16_rawhead.tflite (lib/domain/models/detector_spec.dart)
readonly ARM_ORIGINAL_BYTES=10363712  # yolo26n_conv2d_f16_weights.tflite, rejected by the app
readonly EMBEDDER_MODEL=embeddinggemma-300M_seq512_mixed-precision.tflite
readonly EMBEDDER_TOKENIZER=sentencepiece.model

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

die() {
  printf 'run_macos: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
}

mode=debug
fixture=""
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) mode=debug ;;
    --profile) mode=profile ;;
    --release) mode=release ;;
    --fixture)
      [[ $# -ge 2 && -n "$2" ]] || die "--fixture needs a directory of images or one image file"
      fixture="$2"
      shift
      ;;
    --fixture=*) fixture="${1#--fixture=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      extra=("$@")
      break
      ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

# `${VAR-default}`: unset → default, set but empty → empty (define left out).
gemma="${GEMMA_MODEL_PATH-$HOME/Work/gemma-4-E2B-it.litertlm}"
detector="${DETECTOR_MODEL_PATH-$HOME/Work/models/yolo26n/fp16/yolo26n_fp16_rawhead.tflite}"
embedding="${EMBEDDING_MODEL_DIR-$HOME/Work/models/embeddinggemma}"

problems=()
problem() { problems+=("$*"); }

# The sandboxed debug/profile app reads only ~/Work/ and its own container.
check_sandbox_readable() { # <label> <path>
  [[ "$mode" == release ]] && return 0
  case "$2" in
    "$SANDBOX_READ_ROOT"* | "$CONTAINER_DOCS"/*) ;;
    *) problem "$1: $2 is outside ~/Work/; the sandboxed $mode build can only read ~/Work/ (DebugProfile.entitlements). Move it under ~/Work/." ;;
  esac
}

file_size() { stat -f%z "$1"; }

# What the app reads for a --dart-define path (lib/data/services/model_store/local_files.dart):
# absolute as given, otherwise relative to Documents.
resolve() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$CONTAINER_DOCS" "$1" ;;
  esac
}

if [[ -n "$gemma" ]]; then
  gemma_abs="$(resolve "$gemma")"
  if [[ ! -f "$gemma_abs" ]]; then
    problem "Gemma: no file at $gemma_abs. Download gemma-4-E2B-it.litertlm from huggingface.co/litert-community/gemma-4-E2B-it-litert-lm, or set GEMMA_MODEL_PATH."
  elif [[ ! -r "$gemma_abs" ]]; then
    problem "Gemma: $gemma_abs is not readable."
  else
    check_sandbox_readable Gemma "$gemma_abs"
  fi
else
  printf 'note: GEMMA_MODEL_PATH is empty: choose a chat model on the setup screen (models folder, Path..., or Download from URL...).\n'
fi

if [[ -n "$detector" ]]; then
  detector_abs="$(resolve "$detector")"
  if [[ ! -f "$detector_abs" ]]; then
    problem "Detector: no file at $detector_abs. Derive it: ~/Work/models/yolo26n/.venv/bin/python tool/prune_yolo26n_head.py <Arm/yolo26n-fp16-litert>/yolo26n_conv2d_f16_weights.tflite $detector_abs (docs/design/detector-yolo26n.md §2.2), or set DETECTOR_MODEL_PATH."
  else
    size="$(file_size "$detector_abs")"
    if [[ "$size" == "$ARM_ORIGINAL_BYTES" ]]; then
      problem "Detector: $detector_abs is Arm's original file (its TopK/GatherND head cannot run on the GPU). Use the derived yolo26n_fp16_rawhead.tflite from tool/prune_yolo26n_head.py."
    elif [[ "$size" != "$DETECTOR_BYTES" ]]; then
      problem "Detector: $detector_abs has $size bytes; the app accepts only yolo26n_fp16_rawhead.tflite ($DETECTOR_BYTES bytes)."
    else
      check_sandbox_readable Detector "$detector_abs"
    fi
  fi
else
  printf 'note: DETECTOR_MODEL_PATH is empty, so the detector comes from the model store (Models screen).\n'
fi

if [[ -n "$embedding" ]]; then
  embedding_abs="$(resolve "$embedding")"
  if [[ ! -d "$embedding_abs" ]]; then
    problem "EmbeddingGemma: no directory at $embedding_abs. It needs $EMBEDDER_MODEL and $EMBEDDER_TOKENIZER from the gated huggingface.co/litert-community/embeddinggemma-300m, or set EMBEDDING_MODEL_DIR."
  else
    for name in "$EMBEDDER_MODEL" "$EMBEDDER_TOKENIZER"; do
      [[ -f "$embedding_abs/$name" ]] || problem "EmbeddingGemma: $embedding_abs/$name is missing."
    done
    check_sandbox_readable EmbeddingGemma "$embedding_abs"
  fi
else
  printf 'note: EMBEDDING_MODEL_DIR is empty: the knowledge base uses the built-in EmbeddingGemma.\n'
fi

# The built-in models (assets/models/) are not in git; tool/fetch_models.sh fetches them.
"$REPO_ROOT/tool/fetch_models.sh" --check >/dev/null 2>&1 ||
  problem "Built-in models: assets/models/ lacks verified model files (they are not in git). Run tool/fetch_models.sh; tool/fetch_models.sh --check lists them."

if [[ -n "$fixture" ]]; then
  if [[ -d "$fixture" ]]; then
    fixture="$(cd "$fixture" && pwd -P)"
    check_sandbox_readable Fixture "$fixture"
  elif [[ -f "$fixture" ]]; then
    fixture="$(cd "$(dirname "$fixture")" && pwd -P)/$(basename "$fixture")"
    check_sandbox_readable Fixture "$fixture"
  else
    problem "Fixture: no file or directory at $fixture."
  fi
fi

if [[ -n "${DETECTOR_BACKEND:-}" && "$DETECTOR_BACKEND" != gpu && "$DETECTOR_BACKEND" != cpu ]]; then
  problem "DETECTOR_BACKEND must be gpu or cpu, got \"$DETECTOR_BACKEND\"."
fi

if [[ ${#problems[@]} -gt 0 ]]; then
  printf 'run_macos: cannot start, %d problem(s):\n' "${#problems[@]}" >&2
  for p in "${problems[@]}"; do
    printf '  - %s\n' "$p" >&2
  done
  exit 1
fi

# --release: clone the inputs into the container and use documents-relative paths
# (FIXTURE_DIR is not documents-relative, so it gets the absolute container path).
stage_file() { # <src> <path relative to Documents>
  local dst="$CONTAINER_DOCS/$2"
  if [[ -f "$dst" && "$(file_size "$dst")" == "$(file_size "$1")" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  printf 'staging %s -> %s\n' "$1" "$dst"
  cp -c "$1" "$dst"
}

# Prints the documents-relative path of a file inside the container, or nothing.
docs_relative() {
  case "$1" in
    "$CONTAINER_DOCS"/*) printf '%s' "${1#"$CONTAINER_DOCS"/}" ;;
  esac
}

if [[ "$mode" == release ]]; then
  [[ -d "$CONTAINER_DOCS" ]] ||
    die "no sandbox container at $CONTAINER_DOCS yet. Run once without --release (or --profile) so macOS creates it, then retry."
  if [[ -n "$gemma" ]]; then
    gemma="$(docs_relative "$gemma_abs")"
    if [[ -z "$gemma" ]]; then
      gemma="models/$(basename "$gemma_abs")"
      stage_file "$gemma_abs" "$gemma"
    fi
  fi
  if [[ -n "$detector" ]]; then
    detector="$(docs_relative "$detector_abs")"
    if [[ -z "$detector" ]]; then
      detector="models/$(basename "$detector_abs")"
      stage_file "$detector_abs" "$detector"
    fi
  fi
  if [[ -n "$embedding" ]]; then
    embedding="$(docs_relative "$embedding_abs")"
    if [[ -z "$embedding" ]]; then
      embedding="models/embeddinggemma"
      stage_file "$embedding_abs/$EMBEDDER_MODEL" "$embedding/$EMBEDDER_MODEL"
      stage_file "$embedding_abs/$EMBEDDER_TOKENIZER" "$embedding/$EMBEDDER_TOKENIZER"
    fi
  fi
  if [[ -n "$fixture" && -z "$(docs_relative "$fixture")" ]]; then
    staged="$CONTAINER_DOCS/fixtures/$(basename "$fixture")"
    if [[ -d "$fixture" ]]; then
      # Copies the contents over an earlier staging (a trailing / on a BSD cp source
      # copies the contents); images removed from the source stay in the copy.
      mkdir -p "$staged"
      printf 'staging %s/ -> %s/\n' "$fixture" "$staged"
      cp -cR "$fixture/" "$staged/"
    else
      stage_file "$fixture" "fixtures/$(basename "$fixture")"
    fi
    fixture="$staged"
  fi
fi

defines=()
[[ -n "$gemma" ]] && defines+=("GEMMA_MODEL_PATH=$gemma")
[[ -n "$detector" ]] && defines+=("DETECTOR_MODEL_PATH=$detector")
[[ -n "$embedding" ]] && defines+=("EMBEDDING_MODEL_DIR=$embedding")
[[ -n "${DETECTOR_BACKEND:-}" ]] && defines+=("DETECTOR_BACKEND=$DETECTOR_BACKEND")
[[ -n "${VOICE_GATE_DBFS:-}" ]] && defines+=("VOICE_GATE_DBFS=$VOICE_GATE_DBFS")
if [[ -n "$fixture" ]]; then
  defines+=("FRAME_SOURCE=fixture" "FIXTURE_DIR=$fixture")
fi

cmd=(fvm flutter run -d macos)
[[ "$mode" != debug ]] && cmd+=("--$mode")
for d in ${defines[@]+"${defines[@]}"}; do
  cmd+=("--dart-define=$d")
done
cmd+=(${extra[@]+"${extra[@]}"})

if [[ "$(defaults read "$BUNDLE_ID" NSAppSleepDisabled 2>/dev/null || true)" != 1 ]]; then
  printf 'note: App Nap is on for this app; for honest latencies run\n  defaults write %s NSAppSleepDisabled -bool YES\n' "$BUNDLE_ID"
fi

cd "$REPO_ROOT"
printf '+'
printf ' %q' "${cmd[@]}"
printf '\n'
exec "${cmd[@]}"
