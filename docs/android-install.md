# LiteRT Demos on Android — install and run

Two on-device AI demos: a voice chat with Gemma and a live camera assistant. Everything runs on the phone and the
app needs **no internet**. Speech recognition, spoken replies, the object detector and the knowledge base are
inside the app. **You bring the chat model**: one `.litertlm` file, copied to the phone once.

## Before you start

- **Phone:** Android 11 or newer, 64-bit, **8 GB of RAM or more recommended**. Tested on a Samsung Galaxy S24
  (Snapdragon 8 Gen 3, GPU) and a Galaxy S26 (Snapdragon 8 Elite Gen 5, NPU).
- **Free storage:** about **4 GB** (the app 0.6 GB, its built-in models unpacked once 0.4 GB, and the chat model
  about 2.6 GB).
- **The chat model file** (`.litertlm`), one of:
  - a **Gemma build for your phone's Qualcomm NPU**, e.g. `gemma4_2b_SM8850.litertlm` for a Snapdragon 8 Elite Gen 5
    (SM8850). NPU builds only run on the chip family they were compiled for;
  - or the general **Gemma 4 E2B** for the GPU, which runs on any recent phone:
    `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm` → `gemma-4-E2B-it.litertlm` (2.5 GB).
- **A computer with adb** to copy the model (step 3), or a direct download link to the model (step 3, option C).

## 1. Install the APK

**On the phone (main way)**
1. Get `litert_hackathon-v0.1.2-arm64.apk` onto the phone: download it from the link you received, or copy it over USB
   into *Downloads*.
2. Open it from **My Files → Downloads** (or from the browser's downloads).
3. Android asks to allow installing apps from this source: tap **Settings**, turn on **Allow from this source**, go
   back, tap **Install**.
4. If **Google Play Protect** warns about an unknown app: tap **More details → Install anyway**. (The app is signed
   by the developer but not published on Google Play.)

**Samsung: Auto Blocker.** On newer Galaxy phones (One UI 6 and later) *Auto Blocker* may stop the install with
"Blocked by Auto Blocker", and it also blocks adb over USB. Turn it off while you install and copy the model:
**Settings → Security and privacy → Auto Blocker → off**. You can turn it back on afterwards.

**From a computer with adb (alternative)**: see step 2 for setting up adb, then
`adb install -r litert_hackathon-v0.1.2-arm64.apk` (`-r` updates an existing install and keeps its data).

**Updating later:** install the new APK over the old one. Do not uninstall first: that deletes the unpacked models
and the app's folder with your chat model.

## 2. Set up adb on your computer (once)

1. Install the Android platform tools:
   - macOS: `brew install --cask android-platform-tools`
   - Ubuntu/Debian: `sudo apt install adb`
   - Windows: `winget install Google.PlatformTools`
   - or download "SDK Platform-Tools" from developer.android.com/tools/releases/platform-tools and unzip it.
2. Turn on **USB debugging** on the phone:
   - Samsung: **Settings → About phone → Software information**, tap **Build number** 7 times (enter your PIN),
     then **Settings → Developer options → USB debugging → on**.
   - Other phones: **Settings → About phone**, tap **Build number** 7 times, then **Developer options → USB
     debugging**.
3. Connect the phone by USB, accept **Allow USB debugging?** on the phone, and check: `adb devices` lists it as
   `device`.

## 3. Copy the chat model to the phone

**Open the app once first.** On the first start it creates its models folder; a file pushed before that may be
unreadable for the app.

**A. Into the app's models folder (recommended)**
```sh
adb push gemma4_2b_SM8850.litertlm /sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/models/
```

**B. Into the shared folder (if A says "cannot be read")**
```sh
adb shell mkdir -p /data/local/tmp/litert-models
adb push gemma4_2b_SM8850.litertlm /data/local/tmp/litert-models/
```
The app looks in both folders. Copying 2.6 GB takes a minute or two over USB.

**C. Without a computer:** in the app, **Download from URL…** with a direct link to the `.litertlm` file (stay on
Wi-Fi; a dropped download resumes).

## 4. Choose the model in the app

1. Open **LiteRT Demos**. The **Set up models** screen shows the **CHAT MODEL** card. Under **Models folders (used
   in place, no copy)** it lists both folders (with **Copy the folder path**) and the `.litertlm` files it finds.
   Tap **Rescan** if your file is not listed yet; **Path…** accepts any full path.
2. Tap your file. Check the settings:
   - **NPU / GPU / CPU**: an NPU build should run on **NPU**; Gemma 4 E2B on **GPU**. NPU is only offered where the
     phone's NPU can be reached; otherwise the card says why.
   - **Context length**: an NPU build has one compiled length (the app fills it in, e.g. 4096).
   - **Images** and **Tools**: the app sets them from the file (NPU builds usually have no image support; then
     photos in the demos are switched off with a note).
3. Tap **Use this model**. The app loads it **on exactly the backend you chose**. If that fails (wrong chip, NPU not
   available) it shows the reason and offers **Run on GPU** / **Run on CPU**; it never switches silently.
4. When it is loaded the app opens the home screen with two tiles. The first launch also unpacks the built-in models
   once (a few seconds).

## 5. Run the demos

**Voice chat**
- Allow the **microphone** when asked.
- Hold the **mic** button, speak, release. Or type.
- Try: *"What can you do?"* · *"What is the input size of the YOLO 26 nano detector?"* (an answer from the knowledge
  base, with source chips) · *"What time is it?"* · *"Which accelerator are you running on?"* (it names your chip
  and whether the model runs on the NPU, GPU or CPU) · with a model that supports images, attach a photo.
- Tap the mic while it speaks to interrupt.

**Live camera**
- Allow the **camera** and the **microphone** when asked.
- Point the camera: boxes appear around objects.
- Hold the mic and ask, in under 5 seconds: *"What do you see?"*, *"How many people are there?"*,
  *"Is there a cup?"* (instant, from the detector), or *"Describe the scene"* (Gemma looks at the frame, if the model
  supports images).

## 6. If something goes wrong

| Problem | Fix |
|---|---|
| "App not installed" | Free up storage; if an older build with a different signature is installed, uninstall it first |
| Blocked by Auto Blocker (Samsung) | Settings → Security and privacy → Auto Blocker → off |
| The model file is not listed | Tap **Rescan**; check the file name ends in `.litertlm`; open the app once before pushing |
| "cannot be read (Permission denied)" | Push it into `/data/local/tmp/litert-models/` instead (step 3 B) |
| NPU not offered / NPU load fails | The file is not for this phone's chip, or the phone's NPU cannot be reached: use the right NPU build, or Gemma 4 E2B on **GPU** |
| No voice reply | Check the media volume; the reply also appears as text |

## 7. Tell us how it went

Home screen **⋮ → Models → Run self-test**, then **Copy**, and send the report together with what you tried and what
happened. The **This device** card on the home screen (**Copy diagnostics**) shows the chip and where each model
actually ran.

If the app crashed or froze, also attach the phone's log, taken right after it happened:
```sh
adb logcat -d > litert-demos-log.txt
```
