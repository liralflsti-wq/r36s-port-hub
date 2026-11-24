-- =============================================================================
--  MascotLoader: le um modelo glTF 2.0 binario (.glb) dos mascotes
--  Suporta o que o gerador (tools/make_mascots_glb.py) produz e o basico do
--  padrao: nos com hierarquia, translation/rotation/scale, malhas de
--  triangulos com POSITION (float), COLOR_0 (float ou byte/short normalizado)
--  e NORMAL opcional (sem NORMAL calcula a normal chapada de cada face, como
--  manda o glTF). Indices (byte/short/int) tambem funcionam.
--    Loader.load(path)  -> modelo (cacheado) ou nil, erro
--    Loader.unload(path) / Loader.clear()   libera da memoria
--  Modelo: { parts = { {name, parent, t, r, s, mesh, extras, smooth}... },
--            by_name = { nome -> parte }, tris = n }
--  Cada mesh do LOVE tem VertexPosition, VertexNormal (chapada),
--  VertexSmooth (normal media, para o contorno) e VertexColor.
-- =============================================================================
local json = require("lib.json")

local Loader = {}
local cache = {}

Loader.FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexNormal", "float", 3 },
  { "VertexSmooth", "float", 3 },
  { "VertexColor", "byte", 4 },
}

local unpack_ = love.data.unpack
local SIZES = { [5120] = 1, [5121] = 1, [5122] = 2, [5123] = 2, [5125] = 4, [5126] = 4 }
local FMT = { [5120] = "b", [5121] = "B", [5122] = "h", [5123] = "H", [5125] = "I4", [5126] = "f" }
local NCOMP = { SCALAR = 1, VEC2 = 2, VEC3 = 3, VEC4 = 4 }

--- le um accessor inteiro: lista de tuplas { {a,b,c}, ... }
local function read_accessor(doc, bin, idx)
  local acc = doc.accessors[idx + 1]
  local view = doc.bufferViews[acc.bufferView + 1]
  local n = NCOMP[acc.type] or 1
  local ct = acc.componentType
  local csize = SIZES[ct]
  local stride = view.byteStride or (csize * n)
  local base = (view.byteOffset or 0) + (acc.byteOffset or 0) + 1
  local fmt = "<" .. string.rep(FMT[ct], n)
  local norm = acc.normalized and (ct == 5121 and 255 or ct == 5123 and 65535 or ct == 5120 and 127 or ct == 5122 and 32767) or nil
  local out = {}
  for i = 0, acc.count - 1 do
    local v = { unpack_(fmt, bin, base + i * stride) }
    v[n + 1] = nil -- unpack devolve a posicao seguinte no fim
    if norm then for k = 1, n do v[k] = math.max(-1, v[k] / norm) end end
    out[i + 1] = v
  end
  return out
end

local function sub(a, b) return a[1] - b[1], a[2] - b[2], a[3] - b[3] end
local function normalize(x, y, z)
  local l = math.sqrt(x * x + y * y + z * z)
  if l < 1e-9 then return 0, 1, 0 end
  return x / l, y / l, z / l
end

