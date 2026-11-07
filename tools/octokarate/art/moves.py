# Vic's moves: walk (a shuffle step forward in guard), front punch (lead fist), front kick (front leg).
# Each frame is a posed drawing; frames are held like arcade animation (each drawing shown for a few game frames).
import numpy as np, sys, subprocess, time
from PIL import Image
sys.argv=['x']; exec(open('fighter2.py').read().split("if __name__")[0]); exec(open('footart.py').read())
SW=150                                   # wider sprite box: kicks and punches reach out
G,_=pose_guard(0)
LEG=('ank_f','toe_f','knee_f','ank_b','toe_b','knee_b')
def mv(J,names,d):
    J=dict(J)
    for n in names: J[n]=tuple(a+b for a,b in zip(J[n],d+(0,)*(3-len(d))))
    return J
def upper(J,d): return mv(J,[n for n in J if n not in LEG],d)
def lean(J,deg):
    # tilt the upper body back round the hips (facing right: + leans back), arms and head go with it
    a=math.radians(deg); cx,cy=J['pelvis'][0],J['pelvis'][1]; J=dict(J)
    for n in J:
        if n in LEG or n in ('pelvis','hip_f','hip_b'): continue
        x,y,z=J[n]; dx,dy=x-cx,y-cy
        J[n]=(cx+dx*math.cos(a)-dy*math.sin(a), cy+dx*math.sin(a)+dy*math.cos(a), z)
    return J
def lerpJ(A,B,t): return {n:tuple(a+(b-a)*t for a,b in zip(A[n],B[n])) for n in A if n!='_foot'}
def setj(J,**kw):
    J=dict(J); J.update(kw); return J
def ease(t): return t*t*(3-2*t)                 # slow out of one pose, slow into the next
def tween(A,B,ts,h): return [(lerpJ(A,B,ease(t)),h) for t in ts]

# ---- walk: a stepping walk in guard. Front foot: lift, reach, land; then the back foot: lift, pass, land.
# The planted foot never moves (no sliding); the body rises as a foot passes and dips as it lands.
def step(J,front=None,back=None,body=(0,0)):
    J=upper(J,body)
    if front: J=mv(J,('ank_f','toe_f'),front[0]); J=mv(J,('knee_f',),front[1])
    if back:  J=mv(J,('ank_b','toe_b'),back[0]);  J=mv(J,('knee_b',),back[1])
    return J
F1=step(G,front=((3,5),(3,5)),body=(3,-1))          # front heel lifts, weight on the back leg
F2=step(G,front=((9,3),(7,5)),body=(6,1))           # front foot reaching, body up
F3=step(G,front=((14,0),(12,0)),body=(8,-1))        # front foot lands, wide stance, body down
F4=mv(F3,('ank_b','toe_b'),(3,5)); F4=mv(F4,('knee_b',),(5,6)); F4=upper(F4,(3,1))            # back heel peels up
F5=mv(F3,('ank_b','toe_b'),(9,8)); F5=mv(F5,('knee_b',),(10,11)); F5=upper(F5,(5,2))          # back foot passing, body at its highest
WALK=[(G,3),(F1,3),(F2,3),(F3,3),(F4,3),(F5,3)]     # then the guard 14 px further on
STRIDE=14

# ---- front punch with the lead (far) fist: shoulder drives forward, arm straight at shoulder height
P=upper(G,(2,0)); P=dict(P)
P['sh_f']=(12,73,-9); P['elb_f']=(29,73,-7); P['wr_f']=(39,73,-5); P['fist_f']=(43,73,-4)
P['elb_n']=(6,58,12); P['wr_n']=(11,66,11); P['fist_n']=(14,69,10)      # rear fist pulls up to the chin
P=upper(P,(6,0))                                    # build 3: a lunging punch - the body drives 6 px forward over the planted feet (the reach the fighting distance needs)
Pw=setj(upper(G,(-1,0)), elb_f=(19,61,-8), wr_f=(26,67,-6), fist_f=(30,69,-5))      # wind-up: the lead fist draws back
PUNCH=[(G,3),(Pw,2),(lerpJ(Pw,P,0.5),1),(lerpJ(Pw,P,0.9),1),(P,5)]+tween(P,G,[0.3,0.55,0.75,0.9],2)

