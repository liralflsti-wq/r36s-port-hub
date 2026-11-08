-- varredura de telas (somente teste): abre cada tela, desenha, registra erros
-- e textos que ficaram em portugues no idioma atual
local I = require("lib.i18n")
local S = { found = {}, errs = {} }
local PT = { "ção", "ções", "ã", "õ", "ç", "á", "é", "í", "ó", "ú", "ê", "ô", " não ", " para ", " você", " de ", " com ", " sem ", " uma ", " do ", " da ", " os ", " ao " }
local function looks_pt(s)
  local l = " " .. s:lower() .. " "
  for _, w in ipairs(PT) do if l:find(w, 1, true) then return true end end
  return false
end
S.globals = {}
function S.install(App)
  S.App = App
  local known = {}
  for k in pairs(_G) do known[k] = true end
  setmetatable(_G, {
    __index = function(_, k)
      local info = debug.getinfo(2, "Sl")
      local where = info and (info.short_src .. ":" .. tostring(info.currentline)) or "?"
      if not where:find("boot.lua") then S.globals["LEITURA " .. tostring(k) .. " @ " .. where] = true end
      return nil
    end,
    __newindex = function(t, k, v)
      local info = debug.getinfo(2, "Sl")
      S.globals["ESCRITA " .. tostring(k) .. " @ " .. (info and (info.short_src .. ":" .. tostring(info.currentline)) or "?")] = true
      rawset(t, k, v)
    end })
  local orig = I.tr
  I.tr = function(s)
    local r = orig(s)
    if I.lang ~= "pt-BR" and type(r) == "string" and #r > 2 and looks_pt(r) and not r:find("^/") and not r:find("%.%a%a%a?$") then
      local key = I.lang .. " | " .. tostring(S.cur) .. " | " .. r:gsub("\n", "\\n")
      S.found[key] = true
    end
    return r
  end
  for name, sc in pairs(App.screens) do
    if not sc.__wrapped then
      for _, fn in ipairs({ "draw", "action", "update" }) do
        local d = sc[fn]
        if d then
          sc[fn] = function(self, ...)
            local ok, e = pcall(d, self, ...)
            if not ok then S.errs[I.lang .. " | " .. fn .. " " .. name .. " | " .. tostring(e)] = true end
            return ok and e or nil
          end
        end
      end
      sc.__wrapped = true
    end
  end
end
function S.open(name, params)
  S.cur = name
  local ok, e = pcall(S.App.push, name, params)
  if not ok then S.errs[I.lang .. " | enter " .. name .. " | " .. tostring(e)] = true end
end
function S.dump(path)
  local f = io.open(path, "a")
  for k in pairs(S.errs) do f:write("ERRO   " .. k .. "\n") end
  for k in pairs(S.found) do f:write("TEXTO  " .. k .. "\n") end
  for k in pairs(S.globals) do f:write("GLOBAL " .. k .. "\n") end
  f:close()
  S.found, S.errs = {}, {}
end
return S
