# Vic (blue, from the left) against Sid (white, from the right) on the eclipse beach.
# Every frame is one of the posed drawings; hits connect at the strike frame and the one hit reels back.
import numpy as np, sys, subprocess, time
src=open('moves.py').read(); exec(src[:src.index("cache={}")])
from PIL import Image
cache={}
def draw(C,J,flip):
    k=(C['name'],flip,tuple(sorted((n,tuple(round(c,2) for c in v)) for n,v in J.items())))
    if k in cache: return cache[k]
    im=render(C,{n:v for n,v in J.items() if n!='_foot'},0.0,flip=flip,imgflip=False)
    if '_foot' in J:
        o=np.asarray(im).copy(); sk=RAMPS[C['skin']]; d=1
        col={'O':outl(C['skin']),'1':sk[0],'2':sk[2-d],'3':sk[3-d],'4':sk[4-d],'p':tuple(int(c*0.85) for c in sk[3])}
        kind=int(J['_foot'][0]); art,(pvx,pvy),off={1:(FOOT45,FOOT45_PIVOT,(5,1)),2:(FOOT_PT,FOOT_PT_PIVOT,(5,0)),3:(FOOT_PT45,FOOT_PT45_PIVOT,(4,-3))}[kind]
        ax,ay=J['ank_b'][0]+SW/2-2+off[0], SH-J['ank_b'][1]+off[1]
        for j,row in enumerate(art):
            for i,ch in enumerate(row):
                if ch!='.':
                    y,x=int(round(ay))+j-pvy,int(round(ax))+i-pvx
                    if 0<=y<SH and 0<=x<SW: o[y,x,:3]=col[ch]; o[y,x,3]=255
        im=Image.fromarray(o,'RGBA')
    if flip: im=im.transpose(Image.FLIP_LEFT_RIGHT)
    cache[k]=im; return im

# hit reaction: the head snaps back, the body rocks back and the guard opens, then recovers
H1=setj(lean(upper(G,(-3,0)),16), elb_f=(15,63,-8), wr_f=(20,70,-6), fist_f=(22,73,-5))
H1['head']=tuple(a+b for a,b in zip(H1['head'],(-2,1,0)))
H2=lean(upper(G,(-2,0)),8)
HIT=[(H1,5),(H2,5)]+tween(H2,G,[0.5],4)
HITPUSH=[3,2,1,1,0,0,0,0,0,0,0,0,0,0]          # pixels knocked back on each frame of the reaction

class F:   # one fighter's timeline
    def __init__(s,C,x,flip): s.C,s.x,s.flip,s.t=C,x,flip,[]
    def dir(s): return -1 if s.flip else 1
    def hold(s,n,J=None): s.t+=[(J or G,s.x)]*n
    def play(s,seq):
        for J,h in seq: s.t+=[(J,s.x)]*h
    def walk(s,steps):
        for _ in range(steps):
            for J,h in WALK: s.t+=[(J,s.x)]*h
            s.x+=STRIDE*s.dir()
    def hit_at(s,frame):
        s.hold(frame-len(s.t)); k=0
        for J,h in HIT:
            for _ in range(h):
                s.x-=s.dir()*(HITPUSH[k] if k<len(HITPUSH) else 0); k+=1; s.t.append((J,s.x))
    def strike_index(s,seq):   # the frame where the blow lands: the first frame of the longest-held pose
        i=0; best=(0,0)
        for J,h in seq:
            if h>best[0]: best=(h,i)
            i+=h
        return best[1]

def reach(C_att,seq,C_def):
    # measured, not guessed: the gap (sprite to sprite) at which the strike's tip sinks 3 px into the defender
    i=0; best=(0,None)
    for J,h in seq:
        if h>best[0]: best=(h,J)
    A=np.asarray(draw(C_att,best[1],False))[...,3]>0; D=np.asarray(draw(C_def,G,True))[...,3]>0
    ys,xs=np.where(A); tip=xs.max(); rows=ys[xs>=tip-1]
    dl=min(np.where(D[max(0,r-2):r+3].any(0))[0].min() for r in rows if D[max(0,r-2):r+3].any())
    return tip-dl-3
def gap(): return sid.x-vic.x
def sync():
    n=max(len(vic.t),len(sid.t)); vic.hold(n-len(vic.t)); sid.hold(n-len(sid.t))
def walk_back(s,steps=1):
    for _ in range(steps):
        s.x-=STRIDE*s.dir()
        for J,h in reversed(WALK): s.t+=[(J,s.x)]*h
F.walk_back=walk_back
def attack(a,d,seq):
    sync(); r=reach(a.C,seq,d.C)
    while gap()-STRIDE>=r-4: a.walk(1); sync()
    start=len(a.t); a.play(seq); d.hit_at(start+a.strike_index(seq)); sync()
    a.walk_back(1); sync()

vic=F(VIC,34,False); sid=F(SID,150,True)
sync(); vic.hold(40); sid.hold(40); sync()
attack(vic,sid,KICK); vic.hold(10); sid.hold(10)
attack(sid,vic,BODYK); vic.hold(8)
attack(vic,sid,HEADK); sid.hold(14); vic.hold(14)
attack(sid,vic,PUNCH); vic.hold(8)
attack(vic,sid,SHIN); sync(); vic.hold(40); sid.hold(40); sync()
N=len(vic.t); print('frames',N,'gap at end',sid.x-vic.x)

# the eclipse plays out behind them (every 3rd frame of the backdrop mockup, so it reaches totality mid-fight)
p=subprocess.run(['ffmpeg','-v','error','-i','../stage/Eclipse fight mockup 25.mp4','-vf',"select=not(mod(n\\,3)),scale=320:200:flags=neighbor",
                  '-vsync','0','-f','rawvideo','-pix_fmt','rgb24','-'],capture_output=True,check=True).stdout
BG=np.frombuffer(p,np.uint8).reshape(-1,200,320,3); print('backdrop frames',len(BG))
SAND=BG[:,170:200].mean(axis=(1,2,3)); LIGHT=np.clip(SAND/SAND[0],0,1)          # how much daylight is left
def lit(im,f):
    a=np.asarray(im).astype(np.float32).copy(); k=0.30+0.70*f
    a[...,:3]=a[...,:3]*k+np.array([18,22,48])*(1-f)*0.6                           # darker and bluer as the light goes
    return Image.fromarray(np.clip(a,0,255).astype(np.uint8),'RGBA')
t0=time.time(); raw=bytearray()
for i in range(N):
    c=Image.fromarray(BG[min(i,len(BG)-1)]).convert('RGBA')
    (Jv,xv),(Js,xs)=vic.t[i],sid.t[i]
    f=float(LIGHT[min(i,len(BG)-1)])
    c.alpha_composite(lit(draw(SID,Js,True),f),(int(xs),80)); c.alpha_composite(lit(draw(VIC,Jv,False),f),(int(xv),80))
    raw+=c.convert('RGB').tobytes()
print('drawn',len(cache),'in',round(time.time()-t0),'s')
subprocess.run(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','320x200','-r','30','-i','-','-vf','scale=1280:800:flags=neighbor',
  '-c:v','libx264','-crf','16','-pix_fmt','yuv420p','Vic vs Sid 2.mp4'],input=bytes(raw),check=True)
# a still of Sid on his own
z=Image.new('RGBA',(SW,SH),(70,74,92,255)); z.alpha_composite(draw(SID,G,True)); z.resize((SW*5,SH*5),Image.NEAREST).convert('RGB').save('Sid close-up.png')
print('ok')
