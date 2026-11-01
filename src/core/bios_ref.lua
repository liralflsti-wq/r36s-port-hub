-- =============================================================================
--  BIOS do Sistema: onde cada BIOS fica no dArkOS/dArkOSRE e como reconhece-la
--
--  Lista de sistemas, nomes e pastas: wiki do ArkOS ("ArkOS Emulators and Ports
--  information", christianhaitian), de onde o dArkOS herda a organizacao:
--  https://github.com/christianhaitian/arkos/wiki/ArkOS-Emulators-and-Ports-information
--  (consultada em 01/11/2026). Regras copiadas do texto da wiki:
--    all  = a wiki liga os arquivos com "and" (todos)
--    any  = a wiki liga com "or" (qualquer um basta)
--    list = a wiki so lista, separados por virgula (nao diz se todos sao
--           necessarios: o hub so mostra quantos existem)
--    opt  = a wiki marca como "(optional)"
--  Caminhos: relativos a pasta de BIOS; "@pasta/arquivo" = pasta de ROMs do
--  sistema (a wiki diz "NOT THE BIOS FOLDER"). Hashes: core/bios_db.lua
--  (libretro System.dat). Este arquivo roda tambem na thread (sem graficos).
-- =============================================================================
local M = {}

M.SOURCE = "https://github.com/christianhaitian/arkos/wiki/ArkOS-Emulators-and-Ports-information"

M.SYSTEMS = {
  { id = "3do", name = "3DO", rule = "any", files = { "panafz1.bin", "panafz10.bin", "panafz10-norsa.bin", "panafz10e-anvil.bin",
    "panafz10e-anvil-norsa.bin", "panafz1j.bin", "panafz1j-norsa.bin", "goldstar.bin", "sanyotry.bin", "3do_arcade_saot.bin" } },
  { id = "advision", name = "Adventure Vision", rule = "all", files = { "@advision/advision.zip" } },
  { id = "amiga", name = "Amiga", rule = "all", files = { "kick33180.A500", "kick34005.A500", "kick40068.A1200" } },
  { id = "amigacd32", name = "Amiga CD32", rule = "all", files = { "kick34005.A500", "kick40063.A600", "kick40068.A1200" } },
  { id = "vmac", name = "Apple Macintosh", rule = "all", files = { "MacII.rom" } },
  { id = "astrocde", name = "Astrocade", rule = "all", files = { "@astrocde/astrocde.zip" } },
  { id = "atari5200", name = "Atari 5200", rule = "all", files = { "5200.rom", "ATARIBAS.ROM" } },
  { id = "atari7800", name = "Atari 7800", rule = "all", files = { "7800 BIOS (U).rom" } },
  { id = "atari800", name = "Atari 800", rule = "all", files = { "ATARIOSA.ROM", "ATARIOSB.ROM", "ATARIBAS.ROM" } },
  { id = "atarilynx", name = "Atari Lynx", rule = "list", files = { "lynxboot.img" }, opt = { ["lynxboot.img"] = true } },
  { id = "atarist", name = "Atari ST", rule = "all", files = { "tos.img" } },
  { id = "atomiswave", name = "Atomiswave", rule = "all", files = { "dc/awbios.zip" } },
  { id = "cdimono1", name = "CD-i", rule = "all", files = { "same_cdi/bios/cdibios.zip", "same_cdi/bios/cdimono1.zip", "same_cdi/bios/cdimono2.zip" } },
  { id = "coleco", name = "ColecoVision (blueMSX)", rule = "all", files = { "coleco.rom" },
    md5 = { ["coleco.rom"] = "2c66f5911e5b42b8ebe113403548eee7" } },
  { id = "dragon32", name = "Dragon 32/64", rule = "any", files = { "d32.rom", "d64.rom" } },
  { id = "dreamcast", name = "Dreamcast", rule = "list", files = { "dc/dc_boot.bin", "dc/dc_flash.bin" } },
  { id = "channelf", name = "Fairchild Channel F", rule = "all", files = { "sl31253.bin", "sl31254.bin", "sl90025.bin" } },
  { id = "fds", name = "Famicom Disk System", rule = "all", files = { "disksys.rom" } },
  { id = "gb", name = "Game Boy", rule = "list", files = { "gb_bios.bin" }, opt = { ["gb_bios.bin"] = true } },
  { id = "gba", name = "Game Boy Advance", rule = "list", files = { "gba_bios.bin", "gb_bios.bin", "gbc_bios.bin", "sgb_bios.bin" },
    opt = { ["gb_bios.bin"] = true, ["gbc_bios.bin"] = true, ["sgb_bios.bin"] = true },
    note = "gba_bios.bin: obrigatória para o lr-gpsp, opcional nos outros núcleos." },
  { id = "gbc", name = "Game Boy Color", rule = "list", files = { "gbc_bios.bin" }, opt = { ["gbc_bios.bin"] = true } },
  { id = "gamegear", name = "Game Gear", rule = "list", files = { "bios.gg" }, opt = { ["bios.gg"] = true } },
  { id = "megadrive", name = "Mega Drive / Genesis", rule = "list", files = { "bios_MD.bin" }, opt = { ["bios_MD.bin"] = true } },
  { id = "intellivision", name = "Intellivision", rule = "list", files = { "exec.bin", "grom.bin" } },
  { id = "mastersystem", name = "Master System", rule = "list", files = { "bios_E.sms", "bios_U.sms", "bios_J.sms" },
    opt = { ["bios_E.sms"] = true, ["bios_U.sms"] = true, ["bios_J.sms"] = true } },
  { id = "msumd", name = "Mega Drive MSU", rule = "list", files = { "bios_md.bin", "bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin" } },
  { id = "naomi", name = "Naomi", rule = "all", files = { "dc/naomi.zip" } },
  { id = "neogeo", name = "Neo Geo", rule = "all", files = { "neogeo.zip" },
    copies = { ["neogeo.zip"] = { "@neogeo/neogeo.zip" } },
    note = "A wiki recomenda manter o neogeo.zip também na pasta de ROMs do Neo Geo." },
  { id = "neogeocd", name = "Neo Geo CD", rule = "groups",
    groups = { { "neocd/000-lo.lo", "neocd/ng-lo.rom" }, { "neocd/neocd_f.rom", "neocd/neocd.bin", "neocd/uni-bioscd.rom" } } },
  { id = "n64dd", name = "Nintendo 64DD", rule = "all", files = { "64DD_IPL.bin" } },
  { id = "nds", name = "Nintendo DS", rule = "list", files = { "nds_bios_arm7.bin", "nds_bios_arm9.bin", "nds_firmware.bin" },
    opt = { ["nds_bios_arm7.bin"] = true, ["nds_bios_arm9.bin"] = true, ["nds_firmware.bin"] = true } },
  { id = "odyssey2", name = "Odyssey 2", rule = "all", files = { "o2rom.bin" } },
  { id = "palm", name = "Palm OS", rule = "all", files = { "palmos41-en-m515.rom" } },
  { id = "pcenginecd", name = "PC Engine CD / TurboGrafx CD", rule = "all", files = { "syscard3.pce" } },
  { id = "pcfx", name = "PC-FX", rule = "all", files = { "pcfx.rom" } },
  { id = "psx", name = "PlayStation", rule = "list", files = { "psxonpsp660.bin", "scph101.bin", "scph7001.bin", "scph5501.bin", "scph1001.bin" } },
  { id = "satellaview", name = "Satellaview", rule = "all", files = { "BS-X.bin" } },
  { id = "saturn", name = "Saturn", rule = "list", files = { "saturn_bios.bin" }, opt = { ["saturn_bios.bin"] = true } },
  { id = "segacd", name = "Sega CD / Mega CD", rule = "list", files = { "bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin" } },
  { id = "x1", name = "Sharp X1", rule = "list", files = { "xmil/IPLROM.X1", "xmil/IPLROM.X1T" } },
  { id = "x68000", name = "Sharp X68000", rule = "list",
    files = { "keropi/iplrom.dat", "keropi/cgrom.dat", "keropi/iplrom30.dat", "keropi/iplromco.dat", "keropi/iplromxv.dat" },
    opt = { ["keropi/iplrom30.dat"] = true, ["keropi/iplromco.dat"] = true, ["keropi/iplromxv.dat"] = true } },
  { id = "sufami", name = "SuFami Turbo", rule = "all", files = { "STBIOS.bin" } },
  { id = "scv", name = "Super Cassette Vision", rule = "all", files = { "upd7801g.s01" },
    md5 = { ["upd7801g.s01"] = "635a978fd40db9a18ee44eff449fc126" } },
  { id = "sgb", name = "Super Game Boy", rule = "all", files = { "sgb_bios.bin" } },
  { id = "supergrafx", name = "SuperGrafx", rule = "all", files = { "syscard3.pce" } },
  { id = "ti99", name = "TI-99", rule = "all", files = { "ti-994a.ctg" } },
  { id = "coco3", name = "TRS-80 CoCo 3 (XRoar)", rule = "list", files = { "coco3.rom", "disk11.rom", "extbas11.rom", "coco3p.rom" },
    opt = { ["coco3p.rom"] = true } },
  { id = "pokemonmini", name = "Pokémon Mini", rule = "list", files = { "bios.min" }, opt = { ["bios.min"] = true } },
  { id = "vircon32", name = "Vircon32", rule = "list", files = { "Vircon32Bios.v32" }, opt = { ["Vircon32Bios.v32"] = true } },
}

-- extensoes de arquivos que acompanham pacotes e nao sao BIOS
M.DOC_EXT = { txt = true, md = true, nfo = true, pdf = true, htm = true, html = true, url = true, jpg = true, jpeg = true,
  png = true, gif = true, bmp = true, ini = false, doc = true, docx = true, rtf = true, diz = true, db = true, ds_store = true }

local function lower(s) return tostring(s or ""):lower() end
M.lower = lower

function M.basename(p) return (tostring(p):match("([^/]+)$")) or p end
function M.ext(p) return lower(M.basename(p):match("%.([^%.]+)$") or "") end

--- todos os caminhos (alvo) que a tabela conhece, sem repetir: { [lower] = {path=, systems={...}} }
function M.targets()
  if M._targets then return M._targets end
  local t = {}
  local function add(p, sys, optional)
    local k = lower(p)
    local e = t[k]
    if not e then e = { path = p, systems = {}, opt = optional }; t[k] = e end
    e.systems[#e.systems + 1] = sys.id
    if not optional then e.opt = false end
  end
  for _, s in ipairs(M.SYSTEMS) do
    for _, f in ipairs(M.files_of(s)) do
      add(f, s, s.opt and s.opt[f] or false)
      for _, c in ipairs((s.copies or {})[f] or {}) do add(c, s, s.opt and s.opt[f] or false) end
    end
  end
  M._targets = t
  return t
end

--- arquivos de um sistema (lista plana, inclui os grupos)
function M.files_of(s)
  if s.files then return s.files end
  local out = {}
  for _, g in ipairs(s.groups or {}) do for _, f in ipairs(g) do out[#out + 1] = f end end
  return out
end

--- Banco de hashes (libretro System.dat), indexado
function M.db()
  if M._db then return M._db end
  local DB = require("core.bios_db")
  local by_md5, by_name = {}, {}
  local list = DB.LIST
  -- testes no PC (sem BIOS reais): PORTHUB_BIOS_TESTDB = arquivo com linhas nome|tamanho|md5
  local tdb = os.getenv("PORTHUB_BIOS_TESTDB")
  if tdb and tdb ~= "" then
    list = {}
    for _, e in ipairs(DB.LIST) do list[#list + 1] = e end
    local f = io.open(tdb, "r")
    if f then
      for line in f:lines() do
        local n, s, m = line:match("^([^|]+)|(%d+)|(%x+)$")
        if n then list[#list + 1] = { n = n, s = tonumber(s), m = m:lower(), h = "", y = 1 } end
      end
      f:close()
    end
  end
  for _, e in ipairs(list) do
    e.system = DB.SYSTEMS[e.y]
    by_md5[e.m] = by_md5[e.m] or {}
    table.insert(by_md5[e.m], e)
    local k = lower(e.n)
    by_name[k] = by_name[k] or {}
    table.insert(by_name[k], e)
    local b = lower(M.basename(e.n))
    if b ~= k then by_name[b] = by_name[b] or {}; table.insert(by_name[b], e) end
  end
  M._db = { by_md5 = by_md5, by_name = by_name, source = DB.SOURCE }
  return M._db
end

--- md5 confirmado para um caminho (banco do libretro ou MD5 citado na wiki)?
function M.md5_known_for(path, md5)
  if not md5 then return false end
  local db = M.db()
  local k, b = lower(path), lower(M.basename(path))
  for _, key in ipairs({ k, b }) do
    for _, e in ipairs(db.by_name[key] or {}) do
      if e.m == md5 then return true end
    end
  end
  for _, s in ipairs(M.SYSTEMS) do
    for f, m in pairs(s.md5 or {}) do
      if lower(f) == k or lower(f) == b then if m == md5 then return true end end
    end
  end
  return false
end

--- tamanhos conhecidos para um nome (para dizer INCOMPATIVEL quando nenhum bate)
function M.sizes_for(path)
  local db = M.db()
  local out = {}
  for _, key in ipairs({ lower(path), lower(M.basename(path)) }) do
    for _, e in ipairs(db.by_name[key] or {}) do if e.s and e.s > 0 then out[e.s] = true end end
  end
  return next(out) and out or nil
end

--- Identifica um arquivo do pacote. Devolve { kind=, target=, sys=, verified= }
---   kind: "bios" (reconhecida), "name" (nome conhecido, hash nao confirmado),
---         "wrong" (nome conhecido, tamanho diferente de todas as versoes conhecidas),
---         "doc" (documentacao/imagem), "unknown"
function M.classify(rel, size, md5)
  local db = M.db()
  local targets = M.targets()
  local base = lower(M.basename(rel))
  -- 1) pelo hash: a BIOS e reconhecida mesmo com outro nome ou em outra pasta
  local hits = md5 and db.by_md5[md5]
  if hits then
    -- prefere o caminho que a wiki do ArkOS usa; depois o do banco (libretro)
    local pick
    for _, e in ipairs(hits) do
      if targets[lower(e.n)] then pick = targets[lower(e.n)].path; break end
    end
    if not pick then
      for _, e in ipairs(hits) do
        local tb = targets[lower(M.basename(e.n))]
        if tb then pick = tb.path; break end
      end
    end
    if not pick then
      -- nome do pacote se o banco tiver esse nome com este hash; senao o primeiro do banco
      for _, e in ipairs(hits) do if lower(M.basename(e.n)) == base then pick = e.n; break end end
      pick = pick or hits[1].n
    end
    return { kind = "bios", target = pick, verified = true, system = hits[1].system }
  end
  -- 2) pelo nome (wiki do ArkOS)
  local tgt
  for k, t in pairs(targets) do
    if k == lower(rel) or lower(M.basename(k)) == base then tgt = t.path; break end
  end
  if tgt then
    local sizes = M.sizes_for(tgt)
    if sizes and size and not sizes[size] then return { kind = "wrong", target = tgt } end
    return { kind = "name", target = tgt }
  end
  if M.DOC_EXT[M.ext(rel)] then return { kind = "doc" } end
  return { kind = "unknown" }
end

return M
