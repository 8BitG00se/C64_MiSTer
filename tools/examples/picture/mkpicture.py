#!/usr/bin/env python3
# MOONLIGHT - draws the picture (320x200 pixel art, ordered dither, original: Octophonic 64 / Mong00se),
# cuts it to 255 colours and packs it in runs for viewer.asm: moonlight.png, moonlight.pal (255 x RGB),
# moonlight.rle
#   python3 mkpicture.py [outdir]
import math, random, sys, os
from PIL import Image, ImageDraw
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
W,H=320,200
random.seed(64)
B4=[[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]
im=Image.new('RGB',(W,H),(0,0,0)); px=im.load()
def ramp(stops,n):
    out=[]
    for i in range(n):
        t=i/(n-1)*(len(stops)-1); k=min(int(t),len(stops)-2); f=t-k
        out.append(tuple(int(stops[k][c]*(1-f)+stops[k+1][c]*f) for c in range(3)))
    return out
SKY=ramp([(6,6,30),(18,14,70),(60,30,110),(150,60,120),(240,120,100),(255,190,120)],12)   # night to horizon glow
SEA=ramp([(255,170,110),(150,60,110),(50,30,100),(14,14,56),(6,8,34)],10)
def dith(ramp_,v,x,y):   # v 0..len-1 float, ordered dither between neighbours
    i=int(v); f=v-i
    if i>=len(ramp_)-1: return ramp_[-1]
    return ramp_[i+1] if f*16>B4[y&3][x&3] else ramp_[i]
HZ=128
for y in range(HZ):
    for x in range(W):
        px[x,y]=dith(SKY,(y/HZ)**1.5*(len(SKY)-1),x,y)
# stars (only where the sky is dark)
for _ in range(90):
    x=random.randrange(W); y=random.randrange(0,80)
    c=random.choice([(255,255,255),(190,200,255),(255,230,170)])
    px[x,y]=c
    if random.random()<0.2:
        for dx,dy in((1,0),(-1,0),(0,1),(0,-1)): px[x+dx,y+dy]=tuple(v//2 for v in c)
# moon
mx,my,mr=222,50,26
MOON=ramp([(255,250,225),(235,225,190),(190,180,160),(120,115,130)],8)
for y in range(my-mr-6,my+mr+7):
    for x in range(mx-mr-6,mx+mr+7):
        d=math.hypot(x-mx,y-my)
        if d<=mr:
            sh=((x-mx)*0.5+(y-my)*0.6)/mr   # lit from the top left
            v=(sh+1)*3.4
            px[x,y]=dith(MOON,max(0,min(6.9,v)),x,y)
        elif d<=mr+6:
            g=1-(d-mr)/6
            r,gg,b=px[x,y]; k=g*g*0.45
            px[x,y]=(int(r+(255-r)*k),int(gg+(240-gg)*k),int(b+(200-b)*k))
for (cx,cy,cr) in ((mx-8,my-6,6),(mx+9,my+8,5),(mx-2,my+14,3),(mx+10,my-12,3),(mx-14,my+6,2)):
    for y in range(cy-cr,cy+cr+1):
        for x in range(cx-cr,cx+cr+1):
            if math.hypot(x-cx,y-cy)<=cr:
                r,g,b=px[x,y]; px[x,y]=(int(r*.72),int(g*.72),int(b*.8))
# far hills and cliff silhouettes
def ridge(base,amp,f,ph,cols,seed):
    for x in range(W):
        h=base-amp*(0.6*math.sin(x*f+ph)+0.4*math.sin(x*f*2.7+ph*1.9))
        for y in range(int(h),HZ+2):
            t=(y-h)/12
            px[x,y]=cols[min(int(t),len(cols)-1)]
ridge(HZ-6,8,0.035,1.1,[(52,30,92),(40,24,80),(30,18,66)],1)
# sea
for y in range(HZ,H):
    t=(y-HZ)/(H-HZ)
    for x in range(W):
        wob=math.sin(y*0.9+x*0.05)*1.2
        px[x,y]=dith(SEA,min(8.9,t**0.7*8.9+(0.0 if wob>0.2 else 0.5)),x,y)
# moon reflection: bright broken stripes
for y in range(HZ+1,H):
    t=(y-HZ)/(H-HZ)
    wid=int(mr*0.9*(0.5+t*0.5)); jit=int(math.sin(y*1.7)*5*t+math.sin(y*0.5)*2)
    if int(y*0.8)%3==0: continue
    for x in range(mx-wid+jit,mx+wid+jit):
        if 0<=x<W:
            d=abs(x-(mx+jit))/wid
            if d<1 and (x+y)&1==0 or d<0.45:
                r,g,b=px[x,y]; k=(1-d)*0.8*(1-t*0.4)
                px[x,y]=(int(r+(255-r)*k),int(g+(235-g)*k),int(b+(190-b)*k))
# the lighthouse on a rock, left, with its beam
LX=64
for y in range(HZ-30,H):    # rock
    for x in range(LX-34,LX+36):
        h=HZ-24+abs((x-LX))*0.45+math.sin(x*0.7)*2
        if y>=h and y<HZ+18+abs(x-LX)*0.05:
            shade=((x-LX)/40*0.5+0.5)
            px[x,y]=dith(ramp([(60,48,84),(26,18,46),(12,8,28)],8),(shade*5+(y-h)*0.06),x,y)
def rect(x0,y0,x1,y1,col):
    for y in range(y0,y1):
        for x in range(x0,x1): px[x,y]=col
# tower: tapered, striped red and white
top=HZ-92
for y in range(top,HZ-22):
    t=(y-top)/(HZ-22-top)
    hw=int(6+t*5)
    band=((y-top)//9)%2
    for x in range(LX-hw,LX+hw+1):
        sh=(x-(LX-hw))/(2*hw+1)
        base=(236,226,214) if band==0 else (200,40,52)
        k=0.55+0.45*(1-sh)
        px[x,y]=tuple(int(c*k) for c in base)
rect(LX-12,top-3,LX+13,top,(30,24,44))             # gallery
rect(LX-9,top-14,LX+10,top-3,(255,240,150))       # lamp room
for x in range(LX-9,LX+10,3): rect(x,top-14,x+1,top-3,(70,50,40))
for y in range(top-22,top-14):                      # roof
    hw=(y-(top-22))+2
    for x in range(LX-hw,LX+hw+1): px[x,y]=(44,30,60) if x>LX else (70,46,90)
px[LX,top-24]=(255,255,255)
# beam to the right, a soft wedge
for y in range(top-30,top+18):
    for x in range(LX+10,W):
        t=(x-LX-10)/(W-LX-10)
        cy=(top-9)+t*12
        half=3+t*18
        if abs(y-cy)<half:
            r,g,b=px[x,y]; k=(1-abs(y-cy)/half)*0.5*(1-t*0.75)
            if (x+y)&1==0 or k>0.3: px[x,y]=(int(r+(255-r)*k),int(g+(240-g)*k),int(b+(160-b)*k))
# a small boat with a lit window on the sea
bx,by=210,HZ+22
for x in range(bx-14,bx+15):
    for y in range(by,by+6):
        if y-by<abs(x-bx)*0.25+0.5 or True:
            if abs(x-bx)<=14-(y-by)*1.0: px[x,y]=(30,16,34)
rect(bx-1,by-16,bx+1,by,(40,26,44))
for y in range(by-16,by-1):
    for x in range(bx+2,bx+2+int((y-(by-16))*0.55)+1): px[x,y]=(230,215,190)
rect(bx-9,by-3,bx-6,by-1,(255,210,90))
# the octopus: a big silhouette rising from the right edge of the sea, tentacles curling
ox,oy=282,HZ+8
OCT=(14,8,30)
for y in range(oy-52,oy+4):
    for x in range(ox-26,ox+26):
        dx=(x-ox)/24; dy=(y-(oy-30))/22
        if dx*dx+dy*dy<=1: px[x,y]=OCT
for sgn in (-1,1):
    for k in range(4):
        for t in range(40):
            tt=t/39
            x=ox+sgn*(8+k*7)+sgn*math.sin(tt*5+k)*5*(1+tt)+sgn*tt*(12+k*2)
            y=oy-14+tt*(30+k*3)
            w=int(5*(1-tt)+1)
            for yy in range(int(y)-w,int(y)+w+1):
                for xx in range(int(x)-w,int(x)+w+1):
                    if 0<=xx<W and 0<=yy<H: px[xx,yy]=OCT
# the eye glints
for (ex,ey) in ((ox-9,oy-32),(ox+9,oy-32)):
    rect(ex-4,ey-3,ex+5,ey+4,(255,200,70)); rect(ex-1,ey-3,ex+1,ey+4,(10,5,20)); px[ex+2,ey-2]=(255,255,255)
# the title, a hand-drawn 5x7 pixel font, doubled
F={'O':["01110","10001","10001","10001","10001","10001","01110"],'C':["01110","10001","10000","10000","10000","10001","01110"],
'T':["11111","00100","00100","00100","00100","00100","00100"],'P':["11110","10001","10001","11110","10000","10000","10000"],
'H':["10001","10001","10001","11111","10001","10001","10001"],'N':["10001","11001","10101","10011","10001","10001","10001"],
'I':["01110","00100","00100","00100","00100","00100","01110"],'6':["01110","10000","10000","11110","10001","10001","01110"],
'4':["00010","00110","01010","10010","11111","00010","00010"],' ':["00000"]*7}
def text(s,x0,y0,sc,cols):
    x=x0
    for ch in s:
        g=F[ch]
        for r,row in enumerate(g):
            for c,v in enumerate(row):
                if v=='1':
                    for sy in range(sc):
                        for sx in range(sc):
                            yy=y0+r*sc+sy; xx=x+c*sc+sx
                            px[xx,yy]=cols[min(r*len(cols)//7,len(cols)-1)]
        x+=6*sc
    return x
title='OCTOPHONIC 64'
wtxt=len(title)*6*2-2
tx=(W-wtxt)//2
for dx,dy in((2,2),(1,2),(2,1)):
    text(title,tx+dx,10+dy,2,[(12,6,30)])
text(title,tx,10,2,[(130,250,255),(100,230,255),(90,200,250),(255,150,230),(240,90,200),(200,60,170),(160,40,150)])
im.save(os.path.join(OUT, 'moonlight.png'))
q = im.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal = q.getpalette()[:255 * 3]; px_ = [p + 1 for p in q.tobytes()]
o = bytearray(); i = 0; n = len(px_)
while i < n:
    j = i
    while j < n and j - i < 127 and px_[j] == px_[i] and (j // W) == (i // W): j += 1
    if j - i >= 3: o += bytes([j - i, px_[i]]); i = j; continue
    k = i; lit = []
    while k < n and len(lit) < 127:
        jj = k
        while jj < n and jj - k < 3 and px_[jj] == px_[k] and (jj // W) == (k // W): jj += 1
        if jj - k >= 3: break
        lit.append(px_[k]); k += 1
    o += bytes([128 + len(lit)]) + bytes(lit); i = k
o += bytes([0])
open(os.path.join(OUT, 'moonlight.rle'), 'wb').write(o); open(os.path.join(OUT, 'moonlight.pal'), 'wb').write(bytes(pal))
print('moonlight: %d bytes packed' % len(o))
