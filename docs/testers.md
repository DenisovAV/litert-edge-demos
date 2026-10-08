# LiteRT Hackathon demos — tester guide (v0.1.2)

Two on-device AI demos in one app. Everything runs **on your device**: no cloud, no account, no internet needed.
Speech recognition, spoken replies, the object detector and the knowledge base are inside the app; **you bring the
chat model** — one `.litertlm` file (a Gemma build for your phone's NPU, or Gemma 4 E2B for the GPU).

- **Voice chat (Demo 1).** Talk or type to Gemma; add a photo; ask questions about the bundled knowledge base
  (answers cite their sources); simple skills ("what time is it?", "which accelerator are you running on?").
- **Live camera (Demo 3).** The camera shows live object boxes; hold the mic button and ask about the scene. Simple
  questions ("how many people?") are answered from the detector instantly; detailed ones ("describe the scene",
  "read the sign") send the current frame to Gemma.

## 1. Which build do I take?

| Your device | File | Requirements |
|---|---|---|
| Android phone or tablet | `android/litert_hackathon-v0.1.2-arm64.apk` | Android 11+, 64-bit ARM, **8 GB RAM recommended**, ~4 GB free storage (app + its models + your chat model) |
| Linux PC / laptop | `linux/litert_hackathon-v0.1.2-linux-x64.tar.gz` | Ubuntu 22.04+ (or any distro with glibc ≥ 2.35), a GPU with a **Vulkan** driver (NVIDIA proprietary driver, or Mesa for AMD/Intel), PulseAudio or PipeWire |
| NVIDIA Jetson Orin (Nano 8 GB, NX, AGX), Raspberry Pi 5 (8/16 GB) | `linux/litert_hackathon-v0.1.2-linux-arm64.tar.gz` | **JetPack 6** or newer (JetPack 5 is not supported). See [jetson-check.md](jetson-check.md) |

Check the download against `linux/SHA256SUMS` (`sha256sum -c SHA256SUMS`).

## 2. Install

**Android**
1. Copy the APK to the phone (or download it there) and open it.
2. Allow "Install unknown apps" for the app you opened it with, when asked.
3. Start **LiteRT Hackathon**. Allow the microphone and the camera when a demo asks.

**Linux / Jetson**
```sh
tar -xzf litert_hackathon-v0.1.2-linux-x64.tar.gz      # or …-arm64 on a Jetson
cd litert_hackathon-v0.1.2-linux-x64
./run.sh
```
`run.sh` checks the sound server, microphone, speaker, GPU (Vulkan) and camera before it starts the app, and prints
what to install if something is missing, for example:
```sh
sudo apt install pulseaudio-utils                 # microphone capture (parecord)
sudo apt install libvulkan1 mesa-vulkan-drivers   # GPU on AMD/Intel; NVIDIA needs its proprietary driver
sudo apt install gstreamer1.0-plugins-good        # USB webcam
```
A log of every run is kept in `~/.local/state/litert_hackathon/run.log`.

## 3. First launch: the chat model

The app ships every model except the chat model:

| Built in | Size | Used for |
|---|---|---|
| Whisper base | 80 MB | speech recognition, voice chat |
| moonshine-tiny | 111 MB | fast speech recognition, live camera |
| Inflect-nano-v2 | 36 MB | spoken replies |
| YOLO26n | 10 MB | object detector |
| EmbeddingGemma + a prebuilt index | 188 MB | knowledge base |

**The chat model** (`.litertlm`) you put into the models folder:
- **Linux / Jetson / Raspberry Pi:** `~/litert-demos/models/`
- **Android:** `/sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/models/` or
  `/data/local/tmp/litert-models/`, copied with `adb push` — see [android-install.md](android-install.md).

Which file:
- a **Gemma build for your phone's Qualcomm NPU** (e.g. `gemma4_2b_SM8850.litertlm` for a Snapdragon 8 Elite Gen 5);
- or **Gemma 4 E2B** for the GPU (any recent device): `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm`
  → `gemma-4-E2B-it.litertlm` (2.5 GB).

On first launch the **Set up models** screen shows the **CHAT MODEL** card: the folders (with **Copy the folder
path**), the files found (**Rescan**, or **Path…** for any file), and **Download from URL…** if you have a direct
link instead. Tap the file, check **NPU / GPU / CPU**, **Context length**, **Images** and **Tools** (filled in from
the file), then **Use this model**. The app loads it on exactly the backend you chose; if that fails it shows the
reason and offers **Run on GPU** / **Run on CPU** — it never switches silently. NPU builds only run on the chip family
they were compiled for.

**The first start of a model on the GPU is slow** (it compiles GPU programs once): up to a minute or two on some
machines. Later starts take seconds. You can change the model later: home screen **⋮ (More) → Models**.

## 5. What to try

**Voice chat**: hold the mic button, speak, release. Or type.
- "What can you do?" · attach a photo and ask "What is in this picture?"
- Knowledge base (answers show source chips): "What is the input size of the YOLO 26 nano detector?",
  "How many dimensions does EmbeddingGemma produce?"
- Skills: "What time is it?", "Which accelerator are you running on?"
- Press the mic while it is speaking to interrupt it.
- Your own skill: put a `SKILL.md` in the skills folder, then **Skills → Reload** (no rebuild):
  Android `/sdcard/Android/data/dev.fluttergemma.litert_hackathon/files/skills/<name>/SKILL.md` (via `adb push`),
  Linux `~/Documents/skills/<name>/SKILL.md`.

**Live camera**: point the camera, hold the mic, ask in under 5 seconds.
- Fast (detector only): "What do you see?", "How many people are there?", "Is there a cup?"
- Detailed (the frame goes to Gemma): "Describe the scene", "What colour is the cup?", "Read the sign"

## 6. Diagnostics: tell us what it ran on

- **This device** card (home screen and Models screen): the chip, GPU, memory, and where each model actually runs
  (e.g. "GPU, confirmed"). **Copy diagnostics** copies a full text report.
- **Run self-test** (⋮ → Models): loads the detector and the chat model, checks the detector against a reference
  picture, measures speed and memory, and tests the speaker and microphone. **Copy** the report.
- Linux / Jetson from a terminal: `./run.sh --selftest` (add `--skip-audio` on a machine without sound). The report
  is printed and saved to a file; the exit code is 0 when everything passed.

## 7. Troubleshooting

| Symptom | What to do |
|---|---|
| "No sound server" / "Microphone unavailable" (Linux) | `systemctl --user start pipewire pipewire-pulse` (or `pulseaudio --start`); `sudo apt install pulseaudio-utils` |
| "No audio output" | No working speaker device: check the sound settings, plug in headphones or a USB speaker |
| The report says the GPU is **llvmpipe / software** (Linux) | No real GPU driver: install the NVIDIA driver or `mesa-vulkan-drivers`. Or choose CPU on the Models screen (slower) |
| The chat model fails to load on GPU | Use the offered **Run on CPU**; on phones with less than 8 GB RAM the GPU model may not fit |
| The model file is not listed | Tap **Rescan**; the name must end in `.litertlm`; on Android open the app once before `adb push` |
| Linux: app does not start, mentions `GLIBC_2.35` | The distribution is too old: use Ubuntu 22.04+ |
| Jetson: very slow first run, or the first detector check fails once | Run again (GPU programs are compiled on the first run); `sudo nvpmodel -m 0` for full power |

## 8. Sending feedback

Please send: what you tried, what happened, and the **Copy diagnostics** or **self-test** report.
Send to: <!-- TODO(owner): contact / channel --> **(to be filled in)**.

## Licences

The app includes YOLO26n (AGPL-3.0, derived from Arm/yolo26n-fp16-litert), EmbeddingGemma (Gemma Terms of Use,
https://ai.google.dev/gemma/terms), Whisper base (Apache-2.0), Inflect-nano-v2 (Apache-2.0; its G2P files MIT) and
moonshine-tiny (MIT); the chat model is your own `.litertlm`, under its own licence. The full list is in the app: home screen **⋮ (More) → Licences**.
