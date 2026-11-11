-- =============================================================================
--  Icones das categorias (desenhados em codigo, estilo retro, leves)
--  Cada funcao desenha num quadro de 24x24 a partir de (x, y).
-- =============================================================================
local lg = love.graphics

local I = {}

local function px(x, y, w, h) lg.rectangle("fill", x, y, w, h) end

local D = {}

-- JOGOS ---------------------------------------------------------------------
D.acao = function(x, y) -- explosao
  lg.polygon("fill", x + 12, y + 1, x + 15, y + 8, x + 23, y + 6, x + 17, y + 12, x + 23, y + 18,
    x + 15, y + 16, x + 12, y + 23, x + 9, y + 16, x + 1, y + 18, x + 7, y + 12, x + 1, y + 6, x + 9, y + 8)
end
D.aventura = function(x, y) -- bussola
  lg.setLineWidth(2); lg.circle("line", x + 12, y + 12, 10); lg.setLineWidth(1)
  lg.polygon("fill", x + 12, y + 4, x + 15, y + 12, x + 12, y + 20, x + 9, y + 12)
end
D.rpg = function(x, y) -- espada
  lg.polygon("fill", x + 19, y + 2, x + 22, y + 2, x + 22, y + 5, x + 10, y + 17, x + 7, y + 14)
  px(x + 4, y + 13, 8, 3); lg.polygon("fill", x + 5, y + 12, x + 12, y + 19, x + 10, y + 21, x + 3, y + 14)
  px(x + 2, y + 19, 4, 4)
end
D.plataforma = function(x, y) -- blocos em escada
  px(x + 1, y + 16, 7, 7); px(x + 9, y + 16, 7, 7); px(x + 17, y + 16, 6, 7)
  px(x + 9, y + 8, 7, 7); px(x + 17, y + 8, 6, 7); px(x + 17, y + 1, 6, 6)
end
D.corrida = function(x, y) -- bandeira quadriculada
  px(x + 3, y + 2, 2, 21)
  for r = 0, 3 do for c = 0, 3 do
    if (r + c) % 2 == 0 then px(x + 5 + c * 4, y + 2 + r * 3, 4, 3) end
  end end
  lg.setLineWidth(1); lg.rectangle("line", x + 5.5, y + 2.5, 16, 12)
end
D.luta = function(x, y) -- luva de boxe
  lg.circle("fill", x + 13, y + 10, 8); px(x + 6, y + 15, 12, 7)
  lg.setColor(0, 0, 0, 0.35); px(x + 7, y + 17, 10, 2); lg.setColor(I.c)
  lg.circle("fill", x + 5, y + 12, 3)
end
D.tiro = function(x, y) -- mira
  lg.setLineWidth(2); lg.circle("line", x + 12, y + 12, 8); lg.setLineWidth(1)
  px(x + 11, y + 1, 2, 7); px(x + 11, y + 16, 2, 7); px(x + 1, y + 11, 7, 2); px(x + 16, y + 11, 7, 2)
  px(x + 11, y + 11, 2, 2)
end
D.terror = function(x, y) -- fantasma
  lg.circle("fill", x + 12, y + 10, 8); px(x + 4, y + 10, 16, 9)
  lg.polygon("fill", x + 4, y + 19, x + 8, y + 23, x + 10, y + 19, x + 14, y + 23, x + 16, y + 19, x + 20, y + 23, x + 20, y + 19)
  lg.setColor(0, 0, 0, 0.7); px(x + 8, y + 8, 3, 4); px(x + 14, y + 8, 3, 4); lg.setColor(I.c)
end
D.puzzle = function(x, y) -- peca de quebra-cabeca
  px(x + 3, y + 7, 15, 15); lg.circle("fill", x + 10, y + 5, 4); lg.circle("fill", x + 20, y + 14, 4)
end
D.estrategia = function(x, y) -- torre de xadrez
  px(x + 5, y + 2, 3, 4); px(x + 10, y + 2, 4, 4); px(x + 16, y + 2, 3, 4); px(x + 5, y + 5, 14, 3)
  px(x + 8, y + 8, 8, 10); px(x + 5, y + 18, 14, 2); px(x + 3, y + 20, 18, 3)
