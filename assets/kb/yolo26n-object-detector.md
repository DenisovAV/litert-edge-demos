---
title: YOLO26n FP16 object detector for LiteRT
source: https://huggingface.co/Arm/yolo26n-fp16-litert/blob/147b75b5a2d6122266f731a16343119ee22b5055/README.md
license: AGPL-3.0
---

# YOLO26n FP16 object detector for LiteRT

This document describes the YOLO26n FP16 LiteRT package published by Arm on Hugging Face (`Arm/yolo26n-fp16-litert`): what the model is, its input and output tensors, its accuracy on COCO, its latency and memory on an Android phone's CPU, how it was converted, and its AGPL-3.0 license.

## What YOLO26n FP16 for LiteRT is

YOLO26n FP16 is a LiteRT object-detection model prepared for the XNNPACK FP16 packed-weight path. The package contains the YOLO26n object detector converted to LiteRT and arranged so XNNPACK can run Conv2D through its FP16 packed-weight path. The model accepts 640 × 640 images and returns up to 300 detections per image.

- Developed by: Ultralytics
- Model type: object detector
- License: AGPL-3.0
- Base model: `Ultralytics/YOLO26`, the `yolo26n.pt` checkpoint at revision `070ac3c51435984d992ba92eb3f234daf4e4500d`
- Upstream repository: Ultralytics
- Packaged variant: a LiteRT model prepared for FP16 execution with XNNPACK

The objective of the package is to provide YOLO26n for object detection with FP16-optimized LiteRT execution. Compared with the FP32 baseline, it delivers 1.85× faster p50 end-to-end inference on an Android Vivo X300, processes 55.99 frames per second on one Arm CPU core of that phone, and achieves 40.23% mAP50–95 on COCO 2017 val, within 0.02 percentage points of the FP32 baseline.

## YOLO26n input and output tensors

The model has one input and one output, both float32:

- Input `img`: a float32 tensor with shape `[1, 3, 640, 640]`.
- Output `output`: a float32 detection tensor with shape `[1, 300, 6]`.

The object-detection manifest specifies external non-maximum suppression with a confidence threshold of 0.25, an NMS threshold of 0.4, a maximum of 300 detections per image, and non-normalized coordinates. Class names come from `assets/class_names.json`, which contains COCO class labels taken from the Darknet `coco.names` file.

## How the FP16 precision path works

The optimized profile executes Conv2D through XNNPACK's FP16 packed-weight path. The model keeps Conv2D weights as direct float32 constants and includes one unused float16 constant so runtime code can detect whether FP16 execution can be forced through XNNPACK. The input and output tensors use float32.

The runtime architecture of the package is:

| Component role | Framework or format |
| --- | --- |
| Object detector | LiteRT (`.tflite`) |
| Runtime configuration | Object-detection manifest (`.json`) |
| Class-name mapping | JSON |
| Representative input | JPEG image |

## YOLO26n accuracy on COCO

Quality was evaluated on all 5,000 images in the COCO 2017 `val2017` split at 640 × 640 input resolution with batch size 1. Higher mAP values are better.

| Metric | FP32 baseline | FP16 optimized | Change |
| --- | --- | --- | --- |
| mAP50–95 | 40.25% | 40.23% | 0.02 percentage points lower |
| mAP50 | 55.78% | 55.78% | no change |
| mAP75 | 43.62% | 43.58% | 0.04 percentage points lower |

## YOLO26n latency and memory on an Android phone

Performance was measured on an Android Vivo X300, running on one Arm CPU core, with 100 warmup runs followed by 100 measured runs. The input was a batch of one 640 × 640 image from COCO 2017 `val2017`. End-to-end latency is the elapsed time from supplying the input image until final detections are available, including preprocessing, model inference, and post-processing. Average memory is the mean sampled resident memory of the benchmark process across measured runs, and peak memory is the maximum high-water-mark resident memory.

| Metric | FP32 baseline | FP16 optimized | Uplift |
| --- | --- | --- | --- |
| End-to-end latency, p50 | 33.02 ms | 17.86 ms | 1.85× faster |
| End-to-end latency, p90 | 34.628 ms | 19.026 ms | 1.82× faster |
| Frames per second | 30.28 | 55.99 | 1.85× higher |
| Time to first inference | 35.579 ms | 19.313 ms | 1.84× faster |
| Model load time | 9.504 ms | 10.218 ms | 7.51% slower |
| Average memory | 82.36 MB | 82.45 MB | 0.11% higher |
| Peak memory | 82.39 MB | 82.50 MB | 0.13% higher |

Lower latency and memory values are better; higher frames-per-second values are better.

## How the YOLO26n LiteRT model was converted

The model file `yolo26n_conv2d_f16_weights.tflite` was converted from the Ultralytics `yolo26n.pt` PyTorch checkpoint to LiteRT with `litert-torch` 0.9.1, using a wrapper that returns the `[1, 300, 6]` detection tensor. Starting from the FP32 LiteRT bundle, Conv2D weights were kept as direct float32 constants, and one unused float16 constant was added so runtime code can detect whether FP16 execution can be forced through XNNPACK. The sample image `samples/sample.jpg` was copied from the YOLO26n FP32 LiteRT model bundle.

## Files in the YOLO26n package and how to run it

The repository contains:

- `yolo26n_conv2d_f16_weights.tflite`: the LiteRT object-detection model referenced by the manifest.
- `yolo_manifest.json`: the object-detection manifest.
- `assets/class_names.json`: the COCO class-name mapping referenced by the manifest.
- `benchmarks/yolo26n-fp16-litert-vivo-x300-fp16.yaml` and `benchmarks/yolo26n-fp16-litert-vivo-x300-fp32.yaml`: FP16 and FP32 baseline quality and performance reports for the Vivo X300.
- `metadata.yaml`: model and benchmark metadata.
- `samples/sample.jpg`: a sample image for `object_detection_cli` smoke tests.
- `SHA256SUMS`: model-package checksums for reproducibility, verifiable with `shasum -a 256 -c SHA256SUMS` from the bundle root.

The inference engine for this model package is available through Arm's Compute Flow Early Access Program; access is requested by email to ai-early-access@arm.com.