local function build_mesh(doc, bin, mesh)
  local verts = {}
  local tris = 0
  for _, prim in ipairs(mesh.primitives or {}) do
    if (prim.mode or 4) == 4 then
      local at = prim.attributes
      local P = read_accessor(doc, bin, at.POSITION)
      local C = at.COLOR_0 and read_accessor(doc, bin, at.COLOR_0)
      local N = at.NORMAL and read_accessor(doc, bin, at.NORMAL)
      local I
      if prim.indices then
        I = {}
        for i, v in ipairs(read_accessor(doc, bin, prim.indices)) do I[i] = v[1] + 1 end
      else
        I = {}
        for i = 1, #P do I[i] = i end
      end
      -- normal media por posicao (para o contorno nao abrir nas quinas)
      local smooth = {}
      local function key(p) return string.format("%.4f,%.4f,%.4f", p[1], p[2], p[3]) end
      local flat = {}
      for i = 1, #I - 2, 3 do
        local a, b, c = P[I[i]], P[I[i + 1]], P[I[i + 2]]
        local ux, uy, uz = sub(b, a)
        local vx, vy, vz = sub(c, a)
        local nx, ny, nz = normalize(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
        flat[i] = { nx, ny, nz }
        for k = 0, 2 do
          local s = smooth[key(P[I[i + k]])] or { 0, 0, 0 }
          s[1], s[2], s[3] = s[1] + nx, s[2] + ny, s[3] + nz
          smooth[key(P[I[i + k]])] = s
        end
      end
      for i = 1, #I - 2, 3 do
        for k = 0, 2 do
          local vi = I[i + k]
          local p = P[vi]
          local n = N and N[vi] or flat[i]
          local s = smooth[key(p)]
          local sx, sy, sz = normalize(s[1], s[2], s[3])
          local c = C and C[vi] or { 1, 1, 1, 1 }
          verts[#verts + 1] = { p[1], p[2], p[3], n[1], n[2], n[3], sx, sy, sz, c[1], c[2], c[3], c[4] or 1 }
        end
        tris = tris + 1
      end
    end
  end
  if #verts == 0 then return nil, 0 end
  return love.graphics.newMesh(Loader.FORMAT, verts, "triangles", "static"), tris
end

local function quat_to_euler(q)
  -- so para completar o padrao: o gerador nao usa rotacao nos nos
  local x, y, z, w = q[1], q[2], q[3], q[4]
  local rx = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
  local ry = math.asin(math.max(-1, math.min(1, 2 * (w * y - z * x))))
  local rz = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
  return { rx, ry, rz }
end

--- interpreta os bytes de um .glb
function Loader.parse(bytes)
  if #bytes < 20 then return nil, "arquivo curto" end
  local magic, version = unpack_("<I4I4", bytes, 1)
  if magic ~= 0x46546C67 or version ~= 2 then return nil, "nao e glb 2.0" end
  local jlen, jtype = unpack_("<I4I4", bytes, 13)
  if jtype ~= 0x4E4F534A then return nil, "sem bloco json" end
  local ok, doc = pcall(json.decode, bytes:sub(21, 20 + jlen))
  if not ok or type(doc) ~= "table" then return nil, "json invalido" end
  local bin = ""
  local boff = 21 + jlen
  if #bytes >= boff + 8 then
    local blen = unpack_("<I4", bytes, boff)
    bin = bytes:sub(boff + 8, boff + 7 + blen)
  end
  local model = { parts = {}, by_name = {}, tris = 0 }
  local meshes = {}
  local function visit(ni, parent)
    local node = doc.nodes[ni + 1]
    local part = {
      name = node.name or ("node" .. ni), parent = parent,
      t = node.translation or { 0, 0, 0 },
      r = node.rotation and quat_to_euler(node.rotation) or nil,
      s = node.scale, extras = node.extras or {},
    }
    if node.mesh then
      if meshes[node.mesh] == nil then
        local m, n = build_mesh(doc, bin, doc.meshes[node.mesh + 1])
        meshes[node.mesh] = m or false
        model.tris = model.tris + n
      end
      part.mesh = meshes[node.mesh] or nil
    end
    model.parts[#model.parts + 1] = part
    model.by_name[part.name] = part
    for _, c in ipairs(node.children or {}) do visit(c, part) end
  end
  local scene = doc.scenes and doc.scenes[(doc.scene or 0) + 1]
  for _, r in ipairs(scene and scene.nodes or {}) do visit(r, nil) end
  if #model.parts == 0 then return nil, "modelo vazio" end
  return model
end

function Loader.load(path)
  if cache[path] then return cache[path] end
  local okr, bytes = pcall(love.filesystem.read, path)
  if not okr or not bytes then return nil, "nao achei " .. tostring(path) end
  local okp, model, err = pcall(Loader.parse, bytes)
  if not okp then return nil, tostring(model) end
  if not model then return nil, err end
  cache[path] = model
  return model
end

function Loader.unload(path)
  local m = cache[path]
  if m then
    for _, p in ipairs(m.parts) do if p.mesh then pcall(p.mesh.release, p.mesh) end end
    cache[path] = nil
  end
end

function Loader.clear()
  for path in pairs(cache) do Loader.unload(path) end
end

function Loader.loaded() local n = 0; for _ in pairs(cache) do n = n + 1 end; return n end

return Loader