end
D.arcade = function(x, y) -- joystick de fliperama
  lg.circle("fill", x + 12, y + 6, 5); px(x + 11, y + 9, 2, 8)
  lg.polygon("fill", x + 2, y + 23, x + 5, y + 16, x + 19, y + 16, x + 22, y + 23)
end
D.esportes = function(x, y) -- bola
  lg.setLineWidth(2); lg.circle("line", x + 12, y + 12, 10)
  lg.line(x + 2, y + 12, x + 22, y + 12); lg.arc("line", "open", x + 12, y + 12, 6, -1.2, 1.2)
  lg.arc("line", "open", x + 12, y + 12, 6, math.pi - 1.2, math.pi + 1.2); lg.setLineWidth(1)
end
D.classicos = function(x, y) -- cartucho
  px(x + 4, y + 2, 16, 18); px(x + 6, y + 20, 12, 3)
  lg.setColor(0, 0, 0, 0.45); px(x + 7, y + 5, 10, 7)
  for i = 0, 3 do px(x + 7 + i * 3, y + 20, 1, 3) end
  lg.setColor(I.c)
end

-- UTILITARIOS --------------------------------------------------------------
D.manutencao = function(x, y) -- chave inglesa
  lg.setLineWidth(4); lg.line(x + 5, y + 19, x + 15, y + 9); lg.setLineWidth(1)
  lg.circle("fill", x + 17, y + 7, 6)
  lg.setColor(0, 0, 0, 0.8); lg.polygon("fill", x + 17, y + 7, x + 21, y + 1, x + 24, y + 4); lg.setColor(I.c)
  lg.circle("fill", x + 5, y + 19, 3)
end
D.diagnostico_do_sistema = function(x, y) -- monitor com pulso
  lg.setLineWidth(2); lg.rectangle("line", x + 1, y + 3, 22, 15, 2, 2)
  lg.line(x + 3, y + 11, x + 8, y + 11, x + 10, y + 6, x + 13, y + 15, x + 15, y + 9, x + 21, y + 9)
  lg.setLineWidth(1); px(x + 9, y + 19, 6, 2); px(x + 6, y + 21, 12, 2)
end
D.testes_de_controles = function(x, y) -- controle
  lg.rectangle("fill", x + 1, y + 7, 22, 12, 6, 6)
  lg.setColor(0, 0, 0, 0.6)
  px(x + 5, y + 12, 6, 2); px(x + 7, y + 10, 2, 6)
  lg.circle("fill", x + 17, y + 11, 1.6); lg.circle("fill", x + 19, y + 14, 1.6)
  lg.setColor(I.c)
end
D.testes_de_analogicos = function(x, y) -- analogico
  lg.setLineWidth(2); lg.circle("line", x + 12, y + 12, 10); lg.setLineWidth(1)
  lg.circle("fill", x + 15, y + 9, 5)
  lg.setColor(0, 0, 0, 0.4); lg.circle("line", x + 15, y + 9, 3); lg.setColor(I.c)
end
D.testes_de_botoes = function(x, y) -- A B X Y
  lg.circle("fill", x + 12, y + 4, 3.5); lg.circle("fill", x + 12, y + 20, 3.5)
  lg.circle("fill", x + 4, y + 12, 3.5); lg.circle("fill", x + 20, y + 12, 3.5)
end
D.ferramentas_de_sistema = function(x, y) -- engrenagem
  lg.circle("fill", x + 12, y + 12, 7)
  for i = 0, 7 do
    local a = i * math.pi / 4
    local cx, cy = x + 12 + math.cos(a) * 9, y + 12 + math.sin(a) * 9
    lg.circle("fill", cx, cy, 2.6)
  end
  lg.setColor(0, 0, 0, 0.7); lg.circle("fill", x + 12, y + 12, 3); lg.setColor(I.c)
end
-- atalhos
D.search = function(x, y) -- lupa
  lg.setLineWidth(3); lg.circle("line", x + 10, y + 10, 7); lg.line(x + 15, y + 15, x + 22, y + 22); lg.setLineWidth(1)
