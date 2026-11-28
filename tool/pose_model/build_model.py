"""Rebuild PoseNet (MobileNetV1 0.75, stride 16) + Teachable Machine head in Keras
from the original tfjs weight files, and export one TFLite model:
  input  [1,257,257,3] float32, RGB 0..255 (already padded to square + resized)
  output [1,12] softmax class probabilities
"""
import json, sys, numpy as np, os
os.environ["TF_ENABLE_ONEDNN_OPTS"]="0"
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

def read_weights(manifest_path, shard_paths):
    m=json.load(open(manifest_path))
    buf=b"".join(open(p,"rb").read() for p in shard_paths)
    out={}; off=0
    for g in m["weightsManifest"]:
        for w in g["weights"]:
            n=int(np.prod(w["shape"]))
            out[w["name"]]=np.frombuffer(buf,dtype="<f4",count=n,offset=off).reshape(w["shape"]).copy()
            off+=n*4
    assert off==len(buf),(off,len(buf))
    return out

W=read_weights("pn/model.json",["pn/s1.bin","pn/s2.bin"])
STRIDES={0:2,2:2,4:2,6:2}  # conv index -> stride (depthwise of that block); conv0 is the stem
def build_posenet():
    inp=keras.Input((257,257,3),name="image")
    x=layers.Rescaling(1/127.5,offset=-1.0)(inp)
    x=layers.Conv2D(24,3,strides=2,padding="same",name="c0")(x)
    x=layers.ReLU(6.)(x)
    chans=[24,48,96,96,192,192,384,384,384,384,384,384,384,384]
    # blocks 1..13: depthwise (stride s) then pointwise
    for i in range(1,14):
        s=2 if i in (2,4,6) else 1
        x=layers.DepthwiseConv2D(3,strides=s,padding="same",name=f"dw{i}")(x)
        x=layers.ReLU(6.)(x)
        x=layers.Conv2D(chans[i],1,padding="same",name=f"pw{i}")(x)
        x=layers.ReLU(6.)(x)
    heat=layers.Conv2D(17,1,name="heat")(x)
    heat=layers.Activation("sigmoid")(heat)
    off=layers.Conv2D(34,1,name="off")(x)
    feat=layers.Concatenate(axis=-1)([heat,off])       # [1,17,17,51], HWC like TM
    feat=layers.Flatten()(feat)                         # 14739, row-major HWC
    m=keras.Model(inp,feat,name="posenet")
    def setw(layer,k,b): layer.set_weights([W[k],W[b]])
    setw(m.get_layer("c0"),"MobilenetV1/Conv2d_0/weights","MobilenetV1/MobilenetV1/Conv2d_0/Conv2D_bias")
    for i in range(1,14):
        setw(m.get_layer(f"dw{i}"),f"MobilenetV1/Conv2d_{i}_depthwise/depthwise_weights",f"MobilenetV1/MobilenetV1/Conv2d_{i}_depthwise/depthwise_bias")
        setw(m.get_layer(f"pw{i}"),f"MobilenetV1/Conv2d_{i}_pointwise/weights",f"MobilenetV1/MobilenetV1/Conv2d_{i}_pointwise/Conv2D_bias")
    setw(m.get_layer("heat"),"MobilenetV1/heatmap_2/weights","MobilenetV1/heatmap_2/Conv2D_bias")
    setw(m.get_layer("off"),"MobilenetV1/offset_2/weights","MobilenetV1/offset_2/Conv2D_bias")
    return m

H=read_weights("tm/model.json",["tm/model.weights.bin"])
def build_head():
    i=keras.Input((14739,))
    x=layers.Dense(100,activation="relu",name="d1")(i)
    x=layers.Dense(12,activation="softmax",use_bias=False,name="d2")(x)
    m=keras.Model(i,x)
    m.get_layer("d1").set_weights([H["dense_Dense95/kernel"],H["dense_Dense95/bias"]])
    m.get_layer("d2").set_weights([H["dense_Dense96/kernel"]])
    return m

if __name__=="__main__":
    pn=build_posenet(); head=build_head()
    full=keras.Model(pn.input,head(pn.output),name="pose_classifier")
    pn.save("posenet_features.keras"); full.save("full.keras")
    conv=tf.lite.TFLiteConverter.from_keras_model(full)
    open("pose_classifier.tflite","wb").write(conv.convert())
    print("ok",os.path.getsize("pose_classifier.tflite"))
