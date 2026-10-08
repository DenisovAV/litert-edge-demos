# LiteRT Demos on an Arduino VENTUNO Q

Every number below comes from our runs on a real board through Qualcomm Device Cloud on 2026-10-08, except
Arduino's own GenieX figures, which are marked as theirs.

The Linux arm64 build of the two demos (voice chat with Gemma, live camera assistant) on an Arduino VENTUNO Q with a
screen, keyboard and mouse. Everything runs on the board.

> **Status:** our Linux arm64 package ran on the board as it is (v0.1.1; v0.1.2 has the same code path plus fixes),
> and its self-test passed 6 of 6 steps. The audio step was skipped because the remote session had no microphone or
> speaker. The board's NPU is not used by the app yet: NPU support on Linux is in progress (see
> [The NPU](#the-npu-in-progress)).

## The board

| | |
|---|---|
| SoC | Qualcomm Dragonwing IQ8 (QCS8275): 4× Cortex-A78C + 4× Cortex-A55 |
| NPU | Hexagon V75, 40 TOPS |
| GPU | Adreno 623, Vulkan through Mesa (turnip) |
| Memory | 16 GB (14.9 GB visible to Linux) |
| System | Ubuntu 24.04.4, kernel 6.8.0-1080-qcom, glibc 2.39 |

## What you need

| | |
|---|---|
| Board | the VENTUNO Q with its Ubuntu 24.04 system |
| Camera | a camera the board sees as `/dev/video*`, **or an Android phone as a Wi-Fi camera** ([phone-camera.md](phone-camera.md)). No camera picture was checked in the remote session (see step 2) |
| Audio | a microphone and a speaker; not tested on this board yet |
| Chat model | one `.litertlm` file: Gemma 4 E2B (`gemma-4-E2B-it.litertlm`, 2.6 GB, no login needed) from [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) (step 3). Everything else is inside the app |

## 1. Prepare the board

```sh
sudo apt update
sudo apt install -y pulseaudio-utils
```
On the tested board this was the only missing package. `pulseaudio-utils` provides `pactl` and `parecord`, which
the app's sound check and microphone use. The rest of what `run.sh` checks was already in place: Vulkan found the
Adreno 623, GStreamer's camera plugin was there, and the JPEG library (libturbojpeg) ships inside the package.

## 2. Install the app

Download the Linux arm64 package from the
[v0.1.2 release](https://github.com/DenisovAV/litert-edge-demos/releases/tag/v0.1.2) on the board (or copy it over),
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
install it, then starts the app. On the tested board it reported Vulkan `Adreno623` OK, the GStreamer camera
(`/dev/video32`, `/dev/video33`) OK and libturbojpeg shipped; it reported `pulseaudio-utils` missing until step 1
was done. Its camera check only sees that GStreamer's camera plugin is installed and that `/dev/video*` nodes exist
and can be opened; whether those two nodes give a picture was not checked. A log of every run is kept in
`~/.local/state/litert_hackathon/run.log`.

## 3. First launch: the chat model, on the CPU

Every model except the chat model is inside the app. Put your `.litertlm` into the models folder before or after
the first start, for example straight from Hugging Face (2.6 GB):
```sh
mkdir -p ~/litert-demos/models
wget -P ~/litert-demos/models https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm
```
On **Set up models**, the **CHAT MODEL** card lists the files in `~/litert-demos/models/` (**Rescan** if needed,
**Path…** for a file elsewhere). Tap it, choose **CPU**, then **Use this model**.

**Why CPU:** on this board the chat model is faster on the CPU, and the detector is faster on the GPU. Measured by
the self-test:

| | CPU | GPU (Adreno 623) |
|---|---|---|
| Gemma 4 E2B, decode | **9.9 tokens/s** | 5.4 tokens/s |
| Gemma 4 E2B, first chunk of the reply | 1.65 s | 1.73 s |
| YOLO26n detector, first run | 223 ms | **108 ms** (fully on the GPU, through WebGPU/Vulkan) |

**Recommendation: the chat model on the CPU, the detector on the GPU.** The detector runs on the GPU by default
(the live camera demo's settings, **Detector**). The app never switches silently: the **This device** card and the
diagnostics overlay show where each model runs.

## 4. Use it

- **Voice chat:** hold the mic button, speak, release; or type. Try *"What is the input size of the YOLO 26 nano
  detector?"* (answer from the knowledge base with sources) and *"Which accelerator are you running on?"*.
- **Live camera:** pick the camera source at the top of the demo: a camera on the board, or **Network camera** with
  your phone's address ([phone-camera.md](phone-camera.md)). Hold the mic and ask *"What do you see?"*,
  *"How many people are there?"*, *"Describe the scene"*.

## 5. Check and report

```sh
./run.sh --selftest            # add --skip-audio if no microphone/speaker is attached
```
It prints a report (board, OS, CPU, GPU and Vulkan driver, where each model ran, speed, memory, detector accuracy on
a reference picture, speaker and microphone) and saves it to a file. Exit code 0 means everything passed. Please
send us that file. In the app: **This device → Copy diagnostics**.

On the tested board the run with `--skip-audio` passed 6 of 6 steps, on the CPU and on the GPU. In v0.1.1 its device
section said `gpu none found` and step 1 said `0 GPU(s)`, although the next line listed `vulkan Adreno623 ·
INTEGRATED_GPU` and the detector step named `Adreno623` as the adapter: the GPU was found and used, only those two
lines were wrong. v0.1.2 names the Adreno 623 there, marked as inferred from Vulkan.

## The NPU (in progress)

- **It works outside the app.** The official `litert-community/gemma-4-E2B-it-litert-lm` repository has a build for
  this chip, `gemma-4-E2B-it_qualcomm_qcs8275.litertlm` (3.29 GB). With LiteRT-LM 0.18.0 on Linux it runs on the
  Hexagon NPU: load 1.1 s, first token 0.20 s, **16.6 tokens/s** decode. A question about an image works too (the
  vision part runs on the CPU; first token 9.2 s).
- **What that takes today:** a Qualcomm LiteRT dispatch library for Linux, which Google does not publish (we built it
  from the LiteRT-LM v0.18.0 source), plus the QAIRT runtime libraries 2.50 or newer. The board's QAIRT from apt
  (2.46) is too old for that dispatch library.
- **Not in the app yet:** the app's NPU path is Android-only today. NPU support on Linux is being added to the app's
  runtime package (`flutter_edge_ai`); this guide will be updated when it lands. Until then, use
  `gemma-4-E2B-it.litertlm` on the CPU (step 3), not the NPU build.
- **NPU builds are compiled per chip:** a build for a phone's SM8850 does not run on the QCS8275.
- **Gemma 4 E2B on this NPU today:** Arduino documents Qualcomm GenieX for it, in the official tutorial
  [docs.arduino.cc/tutorials/ventuno-q/geniex](https://docs.arduino.cc/tutorials/ventuno-q/geniex). Arduino's
  measurement: 12.7 tokens/s on the NPU against 4.7 on the CPU.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `pactl did not run: install pulseaudio-utils` (from `run.sh` or the self-test) | `sudo apt install pulseaudio-utils` |
| The self-test says `gpu none found` / `0 GPU(s)` | v0.1.1 only: the GPU is found (see step 5); v0.1.2 names it |
| Chat replies are slow | Choose **CPU** on the CHAT MODEL card: 9.9 tokens/s against 5.4 on the GPU |
| The `…_qualcomm_qcs8275.litertlm` file does not run in the app | Expected for now: the app has no NPU path on Linux yet. Use `gemma-4-E2B-it.litertlm` |
| No camera picture | Use the phone as a camera ([phone-camera.md](phone-camera.md)) |
