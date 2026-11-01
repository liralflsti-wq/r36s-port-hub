function love.conf(t)
  t.identity = "r36sporthub"
  t.version = "11.5"
  t.window.title = "R36S PORT HUB"
  t.window.width = 0
  t.window.height = 0
  t.window.fullscreen = true
  t.window.resizable = false
  t.window.vsync = 1
  t.modules.joystick = true
  t.modules.audio = true
  t.modules.sound = true
  t.modules.physics = false
  t.modules.video = false
  t.modules.mouse = true
  t.modules.touch = false

  -- Testes no PC: PORTHUB_WINDOWED=1 abre uma janela 640x480
  if os.getenv("PORTHUB_WINDOWED") then
    t.window.width = 640
    t.window.height = 480
    t.window.fullscreen = false
  end
end
