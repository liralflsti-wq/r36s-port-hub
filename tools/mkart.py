from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random, math, sys
import os
R=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F=R+'/src/assets/fonts/'
logo=Image.open(R+'/port/r36sporthub/logo.png').convert('RGBA')
PINK=(255,79,139); CYAN=(56,214,255); YEL=(255,212,71)

def background(W,H,seed=3):
    im=Image.new('RGB',(W,H))
    d=ImageDraw.Draw(im)
    hz=int(H*0.64)
    for y in range(H):
        t=y/H
        if y<hz:
            c=(int(10+30*t),int(8+10*t),int(28+50*t))
        else:
            c=(14,10,34)
        d.line([(0,y),(W,y)],fill=c)
    # estrelas
    rnd=random.Random(seed)
    for _ in range(int(W*H/2600)):
        x,y=rnd.randrange(W),rnd.randrange(int(hz*0.95))
        b=rnd.randint(90,230); s=rnd.choice([1,1,1,2])
        d.rectangle([x,y,x+s-1,y+s-1],fill=(b,b,min(255,b+20)))
    # sol retro listrado
    sun=Image.new('RGBA',(W,H),(0,0,0,0)); sd=ImageDraw.Draw(sun)
    r=int(H*0.20); cx=W//2; cy=hz
    for yy in range(cy-r,cy):
        t=(yy-(cy-r))/r
        col=(255,int(212-150*t),int(71+70*t),255)
        dx=int(math.sqrt(max(0,r*r-(yy-cy)**2)))
        band=(yy-(cy-r))
        if t>0.45 and (band//max(2,int(r*0.05)))%2==1: continue
        sd.line([(cx-dx,yy),(cx+dx,yy)],fill=col)
    glow=sun.filter(ImageFilter.GaussianBlur(r*0.25))
    im.paste(glow,(0,0),glow); im.paste(sun,(0,0),sun)
    # grade em perspectiva
    g=Image.new('RGBA',(W,H),(0,0,0,0)); gd=ImageDraw.Draw(g)
    for i in range(1,22):
        t=(i/21)**2.2
        y=int(hz+(H-hz)*t)
        gd.line([(0,y),(W,y)],fill=PINK+(int(90+140*t),),width=max(1,int(1+2*t)))
    for i in range(-24,25):
        x0=cx+i*(W/40); x1=cx+i*(W/40)*9
        gd.line([(x0,hz),(x1,H+H)],fill=PINK+(170,),width=max(1,W//640))
    gb=g.filter(ImageFilter.GaussianBlur(max(2,W//320)))
    im.paste(gb,(0,0),gb); im.paste(g,(0,0),g)
    d=ImageDraw.Draw(im)
    d.line([(0,hz),(W,hz)],fill=CYAN,width=max(2,W//400))
    return im,hz

def paste_logo(im,cx,top,width):
    s=width/logo.width
    L=logo.resize((int(logo.width*s),int(logo.height*s)),Image.NEAREST)
    sh=Image.new('RGBA',L.size,(0,0,0,0)); sh.putalpha(L.split()[3].point(lambda a:int(a*0.7)))
    blk=Image.new('RGBA',L.size,(0,0,0,255)); blk.putalpha(sh.split()[3])
    blk=blk.filter(ImageFilter.GaussianBlur(6))
    x=int(cx-L.width/2)
    im.paste(blk,(x+6,top+10),blk); im.paste(L,(x,top),L)
    return top+L.height

def ctext(d,y,txt,font,fill,W,shadow=True):
    w=d.textlength(txt,font=font)
    if shadow: d.text(((W-w)/2+2,y+2),txt,font=font,fill=(0,0,0))
    d.text(((W-w)/2,y),txt,font=font,fill=fill)

def cover(W,H,out,tag=True,logo_on=True):
    im,hz=background(W,H)
    if logo_on:
        paste_logo(im,W//2,int(H*0.05),int(W*0.56))
    if tag:
        strip=Image.new('RGBA',(W,int(H*0.25)),(8,6,20,190))
        im.paste(strip,(0,int(H*0.75)),strip)
        d=ImageDraw.Draw(im)
        d.line([(0,int(H*0.75)),(W,int(H*0.75))],fill=PINK,width=2)
        f=ImageFont.truetype(F+'PressStart2P-Regular.ttf',max(8,int(W/42)))
        ctext(d,int(H*0.785),'PORTS, FERRAMENTAS E MAIS PARA O R36S',f,CYAN,W)
        f2=ImageFont.truetype(F+'ChakraPetch-SemiBold.ttf',max(10,int(W/34)))
        ctext(d,int(H*0.85),'Downloads  •  FTP  •  Wi-Fi  •  Temas  •  Diagnósticos',f2,(235,235,245),W)
        fv=ImageFont.truetype(F+'PressStart2P-Regular.ttf',max(7,int(W/80)))
        ctext(d,int(H*0.935),'0.4 BETA',fv,YEL,W)
    im.save(out)

cover(640,480,sys.argv[1]+'/cover.png')
cover(1280,720,sys.argv[1]+'/fanart.png',tag=False,logo_on=False)
