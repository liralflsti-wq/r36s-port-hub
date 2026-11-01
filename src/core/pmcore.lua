-- =============================================================================
--  Gerenciador do PortMaster: regras compartilhadas (interface e thread)
--
--  Tudo aqui vem da distribuicao OFICIAL do PortMaster (PortsMaster/PortMaster-GUI):
--   - version.json da release mais recente (o mesmo arquivo que o proprio
--     PortMaster usa para se atualizar: pylibs/pugwash/update.py) traz, por canal
--     (stable/beta/alpha), a versao, a URL do PortMaster.zip e o md5;
--   - cada release tem PortMaster.zip e PortMaster.zip.md5;
--   - a API do GitHub informa o canal no nome da release ("(stable)", "(beta)",
--     "(alpha)"), se e pre-release e o sha256 de cada arquivo.
--  Pacote escolhido: PortMaster.zip (o generico). muos.portmaster.zip,
--  trimui.portmaster.zip e retrodeck.portmaster.zip sao de outros sistemas, e os
--  Install*.PortMaster.sh sao instaladores autoextraiveis (nunca executados aqui).
-- =============================================================================
local P = {}

P.BASE_DEFAULT = "https://github.com/PortsMaster/PortMaster-GUI/releases"
P.API_DEFAULT = "https://api.github.com/repos/PortsMaster/PortMaster-GUI/releases?per_page=30"
P.ASSET = "PortMaster.zip"

--- fontes (variaveis de ambiente so para os testes do desenvolvedor)
function P.sources()
  local base = os.getenv("PORTHUB_PM_RELEASES") or P.BASE_DEFAULT
  local api = os.getenv("PORTHUB_PM_API") or P.API_DEFAULT
  return { base = base, api = api, vjson = base .. "/latest/download/version.json",
    official = base == P.BASE_DEFAULT }
end

--- URL oficial do pacote de uma versao (o unico formato aceito)
function P.asset_url(base, ver) return base .. "/download/" .. ver .. "/" .. P.ASSET end

--- versao no formato das releases: AAAA.MM.DD-HHMM (testes: AAAA-MM-DD_XX69)
function P.valid_version(v)
  return type(v) == "string" and (v:match("^%d%d%d%d%.%d%d%.%d%d%-%d%d%d%d$") ~= nil
    or v:match("^%d%d%d%d%-%d%d%-%d%d_%d%d%d%d$") ~= nil)
end

local function vparts(v)
  local t = {}
  for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end

