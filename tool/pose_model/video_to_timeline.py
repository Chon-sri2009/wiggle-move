"""Turn a video of a trainer into a reference timeline of body keypoints.

    python video_to_timeline.py trainer.mp4 timeline.json [--hz 10]

Run from the folder that holds pn/ and tm/ (see README) next to build_model.py.
Needs: pip install tensorflow numpy opencv-python

Output JSON: {"durationMs", "hz", "samples": [[x0,y0,s0, x1,y1,s1, ...17 parts], ...]}
Coordinates are in units of the longer video side (x and y share one scale, so
angles computed from them are correct); score is PoseNet's heatmap score.
Only use videos you have the right to process.
"""
import json, sys, os
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"
import cv2, numpy as np
from build_model import build_posenet

def decode(feat):
    f = feat.reshape(17, 17, 51)
    heat, off = f[:, :, :17], f[:, :, 17:]
    out = []
    for k in range(17):
        r, c = np.unravel_index(np.argmax(heat[:, :, k]), (17, 17))
        out.append((c * 16 + off[r, c, k + 17], r * 16 + off[r, c, k], heat[r, c, k]))
    return out

def main(src, dst, hz=10.0):
    pn = build_posenet()
    cap = cv2.VideoCapture(src)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    step = max(1, round(fps / hz))
    samples = []
    i = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if i % step == 0:
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            h, w = rgb.shape[:2]
            side = max(h, w)
            pad_t, pad_l = (side - h) // 2, (side - w) // 2
            sq = cv2.copyMakeBorder(rgb, pad_t, side - h - pad_t, pad_l, side - w - pad_l,
                                    cv2.BORDER_CONSTANT, value=(0, 0, 0))
            x = cv2.resize(sq, (257, 257), interpolation=cv2.INTER_LINEAR).astype("float32")[None]
            pts = decode(pn.predict(x, verbose=0)[0])
            scale = side / 257.0
            row = []
            for px, py, s in pts:
                row += [round(float((px * scale) / side), 4), round(float((py * scale) / side), 4), round(float(s), 3)]
            samples.append(row)
        i += 1
    json.dump({"durationMs": int(1000 * n / fps), "hz": fps / step, "samples": samples}, open(dst, "w"))
    print(f"{len(samples)} samples, {n / fps:.1f}s -> {dst}")

if __name__ == "__main__":
    hz = float(sys.argv[sys.argv.index("--hz") + 1]) if "--hz" in sys.argv else 10.0
    main(sys.argv[1], sys.argv[2], hz)
