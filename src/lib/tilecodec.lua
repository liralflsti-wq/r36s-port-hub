-- =============================================================================
--  Codificador de quadros por blocos (transmissao e gravacao da tela do hub)
--
--  A imagem (RGBA 8 bits) e dividida em blocos de 32x32. So os blocos que
--  mudaram desde o quadro anterior vao para a saida, em RGB:
--     u16 (little-endian) quantidade de blocos
--     para cada bloco: u8 coluna, u8 linha, 32*32*3 bytes RGB
--  A saida e comprimida depois (zlib) por quem chamar.
--  Usa LuaJIT FFI: funciona na thread principal e nas threads do LOVE.
-- =============================================================================
local ffi = require("ffi")
local bit = require("bit")

pcall(ffi.cdef, "int memcmp(const void *a, const void *b, size_t n);")

local M = {}
M.__index = M
M.TS = 32

--- novo codificador para imagens w x h (multiplos de 32)
function M.new(w, h)
  local ts = M.TS
  local o = setmetatable({ w = w, h = h, tw = math.floor(w / ts), th = math.floor(h / ts), has = false }, M)
  o.prev = ffi.new("uint8_t[?]", w * h * 4)
  o.out = ffi.new("uint8_t[?]", 2 + o.tw * o.th * (2 + ts * ts * 3))
  return o
end

-- copia os blocos marcados de src para a saida (RGB)
local function emit(self, src, list, n)
  local out, ts, stride = self.out, M.TS, self.w * 4
  local pos = 2
  for i = 1, n do
    local tx, ty = list[i * 2 - 1], list[i * 2]
    out[pos], out[pos + 1] = tx, ty
    pos = pos + 2
    local base = ty * ts * stride + tx * ts * 4
    for r = 0, ts - 1 do
      local o = base + r * stride
      for c = 0, ts - 1 do
        local s = o + c * 4
        out[pos], out[pos + 1], out[pos + 2] = src[s], src[s + 1], src[s + 2]
        pos = pos + 3
      end
    end
  end
  out[0], out[1] = bit.band(n, 255), bit.rshift(n, 8)
  return ffi.string(out, pos)
end

--- compara `cur` (ponteiro uint8_t* RGBA) com o quadro anterior.
--- Devolve a carga (string) e o numero de blocos, ou nil, 0 se nada mudou.
--- `quiet` = so atualiza o quadro de referencia (sem montar a saida).
function M:diff(cur, quiet)
  local ts, stride, prev = M.TS, self.w * 4, self.prev
  local list, n = {}, 0
  local full = not self.has
  for ty = 0, self.th - 1 do
    for tx = 0, self.tw - 1 do
      local base = ty * ts * stride + tx * ts * 4
      local changed = full
      if not changed then
        for r = 0, ts - 1 do
          local o = base + r * stride
          if ffi.C.memcmp(cur + o, prev + o, ts * 4) ~= 0 then changed = true; break end
        end
      end
      if changed then
        for r = 0, ts - 1 do
          local o = base + r * stride
          ffi.copy(prev + o, cur + o, ts * 4)
        end
        n = n + 1
        list[n * 2 - 1], list[n * 2] = tx, ty
      end
    end
  end
  self.has = true
  if n == 0 or quiet then return nil, n end
  return emit(self, prev, list, n), n
end

--- quadro completo (todos os blocos) a partir da referencia atual
function M:keyframe()
  if not self.has then return nil end
  local list, n = {}, 0
  for ty = 0, self.th - 1 do
    for tx = 0, self.tw - 1 do
      n = n + 1
      list[n * 2 - 1], list[n * 2] = tx, ty
    end
  end
  return emit(self, self.prev, list, n)
end

--- ponteiro para os pixels de um ImageData (FFI quando disponivel)
function M.pixels(img)
  if img.getFFIPointer then
    local p = img:getFFIPointer()
    if p ~= nil then return ffi.cast("uint8_t*", p), nil end
  end
  local s = img:getString()
  return ffi.cast("const uint8_t*", s), s  -- a string precisa continuar viva enquanto o ponteiro e usado
end

return M
