-- =============================================================================
--  Transmissao da tela do hub para o navegador do computador (rede local)
--  Gerenciador na thread principal: liga/desliga a thread do servidor,
--  gera o codigo temporario e monta a pagina de visualizacao.
--  Nada inicia sozinho: so com "Iniciar transmissao".
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")
local T = require("ui.theme")
local Prefs = require("core.prefs")
local Net = require("core.net")
local Cap = require("core.screencap")

local S = {
  state = "off",       -- off | starting | on | stopping
  thread = nil,
  token = nil,
  port = nil,
  viewers = 0,
  kbps = 0,
  last_error = nil,
  started_at = nil,
}

local CTL, OUT, FRAMES = "hub_stream_ctl", "hub_stream_out", "hub_stream_frames"
S.DEFAULT_PORT = 8090
S.FPS_CHOICES = { 5, 10, 15 }

function S.fps()
  local f = tonumber(Prefs.get("stream_fps") or "")
  for _, c in ipairs(S.FPS_CHOICES) do if c == f then return f end end
  return 10
end

function S.set_fps(f)
  Prefs.set("stream_fps", tostring(f))
  if S.state == "on" then Cap.set_fps("stream", S.viewers > 0 and f or 1) end
end

local function random_token(n)
  local chars = "abcdefghjkmnpqrstuvwxyz23456789"
  local bytes
  local f = io.open("/dev/urandom", "rb")
  if f then bytes = f:read(n); f:close() end
  local t = {}
  for i = 1, n do
    local b = bytes and bytes:byte(i) or love.math.random(0, 255)
    local k = b % #chars + 1
    t[i] = chars:sub(k, k)
  end
  return table.concat(t)
end

function S.running() return S.state ~= "off" end

local function port_free(p)
  local ok, socket = pcall(require, "socket")
  if not ok then return true end
  local s = socket.bind("*", p)
  if s then s:close(); return true end
  return false
end

--- endereco completo para digitar no navegador (nil sem rede)
function S.address(net)
  net = net or Net.current() or Net.get(3)
  if not (S.state == "on" and net and net.connected and net.ip) then return nil end
  return "http://" .. net.ip .. ":" .. S.port .. "/" .. S.token
end

