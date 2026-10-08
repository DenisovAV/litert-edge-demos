# LiteRT Demos on an NVIDIA Jetson

The Linux arm64 build of the two demos on a Jetson Orin with a screen, keyboard and mouse. Everything runs on the
board. For a one-command hardware check and how to read its report, see [jetson-check.md](jetson-check.md).

> **Status:** the same arm64 build passed on Ubuntu 22.04 arm64 machines (CPU, and the GPU code path on a software
> Vulkan device). The Jetson's own GPU driver is not yet verified: please send the self-test report (step 5).

## What you need

| | |
|---|---|
| Board | **Jetson Orin Nano 8 GB / Orin Nano Super, Orin NX or AGX Orin**. Orin Nano 4 GB: too little memory for Gemma on the GPU. The 2019 Jetson Nano, TX2 and Xavier do not work (too old a system) |
| System | **JetPack 6 or newer** (Ubuntu 22.04 base). JetPack 5 does not work |
| Storage | about **8 GB free**; an NVMe SSD is much faster than microSD |
| Camera | a USB webcam, **or an Android phone as a Wi-Fi camera** ([phone-camera.md](phone-camera.md)). The CSI camera ports (`nvarguscamerasrc`) are not supported by the app |
| Audio | a USB speakerphone (microphone + speaker in one, best). The Orin Nano developer kit has no audio jack |
| Chat model | one `.litertlm` file, e.g. Gemma 4 E2B (2.6 GB, no login needed) from [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) (step 3); everything else is inside the app |

## 1. Prepare the board

```sh
cat /etc/nv_tegra_release        # R36.x = JetPack 6 (required)
sudo apt update
sudo apt install -y libgtk-3-0 libvulkan1 vulkan-tools pulseaudio-utils \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
sudo nvpmodel -m 0               # full power (MAXN / MAXN SUPER); optional but recommended
sudo jetson_clocks               # optional: fixed maximum clocks until reboot
```
`vulkaninfo --summary` should list the NVIDIA Tegra GPU. If it only lists `llvmpipe`, the NVIDIA Vulkan driver is
missing: reinstall JetPack's `nvidia-l4t-*` packages.

## 2. Install the app

Copy the Linux arm64 package (`litert_hackathon-v0.1.2-linux-arm64.tar.gz` and its `SHA256SUMS`: the package you
received, or one built from source, see the [README](../README.md#building-from-source)) to the board, then check it,
unpack it and start it:
```sh
cd ~
sha256sum --ignore-missing -c SHA256SUMS
tar -xzf litert_hackathon-v0.1.2-linux-arm64.tar.gz
cd litert_hackathon-v0.1.2-linux-arm64
./run.sh
```
`run.sh` checks sound, microphone, speaker, GPU and camera, tells you what to install, then starts the app. Log:
`~/.local/state/litert_hackathon/run.log`.

## 3. First launch: the chat model

Every model except the chat model is built in. Put your `.litertlm` into **`~/litert-demos/models/`**, for example
straight from Hugging Face (2.6 GB):
```sh
mkdir -p ~/litert-demos/models
wget -P ~/litert-demos/models https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm
```
On **Set up models** the
**CHAT MODEL** card lists it (**Rescan**, or **Path…**): tap it, choose **GPU** (or **CPU** if the GPU fails), then
**Use this model**.

**The very first start on the GPU is slow** (the runtime compiles GPU programs once; minutes on an Orin Nano).
If the first detector check fails once with `LiteRtLockTensorBuffer … RuntimeFailure`, start again before
concluding anything.

## 4. Use it

- **Voice chat:** hold the mic button, speak, release; or type. *"Which accelerator are you running on?"* tells you
  where each model runs.
- **Live camera:** choose the camera source at the top of the demo (USB webcam, or **Network camera** with the
  phone's address); hold the mic and ask *"What do you see?"*, *"Describe the scene"*.
- If the GPU cannot be used, the app says so and offers **Run on CPU** / **Run detector on CPU**; it never switches
  silently.

## 5. Check and report

```sh
./run.sh --selftest              # --skip-audio if no microphone/speaker
```
The report names the board (e.g. "NVIDIA Jetson Orin Nano Developer Kit"), JetPack, power mode, the GPU the runtime
selected, speed and **how much of the shared memory** the models took (on a Jetson the GPU uses the same RAM). Send
us the file it saves. Details: [jetson-check.md](jetson-check.md).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `GLIBC_2.35 not found` | JetPack 5 or older: flash JetPack 6 |
| Report says GPU `llvmpipe` / software | NVIDIA Vulkan driver missing (see step 1), or use CPU |
| Out of memory, app closes on an Orin Nano | Close the browser and other apps; choose CPU for the detector; the 4 GB Orin Nano cannot hold Gemma |
| "No sound server" / "Microphone unavailable" | `systemctl --user start pipewire pipewire-pulse` (or `pulseaudio --start`); `sudo apt install pulseaudio-utils` |
| No camera | USB webcam, or the phone ([phone-camera.md](phone-camera.md)) |
