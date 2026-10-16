"""Genera versiones en bucle de las pistas: recorta el silencio final y solapa la cola (fundido de salida)
sobre el inicio (fundido de entrada) en un punto de compas, de modo que el final enlaza con el principio."""
import subprocess,sys,numpy as np,imageio_ffmpeg
ff=imageio_ffmpeg.get_ffmpeg_exe(); SR=44100
BEAT={"boss1":0.4488,"boss2":0.6633,"ending":0.6264,"menu":0.7159,"boss3":0.5012,"death":0.4564}
def load(f):
    r=subprocess.run([ff,"-v","error","-i",f,"-f","f32le","-ac","2","-ar",str(SR),"-"],capture_output=True)
    return np.frombuffer(r.stdout,dtype=np.float32).reshape(-1,2).copy()
def rmsdb(x): return 20*np.log10(np.sqrt((x**2).mean())+1e-9)
src,dst,key=sys.argv[1:4]
a=load(src); w=SR//20
n=len(a)//w; d=np.array([rmsdb(a[i*w:(i+1)*w]) for i in range(n)])
T=(np.where(d>-60)[0][-1]+1)*w
body=np.median(d[: T//w])
bar=4*BEAT[key]*SR
best=None
m=int((T/SR)/(bar/SR))
cands=[]
for k in range(m,0,-1):
    L=int(round(k*bar))
    if T-L<int(1.0*SR) and k==m and L>T: continue
    if L>T-int(0.8*SR): continue
    lvl=rmsdb(a[L-int(0.6*SR):L])
    cands.append((k,L,lvl))
    if lvl>=body-7: break
k,L,lvl=cands[-1]
ov=T-L
print(key,"T=%.2f body=%.1fdB bars=%d L=%.3f overlap=%.2f levelAtL=%.1f"%(T/SR,body,k,L/SR,ov/SR,lvl))
out=a[:L].copy()
tail=a[L:T]
out[:len(tail)]+=tail
pk=np.abs(out).max()
if pk>0.98: out*=0.98/pk
import wave,io
raw=(out.astype(np.float32)).tobytes()
subprocess.run([ff,"-y","-v","error","-f","f32le","-ar",str(SR),"-ac","2","-i","-","-c:a","libvorbis","-q:a","6",dst],input=raw,check=True)
# seam check: jump between last and first sample vs typical
jump=np.abs(out[0]-out[-1]).max(); typ=np.abs(np.diff(out,axis=0)).max(axis=1).mean()
print("  seam jump %.4f typical step %.4f peak %.2f"%(jump,typ,pk))