-- ---------------------------------------------------------------------------
-- Pagina de visualizacao (somente leitura; textos no idioma do hub)
local function esc(s) return (tostring(s):gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" })) end
local function js(s) return (tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", " ")) end

local function build_page(lang)
  local tx = {
    title = L("R36S PORT HUB — transmissão"),
    connecting = L("Conectando ao console..."),
    live = L("AO VIVO"),
    lost = L("Conexão perdida. Tentando de novo..."),
    ended = L("A transmissão foi encerrada no console."),
    oldcode = L("Este endereço não vale mais. Use o endereço mostrado agora no console."),
    busy = L("Muitos computadores assistindo. Feche outra janela e recarregue."),
    oldbrowser = L("Este navegador é antigo demais para a transmissão. Use Firefox ou Chromium atualizados."),
    full = L("Tela cheia"),
    sharp = L("Pixels nítidos"),
    note = L("Somente visualização: nada feito nesta página controla o console."),
  }
  return [[<!DOCTYPE html>
<html lang="]] .. esc(lang) .. [["><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>]] .. esc(tx.title) .. [[</title>
<style>
html,body{margin:0;height:100%;background:#0b0d12;color:#cfd6e4;font:14px/1.4 system-ui,sans-serif}
#wrap{display:flex;flex-direction:column;height:100%}
#bar{display:flex;gap:12px;align-items:center;padding:8px 12px;background:#141821;border-bottom:1px solid #263042}
#bar b{color:#fff;letter-spacing:.5px}#st{flex:1}
.live{color:#ff5a5a;font-weight:700}button{background:#263042;color:#e8eefc;border:1px solid #3a4760;border-radius:6px;padding:5px 10px;cursor:pointer}
#view{flex:1;display:flex;align-items:center;justify-content:center;min-height:0}
canvas{max-width:100%;max-height:100%;aspect-ratio:4/3;width:auto;height:100%;background:#000}
canvas.px{image-rendering:pixelated}
#note{padding:6px 12px;color:#7f8aa3;font-size:12px;text-align:center}
</style></head><body><div id="wrap">
<div id="bar"><b>R36S PORT HUB</b><span id="st">]] .. esc(tx.connecting) .. [[</span>
<button id="px">]] .. esc(tx.sharp) .. [[</button><button id="fs">]] .. esc(tx.full) .. [[</button></div>
<div id="view"><canvas id="c" width="]] .. T.W .. [[" height="]] .. T.H .. [["></canvas></div>
<div id="note">]] .. esc(tx.note) .. [[</div></div>
<script>
(function(){
var W=]] .. T.W .. [[,TS=32,TX={connecting:']] .. js(tx.connecting) .. [[',live:']] .. js(tx.live) .. [[',lost:']] .. js(tx.lost) .. [[',ended:']] .. js(tx.ended) .. [[',oldcode:']] .. js(tx.oldcode) .. [[',busy:']] .. js(tx.busy) .. [[',old:']] .. js(tx.oldbrowser) .. [['};
var cv=document.getElementById('c'),ctx=cv.getContext('2d',{alpha:false}),st=document.getElementById('st');
var tile=ctx.createImageData(TS,TS),px=tile.data,stop=false;
function say(t,live){st.textContent=t;st.className=live?'live':'';}
document.getElementById('fs').onclick=function(){var e=document.getElementById('view');if(document.fullscreenElement)document.exitFullscreen();else if(e.requestFullscreen)e.requestFullscreen();};
document.getElementById('px').onclick=function(){cv.classList.toggle('px');};
if(!window.DecompressionStream||!window.ReadableStream){say(TX.old);return;}
function inflate(u8){var s=new Blob([u8]).stream().pipeThrough(new DecompressionStream('deflate'));return new Response(s).arrayBuffer().then(function(b){return new Uint8Array(b);});}
function apply(d){var n=d[0]|(d[1]<<8),p=2;for(var i=0;i<n;i++){var tx=d[p],ty=d[p+1];p+=2;for(var k=0,j=0;k<TS*TS;k++,j+=4,p+=3){px[j]=d[p];px[j+1]=d[p+1];px[j+2]=d[p+2];px[j+3]=255;}ctx.putImageData(tile,tx*TS,ty*TS);}}
var URL_S=location.pathname.replace(/\/$/,'')+'/s';
function run(){
  if(stop)return;say(TX.connecting);
  fetch(URL_S,{cache:'no-store'}).then(function(r){
    if(r.status===404){stop=true;say(TX.oldcode);return;}
    if(r.status===503){say(TX.busy);setTimeout(run,5000);return;}
    if(!r.ok||!r.body)throw 0;
    say(TX.live,true);
    var rd=r.body.getReader(),buf=new Uint8Array(0),chain=Promise.resolve();
    function pump(){return rd.read().then(function(x){
      if(x.done)throw 0;
      var v=x.value,nb=new Uint8Array(buf.length+v.length);nb.set(buf);nb.set(v,buf.length);buf=nb;
      while(buf.length>=5){var len=((buf[1]<<24)|(buf[2]<<16)|(buf[3]<<8)|buf[4])>>>0;if(buf.length<5+len)break;
        var t=buf[0],pl=buf.slice(5,5+len);buf=buf.slice(5+len);
        if(t===70){(function(pl){chain=chain.then(function(){return inflate(pl);}).then(apply).catch(function(){});})(pl);}
        else if(t===69){stop=true;say(TX.ended);rd.cancel();return;}}
      return pump();});}
    return pump();
  }).catch(function(){if(!stop){say(TX.lost);setTimeout(run,2500);}});
}
run();
})();
</script></body></html>]]
end

local function build_root_page(lang)
  return "<!DOCTYPE html><html lang=\"" .. esc(lang) .. "\"><head><meta charset=\"utf-8\"><title>R36S PORT HUB</title></head>"
    .. "<body style=\"background:#0b0d12;color:#cfd6e4;font:16px system-ui,sans-serif;padding:24px\"><b>R36S PORT HUB</b><p>"
    .. esc(L("Digite o endereço completo mostrado no console, com o código no final.")) .. "</p></body></html>"
end

-- ---------------------------------------------------------------------------
--- inicia a transmissao. Devolve true ou false, motivo
function S.start()
  if S.thread and S.thread:isRunning() then return false, L("A transmissão já está ligada.") end
  local net = Net.status()
  if not (net and net.connected and net.ip) then return false, L("Sem conexão de rede. Conecte o console ao Wi-Fi.") end
  local port
  for p = S.DEFAULT_PORT, S.DEFAULT_PORT + 9 do
    if port_free(p) then port = p; break end
  end
  if not port then return false, L("Nenhuma porta livre entre 8090 e 8099.") end
  local ctl, out, fr = love.thread.getChannel(CTL), love.thread.getChannel(OUT), love.thread.getChannel(FRAMES)
  ctl:clear(); out:clear()
  local img = fr:pop()
  while img do img:release(); img = fr:pop() end
  S.ctl, S.out, S.frames = ctl, out, fr
  S.token = random_token(8)
  S.port = port
  S.viewers, S.kbps, S.last_error = 0, 0, nil
  local lang = require("lib.i18n").lang
  S.thread = love.thread.newThread("threads/stream_thread.lua")
  S.thread:start({ ctl = CTL, out = OUT, frames = FRAMES, port = port, token = S.token, w = T.W, h = T.H,
    page = build_page(lang), page_root = build_root_page(lang) })
  S.state = "starting"
  U.log("Transmissão: iniciando na porta", port)
  return true
end

function S.stop()
  Cap.release("stream")
  if S.thread and S.thread:isRunning() then
    S.ctl:push("stop")
    S.state = "stopping"
  else
    S.state = "off"
  end
end

--- parada sincrona (ao sair do app)
function S.stop_wait()
  S.stop()
  local t0 = love.timer.getTime()
  while S.thread and S.thread:isRunning() and love.timer.getTime() - t0 < 1.5 do love.timer.sleep(0.02) end
  S.update()
  S.state = "off"
end

local function notify(text, kind) if S.on_notify then S.on_notify(text, kind) end end

function S.update()
  local th = S.thread
  if th then
    local e = th:getError()
    if e then
      U.log("Transmissão: erro na thread:", e)
      S.thread = nil
      S.state = "off"
      Cap.release("stream")
      S.last_error = L("Erro interno da transmissão.")
      notify(L("A transmissão parou por um erro interno."), "error")
    end
  end
  if not S.out then return end
  local m = S.out:pop()
  while m do
    if m.t == "started" then
      S.state = "on"
      S.started_at = love.timer.getTime()
      Cap.want("stream", 1, S.frames, 1)    -- 1 quadro/s sem ninguem assistindo
      notify(L("Transmissão ligada."), "ok")
    elseif m.t == "error" then
      S.state = "off"
      S.last_error = m.code == "port_in_use" and L("A porta já está em uso.") or (L("Não foi possível iniciar: ") .. tostring(m.detail))
      notify(S.last_error, "error")
    elseif m.t == "viewers" then
      local before = S.viewers
      S.viewers = m.n
      Cap.set_fps("stream", m.n > 0 and S.fps() or 1)
      if m.n > before then notify(L("Computador conectado à transmissão."), "info") end
    elseif m.t == "stats" then
      S.kbps, S.viewers = m.kbps, m.viewers
    elseif m.t == "stopped" then
      S.state = "off"
      S.viewers, S.kbps = 0, 0
      Cap.release("stream")
      notify(L("Transmissão encerrada."), "info")
    end
    m = S.out:pop()
  end
  if S.state ~= "off" and S.thread and not S.thread:isRunning() and S.out:getCount() == 0 then
    S.state = "off"
    Cap.release("stream")
  end
end

return S
