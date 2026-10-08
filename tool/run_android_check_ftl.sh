#!/usr/bin/env bash
# The Android check (integration_test/android_release_check_test.dart) on Firebase
# Test Lab: a fresh install with no chat model shipped. --model pushes one; the
# test picks it in the setup screen's Chat model card, then checks the built-in
# models, the device card, the knowledge base, Demo 1, Demo 3 and the in-app
# self-test on a real phone.
#
#   tool/run_android_check_ftl.sh --model gs://…/gemma-4-E2B-it.litertlm
#       # Galaxy S24 (SC-51E, API 36), Gemma 4 E2B on the GPU
#   tool/run_android_check_ftl.sh --model ~/Downloads/gemma4_2b_SM8850.litertlm \
#       model=m1q,version=36                           # Galaxy S26, on the NPU
#
# --model <local path | gs://…> (required: the app ships no chat model): a
# .litertlm pushed (--other-files) into the app's models folder,
# /sdcard/Android/data/<app>/files/models/<name>, and into
# /data/local/tmp/litert-models/<name> (used through "Path…" when the folder
# copy is not readable by the app: Test Lab may push before the app exists).
# A local file is uploaded by gcloud on every run; for a multi-GB model upload
# it once (gsutil cp) and pass the gs:// URL.
#
# FTL_SKIP_BUILD=1 reuses the APKs of the previous build (a second device or a
# retry of the same code).
#
# Paid: physical devices are billed per device-minute (see the Firebase pricing
# page). --timeout caps one run. Results (logcat, test output, the screenshots
# and summary the test writes) land in build/ftl/<stamp>/.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="${GCLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
timeout="${FTL_TIMEOUT:-45m}"  # the physical-device maximum
model=""
devices=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      [[ $# -ge 2 ]] || { echo "--model needs a path" >&2; exit 2; }
      model="$2"
      shift 2
      ;;
    --model=*)
      model="${1#--model=}"
      shift
      ;;
    *)
      devices+=("$1")
      shift
      ;;
  esac
done
if [[ -z "$project" || "$project" == "(unset)" ]]; then
  echo "Set GCLOUD_PROJECT or select one with: gcloud config set project PROJECT_ID" >&2
  exit 2
fi
[[ ${#devices[@]} -gt 0 ]] || devices=("model=SC-51E,version=36")
[[ -n "$model" ]] || {
  echo "--model <path|gs://…> is required: the app ships no chat model" >&2
  exit 2
}
# The built-in models are not in git: refuse to build (or upload) without the verified ones.
"$repo_dir/tool/fetch_models.sh" --check
target="integration_test/android_release_check_test.dart"
package="dev.fluttergemma.litert_hackathon"
stamp="$(date +%Y%m%d-%H%M%S)"
results_dir="litert-android-check-$stamp"
out="$repo_dir/build/ftl/$stamp"
mkdir -p "$out"

cd "$repo_dir"
if [[ "${FTL_SKIP_BUILD:-0}" != 1 ]]; then
  fvm flutter build apk --profile --target="$target"
  (
    cd android
    ./gradlew app:assembleAndroidTest -PtestBuildType=profile -Ptarget="$repo_dir/$target"
  )
fi
app_apk=build/app/outputs/flutter-apk/app-profile.apk
test_apk=build/app/outputs/apk/androidTest/profile/app-profile-androidTest.apk
[[ -f "$app_apk" ]] || { echo "App APK not found: $app_apk" >&2; exit 3; }
[[ -f "$test_apk" ]] || { echo "Test APK not found: $test_apk" >&2; exit 3; }

other_files=()
if [[ -n "$model" ]]; then
  if [[ "$model" != gs://* ]]; then
    model="$(cd "$(dirname "$model")" && pwd)/$(basename "$model")"
    [[ -f "$model" ]] || { echo "Model not found: $model" >&2; exit 2; }
  fi
  name="$(basename "$model")"
  other_files=(--other-files="/sdcard/Android/data/$package/files/models/$name=$model,/data/local/tmp/litert-models/$name=$model")
fi

device_args=()
for d in "${devices[@]}"; do
  device_args+=(--device "$d,locale=en,orientation=portrait")
done

set +e
gcloud firebase test android run \
  --project="$project" \
  --type=instrumentation \
  --app="$app_apk" \
  --test="$test_apk" \
  "${device_args[@]}" \
  ${other_files[@]+"${other_files[@]}"} \
  --timeout="$timeout" \
  --no-record-video \
  --num-flaky-test-attempts=0 \
  --directories-to-pull="/sdcard/Android/data/$package/files/ftl" \
  --results-dir="$results_dir" \
  --client-details=matrixLabel=litert-android-check 2>&1 | tee "$out/gcloud.log"
status=${PIPESTATUS[0]}
set -e

bucket=$(grep -oE 'gs://[^/ ]+|storage/browser/[^/ ]+' "$out/gcloud.log" | head -1 \
  | sed -E 's#storage/browser/#gs://#')
if [[ -n "$bucket" ]]; then
  # Not the pushed model Test Lab keeps beside the results (GBs).
  gsutil -m rsync -r -x '(^|.*/)(sdcard|data)/.*\.litertlm$' \
    "$bucket/$results_dir" "$out/" || true
fi
echo "results: $out (gcloud exit $status)"
find "$out" -name 'logcat' -o -name '*.png' -o -name 'summary.txt' -o -name 'selftest*.txt' \
  | sed "s#^$repo_dir/##" | sort
exit "$status"
