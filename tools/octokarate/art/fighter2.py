# Arcade-style fighters, our own characters. A posed 3D body of swept spheres (muscles are extra spheres), lit by the sun,
# rendered at 4x, reduced to 1x with HARD cel tones (4 + a highlight), coloured outlines, depth lines between limbs.
import numpy as np, math
from PIL import Image
S=4; SW,SH=84,112
RAMPS={  # dark -> light; shadows lean purple/blue, highlights warm
 'skin':  [(58,24,34),(116,54,50),(176,96,70),(222,146,104),(250,200,156)],
 'skin2': [(34,16,24),(76,36,34),(122,66,48),(166,104,70),(206,150,108)],
 'indigo':[(14,14,40),(26,34,78),(42,62,122),(70,100,166),(130,160,206)],
 'white': [(52,50,84),(112,112,148),(176,180,204),(226,226,232),(255,252,240)],
 'black': [(10,8,16),(24,22,34),(42,40,58),(68,64,86),(104,100,124)],
 'rope':  [(60,40,20),(110,80,40),(166,128,70),(208,174,110),(240,214,160)],
 'red':   [(52,8,18),(104,16,26),(164,30,34),(212,62,46),(246,120,84)],
 'hair':  [(8,6,12),(20,16,24),(38,30,40),(62,50,60),(92,78,86)],
 'wrap':  [(70,62,76),(132,122,124),(190,180,166),(228,220,200),(252,248,232)],
 'blood': [(40,4,10),(76,8,14),(112,14,20),(150,24,26),(176,40,34)],
 'grey':  [(40,40,52),(84,84,98),(138,138,150),(190,190,198),(236,236,240)],
}
def outl(m): r=RAMPS[m][0]; return tuple(int(c*0.55) for c in r)
L=np.array([0.6,0.5,0.62]); L/=np.linalg.norm(L)
R=np.array([-0.85,0.25,-0.3]); R/=np.linalg.norm(R)

# ---- two original characters
VIC=dict(name='Vic',  # a lean shore fighter: indigo jacket, sleeves rolled to the elbow, rope belt, white headband
  skin='skin', jacket='indigo', pants='indigo', belt='rope', band='white', hair='hair', bare_chest=False, scale=1.0, bulk=1.0, hairstyle='spiky', wraps=False, handwraps=True)
SID=dict(name='Sid',  # Vic's rival: white jacket and trousers, black belt, red headband, hair swept back in a tail
  skin='skin2', jacket='white', pants='white', belt='black', band='red', hair='hair', bare_chest=False, scale=1.0, bulk=1.0, hairstyle='tail', wraps=False, handwraps=True)

def pose_guard(ph=0.0):
    b=1.2*math.sin(ph)
    return dict(
     ank_f=(22,4,5), knee_f=(17,24,7), hip_f=(3,42+b*.3,6), toe_f=(31,1.8,5),
     ank_b=(-22,4,-5), knee_b=(-12,22,-6), hip_b=(-6,42+b*.3,-6), toe_b=(-14,1.8,-5),
     pelvis=(-2,43+b*.4,0), chest=(4,64+b,0), sh_n=(1,71+b,11), sh_f=(8,72+b,-11), neck=(7,76+b,0), head=(11,83+b,0),
     elb_f=(21,61+b,-8), wr_f=(29,67+b,-6), fist_f=(33,70+b,-5),
     elb_n=(9,53+b,12), wr_n=(15,60+b,11), fist_n=(19,64+b,10)), b

