# Gera src/data/console_signatures.json (base do Analisador de Console).
# Antes de rodar, na mesma pasta:
#   1) git clone --depth 1 --filter=blob:none --no-checkout https://github.com/southoz/dArkOSRE-R36 darkosre
#      e faca checkout de files/BOOT/dtb/**/rk3326-*-linux.dtb e files/BOOT/dtb/r36_devices.ini
#   2) idem para https://github.com/lcdyk0517/arkos4clone (boot/dArkOS/consoles/*/*.dtb) -> a4c
#   3) git clone --depth 1 https://github.com/AeolusUX/R36S-DTB aeolus
#   4) python3 fdt2.py / fdt3.py (extraem model, compatible, sha1 da panel-init-sequence e resolucao
#      com fdtparse.py) gerando darkosre_sigs.json, a4c_sigs.json e aeolus_sigs.json
# Nenhuma assinatura e escrita a mao: tudo sai dos arquivos DTB publicados por esses projetos.
import json,re,configparser
DK=json.load(open('darkosre_sigs.json')); A4=json.load(open('a4c_sigs.json')); AE=json.load(open('aeolus_sigs.json'))
DK_COMMIT='3f372c85aa53a26b265c3dc0c2661ec0fae5faf0'; A4_COMMIT='6db5325716d49bd7e87df0d60b5d3ccdf340424e'
import subprocess
AE_COMMIT=subprocess.check_output(['git','-C','aeolus','rev-parse','HEAD']).decode().strip()
ini={}
cur=None
for line in open('darkosre/files/BOOT/dtb/r36_devices.ini',encoding='utf-8'):
    line=line.strip()
    m=re.match(r'^\[(.+)\]$',line)
    if m: cur=m.group(1); ini[cur]={}; continue
    if cur and '=' in line and not line.startswith(';'):
        k,v=[x.strip() for x in line.split('=',1)]; ini[cur][k]=v
SRC_DK={'name':'dArkOSRE-R36 (southoz)','url':'https://github.com/southoz/dArkOSRE-R36','commit':DK_COMMIT}
SRC_A4={'name':'ArkOS4Clone (lcdyk0517)','url':'https://github.com/lcdyk0517/arkos4clone','commit':A4_COMMIT}
SRC_AE={'name':'R36S-DTB (AeolusUX)','url':'https://github.com/AeolusUX/R36S-DTB','commit':AE_COMMIT}
def board_kind(model, variant):
    if variant=='clone': return 'clone'
    if variant=='soysauce': return 'variant'
    if model.startswith('R36S-V') or model.startswith('R36S-Y'): return 'r36s'
    return 'other'
def board_name(model, kind):
    if kind=='r36s': return 'R36S'
    if kind=='clone': return 'Clone de R36S'
    if kind=='variant': return 'R36S Soy Sauce (Y3506)'
    for pre,n in [('HL-R36H','R36H'),('R35S','R35S'),('R36S Plus','R36S Plus'),('R36XX','R36XX'),('RG36S','RG36S')]:
        if model.startswith(pre): return n
    return model
boards=[]
seen=set()
for r in DK:
    m=r['model'][0]
    if m in seen: continue
    seen.add(m)
    v=ini.get(m,{}).get('variant')
    if v is None:
        # nomes com caixa diferente no ini (ex.: Y3506_v03)
        for k in ini:
            if k.lower()==m.lower(): v=ini[k]['variant']
    k=board_kind(m,v)
    res=ini.get(m,{}).get('resolution') or r.get('res')
    boards.append({'match':{'model':m},'kind':k,'name':board_name(m,k),'board':m,'resolution':res,'panel_sha1':r.get('init_sha1'),
       'panel_compat':r.get('panel_compat'),'source':dict(SRC_DK,file='files/BOOT/dtb/'+r['file']),'source_class':'dArkOSRE: '+str(v),'reliability':'alta'})
for m,d in ini.items():
    if m not in seen and m.lower() not in {x.lower() for x in seen}:
        k=board_kind(m,d.get('variant'))
        boards.append({'match':{'model':m},'kind':k,'name':board_name(m,k),'board':m,'resolution':d.get('resolution'),'panel_sha1':None,
          'source':dict(SRC_DK,file='files/BOOT/dtb/r36_devices.ini'),'source_class':'dArkOSRE: '+str(d.get('variant')),'reliability':'media'})
# ArkOS4Clone: modelo + compatible
for r in A4:
    m=r['model'][0].strip(); c=r['compat'][0] if r['compat'] else ''
    if 'R36S Clone' in m: k,n='clone','Clone de R36S ('+m.replace('R36S Clone ','')+')'
    elif 'Soy Sauce' in m: k,n='variant','R36S Soy Sauce'
    elif m=='GameConsole R36S': k,n='r36s','R36S'
    else: k,n='other',m.replace('GameConsole ','')
    boards.append({'match':{'model':m,'compatible':c},'kind':k,'name':n,'board':m+' ('+r['dir']+')','resolution':r.get('res'),'panel_sha1':r.get('init_sha1'),
      'panel_compat':r.get('panel_compat'),'source':dict(SRC_A4,file='boot/dArkOS/consoles/'+r['dir']+'/'+r['file']),'source_class':'ArkOS4Clone: '+r['dir'],'reliability':'alta'})
# paineis: hash -> rotulos de todas as fontes
panels={}
def addp(h,label,kind,src):
    if not h: return
    panels.setdefault(h,[]).append({'label':label,'kind':kind,'source':src})
for b in boards:
    addp(b.get('panel_sha1'),b['board'],b['kind'],b['source']['name'])
for r in AE:
    f=r['file']
    if 'rk3326-r35s-linux' in f and '/R36S/' in f:
        p=f.split('/R36S/')[1].split('/')[0]
        addp(r.get('init_sha1'),'R36S '+p,'r36s',SRC_AE['name'])
json.dump({'version':1,'generated':'2026-10-31',
  'note':'Assinaturas extraidas dos arquivos DTB publicos de cada projeto (modelo, compatible, sha1 de panel-init-sequence, resolucao). Gerado por tools/mkconsoledb.py.',
  'sources':[SRC_DK,SRC_A4,SRC_AE,{'name':'ROCKNIX Wiki - Game Console R35S/R36S','url':'https://rocknix.org/devices/unbranded/game-console-r35s-r36s/'}],
  'reference':{'name':'R36S','soc':'rk3326','cores':4,'cpu':'Cortex-A35','ram_mb':1024,'resolution':'640x480','emmc':False,
     'source':'ROCKNIX Wiki: RK3326, Cortex-A35 quad-core, Mali G31, 3.5" 640x480, 1 GB DDR3, sem eMMC'},
  'boards':boards,'panels':panels},open('console_signatures.json','w'),ensure_ascii=False,separators=(',',':'))
from collections import Counter
print(len(boards),Counter(b['kind'] for b in boards),len(panels))
for h,l in panels.items(): print(h[:10],sorted(set(x['kind'] for x in l)),len(l))
