-- =============================================================================
--  Renderizador 3D do assistente (LOVE 11.5, OpenGL ES 2 no R36S)
--  Desenha o modelo numa tela pequena (canvas) com buffer de profundidade e
--  um shader proprio: luz difusa + luz do ceu/chao + brilho de borda, cor
--  escolhida pelo jogador nas pecas "tint", pecas que brilham ("emissive")
--  e contorno de desenho animado (casca invertida, so na qualidade alta).
--    R.available()                    o aparelho aguenta? (testa uma vez)
--    R.draw(model, pose, o)           desenha no canvas atual (com depth)
--    R.render(key, w, h, ss, fn)      prepara/reusa um canvas e devolve-o
--  Matrizes 4x4 em linha (row-major), enviadas com shader:send(..., "row").
-- =============================================================================
local lg = love.graphics
local R = {}

-- ---------------------------------------------------------------- matrizes
local function mul(a, b)
  local r = {}
  for i = 0, 3 do
    local a1, a2, a3, a4 = a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3], a[i * 4 + 4]
    for j = 1, 4 do
      r[i * 4 + j] = a1 * b[j] + a2 * b[4 + j] + a3 * b[8 + j] + a4 * b[12 + j]
    end
  end
  return r
end
R.mul = mul

local function ident() return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } end

--- T * Ry * Rx * Rz * S num passo so
local function trs(tx, ty, tz, rx, ry, rz, sx, sy, sz)
  local cx, sx_, cy, sy_, cz, sz_ = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
  -- R = Ry * Rx * Rz
  local r11 = cy * cz + sy_ * sx_ * sz_
  local r12 = -cy * sz_ + sy_ * sx_ * cz
  local r13 = sy_ * cx
  local r21 = cx * sz_
  local r22 = cx * cz
  local r23 = -sx_
  local r31 = -sy_ * cz + cy * sx_ * sz_
  local r32 = sy_ * sz_ + cy * sx_ * cz
  local r33 = cy * cx
  return { r11 * sx, r12 * sy, r13 * sz, tx,
    r21 * sx, r22 * sy, r23 * sz, ty,
    r31 * sx, r32 * sy, r33 * sz, tz,
    0, 0, 0, 1 }
end
R.trs = trs

local function perspective(fovy, aspect, n, f)
  local t = 1 / math.tan(fovy / 2)
  return { t / aspect, 0, 0, 0, 0, t, 0, 0, 0, 0, (f + n) / (n - f), 2 * f * n / (n - f), 0, 0, -1, 0 }
end

-- ---------------------------------------------------------------- shader
-- OpenGL ES (R36S): uma uniform declarada nas duas etapas (vertice e pixel)
-- com precisoes diferentes nao liga o programa. Por isso cada uniform existe
-- em UMA etapa so: u_outline (vertice) e u_isline (pixel) sao separadas.
local CODE = [[
varying vec3 v_n;
varying vec4 v_c;
#ifdef VERTEX
uniform mat4 u_mvp;
uniform mat4 u_model;
uniform float u_outline;
uniform float u_smooth;
attribute vec3 VertexNormal;
attribute vec3 VertexSmooth;
vec4 position(mat4 tp, vec4 p) {
  vec3 pos = p.xyz + VertexSmooth * u_outline;
  v_n = (u_model * vec4(mix(VertexNormal, VertexSmooth, u_smooth), 0.0)).xyz;
  v_c = VertexColor;
  return u_mvp * vec4(pos, 1.0);
}
#endif
#ifdef PIXEL
uniform float u_isline;
uniform vec3 u_tint;
uniform float u_tintk;
uniform float u_emis;
uniform vec4 u_over;
uniform vec3 u_ink;
uniform vec3 u_light;
uniform float u_bright;
uniform float u_gloss;
vec4 effect(vec4 col, Image tex, vec2 uv, vec2 sc) {
  if (u_isline > 0.5) return vec4(u_ink, 1.0);
  vec3 base = v_c.rgb;
  base = mix(base, base * u_tint, u_tintk);
  base = mix(base, u_over.rgb, u_over.a);
  base = base * u_bright;
  if (u_emis > 0.5) return vec4(base, 1.0);
  vec3 n = normalize(v_n);
  float d = max(dot(n, u_light), 0.0);
  float hemi = 0.5 + 0.5 * n.y;
  float rim = pow(1.0 - max(n.z, 0.0), 2.5);
  vec3 sky = vec3(0.42, 0.44, 0.55);
  vec3 ground = vec3(0.22, 0.18, 0.20);
  vec3 lit = base * (mix(ground, sky, hemi) + vec3(1.0, 0.96, 0.9) * d * 0.78);
  lit += rim * 0.22 * vec3(0.75, 0.85, 1.0);
  // brilho especular (ceramica polida / vidro do visor)
  vec3 h = normalize(u_light + vec3(0.0, 0.0, 1.0));
  float sp = pow(max(dot(n, h), 0.0), 24.0 + 40.0 * u_gloss) * u_gloss;
  lit += vec3(sp);
  return vec4(lit, 1.0);
}
#endif
]]

