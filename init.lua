if file.exists("update.txt") then
  -- enter update mode
  file.remove("update.txt")
  print("go into update mode")
  dofile("update.lua")
elseif file.exists("config.lua") and (not file.exists("flashkey.txt")) then
  print("normal startup")
  tmr.alarm(1,3000,0,function()
    dofile("bme280.lua")
  end)
else
  -- enter setup mode
  print("go in setup mode")
  file.remove("flashkey.txt")
  dofile("setup.lua")
end