end
D.news = function(x, y) -- selo "novo"
  lg.polygon("fill", x + 12, y + 1, x + 15, y + 5, x + 20, y + 4, x + 19, y + 9, x + 23, y + 12, x + 19, y + 15,
    x + 20, y + 20, x + 15, y + 19, x + 12, y + 23, x + 9, y + 19, x + 4, y + 20, x + 5, y + 15, x + 1, y + 12,
    x + 5, y + 9, x + 4, y + 4, x + 9, y + 5)
  lg.setColor(0, 0, 0, 0.6); px(x + 11, y + 6, 2, 8); px(x + 11, y + 16, 2, 2); lg.setColor(I.c)
end
D.download = function(x, y) -- seta para baixo
  px(x + 10, y + 2, 4, 11); lg.polygon("fill", x + 5, y + 11, x + 19, y + 11, x + 12, y + 18); px(x + 3, y + 20, 18, 3)
end
-- areas
D.games = function(x, y) return D.testes_de_controles(x, y) end
D.tools = function(x, y) return D.manutencao(x, y) end
D.bios = function(x, y) -- chip (BIOS): corpo, pinos e marca
  lg.setLineWidth(2); lg.rectangle("line", x + 5, y + 5, 14, 14, 2, 2); lg.setLineWidth(1)
  for k = 0, 2 do
    px(x + 8 + k * 4, y + 1, 2, 3); px(x + 8 + k * 4, y + 20, 2, 3)
    px(x + 1, y + 8 + k * 4, 3, 2); px(x + 20, y + 8 + k * 4, 3, 2)
  end
  px(x + 9, y + 9, 6, 6)
end
D.generic = function(x, y) -- estrela
  lg.polygon("fill", x + 12, y + 2, x + 15, y + 9, x + 22, y + 9, x + 16, y + 14, x + 18, y + 22,
    x + 12, y + 17, x + 6, y + 22, x + 8, y + 14, x + 2, y + 9, x + 9, y + 9)
end


-- CONFIGURACOES ---------------------------------------------------------------
D.set_appearance = function(x, y) -- paleta
  lg.setLineWidth(2)
  lg.arc("line", "open", x + 12, y + 12, 10, 0.9, 5.6)
  lg.line(x + 12 + math.cos(5.6) * 10, y + 12 + math.sin(5.6) * 10, x + 15, y + 14, x + 12 + math.cos(0.9) * 10, y + 12 + math.sin(0.9) * 10)
  lg.setLineWidth(1)
  lg.circle("fill", x + 7, y + 10, 2.2); lg.circle("fill", x + 11, y + 6, 2.2)
  lg.circle("fill", x + 16, y + 7, 2.2); lg.circle("fill", x + 8, y + 16, 2.2)
end
D.set_audio = function(x, y) -- alto-falante
  lg.polygon("fill", x + 2, y + 9, x + 7, y + 9, x + 13, y + 3, x + 13, y + 21, x + 7, y + 15, x + 2, y + 15)
  lg.setLineWidth(2)
  lg.arc("line", "open", x + 13, y + 12, 5, -0.9, 0.9)
  lg.arc("line", "open", x + 13, y + 12, 9, -0.9, 0.9)
  lg.setLineWidth(1)
end
D.set_network = function(x, y) -- wi-fi
  lg.setLineWidth(2)
  lg.arc("line", "open", x + 12, y + 20, 18, -2.4, -0.74)
  lg.arc("line", "open", x + 12, y + 20, 12, -2.4, -0.74)
  lg.arc("line", "open", x + 12, y + 20, 6, -2.4, -0.74)
  lg.setLineWidth(1)
  lg.circle("fill", x + 12, y + 20, 2.5)
end
D.set_battery = function(x, y) -- bateria com raio
  lg.setLineWidth(2); lg.rectangle("line", x + 1, y + 6, 19, 12, 2, 2); lg.setLineWidth(1)
  px(x + 20, y + 9, 3, 6)
  lg.polygon("fill", x + 12, y + 7, x + 6, y + 13, x + 10, y + 13, x + 9, y + 17, x + 15, y + 11, x + 11, y + 11)
end
D.set_controls = function(x, y) -- controle
  lg.setLineWidth(2); lg.rectangle("line", x + 1, y + 6, 22, 13, 6, 6); lg.setLineWidth(1)
  px(x + 5, y + 11, 6, 2); px(x + 7, y + 9, 2, 6)
  lg.circle("fill", x + 16, y + 10, 1.6); lg.circle("fill", x + 19, y + 13, 1.6)