local state = { checked = false, ok = false, err = nil }
local shader
local canvases = {}

--- testa uma vez se o aparelho tem shader e profundidade
function R.available()
  if state.checked then return state.ok, state.err end
  state.checked = true
  local ok, err = pcall(function()
    local fmts = lg.getCanvasFormats and lg.getCanvasFormats() or {}
    if not (fmts.depth16 or fmts.depth24 or fmts.depth24stencil8) then error("sem buffer de profundidade") end
    shader = lg.newShader(CODE)
    local c = lg.newCanvas(8, 8)
    lg.push("all")
    lg.setCanvas({ c, depth = true })
    lg.setDepthMode("lequal", true)
    lg.clear(0, 0, 0, 0)
    lg.pop()
    c:release()
  end)
  state.ok, state.err = ok, (not ok) and tostring(err) or nil
  -- registra no log do hub (para descobrir o motivo no aparelho)
  pcall(function()
    local info = table.concat({ lg.getRendererInfo() }, " | ")
    require("lib.util").log("assistente 3D:", ok and "ativo" or ("indisponivel: " .. state.err), "|", info)
  end)
  return state.ok, state.err
end

function R.error() return state.err end

--- (para testes) forca o modo 2D
function R.disable(reason) state.checked, state.ok, state.err = true, false, reason or "desligado" end

--- camera: projecao * vista (o = { fov, aspect, dist, pitch, target_y })
function R.viewproj(o)
  local proj
  if o.ortho then
    -- ortografica (sprites em pixel art): o.ortho = meia altura visivel
    local hh = o.ortho
    local hw = hh * (o.aspect or 1)
    local n, f = 0.1, 20
    proj = { 1 / hw, 0, 0, 0, 0, 1 / hh, 0, 0, 0, 0, -2 / (f - n), -(f + n) / (f - n), 0, 0, 0, 1 }
  else
    proj = perspective(math.rad(o.fov or 30), o.aspect or 1, 0.1, 20)
  end
  local view = mul(trs(0, 0, -(o.dist or 3.0), o.pitch or 0.16, 0, 0, 1, 1, 1),
    trs(0, -(o.target_y or 0.55), 0, 0, 0, 0, 1, 1, 1))
  return mul(proj, view)
end

--- ponto do mundo -> pixel (0..w, 0..h, y para baixo) com a mesma camera
function R.project(o, x, y, z, w, h)
  local m = R.viewproj(o)
  local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
  local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
  local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
  return (cx / cw * 0.5 + 0.5) * w, (0.5 - cy / cw * 0.5) * h
end

-- matrizes de mundo de cada peca: pai * T(posicao + desloc) * R * S
local function world_mats(model, pose, root)
  local W = {}
  for _, p in ipairs(model.parts) do
    local q = pose and pose[p.name]
    local tx, ty, tz = p.t[1], p.t[2], p.t[3]
    local rx, ry, rz, sx, sy, sz = 0, 0, 0, 1, 1, 1
    if p.r then rx, ry, rz = p.r[1], p.r[2], p.r[3] end
    if p.s then sx, sy, sz = p.s[1], p.s[2], p.s[3] end
    if q then
      tx, ty, tz = tx + (q.tx or 0), ty + (q.ty or 0), tz + (q.tz or 0)
      rx, ry, rz = rx + (q.rx or 0), ry + (q.ry or 0), rz + (q.rz or 0)
      local s = q.s or 1
      sx, sy, sz = sx * (q.sx or s), sy * (q.sy or s), sz * (q.sz or s)
    end
    local m = trs(tx, ty, tz, rx, ry, rz, sx, sy, sz)
    W[p] = p.parent and mul(W[p.parent], m) or mul(root, m)
  end
  return W
end

--- posicao (pixel) do pivo de uma peca, com a mesma camera e pose
function R.locate(model, pose, o, name, w, h)
  local part = model.by_name[name]
  if not part then return nil end
  local root = trs(o.x or 0, 0, 0, 0, o.yaw or 0, 0, o.scale or 1, o.scale or 1, o.scale or 1)
  local Wm = world_mats(model, pose, root)[part]
  return R.project(o, Wm[4], Wm[8], Wm[12], w, h)
