# LiteRT Demos on a Raspberry Pi 5

The Linux arm64 build of the two demos (voice chat with Gemma, live camera assistant) on a Raspberry Pi 5 with a
screen, keyboard and mouse. Everything runs on the Pi.

> **Status:** written for the Pi 5 and tested on the same Linux arm64 build on other arm64 machines (Ubuntu 22.04
> arm64, CPU and software GPU). Not yet run on a physical Pi 5: please send us the self-test report (step 6).

## What you need

| | |
|---|---|
| Board | **Raspberry Pi 5 with 8 GB or 16 GB** (4 GB is not enough for Gemma) |
| OS | **Raspberry Pi OS (64-bit)** with desktop, Bookworm or newer (glibc 2.36+). The 32-bit OS does not work |
| Storage | a fast microSD (A2) or, better, an NVMe SSD; about **8 GB free** |
| Cooling | the **Active Cooler** (or a case fan): the models keep all four cores busy |
| Power | the official 27 W USB-C supply |
| Camera | a USB webcam, **or an Android phone as a Wi-Fi camera** ([phone-camera.md](phone-camera.md)). The Pi Camera Module (CSI) is not supported by the app |
| Audio | a USB speakerphone (microphone + speaker in one, best) or a USB microphone + speaker/HDMI audio |
| Chat model | one `.litertlm` file, e.g. Gemma 4 E2B (2.6 GB, no login needed) from [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) (step 3); everything else is inside the app |

## 1. Prepare the Pi

```sh
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y libgtk-3-0 libvulkan1 mesa-vulkan-drivers vulkan-tools \
  pulseaudio-utils gstreamer1.0-plugins-base gstreamer1.0-plugins-good
sudo reboot
```
`pulseaudio-utils` provides `parecord`, which the app uses for the microphone (it works with the Pi's default
PipeWire sound server).

## 2. Install the app

Download the Linux arm64 package from the
[v0.1.2 release](https://github.com/DenisovAV/litert-edge-demos/releases/tag/v0.1.2) on the Pi (or copy it over: USB stick, `scp`),
check it, unpack it and start it:
```sh
cd ~
wget https://github.com/DenisovAV/litert-edge-demos/releases/download/v0.1.2/litert_hackathon-v0.1.2-linux-arm64.tar.gz \
     https://github.com/DenisovAV/litert-edge-demos/releases/download/v0.1.2/SHA256SUMS
sha256sum --ignore-missing -c SHA256SUMS
tar -xzf litert_hackathon-v0.1.2-linux-arm64.tar.gz
cd litert_hackathon-v0.1.2-linux-arm64
./run.sh
```
`run.sh` checks the sound server, microphone, speaker, GPU (Vulkan) and camera, prints what is missing and how to
install it, then starts the app. A log of every run is kept in `~/.local/state/litert_hackathon/run.log`.

## 3. First launch: the chat model

Every model except the chat model is inside the app. Put your `.litertlm` into the models folder before or after
the first start, for example straight from Hugging Face (2.6 GB):
```sh
mkdir -p ~/litert-demos/models
wget -P ~/litert-demos/models https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm
```
On **Set up models**, the **CHAT MODEL** card lists the files in `~/litert-demos/models/` (**Rescan** if needed,
**Path…** for a file elsewhere). Tap it, choose **CPU** (see step 4), then **Use this model**.

## 4. GPU or CPU

The Pi 5's GPU (VideoCore VII) is reached through Vulkan. Whether the AI runtime can use it for these models is
**not yet confirmed**:
- If loading on the GPU fails, the app says so and offers **Run on CPU** (chat model) or **Run detector on CPU**
  (live camera). Choose it: on the Pi the CPU path is the expected one.
- The app never switches silently: the **This device** card and the diagnostics overlay show where each model runs.

Expect on the CPU (rough, from comparable arm64 cores): the chat model a few to ~10 words per second, a spoken
question transcribed in a few seconds, the live boxes a few frames per second. The first start of each model is
slower than later ones.

## 5. Use it

- **Voice chat:** hold the mic button, speak, release; or type. Try *"What is the input size of the YOLO 26 nano
  detector?"* (answer from the knowledge base with sources) and *"Which accelerator are you running on?"*.
- **Live camera:** pick the camera source at the top of the demo: a USB webcam, or **Network camera** with your
  phone's address. Hold the mic and ask *"What do you see?"*, *"How many people are there?"*,
  *"Describe the scene"*.

## 6. Check and report

```sh
./run.sh --selftest            # add --skip-audio if no microphone/speaker is attached
```
It prints a report (board, OS, CPU, GPU and Vulkan driver, where each model ran, speed, memory, detector accuracy on
a reference picture, speaker and microphone) and saves it to a file. Exit code 0 means everything passed. Please
send us that file. In the app: **This device → Copy diagnostics**.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `GLIBC_2.35 not found` | You are on an old or 32-bit OS: install Raspberry Pi OS (64-bit), Bookworm or newer |
| "No sound server" / "Microphone unavailable" | `systemctl --user start pipewire pipewire-pulse`; `sudo apt install pulseaudio-utils` |
| "No audio output" | Select the speaker in the desktop's sound settings (HDMI or USB) |
| GPU load fails | Use **Run on CPU** / **Run detector on CPU** |
| Very slow, the Pi gets hot | Fit the Active Cooler; close other apps |
| No camera listed | Plug in a USB webcam, or use the phone ([phone-camera.md](phone-camera.md)) |