end
D.set_downloads = function(x, y) -- seta para baixo + base
  px(x + 10, y + 1, 4, 11)
  lg.polygon("fill", x + 5, y + 10, x + 19, y + 10, x + 12, y + 17)
  px(x + 2, y + 19, 20, 3); px(x + 2, y + 15, 3, 5); px(x + 19, y + 15, 3, 5)
end
D.set_backup = function(x, y) -- disquete
  lg.setLineWidth(2); lg.rectangle("line", x + 2, y + 2, 20, 20, 2, 2); lg.setLineWidth(1)
  px(x + 6, y + 3, 11, 6); px(x + 6, y + 13, 12, 8)
  lg.setColor(0, 0, 0, 0.35); px(x + 14, y + 4, 2, 4)
  lg.setColor(I.c)
end
D.set_notify = function(x, y) -- sino
  lg.polygon("fill", x + 12, y + 2, x + 17, y + 6, x + 18, y + 14, x + 21, y + 18, x + 3, y + 18, x + 6, y + 14, x + 7, y + 6)
  lg.circle("fill", x + 12, y + 21, 2.5)
end
D.set_analyzer = function(x, y) -- lupa sobre chip
  lg.setLineWidth(2); lg.rectangle("line", x + 2, y + 2, 13, 13, 2, 2); lg.setLineWidth(1)
  px(x + 6, y + 6, 5, 5)
  lg.setLineWidth(2); lg.circle("line", x + 15, y + 15, 5.5); lg.line(x + 19, y + 19, x + 23, y + 23); lg.setLineWidth(1)
end
D.set_text = function(x, y) -- tamanho do texto: "A" pequeno e "A" grande
  lg.setLineWidth(2)
  lg.line(x + 1, y + 21, x + 6, y + 9, x + 11, y + 21); lg.line(x + 3, y + 17, x + 9, y + 17)
  lg.line(x + 10, y + 21, x + 16, y + 3, x + 22, y + 21); lg.line(x + 12.5, y + 15, x + 19.5, y + 15)
  lg.setLineWidth(1)
end
D.set_led = function(x, y) -- LED: cupula com dois terminais e raios de luz
  lg.setLineWidth(2)
  lg.arc("line", "open", x + 12, y + 11, 6, math.pi, 2 * math.pi)
  lg.line(x + 6, y + 11, x + 6, y + 17, x + 18, y + 17, x + 18, y + 11)
  lg.line(x + 9, y + 17, x + 9, y + 23); lg.line(x + 15, y + 17, x + 15, y + 21)
  lg.line(x + 3, y + 3, x + 6, y + 6); lg.line(x + 21, y + 3, x + 18, y + 6); lg.line(x + 12, y, x + 12, y + 2)
  lg.setLineWidth(1)
end
D.set_sdmaint = function(x, y) -- cartao SD com marca de verificacao
  lg.setLineWidth(2)
  lg.polygon("line", x + 5, y + 2, x + 15, y + 2, x + 19, y + 6, x + 19, y + 22, x + 5, y + 22)
  lg.line(x + 9, y + 3, x + 9, y + 7); lg.line(x + 12, y + 3, x + 12, y + 7); lg.line(x + 15, y + 4, x + 15, y + 8)
  lg.line(x + 8, y + 15, x + 11, y + 18, x + 16, y + 12)
  lg.setLineWidth(1)
end
D.set_storage = function(x, y) -- cartao SD com barra de uso
  lg.setLineWidth(2)
  lg.polygon("line", x + 5, y + 2, x + 15, y + 2, x + 19, y + 6, x + 19, y + 22, x + 5, y + 22)
  lg.line(x + 9, y + 3, x + 9, y + 7); lg.line(x + 12, y + 3, x + 12, y + 7); lg.line(x + 15, y + 4, x + 15, y + 8)
  lg.setLineWidth(1)
  px(x + 8, y + 17, 8, 2); px(x + 8, y + 13, 5, 2)
end
D.set_clock = function(x, y) -- relogio
  lg.setLineWidth(2)
  lg.circle("line", x + 12, y + 12, 10)
  lg.line(x + 12, y + 12, x + 12, y + 6)
  lg.line(x + 12, y + 12, x + 16, y + 15)
  lg.setLineWidth(1)
  px(x + 11, y + 11, 2, 2)
