-- Leitor/escritor JSON minimo (Lua 5.1 / LuaJIT), sem dependencias.
local json = {}

---------------------------------------------------------------------------
-- decode
---------------------------------------------------------------------------
local escapes = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function utf8_char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

function json.decode(str)
  if type(str) ~= "string" then return nil, "entrada nao e texto" end
  -- remove BOM
  if str:sub(1, 3) == "\239\187\191" then str = str:sub(4) end
  local pos = 1
  local len = #str

  local function err(msg)
    error({ json_error = msg .. " (posicao " .. pos .. ")" }, 0)
  end

  local function skip()
    pos = str:find("[^ \t\r\n]", pos) or (len + 1)
  end

  local parse_value

  local function parse_string()
    pos = pos + 1 -- abre aspas
    local buf = {}
    local start = pos
    while true do
      local c = str:sub(pos, pos)
      if c == "" then err("texto nao terminado") end
      if c == '"' then
        buf[#buf + 1] = str:sub(start, pos - 1)
        pos = pos + 1
        break
      elseif c == "\\" then
        buf[#buf + 1] = str:sub(start, pos - 1)
        local e = str:sub(pos + 1, pos + 1)
        if e == "u" then
          local hex = str:sub(pos + 2, pos + 5)
          local cp = tonumber(hex, 16)
          if not cp then err("escape \\u invalido") end
          pos = pos + 6
          -- par substituto (emoji etc.)
          if cp >= 0xD800 and cp <= 0xDBFF and str:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(str:sub(pos + 2, pos + 5), 16)
            if lo and lo >= 0xDC00 and lo <= 0xDFFF then
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
              pos = pos + 6
            end
          end
          buf[#buf + 1] = utf8_char(cp)
        else
          local r = escapes[e]
          if not r then err("escape invalido") end
          buf[#buf + 1] = r
          pos = pos + 2
        end
        start = pos
      else
        pos = pos + 1
      end
    end
    return table.concat(buf)
  end

  local function parse_number()
    local s, e = str:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not s then err("numero invalido") end
    local n = tonumber(str:sub(s, e))
    if not n then err("numero invalido") end
    pos = e + 1
    return n
  end

  local function parse_array()
    pos = pos + 1
    local arr = {}
    skip()
    if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
    while true do
      arr[#arr + 1] = parse_value()
      skip()
      local c = str:sub(pos, pos)
      if c == "]" then pos = pos + 1; return arr end
      if c ~= "," then err("esperado ',' ou ']'") end
      pos = pos + 1
    end
  end

  local function parse_object()
    pos = pos + 1
    local obj = {}
    skip()
    if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
    while true do
      skip()
      if str:sub(pos, pos) ~= '"' then err("esperado nome do campo") end
      local k = parse_string()
      skip()
      if str:sub(pos, pos) ~= ":" then err("esperado ':'") end
      pos = pos + 1
      obj[k] = parse_value()
      skip()
      local c = str:sub(pos, pos)
      if c == "}" then pos = pos + 1; return obj end
      if c ~= "," then err("esperado ',' ou '}'") end
      pos = pos + 1
    end
  end

  parse_value = function()
    skip()
    local c = str:sub(pos, pos)
    if c == "{" then return parse_object()
    elseif c == "[" then return parse_array()
    elseif c == '"' then return parse_string()
    elseif c == "-" or c:match("%d") then return parse_number()
    elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    end
    err("valor inesperado")
  end

  local ok, res = pcall(function()
    local v = parse_value()
    skip()
    if pos <= len then err("conteudo extra no final") end
    return v
  end)
  if ok then return res end
  if type(res) == "table" and res.json_error then return nil, res.json_error end
  return nil, tostring(res)
end

---------------------------------------------------------------------------
-- encode
---------------------------------------------------------------------------
local function esc(s)
  return (s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    if c == "\t" then return "\\t" end
    return string.format("\\u%04x", c:byte())
  end))
end

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  return n == #t
end

local function enc(v, indent, lvl)
  local tv = type(v)
  if tv == "nil" then return "null" end
  if tv == "boolean" then return tostring(v) end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v % 1 == 0 and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.14g", v)
  end
  if tv == "string" then return '"' .. esc(v) .. '"' end
  if tv == "table" then
    local nl, pad, pad2 = "", "", ""
    if indent then
      nl = "\n"; pad = string.rep(indent, lvl + 1); pad2 = string.rep(indent, lvl)
    end
    local parts = {}
    if next(v) == nil then return "[]" end
    if is_array(v) then
      for i = 1, #v do parts[#parts + 1] = pad .. enc(v[i], indent, lvl + 1) end
      return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad2 .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = pad .. '"' .. esc(k) .. '":' .. (indent and " " or "") .. enc(v[k], indent, lvl + 1)
    end
    return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad2 .. "}"
  end
  return "null"
end

function json.encode(v, pretty)
  return enc(v, pretty and "  " or nil, 0)
end

return json
