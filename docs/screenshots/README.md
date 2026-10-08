# Screenshots

Taken on macOS (M4 Pro) on 2026-10-02 by `integration_test/showcase_test.dart` and
`integration_test/email_shots_test.dart`, with fixture images and pre-recorded questions instead of the camera and
the microphone. Everything runs on the device: Gemma 4 E2B on the GPU, YOLO26n on the GPU, speech and embeddings on
the CPU. The diagnostics overlay is off, except in the two `*-overlay-nerd` shots.

| File | What it shows |
|---|---|
| `home.png` | The home screen: both demos ready after setup |
| `demo1-image-qa-bear.png` | Demo 1: a photo attached to the question "What's going on in this picture?", answered "A large brown bear is looking directly at the camera in a grassy area." |
| `demo1-rag-citations.png` | Demo 1: a knowledge-base answer ("640 × 640") with its three citation chips, and no tool step |
| `demo1-rag-source.png` | Demo 1: citation [1] opened, showing the excerpt, its document, the similarity and the source link |
| `demo1-skill-steps-timer.png` | *(Timer skill removed 2026-10-06; kept for history.)* Demo 1: "Set a timer for 10 seconds", run directly by the app; the steps panel shows `runIntent(start_timer, {"seconds":10})` and its result |
| `demo1-device-info.png` | Demo 1: "Which accelerator is running right now?": `loadSkill(device_info)` → `runIntent(device_info)` with the real backends (Gemma and YOLO26n on the GPU, speech and EmbeddingGemma on the CPU) |
| `demo1-skills-sheet.png` | Demo 1: the Skills sheet after Reload, listing the Markdown skills from the skills folder |
| `demo1-tea-timer-runtime-skill.png` | *(Timer skill removed 2026-10-06; kept for history — the runtime example is now `kid-clock`.)* Demo 1: "Start the tea timer", a skill added as a Markdown file at run time, starting a three-minute "tea" timer |
| `demo1-watcher-cup.png` | *(Camera watcher removed 2026-10-06; kept for history.)* Demo 1: the camera watcher: the picture-in-picture with the mug's box ("cup 0.96") and the app's own announcement "I can see a cup." |
| `demo1-overlay-nerd.png` | Demo 1 with the diagnostics overlay: models and their backends, load and warm-up times, TTFT, tokens/s, context use, STT/TTS timings, knowledge base and memory |
| `demo3-fast-count-cats.jpg` | Demo 3: live boxes, and "How many cats do you see?" answered "I count two cats." from the detections, with no LLM (chip "cat ×2 · remote — detector, no LLM") |
| `demo3-fast-bear.jpg` | Demo 3: "Is there a bear?" → "Yes, I see a bear.", a fast answer from the detector |
| `demo3-detailed-describe.jpg` | Demo 3: "Describe the scene." on a cat on a laptop: the view frozen on the frame sent to Gemma, with Gemma's description |
| `demo3-sign-do-not-feed-the-ai.jpg` | Demo 3: "What does the sign say?" → "The sign says "PLEASE DO NOT FEED THE AI"", read by Gemma from the frozen frame |
| `demo3-sign-wifi-password.jpg` | Demo 3: the same question on a sticky note → "The sign says "WIFI PASSWORD: gemma4"" |
| `demo3-overlay-nerd.jpg` | Demo 3 with the diagnostics overlay: detector backend (GPU fp32, fully accelerated), 15 fps, per-frame pre/run/post times, route and latencies |

## Image sources

- The bear, cats, cat-on-laptop and zebra scenes and the pirate mug are from the
  [COCO 2017](https://cocodataset.org) validation set. The COCO Consortium does not own the images: each one is a
  Flickr photo under the Creative Commons licence recorded in the COCO annotations (`captions_val2017.json`), and it
  stays under that licence here, in `test_assets/showcase/`, in `test_assets/yolo26n/` and in these screenshots. The
  photographer is named on each Flickr page.

  | COCO id | Scene | Flickr photo | Licence |
  |---|---|---|---|
  | 285 | bear | [9138147604](https://www.flickr.com/photo.gne?id=9138147604) | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) |
  | 39769 | two cats on a blanket | [210383891](https://www.flickr.com/photo.gne?id=210383891) | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/) |
  | 1675 | cat on a laptop | [301990977](https://www.flickr.com/photo.gne?id=301990977) | [CC BY-NC-SA 2.0](https://creativecommons.org/licenses/by-nc-sa/2.0/) |
  | 1818 | zebras | [7923308928](https://www.flickr.com/photo.gne?id=7923308928) | [CC BY-NC-SA 2.0](https://creativecommons.org/licenses/by-nc-sa/2.0/) |
  | 2592 | pirate mug | [2864950455](https://www.flickr.com/photo.gne?id=2864950455) | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/) |

  The two NC images (1675, 1818) and the screenshots that show them are for non-commercial use only.
- The two signs were drawn for this showcase by `tool/make_showcase_signs.py`.
- The fixtures are in `test_assets/showcase/`, and the questions there were spoken by macOS `say`.
