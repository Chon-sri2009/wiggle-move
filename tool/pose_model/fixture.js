const tf=require('@tensorflow/tfjs'); const fs=require('fs');
const px=(x,y,c)=>(x*7+y*13+c*50+((x*y)%31))%256;
function run(w,h){
  const a=new Int32Array(h*w*3); for(let y=0;y<h;y++)for(let x=0;x<w;x++)for(let c=0;c<3;c++)a[(y*w+x)*3+c]=px(x,y,c);
  const asp=w/h; let pT=0,pB=0,pL=0,pR=0;
  if(asp<1){pL=pR=Math.round(0.5*(h-w));}else{pT=pB=Math.round(0.5*(w-h));}
  const res=tf.tidy(()=>tf.pad3d(tf.tensor3d(a,[h,w,3],'int32'),[[pT,pB],[pL,pR],[0,0]]).resizeBilinear([257,257])).dataSync();
  const vals=[]; for(let y=0;y<257;y+=16)for(let x=0;x<257;x+=16)for(let c=0;c<3;c++)vals.push(res[(y*257+x)*3+c]);
  return {w,h,vals};
}
fs.writeFileSync('fixture.json',JSON.stringify([run(40,30),run(24,36),run(31,31)]));
console.log('ok');