# ---- front kick with the TRAILING (back) leg: the weight rolls onto the front leg, the back hip turns through,
# the knee drives up past the front leg, the leg snaps out and the body leans back against it, then it folds back.
def setj(J,**kw):
    J=dict(J); J.update(kw); return J
R0=setj(upper(G,(-1,-1)))                                                                            # anticipation: settle back a touch
R1=setj(upper(G,(3,0)), ank_b=(-19,7,-5), toe_b=(-13,3,-5), knee_b=(-8,25,-5))                      # weight forward, back heel up
R2=setj(lean(upper(G,(5,1)),9), hip_b=(3,45,-6), hip_f=(0,43,6), pelvis=(1,44,0),
        knee_b=(17,47,-7), ank_b=(20,28,-7), toe_b=(26,26,-7), knee_f=(18,25,7), ank_f=(22,4,6), toe_f=(31,1.8,6))   # chamber
R3=setj(G, elb_n=(6,58,12), wr_n=(11,63,11), fist_n=(14,66,10))                                  # guard tucks in for balance
R3=setj(lean(upper(R3,(8,1)),30), hip_b=(8,47,-6), hip_f=(1,43,6), pelvis=(3,45,0),
        knee_b=(31,52,-7), ank_b=(55,57,-7), toe_b=(55.1,57,-7), knee_f=(16,25,7), ank_f=(22,4,6), toe_f=(31,1.8,6))  # full extension
R3['head']=tuple(a+b for a,b in zip(R3['head'],(2,0,0)))                                             # eyes stay on the target
R3['_foot']=(1,0,0)
R3r=dict(lerpJ(R3,R2,0.18)); R3r['ank_b']=(R3r['ank_b'][0],R3r['ank_b'][1],-7); R3r['toe_b']=(R3r['ank_b'][0]+0.1,R3r['ank_b'][1],-7); R3r['_foot']=(1,0,0)
KICK=[(G,2),(R0,3)]+tween(R0,R1,[0.6],2)+[(R1,2)]+tween(R1,R2,[0.5],2)+[(R2,2),(lerpJ(R2,R3,0.6),1),(R3,6),(R3r,3),(R2,3)]+tween(R2,R1,[0.5],2)+[(R1,2)]+tween(R1,G,[0.4,0.8],2)

# ---- body kick (roundhouse to the ribs): the knee comes up sideways with the heel folded back, the hips turn
# over and the shin whips out level, the instep leading (pointed foot); the near fist drops to the hip for power.
def kickset(chamber, strike, lean_c, lean_s, push, foot, arms=None):
    C1=setj(lean(upper(G,(4,1)),lean_c), hip_b=(3,45,-6), hip_f=(0,43,6), pelvis=(1,44,0),
            knee_f=(18,25,7), ank_f=(22,4,6), toe_f=(31,1.8,6), **chamber)
    S0=setj(G,**(arms or {}))
    S=setj(lean(upper(S0,(push,1)),lean_s), hip_b=(push,47,-6), hip_f=(1,43,6), pelvis=(3,45,0),
           knee_f=(16,26,7), ank_f=(22,4,6), toe_f=(31,1.8,6), **strike)
    S['head']=tuple(a+b for a,b in zip(S['head'],(2,0,0)))
    S['toe_b']=(S['ank_b'][0]+0.1,S['ank_b'][1],-7); S['_foot']=(foot,0,0)
    Sr=dict(lerpJ(S,C1,0.15)); Sr['toe_b']=(Sr['ank_b'][0]+0.1,Sr['ank_b'][1],-7); Sr['_foot']=(foot,0,0)
    return [(G,2),(R0,3)]+tween(R0,R1,[0.6],2)+[(R1,2)]+tween(R1,C1,[0.5],2)+[(C1,2),(lerpJ(C1,S,0.6),1),(S,6),(Sr,3),(C1,3)]+tween(C1,R1,[0.5],2)+[(R1,2)]+tween(R1,G,[0.4,0.8],2)
