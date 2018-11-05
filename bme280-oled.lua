dofile("config.lua")

mqtt_connected = false
count = 0
temp = 0
humi = 0
press = 0
rssi = 0

local ledpin = 4
gpio.mode(ledpin, gpio.OUTPUT)
gpio.write(ledpin, 1)

i2c.setup(0, sda, scl, i2c.SLOW) -- call i2c.setup() only once
bme280.setup()

disp = u8g2.ssd1306_i2c_128x64_noname(0, 0x3c)
disp:setFont(u8g2.font_unifont_t_symbols)
disp:setFontRefHeightExtendedText()
disp:setDrawColor(1)
disp:setFontPosTop()
disp:setFontDirection(0)

function blinkled(t)
  if not flash_led then
    return
  end
  gpio.write(ledpin, 0)
  tmr.alarm(0, t, 0, function ()
    gpio.write(ledpin, 1)
  end)
end

function mqtt_connect()
  m:connect(mqtt_host, mqtt_port, 0, function(c)
    mqtt_connected = true
    print("mqtt online")
    if mqtt_update then
      m:subscribe("/cmd/"..node.chipid(),0,function(conn)
        print("subscribe to cmd topic")
      end)
    end
  end)
end

wifi_connect_event = function(T)
  print("AP("..T.SSID..") connected!")
end

wifi_got_ip_event = function(T)
  print("IP is: "..T.IP)
  if (send_mqtt and not mqtt_connected) then
    print("mqtt try connect to "..mqtt_host..":"..mqtt_port)
    mqtt_connect()
  end
end

wifi_disconnect_event = function(T)
  print("wifi disc")  
end

function updatedisplay()
  disp:clearBuffer()
  disp:drawStr(1, 1, "BME280    BG6CQ")
  disp:drawStr(1, 16, "Temp: "..string.format("%.1f", temp).."C")
  disp:drawStr(1, 31, "Humi: "..string.format("%.1f", humi).."%")
  disp:drawStr(1, 47, "Press:"..string.format("%.1f", press/10.0).."mpar")
  disp:sendBuffer()
end

laststr = '|/-\\'
last_index = 1
function updateprogress()
  last_index = last_index + 1
  if last_index == 5 then
     last_index = 1
  end
  disp:drawStr( 60, 1, laststr.sub(laststr, last_index,1))
  disp:sendBuffer()
end

function send_data()
  if send_aprs then
    print("aprs send "..aprs_host)
    str = aprs_prefix.."000/000g000t"..string.format("%03d", temp*9/5+32).."r000p000h"..string.format("%02d",humi).."b"..string.format("%05d", press)
    str = str.."ESP8266 MAC "..wifi.sta.getmac().." RSSI: "..rssi
    print(str)
    conn = net.createUDPSocket()
    conn:send(aprs_port,aprs_host,str)
    conn:close()
    data_send = true
  end
  if send_http then
    req_url = http_url.."?mac="..wifi.sta.getmac().."&"..string.format("temp=%.1f&humi=%.1f&press=%.2f&rssi=%d",temp,humi,press,rssi)
    print("http send "..req_url)
    http.get(req_url, nil, function(code, data)
      if code < 0 then
        print("HTTP req err")
      else
        print(code, data)
        data_send = true
      end
    end)
  end
end

read_error = 0
wifi_error = 0

function func_read_bme280()
  count = count + 1
  if count*3 >= send_interval then
    count = 0
  end
  P, T = bme280.baro()
  H, T = bme280.humi()
  if P == nil or H == nil then
    print("bme280 read error")
    read_error = read_error + 1
    if read_error > 100 then
      node.restart()
    end
    return
  end
  press = P / 100
  temp = T / 100
  humi = H / 1000
  updatedisplay()
  if wifi.sta.status() ~= 5 then
    wifi_error = wifi_error + 1
    if wifi_error > 200 then
      node.restart()
    end
    print("wifi not ready")
    blinkled(100)
    return
  end

  rssi = wifi.sta.getrssi()
  if rssi == nil then
    rssi = -100
  end
  data_send = false
  print("read count="..string.format("%d: t=%.1f, h=%.1f, p=%.1f, rssi=%d, uptime=%d",
    count,temp,humi,press,rssi,tmr.time()))
  if mqtt_connected then
    print("mqtt publish")
    m:publish(mqtt_topic, string.format("{\"temperature\": %.1f, \"humidity\": %.1f, \"press\": %.1f, \"rssi\": %d, \"uptime\": %d}",
      temp, humi, press, rssi, tmr.time()),0,0)
    data_send = true
  elseif send_mqtt then
    print("mqtt try connect to "..mqtt_host..":"..mqtt_port)
    mqtt_connect()
  end

  if count == 4 then
    send_data()
  end
  if data_send then
    wifi_error = 0
    updateprogress()
    blinkled(500)
  else
    wifi_error = wifi_error + 1
    if wifi_error > 200 then
      node.restart()
    end
    blinkled(100)
  end
end

if send_interval < 15 then
  send_interval = 15
elseif send_interval > 300 then
  send_interval = 300
end

if send_mqtt then
  print("init mqtt ChipID"..node.chipid().." "..mqtt_user.." "..mqtt_password)
  _, reset_reason = node.bootreason()
  if reset_reason == nil then reset_reason = 255 end
  m = mqtt.Client("ESP8266Sensor_"..node.chipid()..string.format("_%d",reset_reason),180,mqtt_user,mqtt_password)
  if mqtt_update then
    m:on("message",function(conn, topic, data)
      if data ~= nil then
        print(topic .. ": " .. data)
        if data == "update" then
           print("reboot into update mode")
           file.open("update.txt","w")
           file.close()
           node.restart()
        end
      end
    end)
  end
  m:on("offline", function(c)
    print("mqtt offline, try connect to "..mqtt_host..":"..mqtt_port)
    mqtt_connected = false
    mqtt_connect()
  end)
end

print("My MAC is: "..wifi.sta.getmac())
print("Trying AP...")

wifi.eventmon.register(wifi.eventmon.STA_CONNECTED, wifi_connect_event)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, wifi_got_ip_event)
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, wifi_disconnect_event)
wifi.setmode(wifi.STATION)
wifi.sta.config({ssid=wifi_ssid, pwd=wifi_password})
wifi.sta.autoconnect(1)
wifi.sta.connect()

flashkeypressed = false
function flashkeypress()
  if flashkeypressed then
    return
  end
  flashkeypressed = true
  print("flash key pressed, boot into config mode")
  file.open("flashkey.txt","w")
  file.close()
end

gpio.mode(3, gpio.INPUT, gpio.PULLUP)
gpio.trig(3, "low", flashkeypress)

tmr.alarm(1,3000,tmr.ALARM_AUTO,func_read_bme280)