def build(C,J,b):
    k=C['bulk']; jk=C['jacket']; pn=C['pants']; sk=C['skin']
    arm_up = sk if C['bare_chest'] else jk
    segs=[ # name, a, b, ra, rb, mat
     ('thigh_b','hip_b','knee_b',8.0*k,6.6*k,pn),('shin_b','knee_b','ank_b',6.6*k,7.2*k,pn),('foot_b','ank_b','toe_b',3.4,3.0,sk),
     ('uarm_f','sh_f','elb_f',5.6*k,5.0*k,arm_up),('farm_f','elb_f','wr_f',5.0*k,4.0*k,sk),
     ('torso','pelvis','chest',11.0*k,13.0*k,sk if C['bare_chest'] else jk),('neck','neck','head',4.6*k,5.0,sk),
     ('thigh_f','hip_f','knee_f',8.2*k,6.6*k,pn),('shin_f','knee_f','ank_f',6.6*k,7.4*k,pn),('foot_f','ank_f','toe_f',3.5,3.1,sk),
     ('uarm_n','sh_n','elb_n',5.8*k,5.2*k,arm_up),('farm_n','elb_n','wr_n',5.2*k,4.2*k,sk),
    ]
    sph=[('fist_f',J['fist_f'],3.4,sk),('fist_n',J['fist_n'],3.6,sk),('head',J['head'],7.0,sk),
         ('delt_n',(J['sh_n'][0],J['sh_n'][1]-1.5,J['sh_n'][2]),7.0*k,arm_up),('delt_f',(J['sh_f'][0],J['sh_f'][1]-1.5,J['sh_f'][2]),6.6*k,arm_up),
         ('nose',(J['head'][0]+6.2,J['head'][1]-1.2,2.5),1.7,sk),('jaw',(J['head'][0]+3.5,J['head'][1]-5.0,1.5),4.0,sk),
         ('fore_n',(J['elb_n'][0]+2.2,J['elb_n'][1]+2.6,J['elb_n'][2]+1.2),4.6*k,sk),('fore_f',(J['elb_f'][0]+2.4,J['elb_f'][1]+2.2,J['elb_f'][2]+1),4.3*k,sk)]
    if C.get('wraps'):   # knuckles: four ridges across the front of each fist
        for f,zz in (('fist_n',10),('fist_f',-5)):
            fx,fy,fz=J[f]
            for q in range(4): sph.append((f,(fx+3.2,fy+2.6-q*1.7,fz+1.5-q*0.4),1.7,sk))
    if C['bare_chest']:
        c=J['chest']; p=J['pelvis']
        sph+=[('pec_n',(c[0]+5*k,c[1]+1,5*k),7.0*k,sk),('pec_f',(c[0]+6*k,c[1]+1.5,-4*k),6.6*k,sk),
              ('belly',(p[0]+7*k,p[1]+11,2.5),8.2*k,sk),('bic_n',(J['sh_n'][0]+3,J['sh_n'][1]-8,J['sh_n'][2]+2.5),5.4*k,sk)]
    return segs,sph

exec(open('fistart.py').read())
def paste_fist(o,wx,wy,ang,dim):
    """Paste a hand-drawn fist with its wrist end on (wx,wy). Two hand-drawn angles (level and 45 degrees up);
    the nearest one is used - small pixel art is redrawn per angle, never rotated."""
    w=RAMPS['wrap']; bl=RAMPS['blood']
    col={'O':outl('wrap'),'1':w[max(0,1-dim)],'2':w[2-dim],'3':w[3-dim],'4':w[4-dim],'R':bl[2-dim],'r':bl[4-dim]}
    if ang>22: art,ox_,oy_=FIST45,12,12-FIST45_TOP
    else:      art,ox_,oy_=FIST,1,5
    for j,row in enumerate(art):
        for i,ch in enumerate(row):
            if ch=='.': continue
            y,x=int(round(wy))+j-oy_,int(round(wx))+i-ox_
            if 0<=y<o.shape[0] and 0<=x<o.shape[1]: o[y,x,:3]=col[ch]; o[y,x,3]=255

