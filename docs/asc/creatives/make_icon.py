from PIL import Image, ImageDraw, ImageFilter
S=4096; W=S
img=Image.new('RGB',(S,S))
# vertical gradient indigo -> deep navy
top=(58,44,140); bot=(14,18,48)
px=img.load()
g=Image.linear_gradient('L').resize((S,S))
img=Image.composite(Image.new('RGB',(S,S),bot),Image.new('RGB',(S,S),top),g)
d=ImageDraw.Draw(img)
u=S/1024
# viewfinder corner brackets (amber)
amber=(255,196,72); t=int(34*u); L=int(170*u); m=int(150*u)
for (x,y,dx,dy) in [(m,m,1,1),(S-m,m,-1,1),(m,S-m,1,-1),(S-m,S-m,-1,-1)]:
    d.rounded_rectangle([min(x,x+dx*L),min(y,y+dy*t)-0,max(x,x+dx*L),max(y,y+dy*t)],radius=t//2,fill=amber)
    d.rounded_rectangle([min(x,x+dx*t),min(y,y+dy*L),max(x,x+dx*t),max(y,y+dy*L)],radius=t//2,fill=amber)
# staff lines (white)
white=(245,245,250); lw=int(14*u); gap=int(62*u); y0=int(360*u); x0=int(250*u); x1=S-int(250*u)
for i in range(5):
    y=y0+i*gap; d.rounded_rectangle([x0,y-lw//2,x1,y+lw//2],radius=lw//2,fill=white)
# beamed eighth-note pair
def head(cx,cy):
    r=int(52*u); hh=Image.new('L',(4*r,4*r),0); hd=ImageDraw.Draw(hh)
    hd.ellipse([r*0.6,r*1.2,r*3.4,r*2.8],fill=255)
    hh=hh.rotate(22,resample=Image.BICUBIC)
    img.paste(white,(int(cx-2*r),int(cy-2*r)),hh)
    return r
n1=(int(420*u), y0+4*gap); n2=(int(640*u), y0+3*gap)
r=head(*n1); head(*n2)
sw=int(20*u); stem_top=int(250*u)
sx1=n1[0]+int(1.25*r); sx2=n2[0]+int(1.25*r)
d.rectangle([sx1-sw,stem_top+int(40*u),sx1,n1[1]-int(10*u)],fill=white)
d.rectangle([sx2-sw,stem_top,sx2,n2[1]-int(10*u)],fill=white)
bw=int(46*u)
d.polygon([(sx1-sw,stem_top+int(40*u)),(sx2,stem_top),(sx2,stem_top+bw),(sx1-sw,stem_top+int(40*u)+bw)],fill=white)
# playback highlight: amber glow under second note + small play triangle bottom
glow=Image.new('L',(S,S),0); ImageDraw.Draw(glow).ellipse([n2[0]-int(95*u),n2[1]-int(80*u),n2[0]+int(95*u),n2[1]+int(80*u)],fill=150)
glow=glow.filter(ImageFilter.GaussianBlur(int(30*u)))
img=Image.composite(Image.new('RGB',(S,S),amber),img,glow)
d=ImageDraw.Draw(img); head(*n2)
# play button
cx,cy,R=S//2,int(790*u),int(92*u)
d.ellipse([cx-R,cy-R,cx+R,cy+R],fill=amber)
tri=[(cx-int(30*u),cy-int(46*u)),(cx-int(30*u),cy+int(46*u)),(cx+int(50*u),cy)]
d.polygon(tri,fill=(20,22,56))
img.resize((1024,1024),Image.LANCZOS).save('AppIcon-1024.png')
