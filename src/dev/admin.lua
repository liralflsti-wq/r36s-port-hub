-- =============================================================================
--  Modo administrador (SO no pacote de teste: tools/build.sh --admin)
--  O build normal exclui a pasta dev/, entao a versao publica nunca tem isto.
--  Na abertura do hub: libera todas as conquistas da temporada (sem 27
--  comemoracoes seguidas), deixa a carta final "Lenda" comemorar uma vez
--   e avisa que o modo administrador esta ativo.
--  A gravacao continua assinada com o ID deste console, como sempre.
-- =============================================================================
local Adm = {}

function Adm.run()
  local A = require("core.achievements")
  local missing = 0
  for _, d in ipairs(A.DEFS) do
    if not d.final and not d.id:match("^demo_") and not A.unlocked(d.id) then missing = missing + 1 end
  end
  if missing > 0 then
    local P = require("ui.achv_popup")
    local show = P.show
    P.show = function() end
    for _, d in ipairs(A.DEFS) do
      if not d.final and not d.id:match("^demo_") then A.unlock(d.id) end
    end
    P.show = show
    A.check_final()   -- "Lenda": comemora uma vez
  end
  pcall(function() App.toast("Modo administrador: tudo liberado para teste", "ok") end)
end

return Adm
