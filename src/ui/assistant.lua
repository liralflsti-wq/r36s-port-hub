-- =============================================================================
--  Desenho do assistente: o drone flutuante 3D (assets/assistant/drone.glb,
--  gerado por tools/make_assistant_glb.py), animado por peca
--  (core/assistant3d/anim.lua) e desenhado num canvas pequeno com
--  profundidade, sombreamento suave e brilho (core/assistant3d/render.lua).
--  Sem 3D no aparelho (ou se o modelo falhar), usa a imagem 2D do drone
--  (drone_front.png / drone_small.png).
--    AV.draw(cx, feet_y, height_px, o)   o = { key, yaw }
--    AV.draw_corner()                   no canto da tela
--    AV.bubble(text, cx, top)
-- =============================================================================
local T = require("ui.theme")
local G = require("ui.gfx")
local lg = love.graphics

local AV = {}
local model, failed
local imgs = {}
local canvases = {}

local function anim() return App and App.animations and App.animations() end

local function img(name)
  if imgs[name] == nil then
    local ok, im = pcall(lg.newImage, "assets/assistant/" .. name .. ".png")
    imgs[name] = ok and im or false
    if imgs[name] then imgs[name]:setFilter("linear", "linear") end
  end
  return imgs[name] or nil
end

local function load3d()
  if failed then return nil end
  if model then return model end
  local R = require("core.assistant3d.render")
  if not R.available() then failed = true; return nil end
  local m, err = require("core.assistant3d.loader").load("assets/assistant/drone.glb")
  if not m then
    failed = true
    pcall(function() require("lib.util").log("assistente 3D: modelo falhou:", tostring(err)) end)
    return nil
  end
  model = m
  return m
end

function AV.uses_3d() return load3d() ~= nil end

local CAM = { dist = 3.3, target_y = 0.66, pitch = 0.12 }
local FRAME_W, FRAME_H = 1.5, 1.95     -- area visivel (unidades) -> proporcao do canvas

--- desenha o drone com os pes (ponta do propulsor) em (cx, feet_y), altura ~h px
function AV.draw(cx, feet_y, h, o)
  o = o or {}
  local A = require("core.assistant")
  local m = load3d()
  if m then
    local R = require("core.assistant3d.render")
    local Anim = require("core.assistant3d.anim")
    local ctl = A.ctl()
    local pose = Anim.pose(ctl, anim())
    local ch = math.floor(h * 1.25)
    local cw = math.floor(ch * FRAME_W / FRAME_H)
    local ss = (h < 120) and 2 or 1
    local key = o.key or "corner"
    local okr, cv = pcall(R.render, key, cw, ch, ss, function(w, hh)
      R.draw(m, pose, { yaw = o.yaw or -0.2, aspect = w / hh, dist = CAM.dist, target_y = CAM.target_y,
        pitch = CAM.pitch, outline = true, outline_w = 0.008 })
    end)
    if okr and cv then
      -- onde a base do drone cai no canvas -> encaixa em feet_y
      local cam = { aspect = cw / ch, dist = CAM.dist, target_y = CAM.target_y, pitch = CAM.pitch }
      local fx, fy = R.project(cam, 0, -0.02, 0, cw, ch)
      lg.setColor(0, 0, 0, 0.25)
      lg.ellipse("fill", cx, feet_y + 2, h * 0.18, math.max(2, h * 0.03))
      lg.setColor(1, 1, 1, o.alpha or 1)
      lg.draw(cv, cx - fx, feet_y - fy, 0, 1 / ss, 1 / ss)
      return true
    end
    failed = true
  end
  -- reserva 2D
  local im = img(h < 120 and "drone_small" or "drone_front")
  if not im then return false end
  local k = h / im:getHeight() * 1.0
  local bob = anim() and math.sin((App and App.t or 0) * 1.7) * 2 or 0
  lg.setColor(1, 1, 1, o.alpha or 1)
  lg.draw(im, cx - im:getWidth() * k / 2, feet_y - im:getHeight() * k + bob, 0, k, k)
  return true
end

--- balao de fala (texto ja traduzido)
function AV.bubble(text, cx, top)
  local f = T.f.small
  local w = math.min(290, f:getWidth(text) + 18)
  local lines = select(2, f:getWrap(text, w - 14))
  local h = #lines * f:getHeight() + 10
  local x = math.max(6, math.min(T.W - w - 6, cx - w + 24))
  local y = math.max(44, top - h - 10)
  lg.setColor(0, 0, 0, 0.35)
  lg.rectangle("fill", x + 2, y + 3, w, h, 8, 8)
  lg.setColor(0.94, 0.97, 1, 0.98)
  lg.rectangle("fill", x, y, w, h, 8, 8)
  lg.setColor(0.35, 0.85, 1, 1)
  lg.setLineWidth(1.5)
  lg.rectangle("line", x, y, w, h, 8, 8)
  lg.setLineWidth(1)
  lg.setColor(0.94, 0.97, 1, 0.98)
  lg.polygon("fill", cx - 6, y + h, cx + 4, y + h, cx, y + h + 8)
  for i, l in ipairs(lines) do G.text(f, l, x + 8, y + 5 + (i - 1) * f:getHeight(), { 0.08, 0.1, 0.16 }) end
end

local HIDE = { achievements = true, splash = true, disclaimer = true, language = true, textinput = true, padtest = true, tester = true,
  assistant = true }

function AV.draw_corner()
  local A = package.loaded["core.assistant"]
  if not A or not A.enabled() or (App and App.capturing) then return end
  local cur = App.current and App.current()
  if not cur or HIDE[cur.name] or (cur.name == "birthday" and cur.p and cur.p.first) then return end
  local P = package.loaded["ui.achv_popup"]
  if P and P.t0 then return end
  local k = A.SIZE_SCALE[A.get("size") or "medium"] or 1
  local h = math.floor(62 * k)
  local cx, by = T.W - 30 * k, T.H - 26
  AV.draw(cx, by, h, { key = "corner" })
  if A.bubble then AV.bubble(A.bubble.text, cx, by - h - 4) end
end

return AV
