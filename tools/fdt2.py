import sys,hashlib,json,glob,os,struct
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from fdtparse import parse,txt
def u32(v): return struct.unpack('>I',v[:4])[0] if v and len(v)>=4 else None
out=[]
for f in sorted(glob.glob(sys.argv[1]+'/**/rk3326-r*-linux.dtb',recursive=True)):
    n=parse(open(f,'rb').read()); root=n.get('') or n.get('/')
    rec={'file':f.split('/dtb/')[-1] if '/dtb/' in f else f,'model':txt(root.get('model',b'')),'compat':txt(root.get('compatible',b''))}
    for k,v in n.items():
        if 'panel-init-sequence' in v:
            seq=v['panel-init-sequence']; rec['panel_node']=k; rec['panel_compat']=txt(v.get('compatible',b'')); rec['init_sha1']=hashlib.sha1(seq).hexdigest(); rec['init_len']=len(seq)
        if k.endswith('display-timings') or '/display-timings/' in k:
            if 'hactive' in v: rec['res']=f"{u32(v['hactive'])}x{u32(v['vactive'])}"
        if k.count('/')==1 and 'compatible' in v and ('joypad' in ''.join(txt(v['compatible']))): rec['joypad']=txt(v['compatible'])
    out.append(rec)
json.dump(out,open(sys.argv[2],'w'),indent=1)
for r in out: print(r['file'][:48].ljust(48), r['model'], r.get('panel_compat'), r.get('res'), r.get('init_sha1','')[:10], r.get('joypad'))
