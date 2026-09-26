"""Marketing frames for App Store Connect (AI Camera - Music Reader).
Illustrative frames built from the repo's own LilyPond fixtures (fixtures/*/input.png).
Usage: python3 docs/asc/screenshots/make_screenshots.py   (needs Pillow and the Inter font path below)
Outputs: iphone-69-0N-*.png (1320x2868) and ipad-13-0N-*.png (2064x2752), RGB, no alpha."""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps
_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
REPO = sys.argv[1] if len(sys.argv) > 1 else _ROOT
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, 'docs', 'asc', 'screenshots')
os.makedirs(OUT, exist_ok=True)
INTER = '/usr/share/fonts/truetype/sand-box/google/Inter/Inter-VariableFont_opsz,wght.ttf'
def font(sz, w='Bold'):
    f = ImageFont.truetype(INTER, int(sz))
    try: f.set_variation_by_name(w)
    except Exception: pass
    return f
TOP=(58,44,140); BOT=(14,18,48); AMBER=(255,196,72); WHITE=(246,246,250); INK=(20,22,40); MUTED=(186,184,220)

def bg(W,H):
    g=Image.linear_gradient('L').resize((W,H))
    return Image.composite(Image.new('RGB',(W,H),BOT),Image.new('RGB',(W,H),TOP),g)

def crop_score(name):
    i=Image.open(f'{REPO}/fixtures/{name}/input.png').convert('L')
    bb=Image.eval(i,lambda v:255-v).getbbox()
    return i.crop(bb)

def text_center(d, cx, y, s, f, fill):
    w=d.textlength(s,font=f); d.text((cx-w/2,y),s,font=f,fill=fill)

def device(W,H,kind):
    """Return (frame image RGBA, screen box) for a simple device mock."""
    fr=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(fr)
    r=int(W*(0.16 if kind=='phone' else 0.06)); bez=int(W*(0.035 if kind=='phone' else 0.03))
    d.rounded_rectangle([0,0,W-1,H-1],radius=r,fill=(8,8,14,255))
    d.rounded_rectangle([3,3,W-4,H-4],radius=r,outline=(70,70,90,255),width=4)
    box=(bez,bez,W-bez,H-bez)
    return fr, box, r-bez

