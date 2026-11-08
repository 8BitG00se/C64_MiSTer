# Sacred geometry for the Octophonic 64: one d64 per figure, each a plain BASIC V2 program (list it, edit it,
# compile it) that draws on OctoVIC's bitmap layer with the blitter's lines and sounds the figure on the SID.
import subprocess, os, textwrap
LIB = r'''
8000 rem ---- line x0,y0 - x1,y1 in colour c
8010 lx=int(x0+.5):ly=int(y0+.5):lu=int(x1+.5):lv=int(y1+.5)
8015 lx=-lx*(lx>0):ly=-ly*(ly>0):lu=-lu*(lu>0):lv=-lv*(lv>0)
8020 poke v+102,lx and 255:poke v+103,lx/256
8025 poke v+104,ly and 255:poke v+105,ly/256
8030 poke v+106,lu and 255:poke v+107,lu/256:poke v+108,lv and 255
8040 poke v+109,lv/256:poke v+126,c:poke v+127,7:return
8100 rem ---- circle at cx,cy radius r colour c
8110 x1=cx+r:y1=cy:for ck=1 to 36:ca=ck*p/18
8120 x0=x1:y0=y1:x1=cx+r*cos(ca):y1=cy+r*sin(ca):gosub 8000:next:return
8200 rem ---- a bell: f hz on voice w (0-2)
8210 bs=54272+7*w:bq=int(f*17.03):poke bs+4,16
8215 poke bs,bq and 255:poke bs+1,bq/256
8220 poke bs+5,10:poke bs+6,9:poke bs+4,17:return
8300 rem ---- wait t sixtieths
8310 t0=ti
8320 if ti-t0<t then 8320
8330 return
8400 rem ---- clear the picture
8410 poke v+118,0:poke v+119,2:poke v+120,0:poke v+121,2
8420 poke v+115,0:poke v+116,0:poke v+117,16:poke v+126,0:poke v+127,3:return
8500 rem ---- 3d point (x,y,z) turned by angles ra,rb, seen: sx,sy
8510 pu=x*cos(ra)-z*sin(ra):pw=x*sin(ra)+z*cos(ra)
8520 sy=y*cos(rb)-pw*sin(rb):sz=y*sin(rb)+pw*cos(rb)
8530 pm=sc*4/(4+sz):sx=ox+pu*pm:sy=oy+sy*pm:return
8900 rem ---- the end: space again, q quit
8910 poke 214,22:print:print " space: again    q: quit";
8920 get k$:if k$="" then 8920
8930 if k$="q" then poke v+32,0:poke v+5,0:print "{clr}":end
8940 run
9000 rem ---- octovic set-up: the bitmap layer, its palette, the blitter
9010 v=54784:p=4*atn(1):poke 53311,79:poke 53311,56
9020 if peek(v+30)<>140 then print "this needs the octophonic 64":end
9030 for i=5 to 159:poke v+i,0:next:poke 53280,0:poke 53281,0
9040 poke v+25,1:poke v+26,0:for i=0 to 15:c=0:if i=1 then c=225
9050 poke v+27,c:poke v+28,c:poke v+29,c:next
9060 poke v+25,2:poke v+26,0:poke v+27,6:poke v+28,4:poke v+29,18
9065 restore
9066 read r:if r<>999 then 9066
9070 poke v+25,0:for i=1 to 15:read r,g,b:poke v+26,i
9080 poke v+27,r:poke v+28,g:poke v+29,b:next
9090 poke v+36,0:poke v+37,0:poke v+38,16:poke v+47,0
9100 poke v+40,32:poke v+41,0:poke v+42,36:poke v+43,0
9110 poke v+124,0:poke v+125,2:gosub 8400
9120 poke v+6,0:poke v+5,11:poke v+32,91
9130 for i=54272 to 54296:poke i,0:next:poke 54296,15:restore:return
9500 data 999,240,190,80, 245,235,205, 90,220,240, 170,110,240, 240,120,160
9510 data 120,220,140, 80,120,240, 255,255,255, 200,140,50, 60,170,190
9520 data 120,70,190, 190,80,120, 70,160,90, 50,70,170, 150,150,160
'''
# palette: 1 gold 2 cream 3 cyan 4 violet 5 rose 6 green 7 blue 8 white 9 deep gold 10 teal 11 deep violet 12 wine 13 leaf 14 navy 15 grey
P = {}
P['seed'] = ('seed of life', 'seven circles: the first days', r'''
10 rem seed of life - seven circles, each through the others' centres
20 gosub 9000:print "{clr}{wht} seed of life":print " seven circles, one radius"
30 cx=198:cy=150:r=44:s1=r:dim n(7):for i=1 to 7:read n(i):next
40 for i=0 to 6:if i=0 then x=cx:y=cy
50 if i>0 then a=(i-1)*p/3:x=cx+r*cos(a):y=cy+r*sin(a)
60 c=1:if i>0 then c=2+(i and 1)
70 cx=x:cy=y:r=s1:gosub 8100:cx=198:cy=150
80 f=196*n(i+1):w=i-int(i/3)*3:gosub 8200:t=20:gosub 8300:next
90 cx=198:cy=150:r=2*s1:c=9:gosub 8100:gosub 8900
100 rem the seven notes: just intonation, one for each circle
110 data 1,1.125,1.25,1.333,1.5,1.667,1.875
''')
P['egg'] = ('egg of life', 'seven circles, touching', r'''
10 rem egg of life - from the flower: seven circles that only touch
20 gosub 9000:print "{clr}{wht} egg of life":print " seven spheres, the first cells"
30 r=32:dim n(7):for i=1 to 7:read n(i):next
40 cx=198:cy=150:r=3*r:c=9:gosub 8100:r=r/3
50 for i=0 to 6:if i=0 then x=198:y=150
60 if i>0 then a=(i-1)*p/3+p/6:x=198+2*r*cos(a):y=150+2*r*sin(a)
70 cx=x:cy=y:c=3+(i>0):gosub 8100
80 f=131*n(i+1):w=i-int(i/3)*3:gosub 8200:t=24:gosub 8300:next:gosub 8900
100 rem the cells divide: 1, 2, 4, 8 - octaves, then the fifths between
110 data 1,2,1.5,3,4,6,8
''')
P['flower'] = ('flower of life', 'nineteen circles in a ring', r'''
10 rem flower of life - nineteen circles on a hexagon grid, in two rings
20 gosub 9000:print "{clr}{wht} flower of life":print " 19 circles, 2 rings"
30 r=30:m=0:dim n(8):for i=0 to 7:read n(i):next
40 for d=0 to 2:for a=-2 to 2:for b=-2 to 2
50 x=198+r*(a+b/2):y=150+r*b*sqr(3)/2:q=(abs(a)+abs(b)+abs(a+b))/2
60 if q<>d then 90
70 cx=x:cy=y:c=1+d:gosub 8100
80 f=110*n(m and 7):w=m-int(m/3)*3:gosub 8200:m=m+1
90 next:next:next
100 cx=198:cy=150:r=3*r:c=9:gosub 8100:r=r+3:gosub 8100:gosub 8900
110 rem a pentatonic, rising with each ring
120 data 2,2.25,2.5,3,3.333,4,4.5,5
''')
P['metatron'] = ('metatron cube', '13 centres, every one joined', r'''
10 rem metatron's cube - the fruit of life's 13 centres, each joined to all 12 others
20 gosub 9000:print "{clr}{wht} metatron's cube":print " 13 circles, 78 lines"
30 r=22:dim x(12),y(12):x(0)=198:y(0)=150
40 for i=0 to 5:a=i*p/3+p/6:x(i+1)=198+2*r*cos(a):y(i+1)=150+2*r*sin(a)
50 x(i+7)=198+4*r*cos(a):y(i+7)=150+4*r*sin(a):next
60 for i=0 to 12:cx=x(i):cy=y(i):c=7:gosub 8100:next
70 for i=0 to 11:for j=i+1 to 12:x0=x(i):y0=y(i):x1=x(j):y1=y(j)
80 c=3:if i>0 and j>6 then c=4
90 gosub 8000:next
100 f=65.4*(i+1):w=i-int(i/3)*3:if i<8 then gosub 8200
110 next:gosub 8900
120 rem each centre's lines ring the next overtone: the harmonic series
''')
P['vesica'] = ('vesica piscis', 'two circles, root three', r'''
10 rem vesica piscis - two circles, each through the other's centre
20 gosub 9000:print "{clr}{wht} vesica piscis":print " its height : width = root 3"
30 r=80:cx=158:cy=150:c=1:gosub 8100:cx=238:c=3:gosub 8100
40 h=r*sqr(3)/2:x0=198:y0=150-h:x1=198:y1=150+h:c=8:gosub 8000
50 x0=158:y0=150:x1=238:y1=150:c=8:gosub 8000
60 x0=158:y0=150:x1=198:y1=150-h:c=5:gosub 8000:x0=238:gosub 8000
70 y1=150+h:gosub 8000:x0=158:gosub 8000
80 f=146.8:w=0:gosub 8200:t=50:gosub 8300
90 f=146.8*sqr(3):w=1:gosub 8200:t=50:gosub 8300
100 f=146.8*2:w=2:gosub 8200:gosub 8900
110 rem the two notes are in the vesica's own ratio, 1 : 1.732
''')
P['tree'] = ('tree of life', 'ten spheres, 22 paths', r'''
10 rem tree of life - ten spheres (sephiroth) and the 22 paths between them
20 gosub 9000:print "{clr}{wht} tree of life":print " 10 spheres, 22 paths"
30 dim x(10),y(10):for i=1 to 10:read a,b:x(i)=198+a*52:y(i)=48+b*30:next
40 for i=1 to 22:read a,b:x0=x(a):y0=y(a):x1=x(b):y1=y(b):c=2:gosub 8000:next
50 restore:for i=1 to 64:read a:next
60 for i=1 to 10:cx=x(i):cy=y(i):r=12:c=1:gosub 8100:r=9:c=9:gosub 8100
70 read f:w=i-int(i/3)*3:gosub 8200:t=22:gosub 8300:next:gosub 8900
100 data 0,0, 1,1, -1,1, 1,3, -1,3, 0,4, 1,5, -1,5, 0,6, 0,7.6
110 data 1,2,1,3,1,6,2,3,2,4,2,6,3,5,3,6,4,5,4,6,4,7,5,6,5,8,6,7,6,8
120 data 6,9,7,8,7,9,7,10,8,9,8,10,9,10
130 rem from the crown down: a falling scale, one note a sphere
140 data 784,698,659,587,523,494,440,392,349,330
''')
P['merkaba'] = ('merkaba', 'two tetrahedra, turning', r'''
10 rem merkaba - a star tetrahedron: two tetrahedra, one up, one down, turning
20 gosub 9000:print "{clr}{wht} merkaba":print " two tetrahedra, counter-turning"
30 dim x(7),y(7),z(7),a(7),b(7),e(11),g(11):sc=70:ox=198:oy=150
40 for i=0 to 7:read x(i),y(i),z(i):next:for i=0 to 11:read e(i),g(i):next
45 dim c(7),d(7)
50 for f1=0 to 47:ra=f1*p/24:rb=.35
60 for i=0 to 7:x=x(i):y=y(i):z=z(i):gosub 8500:a(i)=sx:b(i)=sy:next
70 c=0:if f1=0 then 75
72 for i=0 to 11:x0=c(e(i)):y0=d(e(i)):x1=c(g(i)):y1=d(g(i)):gosub 8000
73 next
75 for i=0 to 11:x0=a(e(i)):y0=b(e(i)):x1=a(g(i)):y1=b(g(i)):c=1-2*(i>5)
76 gosub 8000:next
80 if (f1 and 7)=0 then f=220*(1+(f1 and 8)/16):w=(f1/8)and 1:gosub 8200
90 for i=0 to 7:c(i)=a(i):d(i)=b(i):next
100 next:gosub 8900
110 data 1,1,1, 1,-1,-1, -1,1,-1, -1,-1,1, -1,-1,-1, -1,1,1, 1,-1,1, 1,1,-1
120 data 0,1,0,2,0,3,1,2,1,3,2,3, 4,5,4,6,4,7,5,6,5,7,6,7
130 rem up and down: a note and its fifth swap as it turns
''')
P['tetra64'] = ('64 tetrahedron', 'the grid seen from above', r'''
10 rem 64 tetrahedron grid, seen down its axis: two big triangles, each cut into 16
20 gosub 9000:print "{clr}{wht} 64 tetrahedron grid":print " seen from above: 4 x 4 x 4"
30 r=96:dim tx(2),ty(2)
40 for t=0 to 1:s=1-2*t:c=1+2*t
60 for i=0 to 2:a=p/2+i*2*p/3:tx(i)=198+r*cos(a):ty(i)=150-s*r*sin(a):next
70 for k=0 to 4:for e=0 to 2:i=e:j=e+1:if j=3 then j=0
80 l=e+2:if l>2 then l=l-3
90 x0=tx(i)+(tx(l)-tx(i))*k/4:y0=ty(i)+(ty(l)-ty(i))*k/4
100 x1=tx(j)+(tx(l)-tx(j))*k/4:y1=ty(j)+(ty(l)-ty(j))*k/4:gosub 8000
110 next:f=131*(1+k/4)*(1+t/2):w=t:gosub 8200:t1=t:t=15:gosub 8300:t=t1:next
120 next:cx=198:cy=150:r=r+4:c=9:gosub 8100:gosub 8900
130 rem the cuts sound the quarters: 1, 5/4, 6/4, 7/4, 2
''')
P['sriyantra'] = ('sri yantra', 'nine triangles: four up, five down', r'''
10 rem sri yantra - nine triangles (4 up, 5 down) in a circle, in lotus rings and a square gate
20 gosub 9000:print "{clr}{wht} sri yantra":print " 4 up, 5 down, one point"
30 r=86:cx=198:cy=152
40 for i=1 to 9:read u,yb,ya,hw
50 x0=cx-hw*r:y0=cy+yb*r*u:x1=cx+hw*r:y1=y0:c=1+(u<0)*-3:gosub 8000
60 x0=cx:y0=cy+ya*r*u:gosub 8000:x1=cx-hw*r:gosub 8000
70 f=110*2^((i-1)/9*2):w=i-int(i/3)*3:gosub 8200:t=18:gosub 8300:next
80 c=9:r=r+2:gosub 8100:r=r+14:c=5:gosub 8100:r=r+6:gosub 8100
90 for i=0 to 15:a=i*p/8:x0=cx+(r-6)*cos(a):y0=cy+(r-6)*sin(a)
100 x1=cx+(r+10)*cos(a+p/16):y1=cy+(r+10)*sin(a+p/16):c=5:gosub 8000:next
110 x0=cx-r-18:y0=cy-r-18:x1=cx+r+18:y1=y0:c=6:gosub 8000
115 y0=cy+r+18:y1=y0:gosub 8000
120 x1=x0:y0=cy-r-18:gosub 8000:x0=cx+r+18:x1=x0:gosub 8000
130 x0=cx:y0=cy+8:x1=cx:y1=cy+9:c=8:gosub 8000:f=440:w=0:gosub 8200:gosub 8900
140 rem u: 1 up, -1 down; base y, apex y, half width (of the radius)
150 data -1,-.2,1,.6, 1,.82,-1,.57, -1,-.56,.72,.6, 1,.55,-.66,.68
160 data -1,-.4,.53,.45, 1,.38,-.4,.44, -1,-.24,.37,.32, 1,.2,-.22,.3
170 data -1,-.06,.24,.17
''')
P['vectoreq'] = ('vector equilibrium', 'twelve spheres round one', r'''
10 rem vector equilibrium (cuboctahedron): 12 around 1, every edge = every radius
20 gosub 9000:print "{clr}{wht} vector equilibrium":print " edge = radius"
30 dim x(12),y(12),z(12),a(12),b(12),c(12),d(12):sc=60:ox=198:oy=150:n=0
40 for i=0 to 2:for s=-1 to 1 step 2:for t=-1 to 1 step 2
50 v(0)=0:v(1)=0:v(2)=0:v((i+1)-3*int((i+1)/3))=s:v((i+2)-3*int((i+2)/3))=t
60 x(n)=v(0):y(n)=v(1):z(n)=v(2):n=n+1:next:next:next
70 for f1=0 to 35:ra=f1*p/36:rb=.4
80 for i=0 to 11:x=x(i):y=y(i):z=z(i):gosub 8500:a(i)=sx:b(i)=sy:next
90 x=0:y=0:z=0:gosub 8500:a(12)=sx:b(12)=sy
100 if f1>0 then c1=0:c3=0:gosub 200
110 for i=0 to 12:c(i)=a(i):d(i)=b(i):next:c1=1:c3=3:if f1=35 then c1=9:c3=10
120 gosub 200:if (f1 and 3)>0 then 130
125 f=196*(1+(f1/4 and 3)/4):w=f1/4 and 1:gosub 8200
130 next:gosub 8900
200 for i=0 to 11:for j=i+1 to 11
210 d=(x(i)-x(j))^2+(y(i)-y(j))^2+(z(i)-z(j))^2:if d>2.1 then 230
220 x0=c(i):y0=d(i):x1=c(j):y1=d(j):c=c1:gosub 8000
230 next:x0=c(12):y0=d(12):x1=c(i):y1=d(i):c=c3:gosub 8000:next:return
''')
P['golden'] = ('golden ratio', 'phi: the whirling rectangles', r'''
10 rem the golden ratio: a golden rectangle cut into squares, and the spiral through them
20 gosub 9000:print "{clr}{wht} golden ratio  phi = 1.618..."
30 ph=(1+sqr(5))/2:x=40:y=60:w1=316:h=w1/ph:d=0:r2=0
40 x0=x:y0=y:x1=x+w1:y1=y:c=2:gosub 8000:y0=y+h:y1=y0:gosub 8000
50 x1=x:y0=y:gosub 8000:x0=x+w1:x1=x0:gosub 8000:f=130.8:n=0
60 for k=0 to 9:s=h:if w1<h then s=w1
70 if d=0 then x0=x+s:y0=y:x1=x0:y1=y+h:ax=x+s:ay=y+s:a0=p:x=x+s:w1=w1-s
80 if d=1 then x0=x:y0=y+s:x1=x+w1:y1=y0:ax=x+w1-s:ay=y+s:a0=1.5*p:y=y+s:h=h-s
90 if d=2 then x0=x+w1-s:y0=y:x1=x0:y1=y+h:ax=x0:ay=y+h-s:a0=0:w1=w1-s
100 if d=3 then x0=x:y0=y+h-s:x1=x+w1:y1=y0:ax=x+s:ay=y0:a0=p/2:h=h-s
110 c=9:gosub 8000:x1=ax+s*cos(a0):y1=ay+s*sin(a0)
120 for j=1 to 12:a=a0+j*p/24:x0=x1:y0=y1:x1=ax+s*cos(a):y1=ay+s*sin(a)
125 c=1:gosub 8000:next
130 w=k-3*int(k/3):gosub 8200:f=f*ph:if f>1600 then f=f/4
140 t=20:gosub 8300:d=(d+1) and 3:next:gosub 8900
150 rem each square sounds phi times the last (folded back down when it gets too high)
''')
P['fibonacci'] = ('fibonacci', '1 1 2 3 5 8 13 21', r'''
10 rem fibonacci: squares 1,1,2,3,5,8,13,21 laid in a spiral, each note a step of the scale
20 gosub 9000:print "{clr}{wht} fibonacci  1 1 2 3 5 8 13 21"
30 u=5:dim n(6):for i=0 to 6:read n(i):next
40 a=1:b=1:x=200:y=176:l=x:t2=y:r1=x+u:b1=y+u:d=0
50 for k=1 to 8:s=a*u
60 if k=1 then x=200:y=176:goto 110
70 if d=0 then x=r1:y=t2
80 if d=1 then x=r1-s:y=b1
90 if d=2 then x=l-s:y=b1-s
100 if d=3 then x=l:y=t2-s
110 x0=x:y0=y:x1=x+s:y1=y:c=2+(k and 1):gosub 8000:y0=y+s:y1=y0:gosub 8000
120 x1=x:y0=y:gosub 8000:x0=x+s:x1=x0:gosub 8000
130 if x<l then l=x
140 if y<t2 then t2=y
150 if x+s>r1 then r1=x+s
160 if y+s>b1 then b1=y+s
170 f=220*n(a-7*int(a/7))*(1+int(a/7)/7):w=k-3*int(k/3):gosub 8200
175 t=24:gosub 8300
180 c=a:a=b:b=b+c:d=(d+1) and 3:next:gosub 8900
190 rem the numbers, counted round a seven-note scale (mod 7)
200 data 1,1.125,1.25,1.333,1.5,1.667,1.875
''')
P['platonic'] = ('platonic solids', 'the five regular solids', r'''
10 rem the five platonic solids: every face the same, every corner the same
20 gosub 9000:print "{clr}{wht} the platonic solids":print " 4, 6, 8, 12, 20 faces"
30 dim x(19),y(19),z(19),a(19),b(19):g=(1+sqr(5))/2:sc=26:ra=.6:rb=.5
40 for s=1 to 5:read nv,el,ox,oy,c,f:for i=0 to nv-1:read x(i),y(i),z(i):next
50 for i=0 to nv-1:x=x(i):y=y(i):z=z(i):gosub 8500:a(i)=sx:b(i)=sy:next
60 for i=0 to nv-2:for j=i+1 to nv-1
70 d=(x(i)-x(j))^2+(y(i)-y(j))^2+(z(i)-z(j))^2:if abs(d-el)>.05 then 90
80 x0=a(i):y0=b(i):x1=a(j):y1=b(j):gosub 8000
90 next:next:w=s-3*int(s/3):gosub 8200:t=30:gosub 8300:next:gosub 8900
100 rem vertices, edge length squared, place, colour, note (the solids' face counts as harmonics)
110 data 4,8,70,110,1,196, 1,1,1,1,-1,-1,-1,1,-1,-1,-1,1
120 data 8,4,198,110,3,294, 1,1,1,1,1,-1,1,-1,1,1,-1,-1
125 data -1,1,1,-1,1,-1,-1,-1,1,-1,-1,-1
130 data 6,2,326,110,5,392, 1,0,0,-1,0,0,0,1,0,0,-1,0,0,0,1,0,0,-1
140 data 12,4,120,215,6,588, 0,1,1.618,0,1,-1.618,0,-1,1.618,0,-1,-1.618
150 data 1,1.618,0,1,-1.618,0,-1,1.618,0,-1,-1.618,0
155 data 1.618,0,1,1.618,0,-1,-1.618,0,1,-1.618,0,-1
160 data 20,1.528,276,215,4,980
170 data 1,1,1,1,1,-1,1,-1,1,1,-1,-1,-1,1,1,-1,1,-1,-1,-1,1,-1,-1,-1
180 data 0,.618,1.618,0,.618,-1.618,0,-.618,1.618,0,-.618,-1.618
190 data .618,1.618,0,.618,-1.618,0,-.618,1.618,0,-.618,-1.618,0
200 data 1.618,0,.618,1.618,0,-.618,-1.618,0,.618,-1.618,0,-.618
''')
P['rose'] = ('rose', 'r = cos(n/d a): see it, hear it', r'''
10 rem the rose r = cos(n/d * a): see the petals and hear them - the pen sings its distance from the centre,
20 rem two voices hold the n:d chord. keys n/m and d/e change n and d; space draws the next rose.
30 gosub 9000:n=5:d=4
40 gosub 8400:print "{clr}{wht} rose  r = cos(n/d a)"
45 print " n=";n;" d=";d;"  (keys n/m d/e space q)"
50 g=n:h=d
60 if h>0 then t1=g-h*int(g/h):g=h:h=t1:goto 60
70 n1=n/g:d1=d/g
80 k=n/d:tm=p*d1:if ((n1*d1) and 1)=0 then tm=2*p*d1
90 r=110:x1=198+r:y1=150:b0=110
100 f=b0*n1:if f>880 then f=f/2:goto 100
110 q=int(f*17.03):poke 54279,q and 255:poke 54280,q/256
115 poke 54284,0:poke 54285,160
120 f=b0*d1:if f>880 then f=f/2:goto 120
125 q=int(f*17.03):poke 54286,q and 255:poke 54287,q/256
127 poke 54291,0:poke 54292,160
130 poke 54283,17:poke 54290,17:poke 54277,0:poke 54278,240:poke 54276,17
140 sp=tm/(60*d1):for a=sp to tm+sp/2 step sp
150 q=cos(k*a):x0=x1:y0=y1:x1=198+r*q*cos(a):y1=150+r*q*sin(a)
160 c=1+int(abs(q)*4.99):if q<0 then c=c+5
170 gosub 8000:fq=(b0*2+abs(q)*b0*4)*17.03
175 poke 54272,fq and 255:poke 54273,fq/256
180 get k$:if k$<>"" then 200
190 next
200 poke 54276,16:poke 54283,16:poke 54290,16
210 get k$:if k$="" then 210
220 if k$="n" then n=n+1
230 if k$="m" and n>1 then n=n-1
240 if k$="d" then d=d+1
250 if k$="e" and d>1 then d=d-1
260 if k$="q" then poke v+32,0:poke v+5,0:print "{clr}":end
270 if k$=" " then n=n+1:if n>9 then n=1:d=d+1:if d>9 then d=1
280 goto 40
''')
OUT = 'd64'; os.makedirs(OUT, exist_ok=True); os.makedirs('src', exist_ok=True)
order = ['seed', 'egg', 'flower', 'metatron', 'vesica', 'tree', 'merkaba', 'tetra64', 'sriyantra', 'vectoreq',
         'golden', 'fibonacci', 'platonic', 'rose']
for i, key in enumerate(order, 1):
    title, sub, body = P[key]
    src = body.strip() + '\n' + LIB.strip() + '\n'
    for ln in src.splitlines():
        import re; L = len(re.sub(r'\{[a-z]+\}', 'x', ln))
        assert L <= 80 or ln.split()[1] == 'rem', (key, L, ln)
    fn = 'src/%s.bas' % key; open(fn, 'w').write(src)
    prg = 'src/%s.prg' % key
    r = subprocess.run(['petcat', '-w2', '-o', prg, '--', fn], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    name = title[:16]
    d64 = '%s/%02d %s.d64' % (OUT, i, title.title())
    if os.path.exists(d64): os.remove(d64)
    subprocess.run(['c1541', '-format', '%s,sg' % name, 'd64', d64, '-write', prg, name], capture_output=True, check=True)
    print(i, d64, os.path.getsize(prg))
