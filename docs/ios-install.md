# LiteRT Demos on an iPhone — build and run

The two demos (voice chat with Gemma, live camera assistant) on an iPhone. Everything runs on the phone. There is
no ready-made iPhone build: iOS installs only apps signed for your own devices, so you build it from source on a Mac
with your Apple account (about 15 minutes the first time).

> **Status (2026-10-08, iPhone 17 Pro, iOS 26.5.2, release build):** Gemma 4 E2B loads and answers on the **GPU**
> (Metal, load 3.5 s); speech recognition, spoken replies and the knowledge base work; the object detector runs on the
> **CPU**. The detector on the GPU does not work on iOS yet (see [Known limitations](#known-limitations)).

## What you need

| | |
|---|---|
| Mac | Apple Silicon, **Xcode 26** with the iOS platform installed, [fvm](https://fvm.app) (Flutter 3.47.3 is pinned in `.fvmrc`), python3 3.10+ with venv (the detector file is derived at fetch time) |
| iPhone | **iOS 26 or newer** (a dependency of the agent skills links a library that older iOS lacks), **8 GB of RAM or more** (iPhone 15 Pro or newer), about **4 GB free** |
| Apple account | signed in to Xcode (**Xcode → Settings → Accounts**). A paid Apple Developer Program team is best: it can enable the two memory capabilities below |
| Hugging Face token | a read token in `.env` as `HF_TOKEN=hf_…`, after accepting the Gemma terms on [litert-community/embeddinggemma-300m](https://huggingface.co/litert-community/embeddinggemma-300m) (one built-in model is gated) |
| Chat model | one `.litertlm` file for the GPU: Gemma 4 E2B, `gemma-4-E2B-it.litertlm` (2.6 GB) from [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm). Qualcomm NPU builds (`…_qualcomm_…`) do not run on an iPhone |

## 1. Get the source and the built-in models

```sh
git clone https://github.com/DenisovAV/litert-edge-demos.git
cd litert-edge-demos
fvm install
tool/flutter_litert/vendor.sh     # flutter_litert + the project's patch into third_party/
tool/fetch_models.sh              # the built-in models into assets/models/, each one checked (uses HF_TOKEN)
fvm flutter pub get
```

## 2. Prepare the iPhone

1. Connect it to the Mac with a cable and tap **Trust** on the phone.
2. Turn on **Settings → Privacy & Security → Developer Mode** (the phone restarts; confirm after the restart).
3. Check that the Mac sees it: `fvm flutter devices` lists it as `(mobile) • … • ios`. If it does not, unlock the phone
   and run `fvm flutter devices --device-timeout 20`.

## 3. Sign it with your team

1. `open ios/Runner.xcworkspace`
2. Select the **Runner** target → **Signing & Capabilities**:
   - **Team:** your team, with **Automatically manage signing** on.
   - **Bundle Identifier:** change `dev.fluttergemma.litertHackathon` to one of your own, e.g.
     `com.<you>.litertdemos` (an identifier belongs to one team).
3. Keep the two capabilities the project lists, **Increased Memory Limit** and **Extended Virtual Addressing**
   (`ios/Runner/Runner.entitlements`): they let iOS give the app the memory a 2.6 GB model needs.
   If Xcode reports that your team cannot use them, remove both from that tab: the app still runs (that is how the
   status above was measured), but iOS may stop it under memory pressure.
4. Close Xcode. Don't commit these changes if you contribute back.

## 4. Build and install

```sh
fvm flutter run --release -d <your iPhone>     # the name or ID from `fvm flutter devices`
```
Use **release**: the models run at full speed and the app keeps working after you unplug the phone. The first build
downloads the native libraries (a few hundred MB) and takes several minutes; later builds take about two.

If the phone says *Untrusted Developer* (free accounts): **Settings → General → VPN & Device Management** → your
account → **Trust**.

## 5. Put the chat model on the phone

Every model except the chat model is inside the app. The app's models folder is visible in the **Files** app:
**On My iPhone → LiteRT Demos → models**. Any of these works:

- **Files / AirDrop:** AirDrop the `.litertlm` to the phone or save it in iCloud Drive, then move it into
  *On My iPhone → LiteRT Demos → models*.
- **Import file… in the app** (the Chat model card): pick it in the system picker; the app copies it in.
- **Download from URL… in the app:** for Gemma 4 E2B,
  `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm` (stay on
  Wi-Fi; a dropped download resumes).
- **From the Mac over the cable** (fastest; the app must have been opened once):
  ```sh
  xcrun devicectl list devices      # the phone's name
  xcrun devicectl device copy to --device <name> \
    --domain-type appDataContainer --domain-identifier <your bundle identifier> \
    --source gemma-4-E2B-it.litertlm --destination Documents/models/gemma-4-E2B-it.litertlm
  ```

## 6. First launch

1. Open **LiteRT Demos**. On **Set up models** the **CHAT MODEL** card lists the files in its models folder (tap
   **Rescan** if yours is missing). With exactly one file there and nothing chosen yet, it is already selected.
2. Check **GPU**, then **Use this model**. The first load on the GPU compiles GPU programs once (up to a minute);
   later starts take a few seconds.
3. Allow the **microphone** and the **camera** when a demo asks.

## 7. Use it

- **Voice chat:** hold the mic button, speak, release; or type. Try *"What is the input size of the YOLO 26 nano
  detector?"* (answer from the knowledge base, with sources), *"Which accelerator are you running on?"*, or attach a
  photo and ask about it. Tap the mic while it speaks to interrupt.
- **Live camera:** boxes appear around objects. Hold the mic and ask *"What do you see?"*, *"How many people are
  there?"* (instant, from the detector) or *"Describe the scene"* (Gemma looks at the frame).
- **Check and report:** home screen **⋮ → Models → Run self-test**, then **Copy**. The **This device** card shows where
  each model really runs.

## Known limitations

| | |
|---|---|
| Detector on the GPU | Fails on iOS: the detector's LiteRT (`flutter_litert`) and Gemma's LiteRT-LM both ship a `LiteRtMetalAccelerator.framework`, and the app can hold only one. The detector therefore runs on the **CPU** by default on iOS; choosing GPU in Demo 3's settings shows the error with **Run detector on CPU**. Tracked in [upstream-issues.md](upstream-issues.md) |
| Memory | Without the two memory capabilities iOS may warn and stop a model run (seen once: `LiteRtRunCompiledModel … (status=3)` after a memory warning) |
| iOS 18 and older | The app stops at launch (a dependency links `libswiftWebKit`, present from iOS 26) |
| Reinstalling | iOS moves the app's folders; the app finds the chosen model again in its models folder by name and size |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `No Accounts` / `No profiles for '…' were found` | Sign in to Xcode (step 3) and choose your team; change the bundle identifier |
| The phone is not listed / the install drops | Use the cable, unlock the phone, Developer Mode on; `fvm flutter devices --device-timeout 20` |
| *Untrusted Developer* | Settings → General → VPN & Device Management → Trust |
| The model is not listed | Tap **Rescan**; check it is in *On My iPhone → LiteRT Demos → models* and ends in `.litertlm` |
| Yellow "detector failed on the GPU" | Tap **Run detector on CPU** (see Known limitations) |
| You need the app's log | `fvm flutter run --release` prints it while attached. Without it, Flutter ships `idevicesyslog`: `~/fvm/versions/3.47.3/bin/cache/artifacts/libimobiledevice/idevicesyslog -u <udid> -p Runner` (set `DYLD_LIBRARY_PATH` to that `artifacts/` folder's `libimobiledevice`, `libimobiledeviceglue`, `libplist`, `libusbmuxd` and `openssl` subfolders) |