DROP=dict(elb_n=(3,56,12), wr_n=(9,52,11), fist_n=(12,50,10))          # the near fist swings down to the hip
BODYK=kickset(dict(knee_b=(16,49,-7), ank_b=(0,45,-7), toe_b=(-5,47,-7)),
              dict(knee_b=(27,53,-7), ank_b=(49,56,-7)), 10, 28, 8, 2, DROP)
# ---- head kick: the same whip, but the knee drives high and the leg rises to head height, the body leaning far back
HEADK=kickset(dict(knee_b=(17,56,-7), ank_b=(2,52,-7), toe_b=(-3,55,-7)),
              dict(knee_b=(24,64,-7), ank_b=(40,82,-7)), 14, 42, 7, 3, DROP)
# ---- shin strike (low kick): the leg swings round low and nearly straight, the shin hitting at knee height,
# the hips turning right over and the near fist swinging down for power
SHIN=kickset(dict(knee_b=(10,36,-7), ank_b=(-5,30,-7), toe_b=(-10,31,-7)),
             dict(knee_b=(24,32,-7), ank_b=(44,24,-7)), 6, 16, 8, 2, DROP)

cache={}
def draw(J):
    k=tuple(sorted((n,tuple(round(c,2) for c in v)) for n,v in J.items()))
    if k not in cache:
        im=render(VIC,{n:v for n,v in J.items() if n!='_foot'},0.0)
        if '_foot' in J:             # the hand-drawn foot at the strike, its ankle on the ankle (far leg: one tone darker)
            o=np.asarray(im).copy(); sk=RAMPS['skin']; d=1
            col={'O':outl('skin'),'1':sk[0],'2':sk[2-d],'3':sk[3-d],'4':sk[4-d],'p':(176,104,84)}
            kind=int(J['_foot'][0]); art,(pvx,pvy),off={1:(FOOT45,FOOT45_PIVOT,(5,1)),2:(FOOT_PT,FOOT_PT_PIVOT,(5,0)),3:(FOOT_PT45,FOOT_PT45_PIVOT,(4,-3))}[kind]
            ax,ay=J['ank_b'][0]+SW/2-2+off[0], SH-J['ank_b'][1]+off[1]
            for j,row in enumerate(art):
                for i,ch in enumerate(row):
                    if ch!='.':
                        y,x=int(round(ay))+j-pvy,int(round(ax))+i-pvx
                        if 0<=y<SH and 0<=x<SW: o[y,x,:3]=col[ch]; o[y,x,3]=255
            im=Image.fromarray(o,'RGBA')
        cache[k]=im
    return cache[k]
t0=time.time()
seq=[]; x=40
for rep in range(3):
    for J,h in WALK: seq+= [(draw(J),x)]*h
    x+=STRIDE
for J,h in PUNCH: seq+=[(draw(J),x)]*h
seq+=[(draw(G),x)]*10
for J,h in KICK: seq+=[(draw(J),x)]*h
seq+=[(draw(G),x)]*10
for mvlist in (BODYK,HEADK,SHIN):
    for J,h in mvlist: seq+=[(draw(J),x)]*h
    seq+=[(draw(G),x)]*10
seq+=[(draw(G),x)]*6
print('drawn',len(cache),'frames in',round(time.time()-t0),'s')
bg=Image.open('bg0.png').convert('RGBA'); raw=b''; rawz=b''
for im,xx_ in seq:
    c=bg.copy(); c.alpha_composite(im,(xx_,80)); raw+=c.convert('RGB').tobytes()
subprocess.run(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','320x200','-r','30','-i','-','-vf','scale=1280:800:flags=neighbor',
  '-c:v','libx264','-crf','16','-pix_fmt','yuv420p','Vic moves 8.mp4'],input=raw,check=True)
# the frame sheet: every drawing once, in order
order=[]
for lst in (WALK,PUNCH,KICK):
    for J,h in lst: order.append(draw(J))
sheet=Image.new('RGBA',(SW*16,SH*6),(70,74,92,255))
for r,lst in enumerate((WALK,PUNCH,KICK,BODYK,HEADK,SHIN)):
    for i,(J,h) in enumerate(lst): sheet.alpha_composite(draw(J),(i*SW,r*SH))
sheet.resize((sheet.width*2,sheet.height*2),Image.NEAREST).convert('RGB').save('Vic moves 8 frames.png')
print('ok')
