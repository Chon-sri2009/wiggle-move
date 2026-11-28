// Reference: run the ORIGINAL tfjs PoseNet + TM head exactly like @teachablemachine/pose does.
const tf=require('@tensorflow/tfjs'); const fs=require('fs'); const path=require('path');
const S='..';
function weights(manifestFile,shards){const m=JSON.parse(fs.readFileSync(manifestFile));
  const buf=Buffer.concat(shards.map(p=>fs.readFileSync(p)));
  const specs=[].concat(...m.weightsManifest.map(g=>g.weights));
  return {m,specs,data:buf.buffer.slice(buf.byteOffset,buf.byteOffset+buf.byteLength)};}
(async()=>{
 await tf.setBackend('cpu');
 const pw=weights(S+'/pn/model.json',[S+'/pn/s1.bin',S+'/pn/s2.bin']);
 const base=await tf.loadGraphModel(tf.io.fromMemory(pw.m.modelTopology,pw.specs,pw.data));
 const hw=weights(S+'/tm/model.json',[S+'/tm/model.weights.bin']);
 const head=await tf.loadLayersModel(tf.io.fromMemory(hw.m.modelTopology,hw.specs,hw.data));
 fs.mkdirSync('out',{recursive:true});
 for(const f of fs.readdirSync('in')){
  const b=fs.readFileSync('in/'+f); const h=b.readInt32LE(0), w=b.readInt32LE(4);
  const px=new Uint8Array(b.buffer,b.byteOffset+8,h*w*3);
  const [tH,tW]=[257,257]; const ta=tW/tH, asp=w/h; let pT=0,pB=0,pL=0,pR=0;
  if(asp<ta){pL=pR=Math.round(0.5*(ta*h-w));}else{pT=pB=Math.round(0.5*((1/ta)*w-h));}
  const res=tf.tidy(()=>tf.pad3d(tf.tensor3d(px,[h,w,3],'int32'),[[pT,pB],[pL,pR],[0,0]]).resizeBilinear([tH,tW]));
  const out=tf.tidy(()=>{
    const x=res.toFloat().div(127.5).sub(1).expandDims(0);
    const o=base.predict(x); // order unknown -> pick by shape
    const arr=Array.isArray(o)?o:[o]; const by={};
    arr.forEach(t=>{by[t.shape[3]]=t.squeeze();});
    const heat=by[17].sigmoid(), off=by[34];
    const feat=tf.concat([heat,off],2);
    const probs=head.predict(feat.reshape([1,14739]));
    return {feat:feat.dataSync(),probs:probs.dataSync(),r:res.dataSync()};
  });
  const n=path.basename(f,'.raw');
  fs.writeFileSync(`out/${n}.resized.f32`,Buffer.from(new Float32Array(out.r).buffer));
  fs.writeFileSync(`out/${n}.feat.f32`,Buffer.from(new Float32Array(out.feat).buffer));
  fs.writeFileSync(`out/${n}.probs.json`,JSON.stringify(Array.from(out.probs)));
  console.log(n,'pad',[pT,pB,pL,pR].join(','),'top',out.probs.indexOf(Math.max(...out.probs)),Math.max(...out.probs).toFixed(3));
 }
})();
