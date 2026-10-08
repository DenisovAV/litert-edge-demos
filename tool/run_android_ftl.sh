#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model="${1:-$repo_dir/../gemma-4-E2B-it.litertlm}"
project="${GCLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
device="${FTL_DEVICE:-model=husky,locale=en,orientation=portrait}"
remote_model=/data/local/tmp/flutter_gemma_test/gemma-4-E2B-it.litertlm

if [[ ! -f "$model" ]]; then
  echo "Gemma model not found: $model" >&2
  exit 2
fi
if [[ -z "$project" || "$project" == "(unset)" ]]; then
  echo "Set GCLOUD_PROJECT or select one with: gcloud config set project PROJECT_ID" >&2
  exit 2
fi

cd "$repo_dir"
# The built-in models are not in git: refuse to build without the verified ones.
tool/fetch_models.sh --check

fvm flutter build apk \
  --debug \
  --target=integration_test/model_smoke_test.dart \
  --dart-define=GEMMA_MODEL_PATH="$remote_model" \
  --dart-define=GEMMA_BACKEND=gpu

(
  cd android
  ./gradlew app:assembleAndroidTest
)

app_apk=build/app/outputs/apk/debug/app-debug.apk
test_apk=build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk

[[ -f "$app_apk" ]] || { echo "App APK not found: $app_apk" >&2; exit 3; }
[[ -f "$test_apk" ]] || { echo "Test APK not found: $test_apk" >&2; exit 3; }

gcloud firebase test android run \
  --project="$project" \
  --type=instrumentation \
  --app="$app_apk" \
  --test="$test_apk" \
  --device="$device" \
  --other-files="$remote_model=$model" \
  --timeout=15m \
  --client-details=matrixLabel=litert-hackathon-gemma-gpu-smoke