def render(C,J,b,flip=False,layers=False,imgflip=None):
    W,H=SW*S,SH*S; sc=C['scale']
    zb=np.full((H,W),-1e9,np.float32); N=np.zeros((H,W,3),np.float32)
    mat=np.full((H,W),'',object); part=np.full((H,W),'',object); tb=np.zeros((H,W),np.float32)
    LA=np.full((H,W),-99,np.float32); LC=np.zeros((H,W),np.float32)
    ox=SW/2-2
    def sp(c,r,m,pid,t=0.0,loc=None):
        cx=(c[0]*sc+ox)*S; cy=(SH-c[1]*sc)*S; cz=c[2]*sc*S; rr=r*sc*S
        x0,x1=int(max(0,cx-rr-1)),int(min(W,cx+rr+2)); y0,y1=int(max(0,cy-rr-1)),int(min(H,cy+rr+2))
        if x0>=x1 or y0>=y1: return
        X,Y=np.meshgrid(np.arange(x0,x1)+0.5,np.arange(y0,y1)+0.5)
        dx=X-cx; dy=Y-cy; d2=dx*dx+dy*dy; ins=d2<rr*rr
        dz=np.sqrt(np.clip(rr*rr-d2,0,None)); z=cz+dz
        zs=zb[y0:y1,x0:x1]; upd=ins&(z>zs); zs[upd]=z[upd]
        n=N[y0:y1,x0:x1]; n[...,0][upd]=(dx/rr)[upd]; n[...,1][upd]=(-dy/rr)[upd]; n[...,2][upd]=(dz/rr)[upd]
        mat[y0:y1,x0:x1][upd]=m; part[y0:y1,x0:x1][upd]=pid; tb[y0:y1,x0:x1][upd]=t
        if loc is not None: LA[y0:y1,x0:x1][upd]=loc[0]; LC[y0:y1,x0:x1][upd]=loc[1]
    segs,sph=build(C,J,b)
    for pid,a,bb,ra,rb,m in segs:
        A=np.array(J[a],float); B=np.array(J[bb],float); n=int(np.linalg.norm(B-A)*S/1.5)+2
        for kk in range(n): t=kk/(n-1); sp(A+(B-A)*t, ra+(rb-ra)*t, m, pid, t)
    for pid,c,r,m in sph:
        if pid in ('fist_n','fist_f') and C.get('handwraps'): continue
        sp(np.array(c,float),r,m,pid)
    yy,xx=np.mgrid[0:H,0:W]
    def px(p): return (p[0]*sc+ox)*S,(SH-p[1]*sc)*S
    # belt / sash: a band round the waist, a knot at the front and two tails
    wy=(SH-(J['pelvis'][1]+2.5)*sc)*S
    waist=(np.abs(yy-wy)<(2.0 if C['bare_chest'] else 1.7)*S*sc)&np.isin(part,['torso','thigh_f','thigh_b','belly'])
    if C['bare_chest']: mat[(part=='torso')&(yy>wy)]=C['pants']      # below the sash the trousers, not skin
    mat[waist]=C['belt']
    kx=J['pelvis'][0]+11*C['bulk']; ky=J['pelvis'][1]+2.5; kz=12*C['bulk']
    for (dx1,dy1) in ((1.5,-10),(5,-8.5)):
        A=np.array((kx,ky,kz),float); B=A+np.array((dx1,dy1,1))
        for kk in range(30): sp(A+(B-A)*kk/29,1.4,C['belt'],'tail')
    sp(np.array((kx,ky,kz+0.5)),2.3,C['belt'],'knot')
    # jacket: rolled sleeve cuffs, and the lapel with a V of chest
    if C['jacket']:
        for e in ('elb_n','elb_f'):
            ex,ey=px(J[e]); cuff=(np.abs(np.hypot(xx-ex,yy-ey)-1.0*S)<1.4*S)&np.isin(part,['farm_n','farm_f','fore_n','fore_f','uarm_n','uarm_f'])
            mat[cuff]=C['jacket']
        nxp,nyp=px((J['neck'][0]+3,J['neck'][1]-2)); bxp,byp=px((J['pelvis'][0]+11,J['pelvis'][1]+5))
        vx,vy=bxp-nxp,byp-nyp; ln=math.hypot(vx,vy)
        along=((xx-nxp)*vx+(yy-nyp)*vy)/ln; perp=((xx-nxp)*vy-(yy-nyp)*vx)/ln
        lapel=(part=='torso')&(mat==C['jacket'])&(np.abs(perp)<0.7*S)&(along>0)&(along<ln)
        vsk=(part=='torso')&(mat==C['jacket'])&(perp<-0.7*S)&(along>-2*S)&(along<ln*0.42)&(xx>nxp-1*S)
        mat[vsk]=C['skin']
    else: lapel=np.zeros((H,W),bool)
    # hand wraps: cloth bandage round each fist and wrist, wound in diagonal turns, blood soaked into the knuckles
    if C.get('wraps'):
        rng=np.random.default_rng(5)
        wrap=np.isin(part,['fist_n','fist_f'])|(np.isin(part,['farm_n','farm_f'])&(tb>0.72))
        wrap&=np.isin(mat,[C['skin']])
        mat[wrap]='wrap'
        WRAP=wrap
        for f in ('fist_n','fist_f'):
            fx,fy=px(J[f]); r=5.0*S
            # the knuckles: the front of the fist, facing the opponent; blood in irregular blotches there
            dx=(xx-fx)/r; dy=(yy-fy)/r
            blot=np.zeros_like(dx)
            for _ in range(9):
                cx_,cy_=rng.uniform(0.45,0.95),rng.uniform(-0.75,0.35); rr=rng.uniform(0.14,0.28)
                blot=np.maximum(blot,1-np.hypot(dx-cx_,dy-cy_)/rr)
            mat[(part==f)&(blot>0)&(mat=='wrap')]='blood'
        # a drip and a stain on the wrist wraps
        for f,(ddx,ddy) in (('wr_n',(0.5,1.2)),('wr_f',(1.0,0.4))):
            wx,wy_=px(J[f]); mat[(np.hypot(xx-wx-ddx*S,yy-wy_-ddy*S)<1.3*S)&WRAP]='blood'
    else: WRAP=np.zeros((H,W),bool)
    if C['jacket']:   # the collar covers the back of the neck
        nkx,_=px(J['neck']); mat[(part=='neck')&(xx<nkx+0.5*S)&(yy>px(J['neck'])[1]-2*S)]=C['jacket']
    # hair
    hcx,hcy=px(J['head']); r7=7.4*S*sc
    hd=((xx-hcx)**2+(yy-hcy)**2)<r7**2
    if C['hairstyle']=='spiky':
        top=(yy-hcy)<(-3.4*S-(xx-hcx)*0.25)+np.abs(np.sin((xx-hcx)/S*1.3))*1.2*S
        mat[(part=='head')&hd&(top|((xx-hcx)<-2.8*S))]=C['hair']
        for (a,dx1,dy1) in ((-0.2,-6,7),(0.5,-2,9),(1.0,2,8),(-0.8,-9,3)):       # spikes
            A=np.array((J['head'][0]-1,J['head'][1]+3,0),float); B=A+np.array((dx1,dy1,0))*0.9
            for kk in range(14): sp(A+(B-A)*kk/13,2.4*(1-kk/14)+0.4,C['hair'],'hair')
    elif C['hairstyle']=='tail':   # swept back into a short tied tail
        top=(yy-hcy)<(-3.0*S-(xx-hcx)*0.30)
        mat[(part=='head')&hd&(top|((xx-hcx)<-2.6*S))]=C['hair']
        A=np.array((J['head'][0]-6,J['head'][1]+1.5,-1),float)
        for kk in range(12): sp(A+np.array((-0.7*kk,-0.75*kk,-0.1*kk)),2.1-0.09*kk,C['hair'],'hair')
    else:  # topknot: grey, shaved-high sides
        mat[(part=='head')&hd&(((yy-hcy)<-4.2*S-(xx-hcx)*0.2)|((xx-hcx)<-3.5*S))]=C['hair']
        A=np.array((J['head'][0]-5.5,J['head'][1]+5.0,0),float)        # a small tied knot lying back on the crown
        for kk in range(8): sp(A+np.array((-0.55*kk,-0.1*kk,0)),1.9-0.08*kk,C['hair'],'hair')
        sp(A+np.array((0.6,0.2,0)),1.2,'red','tie')
    if C['band']:
        hb=np.isin(part,['head'])&hd&(np.abs((yy-hcy)-(-3.0*S-(xx-hcx)*0.25))<1.0*S)
        mat[hb]=C['band']
        for (dx1,dy1) in ((-8,-4),(-7,-8)):
            A=np.array((J['head'][0]-6.5,J['head'][1]+1.5,-1),float); B=A+np.array((dx1,dy1,-1))
            for kk in range(24): sp(A+(B-A)*kk/23,1.1,C['band'],'bandtail')
    # ---- light: key (the sun), rim (the sky behind), cloth folds, muscle lines
    Lw=L*np.array([-1,1,1]) if flip else L; Rw=R*np.array([-1,1,1]) if flip else R
    dif=np.clip(N@Lw,0,1); rim=np.clip(N@Rw,0,1)**4
    lum=0.12+0.85*dif
    lum=np.where(np.isin(part,['thigh_b','shin_b','foot_b']),lum-0.14,lum)   # the far leg sits back: one tone darker
    cloth=np.isin(mat,[C['pants'],C['jacket'] or '-'])
    fold=np.clip(np.sin(tb*8.0+(xx/S)*0.35+(yy/S)*0.15),0,1)**8
    lum=np.where(cloth,lum-0.22*fold,lum)
    lum=np.where(lapel,lum-0.6,lum)
    turns=np.clip(np.sin(((xx+yy*0.6)/S)*1.9),0,1)**10                # the bandage's wound turns
    turns=(np.sin(((xx+yy*0.7)/S)*2.2)>0.82)
    lum=np.where(np.isin(mat,['wrap','blood'])&turns,lum-0.32,lum)
    if C['bare_chest']:       # abs: a few dark lines on the belly
        bx,by=px((J['pelvis'][0]+9*C['bulk'],J['pelvis'][1]+12))
        absl=(part=='belly')&((np.abs(((yy-by)/S)%4.0-2.0)<0.35)|(np.abs(xx-bx)<0.4*S))&(np.abs(yy-by)<6*S)
        lum=np.where(absl,lum-0.25,lum)
    # ---- to 1x with hard tones
    TH=[0.30,0.50,0.70,0.90]
    out=np.zeros((SH,SW,4),np.uint8); Z1=np.full((SH,SW),-1e9); M1=np.full((SH,SW),'',object); P1=np.full((SH,SW),'',object); RIM=np.zeros((SH,SW))
    for y in range(SH):
        for x in range(SW):
            sl=(slice(y*S,(y+1)*S),slice(x*S,(x+1)*S))
            bm=mat[sl]; cov=(bm!='')
            if cov.sum()<S*S*0.45: continue
            vals,cnt=np.unique(bm[cov],return_counts=True); m=vals[cnt.argmax()]; sel=bm==m
            l=lum[sl][sel].mean(); k=int(sum(l>t for t in TH))
            out[y,x,:3]=RAMPS[m][k]; out[y,x,3]=255
            Z1[y,x]=zb[sl][sel].max()/S; M1[y,x]=m; RIM[y,x]=rim[sl][sel].mean()
            pv,pc=np.unique(part[sl][sel],return_counts=True); P1[y,x]=pv[pc.argmax()]
    o=out.copy()
    for y in range(SH):
        for x in range(SW):
            if out[y,x,3]==0: continue
            m=M1[y,x]; edge=dep=False
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                X,Y=x+dx,y+dy
                if not(0<=X<SW and 0<=Y<SH) or out[Y,X,3]==0: edge=True
                elif Z1[Y,X]-Z1[y,x]>3.0 and P1[Y,X]!=P1[y,x]: dep=True
            if edge: o[y,x,:3]=outl(m)
            elif dep: o[y,x,:3]=RAMPS[m][0]
            elif RIM[y,x]>0.35: o[y,x,:3]=tuple(min(255,int(c*0.6+v*0.4)) for c,v in zip(out[y,x,:3],(150,170,230)))   # cool sky rim
    # face: eye, brow, mouth line
    hx,hy=J['head'][0]*sc+ox,SH-J['head'][1]*sc
    ex,ey=int(hx+3.6),int(hy-0.2)
    o[ey,ex,:3]=(250,240,230); o[ey,ex+1,:3]=(20,12,16)
    for d in (-1,0,1,2): o[ey-1,ex+d,:3]=RAMPS['hair'][1]
    o[int(hy+3.6),int(hx+4.4),:3]=RAMPS[C['skin']][0]
    if C.get('handwraps'):     # the hand-drawn fists, wrist end on the wrist
        for e_,w_,dim in (('elb_f','wr_f',1),('elb_n','wr_n',0)):
            wx,wy=J[w_][0]*sc+ox, SH-J[w_][1]*sc
            ang=math.degrees(math.atan2(J[w_][1]-J[e_][1],J[w_][0]-J[e_][0]))   # the forearm's angle
            paste_fist(o,wx,wy,ang,dim)
    im=Image.fromarray(o,'RGBA')
    if layers: return im,P1,int(round(SH-(J['pelvis'][1]+1)*sc))
    if imgflip is None: imgflip=flip
    return im.transpose(Image.FLIP_LEFT_RIGHT) if imgflip else im

if __name__=='__main__':
    J,b=pose_guard(0); a=render(VIC,J,b)
    for bgn,nm in (('bg0',''),('bg30',' totality')):
        bg=Image.open(bgn+'.png').convert('RGBA'); bg.alpha_composite(a,(110,80))
        bg.resize((1280,800),Image.NEAREST).convert('RGB').save(f'Kai mockup 8{nm}.png')
    z=Image.new('RGBA',(SW,SH),(70,74,92,255)); z.alpha_composite(a,(0,0))
    z.resize((SW*7,SH*7),Image.NEAREST).convert('RGB').save('Kai mockup 8 close-up.png')
    print('ok')
