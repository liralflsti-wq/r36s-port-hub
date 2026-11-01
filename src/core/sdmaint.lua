-- =============================================================================
--  Otimizador e manutencao do microSD: coleta de dados (somente leitura).
--
--  Fontes, sempre do proprio sistema:
--   * cartao: core/sdcard.lua (/sys/block/mmcblkN, mesmo do Verificador do SD);
--   * particoes: "lsblk" quando existe; senao /proc/partitions;
--   * montagem e opcoes (ro/rw): /proc/mounts ("/dev/root" resolvido por
--     /proc/cmdline);
--   * uso: "df -Pk" de cada ponto de montagem.
--  Nada aqui grava no cartao. As operacoes demoradas ou que precisam de
--  confirmacao ficam em threads/sdmaint_thread.lua.
-- =============================================================================
local U = require("lib.util")

local M = {}

M.MOUNTS = os.getenv("PORTHUB_MOUNTS") or "/proc/mounts"
M.CMDLINE = os.getenv("PORTHUB_CMDLINE") or "/proc/cmdline"
M.PARTS = os.getenv("PORTHUB_PARTITIONS") or "/proc/partitions"

local SBIN = { "/sbin/", "/usr/sbin/", "/bin/", "/usr/bin/", "/usr/local/sbin/", "/usr/local/bin/" }

--- caminho de um programa (tambem em /sbin, que costuma ficar fora do PATH do usuario)
function M.has(tool)
  local p = U.trim(U.capture("command -v " .. U.shq(tool) .. " 2>/dev/null") or "")
  if p ~= "" then return p end
  for _, d in ipairs(SBIN) do
    if U.exec_ok("test -x " .. U.shq(d .. tool)) then return d .. tool end
  end
  return nil
end

--- ferramenta de verificacao para cada sistema de arquivos (nomes alternativos)
M.FSCK = {
  exfat = { "fsck.exfat", "exfatfsck" },
  vfat = { "fsck.vfat", "fsck.fat", "dosfsck" },
  ext4 = { "e2fsck", "fsck.ext4" }, ext3 = { "e2fsck", "fsck.ext3" }, ext2 = { "e2fsck", "fsck.ext2" },
}

function M.fsck_tool(fs)
  for _, n in ipairs(M.FSCK[fs or ""] or {}) do
    local p = M.has(n)
    if p then return p, n end
  end
  return nil, (M.FSCK[fs or ""] or {})[1]
end

--- nome para exibir do sistema de arquivos
function M.fs_label(fs)
  if not fs or fs == "" then return nil end
  local t = { vfat = "FAT (vfat)", exfat = "exFAT", ext4 = "ext4", ext3 = "ext3", ext2 = "ext2", ntfs = "NTFS",
    ntfs3 = "NTFS", btrfs = "btrfs", f2fs = "F2FS", swap = "swap", squashfs = "squashfs" }
  return t[fs] or fs
end

local function unescape(s) return (s:gsub("\\(%d%d%d)", function(o) return string.char(tonumber(o, 8)) end)) end

--- dispositivo de "/dev/root" (raiz) a partir de root= no /proc/cmdline
local function root_device()
  local cmd = U.read_file(M.CMDLINE) or ""
  local r = cmd:match("root=(%S+)")
  if r and r:match("^/dev/") then return r end
  return nil
end