def screen_camera(sw,sh,kind):
    s=Image.new('RGB',(sw,sh),(28,28,30))
    photo=Image.open(f'{REPO}/fixtures/camera.deskew/input.png').convert('RGB')
    ph=int(sh*0.78); area=Image.new('RGB',(sw,ph),(238,238,238))
    # crop around the staff (source coords) and scale to the screen width
    src=photo.crop((250,250,880,600)); k=(sw*0.98)/src.width
    src=src.resize((int(src.width*k),int(src.height*k)),Image.LANCZOS)
    area.paste(src,((sw-src.width)//2,(ph-src.height)//2))
    s.paste(area,(0,int(sh*0.08)))
    d=ImageDraw.Draw(s)
    cx,cy=sw//2,int(sh*0.08)+ph//2
    bw,bh=int(src.width*0.96),int(src.height*0.9); t=max(6,sw//90); L=sw//9
    x0,y0,x1,y1=cx-bw//2,cy-bh//2,cx+bw//2,cy+bh//2
    for (x,y,dx,dy) in [(x0,y0,1,1),(x1,y0,-1,1),(x0,y1,1,-1),(x1,y1,-1,-1)]:
        d.rectangle([min(x,x+dx*L),min(y,y+dy*t),max(x,x+dx*L),max(y,y+dy*t)],fill=AMBER)
        d.rectangle([min(x,x+dx*t),min(y,y+dy*L),max(x,x+dx*t),max(y,y+dy*L)],fill=AMBER)
    f=font(sw*0.04,'SemiBold')
    chip='Frame the staff'; w=d.textlength(chip,font=f)
    d.rounded_rectangle([cx-w/2-sw*0.04,y0-f.size*2.6,cx+w/2+sw*0.04,y0-f.size*0.6],radius=f.size,fill=(0,0,0))
    text_center(d,cx,y0-f.size*2.25,chip,f,WHITE)
    # shutter
    R=int(sw*0.09 if kind=='phone' else sw*0.055); by=int(sh*0.93)
    d.ellipse([cx-R,by-R,cx+R,by+R],outline=WHITE,width=max(6,R//8))
    d.ellipse([cx-R+R//5,by-R+R//5,cx+R-R//5,by+R-R//5],fill=WHITE)
    return s

def notes_csv(name):
    rows=[l.strip().split(',') for l in open(f'{REPO}/fixtures/{name}/expected.notes.csv').read().splitlines()[1:] if l.strip()]
    return [tuple(int(x) for x in r) for r in rows]

def score_screen(sw,sh,kind,title,highlight=False,transport=False,chip=None):
    s=Image.new('RGB',(sw,sh),(250,249,246)); d=ImageDraw.Draw(s)
    pad=int(sw*0.06); ph=kind=='phone'
    d.text((pad,int(sh*0.07)),title,font=font(sw*0.065 if ph else sw*0.045,'Bold'),fill=INK)
    sc=crop_score('piano.grand').convert('RGB').crop((0,0,500,220))   # bars 1-2 (barline at x~497)
    tw=sw-2*pad; k=tw/sc.width; th=int(sc.height*k); sc=sc.resize((tw,th),Image.LANCZOS)
    y=int(sh*0.15)
    s.paste(sc,(pad,y))
    if highlight:
        # playhead on beat 3 of bar 1: the G noteheads (crop x 227..242)
        ov=Image.new('RGBA',(sw,sh),(0,0,0,0)); od=ImageDraw.Draw(ov)
        od.rounded_rectangle([pad+int(219*k),y-int(6*k),pad+int(250*k),y+th+int(6*k)],radius=int(8*k),fill=AMBER+(110,))
        s=Image.alpha_composite(s.convert('RGBA'),ov).convert('RGB'); d=ImageDraw.Draw(s)
    y2=y+th+int(sh*0.04)
    f=font(sw*0.036 if ph else sw*0.025,'SemiBold'); fm=font(sw*0.034 if ph else sw*0.024,'Medium')
    if not transport:
        rows=[('Staves','2 (treble + bass)'),('Key','C major'),('Time','4/4'),('Notes','16 per staff')]
        rh=int(fm.size*2.6)
        d.rounded_rectangle([pad,y2,sw-pad,y2+rh*len(rows)+int(fm.size*0.8)],radius=fm.size,fill=(255,255,255),outline=(226,224,236),width=3)
        yy=y2+int(fm.size*0.8)
        for kk,v in rows:
            d.text((pad+fm.size,yy),kk,font=fm,fill=(110,108,140))
            w=d.textlength(v,font=fm); d.text((sw-pad-fm.size-w,yy),v,font=fm,fill=INK); yy+=rh
        y3=y2+rh*len(rows)+int(fm.size*2.2)
        if chip:
            w=d.textlength(chip,font=f)
            d.rounded_rectangle([pad,y3,pad+w+sw*0.08,y3+f.size*2.1],radius=f.size,fill=(232,228,252))
            d.text((pad+sw*0.04,y3+f.size*0.5),chip,font=f,fill=(58,44,140))
        return s
    # piano roll of bars 1-2 from fixtures/piano.grand/expected.notes.csv
    notes=[n for n in notes_csv('piano.grand') if n[0]<3840]
    top_y=y2; bh=int(sh*0.13); rb=sh-bh-int(sh*0.03)
    lo,hi=min(n[1] for n in notes)-2,max(n[1] for n in notes)+2
    d.rounded_rectangle([pad,top_y,sw-pad,rb],radius=fm.size,fill=(28,26,64))
    ix0,ix1=pad+int(sw*0.04),sw-pad-int(sw*0.04); iy0,iy1=top_y+int(sh*0.03),rb-int(sh*0.03)
    for p in range(lo,hi+1):
        yy=iy1-(p-lo)*(iy1-iy0)/(hi-lo+1)
        if p%12 in (1,3,6,8,10): d.rectangle([ix0,yy-(iy1-iy0)/(hi-lo+1),ix1,yy],fill=(34,32,74))
    for bar in range(3):
        x=ix0+bar*(ix1-ix0)/2; d.line([x,iy0,x,iy1],fill=(70,66,120),width=3)
    ph_tick=960
    for t,p,du,st in notes:
        x0=ix0+t*(ix1-ix0)/3840; x1=ix0+(t+du)*(ix1-ix0)/3840-6
        yy=iy1-(p-lo+1)*(iy1-iy0)/(hi-lo+1); hgt=(iy1-iy0)/(hi-lo+1)
        on=t<=ph_tick<t+du
        d.rounded_rectangle([x0,yy,x1,yy+max(hgt,8)],radius=6,fill=AMBER if on else ((150,140,255) if st==0 else (110,190,240)))
    px=ix0+(ph_tick+240)*(ix1-ix0)/3840; d.line([px,iy0-10,px,iy1+10],fill=WHITE,width=4)
    by=sh-bh
    d.rectangle([0,by,sw,sh],fill=(24,22,58))
    cx=sw//2; cy=by+bh//2+int(sh*0.005); R=int(bh*0.28)
    d.ellipse([cx-R,cy-R,cx+R,cy+R],fill=AMBER)
    d.rectangle([cx-R*0.35,cy-R*0.4,cx-R*0.12,cy+R*0.4],fill=INK); d.rectangle([cx+R*0.12,cy-R*0.4,cx+R*0.35,cy+R*0.4],fill=INK)
    py=by+int(bh*0.12); d.rounded_rectangle([pad,py,sw-pad,py+8],radius=4,fill=(80,76,130)); d.rounded_rectangle([pad,py,pad+int((sw-2*pad)*0.16),py+8],radius=4,fill=AMBER)
    d.text((pad,cy-fm.size//2),'Tempo 96',font=fm,fill=MUTED)
    w=d.textlength('Piano',font=fm); d.text((sw-pad-w,cy-fm.size//2),'Piano',font=fm,fill=MUTED)
    return s

def privacy_screen(sw,sh,kind):
    s=Image.new('RGB',(sw,sh),(250,249,246)); d=ImageDraw.Draw(s); pad=int(sw*0.08)
    big=font(sw*0.06 if kind=='phone' else sw*0.042,'Bold'); f=font(sw*0.042 if kind=='phone' else sw*0.03,'Medium')
    d.text((pad,int(sh*0.08)),'On this device',font=big,fill=INK)
    rows=[('Recognition','Runs on-device'),('Photos','Stay on your device'),('Account','Not required'),('Network','Not needed to read or play')]
    y=int(sh*0.18); rh=int(f.size*3.2)
    for k,v in rows:
        d.rounded_rectangle([pad,y,sw-pad,y+rh-int(f.size*0.6)],radius=f.size,fill=(255,255,255),outline=(226,224,236),width=3)
        d.text((pad+f.size,y+f.size*0.75),k,font=f,fill=INK)
        w=d.textlength(v,font=f); d.text((sw-pad-f.size-w,y+f.size*0.75),v,font=f,fill=(58,44,140))
        y+=rh
    ic=Image.open(f'{REPO}/docs/asc/creatives/AppIcon-1024.png').convert('RGB'); isz=int(sw*0.3)
    ic=ic.resize((isz,isz),Image.LANCZOS); m=Image.new('L',(isz,isz),0); ImageDraw.Draw(m).rounded_rectangle([0,0,isz-1,isz-1],radius=int(isz*0.22),fill=255)
    s.paste(ic,((sw-isz)//2,y+int(sh*0.05)),m)
    return s

FRAMES=[
 ('01-capture','Point at the page','Photograph printed sheet music', lambda sw,sh,k: screen_camera(sw,sh,k)),
 ('02-read','Reads the notes','Clefs, keys, rhythms and rests', lambda sw,sh,k: score_screen(sw,sh,k,'Recognized score',chip='Read on this device')),
 ('03-play','Hear it played','MIDI playback with note highlights', lambda sw,sh,k: score_screen(sw,sh,k,'Now playing',highlight=True,transport=True)),
 ('04-private','Private by design','No account. No uploads.', lambda sw,sh,k: privacy_screen(sw,sh,k)),
]

def render(kind,W,H,prefix):
    for slug,head,sub,fn in FRAMES:
        img=bg(W,H); d=ImageDraw.Draw(img)
        hf=font(W*(0.085 if kind=='phone' else 0.062),'ExtraBold'); sf=font(W*(0.042 if kind=='phone' else 0.032),'Medium')
        ty=int(H*0.055)
        text_center(d,W/2,ty,head,hf,WHITE)
        text_center(d,W/2,ty+hf.size*1.25,sub,sf,AMBER)
        dw=int(W*(0.80 if kind=='phone' else 0.78)); dh=int(dw*(2868/1320) if kind=='phone' else dw*(2752/2064))
        dy=ty+int(hf.size*1.25+sf.size*2.2)
        if dy+dh>H+int(H*0.08): dh=H-dy+int(H*0.08)
        fr,box,sr=device(dw,dh,kind)
        sw,sh=box[2]-box[0],box[3]-box[1]
        scr=fn(sw,sh,kind)
        m=Image.new('L',(sw,sh),0); ImageDraw.Draw(m).rounded_rectangle([0,0,sw-1,sh-1],radius=sr,fill=255)
        fr.paste(scr,(box[0],box[1]),m)
        # shadow
        sh_=Image.new('L',(W,H),0); ImageDraw.Draw(sh_).rounded_rectangle([(W-dw)//2+10,dy+30,(W+dw)//2+10,dy+dh+30],radius=int(dw*0.12),fill=140)
        img=Image.composite(Image.new('RGB',(W,H),(4,4,12)),img,sh_.filter(ImageFilter.GaussianBlur(40)))
        img.paste(fr,((W-dw)//2,dy),fr)
        out=f'{OUT}/{prefix}-{slug}.png'; img.convert('RGB').save(out,optimize=True); print(out,img.size)

render('phone',1320,2868,'iphone-69')
render('pad',2064,2752,'ipad-13')
