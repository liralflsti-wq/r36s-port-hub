import sys,hashlib,json,glob,struct,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from fdtparse import parse,txt
def u32(v): return struct.unpack('>I',v[:4])[0]
out=[]
for f in sorted(glob.glob('/tmp/research/a4c/boot/dArkOS/consoles/*/*.dtb')):
    try: n=parse(open(f,'rb').read())
    except Exception as e: print('ERR',f,e); continue
    root=n.get('') or n.get('/')
    rec={'dir':f.split('/consoles/')[1].split('/')[0],'file':f.split('/')[-1],'model':txt(root.get('model',b'')),'compat':txt(root.get('compatible',b''))}
    for k,v in n.items():
        if 'panel-init-sequence' in v:
            rec['panel_compat']=txt(v.get('compatible',b'')); rec['init_sha1']=hashlib.sha1(v['panel-init-sequence']).hexdigest()
        if '/display-timings/' in k and 'hactive' in v: rec['res']=f"{u32(v['hactive'])}x{u32(v['vactive'])}"
    out.append(rec)
json.dump(out,open('/tmp/research/a4c_sigs.json','w'),indent=1)
for r in out: print(r['dir'][:26].ljust(26), r['model'], r.get('res'), r.get('init_sha1','')[:10], r['compat'][:1])
