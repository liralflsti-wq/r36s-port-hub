import struct,sys,hashlib
def parse(b):
    magic,tot,off_struct,off_str,off_rsv,ver,lcv,bcpu,size_str,size_struct=struct.unpack('>10I',b[:40])
    assert magic==0xd00dfeed, hex(magic)
    p=off_struct; path=[]; nodes={}
    def s(o):
        e=b.index(b'\0',off_str+o); return b[off_str+o:e].decode('latin1')
    while True:
        tok=struct.unpack('>I',b[p:p+4])[0]; p+=4
        if tok==1:
            e=b.index(b'\0',p); name=b[p:e].decode('latin1'); p=(e+4)&~3; path.append(name); nodes['/'.join(path) or '/']={}
        elif tok==2: path.pop()
        elif tok==3:
            ln,no=struct.unpack('>II',b[p:p+8]); p+=8; val=b[p:p+ln]; p=(p+ln+3)&~3
            nodes['/'.join(path) or '/'][s(no)]=val
        elif tok==4: continue
        elif tok==9: break
    return nodes
def txt(v):
    return [x.decode('latin1') for x in v.split(b'\0') if x]
if __name__=='__main__':
    for f in sys.argv[1:]:
        b=open(f,'rb').read()
        try: n=parse(b)
        except Exception as e: print(f,'ERR',e); continue
        root=n.get('') or n.get('/')
        print('==',f,'model=',txt(root.get('model',b'')),'compat=',txt(root.get('compatible',b'')))
        for k,v in n.items():
            if 'panel-init-sequence' in v or ('compatible' in v and any('panel' in c or 'simple-panel' in c for c in txt(v['compatible']))):
                seq=v.get('panel-init-sequence',b'')
                print('   panel',k,txt(v.get('compatible',b'')),'init_len',len(seq),'sha1',hashlib.sha1(seq).hexdigest()[:12],'head',seq[:12].hex())
            if 'compatible' in v and any(x in ''.join(txt(v['compatible'])) for x in ['joypad','adc-keys','gpio-keys']) and k.count('/')<2:
                print('   input',k,txt(v['compatible']))