end

local NO_OUTLINE = { mouth = true, cheeks = true, panel = true }

--- desenha um modelo no canvas atual (que precisa ter depth)
--  o = { tint = {r,g,b}, yaw, pitch, dist, target_y, aspect, outline,
--        hats = modelo de chapeus, hat = id, bright }
function R.draw(model, pose, o)
  if not R.available() then return false end
  o = o or {}
  local vp = R.viewproj(o)
  -- o LOVE desenha nos canvases de cabeca para baixo: compensa no eixo Y
  if lg.getCanvas() then vp = mul({ 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, vp) end
  local root = trs(o.x or 0, 0, 0, 0, o.yaw or 0, 0, o.scale or 1, o.scale or 1, o.scale or 1)
  local W = world_mats(model, pose, root)
  local tint = o.tint or { 1, 1, 1 }
  local lx, ly, lz = -0.45, 0.75, 0.6
  local ll = math.sqrt(lx * lx + ly * ly + lz * lz)
  lg.push("all")
  lg.setDepthMode("lequal", true)
  lg.setShader(shader)
  shader:send("u_light", { lx / ll, ly / ll, lz / ll })
  shader:send("u_ink", o.ink or { 0.07, 0.05, 0.10 })
  local cull = lg.getCanvas() and "back" or "front"
  local function draw_part(p, M, extras)
    shader:send("u_mvp", "row", mul(vp, M))
    shader:send("u_model", "row", M)
    local q = pose and pose[p.name]
    shader:send("u_tint", tint)
    shader:send("u_tintk", extras.tint and 1 or 0)
    shader:send("u_emis", extras.emissive and 1 or 0)
    shader:send("u_over", (q and q.color) or { 0, 0, 0, 0 })
    shader:send("u_bright", (extras.light and 1.12 or 1) * (o.bright or 1))
    shader:send("u_outline", 0)
    shader:send("u_isline", 0)
    shader:send("u_smooth", extras.smooth and 1 or 0)
    shader:send("u_gloss", extras.gloss or 0)
    lg.setMeshCullMode(cull)
    lg.draw(p.mesh)
  end
  local function draw_outline(p, M, w)
    shader:send("u_mvp", "row", mul(vp, M))
    shader:send("u_model", "row", M)
    shader:send("u_outline", w)
    shader:send("u_isline", 1)
    lg.setMeshCullMode(cull == "back" and "front" or "back")
    lg.draw(p.mesh)
  end
  local hat = o.hats and o.hat and o.hats.by_name[o.hat]
  local anchor = model.by_name.hat_anchor
  local hatM
  if hat and hat.mesh and anchor then
    local k = (anchor.extras.hat_scale or 1)
    hatM = mul(W[anchor], trs(0, 0, 0, 0, 0, 0, k, k, k))
  end
  if o.outline then
    local w = o.outline_w or 0.014
    for _, p in ipairs(model.parts) do
      local q = pose and pose[p.name]
      if p.mesh and not NO_OUTLINE[p.name] and not p.name:find("^eye_") and not (q and q.hide) then
        draw_outline(p, W[p], w)
      end
    end
    if hatM then draw_outline(hat, hatM, w / (anchor.extras.hat_scale or 1)) end
  end
  for _, p in ipairs(model.parts) do
    local q = pose and pose[p.name]
    if p.mesh and not (q and q.hide) then draw_part(p, W[p], p.extras) end
  end
  if hatM then draw_part(hat, hatM, hat.extras) end
  lg.pop()
  return true
end

--- canvas reaproveitado por chave; fn() desenha dentro (ja limpo, com depth)
function R.render(key, w, h, ss, fn)
  ss = ss or 1
  local cw, ch = math.max(8, math.floor(w * ss)), math.max(8, math.floor(h * ss))
  local c = canvases[key]
  if not c or c:getWidth() ~= cw or c:getHeight() ~= ch then
    if c then c:release() end
    c = lg.newCanvas(cw, ch)
    c:setFilter("linear", "linear")
    canvases[key] = c
  end
  lg.push("all")
  lg.setCanvas({ c, depth = true })
  lg.clear(0, 0, 0, 0)
  lg.origin()
  fn(cw, ch)
  lg.pop()
  return c
end

function R.release_canvases()
  for k, c in pairs(canvases) do c:release(); canvases[k] = nil end
end

return R