end
D.set_console = function(x, y) -- chip
  lg.setLineWidth(2); lg.rectangle("line", x + 5, y + 5, 14, 14, 2, 2); lg.setLineWidth(1)
  px(x + 9, y + 9, 6, 6)
  for i = 0, 2 do
    local o = 7 + i * 4
    px(x + o, y + 1, 2, 3); px(x + o, y + 20, 2, 3); px(x + 1, y + o, 3, 2); px(x + 20, y + o, 3, 2)
  end
end

-- CENTRAL DE CONFIGURACOES (0.4.7) ------------------------------------------
D.set_prefs = function(x, y) -- tres controles deslizantes
  for i = 0, 2 do
    local yy = y + 4 + i * 8
    px(x + 2, yy, 20, 2)
    lg.circle("fill", x + 6 + ((i * 7) % 14), yy + 1, 3)
  end
end
D.set_lang = function(x, y) -- globo
  lg.setLineWidth(2)
  lg.circle("line", x + 12, y + 12, 10)
  lg.ellipse("line", x + 12, y + 12, 4, 10)
  lg.line(x + 2, y + 12, x + 22, y + 12)
  lg.setLineWidth(1)
end
D.set_catalog = function(x, y) -- livro aberto
  lg.polygon("fill", x + 1, y + 5, x + 11, y + 7, x + 11, y + 21, x + 1, y + 19)
  lg.polygon("fill", x + 13, y + 7, x + 23, y + 5, x + 23, y + 19, x + 13, y + 21)
  lg.setColor(0, 0, 0, 0.35)
  for i = 0, 2 do px(x + 3, y + 10 + i * 3, 6, 1); px(x + 15, y + 10 + i * 3, 6, 1) end
  lg.setColor(I.c)
end
D.set_myports = function(x, y) -- cartucho
  px(x + 4, y + 2, 16, 20)
  lg.setColor(0, 0, 0, 0.4); px(x + 7, y + 5, 10, 7); lg.setColor(I.c)
  for i = 0, 3 do px(x + 6 + i * 4, y + 18, 2, 4) end
end
D.set_ftp = function(x, y) -- pasta com setas
  px(x + 1, y + 7, 22, 15); px(x + 1, y + 4, 9, 4)
  lg.setColor(0, 0, 0, 0.45)
  lg.polygon("fill", x + 8, y + 10, x + 12, y + 14, x + 4, y + 14)
  px(x + 7, y + 14, 2, 5)
  lg.polygon("fill", x + 16, y + 19, x + 12, y + 15, x + 20, y + 15)
  px(x + 15, y + 10, 2, 5)
  lg.setColor(I.c)
