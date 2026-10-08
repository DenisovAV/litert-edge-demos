# Checking a Jetson with `--selftest`

One command tells whether the app runs on a given Jetson and on what: the board, JetPack, the GPU adapter the engine
actually selected, the detector against the cats golden, Gemma's speed, and how much of the shared RAM it takes.
Design: [design/hardware-visibility.md](design/hardware-visibility.md) §5; Linux background:
[design/detector-linux.md](design/detector-linux.md).

## Which Jetsons can run it

| Board | Software | Verdict |
|---|---|---|
| Orin Nano 8 GB / Super, Orin NX, AGX Orin | **JetPack 6.x** (Ubuntu 22.04, glibc 2.35) or newer | expected to work: the arm64 bundle passed on Ubuntu 22.04 arm64 (CPU, and the GPU code path on llvmpipe). The Tegra GPU driver itself is not yet verified |
| Any Orin on JetPack 5.x (Ubuntu 20.04, glibc 2.31) | | **will not start**: flutter_gemma's native libraries need glibc ≥ 2.35; upgrade to JetPack 6 |
| Orin Nano 4 GB | JetPack 6 | starts, but Gemma 4 E2B needs ~3.3 GB of RAM on its own (measured on arm64, CPU); expect GPU loading to fail for memory |
| Jetson Nano (2019, Maxwell) | JetPack 4.6 (Ubuntu 18.04, glibc 2.27) | **cannot run** flutter_gemma at all |

## What to copy

| File | Size | SHA-256 | From |
|---|---|---|---|
| `litert_hackathon-linux-arm64.tar.gz` | 47 MB | `af75c808137261a8fd3597bbda40cfe8d8c9729f94a7205c7191ebfa54201e46` | `build/dist-linux/` on the dev Mac (built 2026-10-06 from `4a32b00`) |
| `gemma-4-E2B-it.litertlm` | 2 538 799 104 B | `2c902a8c1c7675ec57f51020f01571d765af2ca84859e8c8fcf663a56e6e587a` | download on the Jetson (below) |

```sh
mkdir -p ~/lh && cd ~/lh
tar -xzf litert_hackathon-linux-arm64.tar.gz
curl -L -o gemma-4-E2B-it.litertlm \
  https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/a039dc0b173d0710237e4c8dc40452302c8176e4/gemma-4-2p3b-it.litertlm
sha256sum gemma-4-E2B-it.litertlm
```

Runtime packages (a JetPack desktop image normally has them): `libgtk-3-0`, `libvulkan1` with NVIDIA's Vulkan ICD
(`/usr/share/vulkan/icd.d/nvidia_icd.json`), `vulkan-tools` (optional: lets the report list Vulkan devices), and
`xvfb` only for headless runs over SSH.

Optional, for the fastest numbers: `sudo nvpmodel -m 0` (MAXN / MAXN SUPER) and `sudo jetson_clocks`. The report
records the nvpmodel mode either way.

## Run

```sh
cd ~/lh
# on the Jetson's desktop; over SSH without a display, prefix with: xvfb-run -a
./litert_hackathon-linux-arm64/litert_hackathon --selftest \
  --gemma=$PWD/gemma-4-E2B-it.litertlm \
  --out=$HOME/selftest_jetson_1.txt --timeout=1800
echo "exit=$?"
```

- **Run it twice.** The first run compiles GPU programs and writes caches: on the T4 the first Gemma load took 106 s
  and the second 14 s. On a slow GPU the very first detector check may fail once with
  `LiteRtLockTensorBuffer … kLiteRtStatusErrorRuntimeFailure` (seen once on llvmpipe); rerun before concluding.
- If the GPU fails, get CPU numbers too: add `--gemma-backend=cpu --detector-backend=cpu`.
- Exit code 0 = every step passed. A software Vulkan device (llvmpipe) fails the GPU steps on purpose; only
  `--allow-software-gpu` lets them pass, marked as such.
- Step 6 checks audio (a 1 s 440 Hz tone, recorded back from the sink's monitor, then 1 s from the microphone). It
  needs a running PulseAudio/PipeWire session and `pulseaudio-utils`; over SSH without one it fails on purpose with
  what is missing. Add `--skip-audio` for a GPU-only run; a silent microphone is only a WARN.
- Send back the `selftest_jetson_*.txt` files (and the `.native.log` next to them if something failed).

## What to read in the report

- `device`: board model (device tree), L4T/JetPack, nvpmodel mode, RAM.
- `adapter … (confirmed: native log)`: the GPU the engine selected, from LiteRT's own `Selected adapter:` line. On
  an Orin this should name the Tegra GPU with `backend=Vulkan`; `llvmpipe`/`CPU / Software` means no GPU.
- `cats golden`: max box error ≤ 3 px (0.04 px everywhere so far) and the detector's median run time.
- `gemma generate`: tok/s.
- `memory`: the `Δ available` column. On a Jetson the GPU takes its memory from the same RAM, so this is the number
  that decides whether everything fits in 8 GB.

## Reference results (2026-10-06, release bundles)

| Host | Detector | Gemma | Gemma load Δ available / peak RSS |
|---|---|---|---|
| GCP T4 (x86_64), warm | GPU fp32 full, adapter `Tesla T4 (Discrete GPU)` confirmed | GPU, 82.5 tok/s | −987 MB / 2.2 GB (weights in VRAM) |
| GCP t2a arm64, CPU | CPU | CPU, 64 tokens in 6 s | |
| GCP t2a arm64, llvmpipe | `GPU fp32 full` on `llvmpipe … CPU / Software` (allowed), 8.2 s/frame | CPU, 15 tok/s | −3.26 GB / 5.15 GB |
| macOS M4 Pro (release, model store) | GPU fp32 full, Metal, 5.3 ms | GPU, 77.4 tok/s | −970 MB / 1.74 GB |
