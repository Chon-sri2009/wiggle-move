import os,glob,json,numpy as np
os.environ["TF_ENABLE_ONEDNN_OPTS"]="0"
import tensorflow as tf
from tensorflow import keras
it=tf.lite.Interpreter(model_path="pose_classifier.tflite"); it.allocate_tensors()
i=it.get_input_details()[0]; o=it.get_output_details()[0]
pn=keras.models.load_model("posenet_features.keras")
labels=json.load(open("tm/metadata.json"))["labels"]
worst_f=worst_p=0; agree=0; n=0
for f in sorted(glob.glob("ref/out/*.resized.f32")):
    name=os.path.basename(f).split(".")[0]
    x=np.fromfile(f,dtype="<f4").reshape(1,257,257,3)
    ref_feat=np.fromfile(f"ref/out/{name}.feat.f32",dtype="<f4")
    ref_p=np.array(json.load(open(f"ref/out/{name}.probs.json")))
    feat=pn.predict(x,verbose=0)[0]
    it.set_tensor(i["index"],x); it.invoke(); p=it.get_tensor(o["index"])[0]
    df=np.abs(feat-ref_feat).max(); dp=np.abs(p-ref_p).max()
    worst_f=max(worst_f,df); worst_p=max(worst_p,dp); n+=1; agree+=int(p.argmax()==ref_p.argmax())
    print(f"{name:8s} feat maxdiff {df:.2e}  prob maxdiff {dp:.2e}  tfjs={labels[ref_p.argmax()].strip()}({ref_p.max():.2f}) tflite={labels[p.argmax()].strip()}({p.max():.2f})")
print("WORST feat",worst_f,"prob",worst_p,"top1 agree",agree,"/",n)