end
D.set_favorites = function(x, y) -- estrela
  local pts = {}
  for i = 0, 9 do
    local a = -math.pi / 2 + i * math.pi / 5
    local r = (i % 2 == 0) and 11 or 5
    pts[#pts + 1] = x + 12 + math.cos(a) * r
    pts[#pts + 1] = y + 13 + math.sin(a) * r
  end
  -- estrela e concava: divide em triangulos
  local ok, tris = pcall(love.math.triangulate, pts)
  if ok and tris then
    for _, t in ipairs(tris) do lg.polygon("fill", t) end
  else
    lg.circle("fill", x + 12, y + 12, 9)
  end
end
D.set_updates = function(x, y) -- seta circular
  lg.setLineWidth(3)
  lg.arc("line", "open", x + 12, y + 12, 9, -0.4, 4.4)
  lg.setLineWidth(1)
  lg.polygon("fill", x + 20, y + 1, x + 23, y + 10, x + 14, y + 8)
end
D.set_tools = function(x, y) -- chave inglesa
  lg.setLineWidth(4)
  lg.line(x + 6, y + 18, x + 15, y + 9)
  lg.setLineWidth(1)
  lg.circle("fill", x + 17, y + 7, 6)
  lg.setColor(0, 0, 0, 0.6); px(x + 16, y + 1, 4, 6); lg.setColor(I.c)
  lg.circle("fill", x + 5, y + 19, 3)
end
D.set_diag = function(x, y) -- pulso (linha de diagnostico)
  lg.setLineWidth(2)
  lg.line(x + 1, y + 13, x + 7, y + 13, x + 10, y + 5, x + 14, y + 20, x + 17, y + 13, x + 23, y + 13)
  lg.setLineWidth(1)
end
D.set_store = function(x, y) -- sacola com alca
  lg.setLineWidth(2)
  lg.rectangle("line", x + 3, y + 8, 18, 13, 2, 2)
  lg.line(x + 8, y + 8, x + 8, y + 4, x + 16, y + 4, x + 16, y + 8)
  lg.setLineWidth(1)
  px(x + 10, y + 13, 4, 4)
end
D.set_grid = function(x, y) -- quatro blocos (categorias)
  for i = 0, 1 do for j = 0, 1 do lg.rectangle("fill", x + 3 + i * 10, y + 3 + j * 10, 8, 8, 1.5, 1.5) end end
end
D.set_exit = function(x, y) -- porta com seta saindo
  lg.setLineWidth(2)
  lg.line(x + 13, y + 6, x + 13, y + 3, x + 3, y + 3, x + 3, y + 21, x + 13, y + 21, x + 13, y + 18)
  lg.line(x + 9, y + 12, x + 22, y + 12)
  lg.line(x + 18, y + 8, x + 22, y + 12, x + 18, y + 16)
  lg.setLineWidth(1)
end
D.set_about = function(x, y) -- "i" num circulo
  lg.setLineWidth(2); lg.circle("line", x + 12, y + 12, 10); lg.setLineWidth(1)
  px(x + 11, y + 10, 3, 8); px(x + 11, y + 6, 3, 3)
end

-- Icones em imagem (assets/icons/<id>.png, 64x64, branco com fundo transparente).
-- Sao pintados com a cor pedida. Se o arquivo nao existir, usa o desenho abaixo.
local IMG = {}
local IMG_ALIAS = { testes_de_analogicos = "testes_de_controles", testes_de_botoes = "testes_de_controles" }
-- Familia de linha (0.5.0): assets/icons/line/<id>.png, 64x64, traco unico
-- (tools/make_icons.py). Tem prioridade sobre os icones antigos; filtro linear
-- porque e desenhada em varios tamanhos (24 px nas listas, 40+ nos cartoes).
local LINE = {}
local function line_for(id)
  local v = LINE[id]
  if v == nil then
    v = false
    local path = "assets/icons/line/" .. tostring(id) .. ".png"
    if love.filesystem.getInfo(path) then
      local ok, img = pcall(love.graphics.newImage, path, { mipmaps = true })
      if ok and img then
        img:setFilter("linear", "linear")
        pcall(img.setMipmapFilter, img, "linear")
        v = img
      end
    end
    LINE[id] = v
  end
  return v or nil
end

local function image_for(id)
  local name = IMG_ALIAS[id] or id
  local v = IMG[name]
  if v == nil then
    v = false
    local path = "assets/icons/" .. tostring(name) .. ".png"
    if love.filesystem.getInfo(path) then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok and img then
        img:setFilter("nearest", "nearest")   -- pixel art nitida
        v = img
      end
    end
    IMG[name] = v
  end
  return v or nil
end

--- Desenha o icone `id` (24x24) com a cor `c`; scale opcional
function I.draw(id, x, y, c, scale)
  local li = line_for(id)
  if li then
    local size = 24 * (scale or 1)
    local s = size / li:getWidth()
    lg.setColor(c)
    lg.draw(li, x, y, 0, s, s)
    return
  end
  local img = image_for(id)
  if img then
    local size = 24 * (scale or 1)
    local iw = math.max(img:getWidth(), img:getHeight())
    local s = size / iw
    local ox = 0
    -- tamanhos grandes: escala inteira (pixels sem distorcao), centralizada
    if s > 0.9 then
      s = math.max(1, math.floor(s))
      ox = (size - iw * s) / 2
    end
    lg.setColor(c)
    lg.draw(img, math.floor(x + ox), math.floor(y + ox), 0, s, s)
    return
  end
  I.c = c
  local f = D[id] or D.generic
  lg.push()
  lg.translate(math.floor(x), math.floor(y))
  if scale and scale ~= 1 then lg.scale(scale, scale) end
  lg.setColor(c)
  f(0, 0)
  lg.pop()
  lg.setLineWidth(1)
end

function I.has(id) return D[id] ~= nil or line_for(id) ~= nil end

return I