--- -1 / 0 / 1 (nil quando alguma versao nao pode ser comparada)
function P.vcmp(a, b)
  if not (P.valid_version(a) and P.valid_version(b)) then return nil end
  local x, y = vparts(a), vparts(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p < q and -1 or 1 end
  end
  return 0
end

--- version.json: { stable = {version,url,md5}, beta = ..., alpha = ... }
--- So aceita entradas com versao valida, md5 de 32 hex e URL oficial exata.
function P.parse_vjson(text, json, base)
  local ok, d = pcall(json.decode, text or "")
  if not ok or type(d) ~= "table" then return nil, "bad_json" end
  local out, any = {}, false
  for _, ch in ipairs({ "stable", "beta", "alpha" }) do
    local e = d[ch]
    if type(e) == "table" and P.valid_version(e.version) and type(e.md5) == "string"
        and e.md5:match("^%x+$") and #e.md5 == 32 and e.url == P.asset_url(base, e.version) then
      out[ch] = { version = e.version, url = e.url, md5 = e.md5:lower(), channel = ch }
      any = true
    end
  end
  if not any then return nil, "no_channel" end
  return out
end

--- canal a partir do nome da release ("Release: 2026.10.29-1355 (alpha)")
function P.channel_of(name, body)
  local s = ((name or "") .. " " .. (body or "")):lower()
  for _, ch in ipairs({ "stable", "beta", "alpha" }) do
    if s:find("%(" .. ch .. "%)") then return ch end
  end
  return nil
end

--- lista da API de releases -> { {tag, channel, prerelease, draft, asset={size,url,sha256}} }
function P.parse_api(text, json, base)
  local ok, d = pcall(json.decode, text or "")
  if not ok or type(d) ~= "table" then return nil end
  if d.tag_name then d = { d } end
  local out = {}
  for _, r in ipairs(d) do
    if type(r) == "table" and P.valid_version(r.tag_name) then
      local e = { tag = r.tag_name, name = r.name, channel = P.channel_of(r.name, r.body),
        prerelease = r.prerelease == true, draft = r.draft == true }
      for _, a in ipairs(type(r.assets) == "table" and r.assets or {}) do
        -- somente o nome exato: nada de "qualquer arquivo com PortMaster no nome"
        if type(a) == "table" and a.name == P.ASSET and a.browser_download_url == P.asset_url(base, r.tag_name) then
          local sha = type(a.digest) == "string" and a.digest:match("^sha256:(%x+)$")
          e.asset = { size = tonumber(a.size), url = a.browser_download_url,
            sha256 = (sha and #sha == 64) and sha:lower() or nil }
        end
      end
      out[#out + 1] = e
    end
  end
  return out
end

--- release estavel mais recente na API (nunca pre-release nem rascunho)
function P.api_stable(list)
  local best
  for _, r in ipairs(list or {}) do
    if r.channel == "stable" and not r.prerelease and not r.draft and r.asset then
      if not best or (P.vcmp(r.tag, best.tag) or 0) > 0 then best = r end
    end
  end
  return best
end

function P.api_find(list, tag)
  for _, r in ipairs(list or {}) do if r.tag == tag then return r end end
end

-- ---------------------------------------------------------------------------
-- Estrutura de uma instalacao (conferida no PortMaster.zip oficial 2026.06.23-0015)
P.NAME_OF_CFW = { darkosre = "dArkOSRE", darkos = "dArkOS", arkos = "ArkOS" }

--- arquivos essenciais (relativos a pasta PortMaster)
function P.essentials(arch, os_id)
  local t = { "pugwash", "harbourmaster", "control.txt", "funcs.txt", "device_info.txt", "version",
    "gamecontrollerdb.txt", "utils/pmsplash.txt", "runtimes/love_11.5/love.txt" }
  if arch == "armhf" then
    t[#t + 1] = "gptokeyb.armhf"; t[#t + 1] = "7zzs.armhf"
  else
    t[#t + 1] = "gptokeyb"; t[#t + 1] = "7zzs.aarch64"; t[#t + 1] = "runtimes/love_11.5/love.aarch64"
  end
  local cfw = P.NAME_OF_CFW[os_id or ""]
  if cfw then t[#t + 1] = "mod_" .. cfw .. ".txt" end
  return t
end

--- precisam ser executaveis (so em sistemas de arquivos com permissoes Unix)
function P.executables(arch)
  if arch == "armhf" then return { "pugwash", "harbourmaster", "gptokeyb.armhf", "7zzs.armhf" } end
  return { "pugwash", "harbourmaster", "gptokeyb", "7zzs.aarch64", "runtimes/love_11.5/love.aarch64" }
end

--- arquivos que o proprio PortMaster altera depois de instalado (nao sao "defeito")
P.SELF_MANAGED = {
  ["PortMaster/pylibs.zip"] = true,          -- o PortMaster extrai para pylibs/ e apaga o zip
  ["PortMaster/gamecontrollerdb.txt"] = true, -- modo de controle padrao/xbox escolhido no PortMaster
}

--- o pacote serve para este console? (arquitetura e sistema)
function P.package_supports(list_set, arch, os_id)
  local need
  if arch == "armhf" then need = { "PortMaster/gptokeyb.armhf", "PortMaster/7zzs.armhf" }
  elseif arch == "aarch64" then need = { "PortMaster/gptokeyb", "PortMaster/7zzs.aarch64", "PortMaster/runtimes/love_11.5/love.aarch64" }
  else return false, "arch" end
  for _, f in ipairs(need) do if not list_set[f] then return false, "arch", f end end
  local cfw = P.NAME_OF_CFW[os_id or ""]
  if cfw and not list_set["PortMaster/mod_" .. cfw .. ".txt"] then return false, "cfw", "mod_" .. cfw .. ".txt" end
  for _, f in ipairs({ "PortMaster/pugwash", "PortMaster/harbourmaster", "PortMaster/control.txt",
      "PortMaster/version", "PortMaster/PortMaster.sh" }) do
    if not list_set[f] then return false, "structure", f end
  end
  return true
end

--- restaura o backup (B) e remove o que a operacao adicionou (N); nunca apaga outra coisa.
--- plan.tsv: tipo<TAB>origem<TAB>destino<TAB>backup
P.ROLLBACK_SH = [[
set -u
J="$1"; rc=0
while IFS='	' read -r k s d b; do
  case "$k" in
    B) if [ -f "$b" ]; then
         rm -f "$d.phnew"; cp -p "$b" "$d.phnew" && mv -f "$d.phnew" "$d" || rc=6
       else rc=7; fi ;;
    N) rm -f "$d" "$d.phnew" ;;
  esac
done < "$J/plan.tsv"
sync
exit $rc
]]

return P
