# Pose form model: conversion and parity check

`assets/models/pose_classifier.tflite` is the team's Teachable Machine pose model
(<https://teachablemachine.withgoogle.com/models/WfOEVK3Og/>: PoseNet MobileNetV1
0.75 / stride 16 / 257 px + Dense 100 + Dense 12) rebuilt in Keras from the original
tfjs weights and exported as one TFLite file:
input `[1,257,257,3]` float RGB 0..255 (padded to a square and resized, see
`lib/features/workout/form/frame_preprocess.dart`), output `[1,12]` probabilities in the
order of `assets/models/pose_labels.json`.

## Rebuild (Python 3.12/3.13, `pip install tensorflow numpy pillow`; Node for the reference)
Run from a scratch folder holding:
- `pn/model.json`, `pn/s1.bin`, `pn/s2.bin` - from
  `https://storage.googleapis.com/tfjs-models/savedmodel/posenet/mobilenet/float/075/`
  (`model-stride16.json`, `group1-shard1of2.bin`, `group1-shard2of2.bin`)
- `tm/model.json`, `tm/model.weights.bin`, `tm/metadata.json` - from the Teachable Machine
  model link (the weights file is `model.weights.bin`, not `weights.bin`)

1. `python build_model.py` writes `pose_classifier.tflite`.
2. `ref/` (`npm i @tensorflow/tfjs@1.7.4`, then `node ref.js`) runs the ORIGINAL tfjs
   pipeline on raw RGB test images in `ref/in/*.raw` (int32 h, int32 w, then h*w*3 bytes)
   and writes features + probabilities to `ref/out/`.
3. `python parity.py` compares the TFLite model with that reference on the same inputs.
4. `node fixture.js` regenerates `test/features/workout/form/preprocess_fixture.json`
   (tfjs-computed pad + bilinear resize) used by the Dart preprocessing test.

Result when this was written (7 public photos): top-1 agreed 7/7, max probability
difference 1.2e-5, max feature difference 7e-4.

## Pure-Dart engine (Windows demo)
`lib/features/workout/form/posenet_engine.dart` runs the same network without TFLite from
`assets/models/posenet_075_stride16.bin` (the two tfjs PoseNet shards concatenated) and
`assets/models/form_head.bin` (the Teachable Machine `model.weights.bin`).
- `dart run tool/pose_model/parity_engine.dart <scratch>/ref/out` compares it with the tfjs reference.
- `dart run tool/pose_model/keypoints.dart <file.resized.f32>` prints decoded keypoints.

## Trainer video to timeline (follow-the-video)
`python video_to_timeline.py trainer.mp4 timeline.json --hz 10` (run next to `build_model.py` with
`pn/` and `tm/` present; `pip install tensorflow numpy opencv-python`). Then copy the video and the
JSON into `assets/`, declare them in `pubspec.yaml`, and add the routine id to `referenceAssets`.
Film the trainer front-on or from the side the user will be filmed, fully in frame, from a fixed
camera. Only process videos you own or have permission to use.

