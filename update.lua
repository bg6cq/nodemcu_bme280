dofile("config.lua")

url_host = "202.38.64.123"
url_path = "/mqtt/"
mqtt_connected = false

-- blink led every 1s
local ledpin = 4
local ledstatus = 0
gpio.mode(ledpin, gpio.OUTPUT)
gpio.write(ledpin, ledstatus)

function blinkled1s ()
  tmr.alarm(0, 1000, 1, function ()
    if ledstatus == 0 then
      ledstatus = 1
    else
      ledstatus = 0
    end
    gpio.write(ledpin, ledstatus)
  end)
end

function blinkled05s ()
  tmr.alarm(0, 500, 1, function ()
    if ledstatus == 0 then
      ledstatus = 1
    else
      ledstatus = 0
    end
    gpio.write(ledpin, ledstatus)
  end)
end

function mysplit(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t={} ; i=1
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    t[i] = str
    i = i + 1
  end
 return t
end

wifi_connect_event = function(T)
  print("Connection to AP("..T.SSID..") established!")
  print("Waiting for IP address...")
end

wifi_got_ip_event = function(T)
  print("Wifi ready! IP is: "..T.IP)
  if not mqtt_connected then
    print("mqtt try connect to "..mqtt_host..":"..mqtt_port)
    mqtt_connect()
  end
end

wifi_disconnect_event = function(T)
  print("wifi disconnect")
end

function mqtt_connect()
  m:connect(mqtt_host, mqtt_port, 0, function(c)
    print("mqtt online")
    mqtt_connected = true
    if mqtt_update then
      m:subscribe("/cmd/"..node.chipid(),0,function(conn)
        m:publish("/response/"..node.chipid(),"ready" ,0,0)
        print("subscribe to cmd topic")
      end)
    end
  end)
end

function download(name, len)
  print("downloading file "..name.." len="..len)
  blinkled05s()
  file.open("tmp.tmp", "w+")
  payloadFound = false
  conn=net.createConnection(net.TCP)
  conn:on("receive", function(conn, payload)
    if (payloadFound == true) then
      file.write(payload)
      file.flush()
      print("got content len=", #payload)
    else
      if (string.find(payload,"\r\n\r\n") ~= nil) then
        file.write(string.sub(payload,string.find(payload,"\r\n\r\n") + 4))
        file.flush()
        print("got content len=", #payload)
        payloadFound = true
      end
    end
    payload = nil
    collectgarbage()
  end)
  conn:on("disconnection", function(conn)
     conn = nil
     file.close()
     if file.stat("tmp.tmp").size == tonumber(len) then  -- file OK
       file.remove(name)
       fw = file.open(name, "w")
       fd = file.open("tmp.tmp", "r")
       if fd and fw then
         result = fd:read()
         while result ~= nil do
           fw:write(result)
           result = fd:read()
         end
         m:publish("/response/"..node.chipid(),"file "..name.." updated, len="..file.stat(name).size,0,0)
       end
       fd:close()
       fw:close()
       fd = nil
       fw = nil
       file.remove("tmp.tmp")
       collectgarbage()
     else
       m:publish("/response/"..node.chipid(),"size not match, I need "..len..", but got "..file.stat("tmp.tmp").size ,0,0)
     end
     blinkled1s()
  end)
  conn:on("connection", function(conn)
    conn:send("GET /"..url_path.."/"..name.." HTTP/1.0\r\n"..
       "Host: "..url_host.."\r\n"..
       "Connection: close\r\n"..
       "Accept-Charset: utf-8\r\n"..
       "Accept-Encoding: \r\n"..
       "User-Agent: Mozilla/4.0 (compatible; esp8266 Lua; Windows NT 5.1)\r\n"..
       "Accept: */*\r\n\r\n")
    end)
  conn:connect(80,url_host)
end

blinkled1s()
print("init mqtt ESP8266SensorChipID".. node.chipid().." "..mqtt_user.." "..mqtt_password)
m = mqtt.Client("ESP8266SensorChipID" .. node.chipid() .. ")", 180, mqtt_user, mqtt_password)
m:on("message",function(conn, topic, data)
  if data ~= nil then
    print(topic .. ": " .. data)
    if data == "update" then
      print("reboot into update mode")
      file.open("update.txt","w")
      file.close()
      node.restart()
    end
    if data == "restart" then
      node.restart()
    end
    if data == "list" then
      l = file.list();
      for k,v in pairs(l) do
        m:publish("/response/"..node.chipid(),"name:"..k..", size:"..v,0,0)
      end
      l = nil
      collectgarbage()
    end
    d = mysplit(data, " ")
    if d[1] ~= nil and d[2]~= nill then
      download(d[1], d[2])
    end
  end
end)
m:on("offline", function(c)
  print("mqtt offline, try connect to "..mqtt_host..":"..mqtt_port)
  mqtt_connected = false
  mqtt_connect()
end)

wifi.eventmon.register(wifi.eventmon.STA_CONNECTED, wifi_connect_event)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, wifi_got_ip_event)
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, wifi_disconnect_event)

print("My MAC is: "..wifi.sta.getmac())
print("Connecting to WiFi access point...")

wifi.setmode(wifi.STATION)
wifi.sta.config({ssid=wifi_ssid, pwd=wifi_password})
wifi.sta.autoconnect(1)
wifi.sta.connect()
