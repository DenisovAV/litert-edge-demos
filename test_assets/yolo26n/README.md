Fixtures copied from `~/Work/models/yolo26n/dart_probe/fixtures/` (docs/design/detector-yolo26n.md §8):

- `cats_640x480_rgba.u8`: raw RGBA8888, 640×480, COCO val2017 `000000039769.jpg` decoded by PIL
  (SHA-256 prefix `9e0d42666864d10e`).
- `cats_golden.json`: the strict-GPU fp32 detections for that frame (decode threshold 0.25).

COCO `000000039769.jpg` is Flickr photo [210383891](https://www.flickr.com/photo.gne?id=210383891) under
[CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/); the raw frame stays under that licence (all COCO credits:
`docs/screenshots/README.md`). The model file is never committed.