--- montagens: lista { dev, mp, fs, ro }
function M.mounts()
  local t = {}
  local txt = U.read_file(M.MOUNTS) or ""
  local rootdev
  for line in txt:gmatch("[^\n]+") do
    local dev, mp, fs, opts = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    if dev then
      if dev == "/dev/root" then rootdev = rootdev or root_device(); dev = rootdev or dev end
      local ro = false
      for o in opts:gmatch("[^,]+") do if o == "ro" then ro = true end end
      t[#t + 1] = { dev = dev, mp = unescape(mp), fs = fs, ro = ro }
    end
  end
  return t
end

--- uso de um ponto de montagem (df -Pk): total, used, free (bytes)
function M.usage(mp)
  local out = U.capture("df -Pk " .. U.shq(mp) .. " 2>/dev/null") or ""
  local fsname, tot, used, avail = out:match("\n(%S+)%s+(%d+)%s+(%d+)%s+(%d+)")
  if not tot then return nil end
  return { total = tonumber(tot) * 1024, used = tonumber(used) * 1024, free = tonumber(avail) * 1024, fsname = fsname }
end

--- particoes de um cartao (ex.: "mmcblk0"). Devolve lista e a fonte usada.
function M.partitions(card)
  local parts, by = {}, {}
  local src
  if M.has("lsblk") then
    local out = U.capture("lsblk -b -P -o NAME,TYPE,SIZE,FSTYPE,LABEL /dev/" .. card .. " 2>/dev/null") or ""
    for line in out:gmatch("[^\n]+") do
      local f = {}
      for k, v in line:gmatch('([%w_%-]+)="(.-)"') do f[k] = v end
      if f.TYPE == "part" and f.NAME then
        local p = { name = f.NAME, dev = "/dev/" .. f.NAME, size = tonumber(f.SIZE),
          fs = (f.FSTYPE ~= "" and f.FSTYPE or nil), label = (f.LABEL ~= "" and f.LABEL or nil) }
        parts[#parts + 1] = p; by[p.dev] = p
      end
    end
    if #parts > 0 then src = "lsblk" end
  end
  if #parts == 0 then
    local txt = U.read_file(M.PARTS) or ""
    for line in txt:gmatch("[^\n]+") do
      local blocks, name = line:match("^%s*%d+%s+%d+%s+(%d+)%s+(%S+)")
      if name and name:match("^" .. card .. "p%d+$") then
        local p = { name = name, dev = "/dev/" .. name, size = tonumber(blocks) * 1024 }
        parts[#parts + 1] = p; by[p.dev] = p
      end
    end
    if #parts > 0 then src = "/proc/partitions" end
  end
  -- montagem e uso
  for _, m in ipairs(M.mounts()) do
    local p = by[m.dev]
    if p then
      p.mounts = p.mounts or {}
      p.mounts[#p.mounts + 1] = m.mp
      p.fs = p.fs or m.fs
      if m.fs ~= "" then p.mfs = m.fs end
      p.ro = (p.ro == nil) and m.ro or (p.ro and m.ro)
    end
  end
  for _, p in ipairs(parts) do
    if p.mounts then
      table.sort(p.mounts, function(a, b) return #a < #b end)
      p.mp = p.mounts[1]
      p.use = M.usage(p.mp)
    end
    -- exfat montado pelo driver "exfat-fuse" aparece como fuseblk
    if p.fs == "fuseblk" then p.fs = nil end
  end
  -- formato de particoes nao montadas, sem lsblk: blkid (se existir e tiver permissao)
  local blkid
  for _, p in ipairs(parts) do
    if not p.fs then
      blkid = blkid == nil and (M.has("blkid") or false) or blkid
      if blkid then
        local t = U.trim(U.capture(blkid .. " -o value -s TYPE " .. U.shq(p.dev) .. " 2>/dev/null") or "")
        if t ~= "" then p.fs = t end
      end
    end
  end
  table.sort(parts, function(a, b)
    return (tonumber(a.name:match("(%d+)$")) or 0) < (tonumber(b.name:match("(%d+)$")) or 0)
  end)
  return parts, src
end

--- resumo do cartao: soma do uso das particoes montadas
function M.summary(card_info, parts)
  local s = { total = card_info and card_info.bytes, used = 0, free = 0, counted = 0, uncounted = 0 }
  local seen = {}
  for _, p in ipairs(parts) do
    -- o mesmo sistema de arquivos (ex.: montado em dois lugares) entra uma vez so
    local key = p.use and (p.use.fsname .. ":" .. p.use.total .. ":" .. p.use.used)
    if p.use and seen[key] then
      -- ja somado
    elseif p.use then
      seen[key] = true
      s.used = s.used + p.use.used
      s.free = s.free + p.use.free
      s.counted = s.counted + 1
    else
      s.uncounted = s.uncounted + 1
    end
  end
  if s.counted == 0 then s.used, s.free = nil, nil end
  if s.used and s.free and (s.used + s.free) > 0 then s.frac = s.used / (s.used + s.free) end
  return s
end

--- o cartao suporta descarte (TRIM)? (dados do proprio kernel)
function M.discard(card)
  local base = (os.getenv("PORTHUB_BLOCK_DIR") or "/sys/block") .. "/" .. card .. "/queue/"
  local mx = tonumber(U.trim(U.read_file(base .. "discard_max_bytes") or "") or "") or 0
  local gr = tonumber(U.trim(U.read_file(base .. "discard_granularity") or "") or "") or 0
  return mx > 0, mx, gr
end

-- ultimo resultado de cada operacao nesta sessao (para o relatorio)
M.last = {}

return M
