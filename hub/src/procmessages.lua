--[[
  Copyright 2025 Todd Austin

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION

  Bluecharm Beacon Device Driver - handles all MQTT message received for each device type

--]]

local log = require "log"
local capabilities = require "st.capabilities"
local json = require "dkjson"
local stutils = require "st.utils"
local socket = require "cosock.socket"          -- just for time

local sub = require "subscriptions"
local utils = require "utility"
local uuid = {}
lastbutton = {}
lastmotion = {}

local TYPE_TLM = 8
local TYPE_IBEACON = 4
local TYPE_KSENSOR = 1
local COOLDOWN_BUTTON = 30
local COOLDOWN_MOTION = 30

local function process_message(topic, msg)

  --log.debug (string.format("\tFrom topic: %s", topic))
  --log.debug (string.format("Processing received data msg: %s", msg))

  local jsonmsg, pos, err = json.decode (msg, 1, nil)

  if not jsonmsg then
    if err then
      log.error (string.format('JSON decode error: %s', err))
    end
    return
  end
  
  if jsonmsg.obj == nil then
    -- This is probably just a Gateway alive message, so ignore
    return
  end

  local devicelist = sub.get_subscribed_devices_for_topic(topic)

  if #devicelist > 0 then

    for _, device in ipairs(devicelist) do

       -- Traverse the advertisement records in the message
      local gmac = jsonmsg.gmac
      for _, advert in ipairs(jsonmsg.obj) do
        --log.debug ('Advert record for dmac:', advert.dmac)
        if advert.dmac == deviceid[device.device_network_id].dmac then
          log.debug (string.format('Type %d advert received for %s from %s', advert.type,device.label, gmac))
          --utils.disptable(advert, '  ', 8)
          
          if ((advert.type == TYPE_IBEACON) or (advert.type == TYPE_TLM)) then
            -- beacon device is present
            if device.state_cache.main.presenceSensor.presence.value ~= 'present' then
              device:emit_event(capabilities.presenceSensor.presence('present'))
            end
            
            lastseen[device.device_network_id] = socket.gettime()

          end
          
          if advert.type == TYPE_IBEACON then
          
            -- Handle motion adverts
            if advert.uuid == deviceid[device.device_network_id].uuid_motion then
            
              local lastactive = lastmotion[device.device_network_id]
              local currtime = socket.gettime()
              
              if currtime > lastactive + COOLDOWN_MOTION then
            
                device:emit_event(capabilities.motionSensor.motion.active())
                lastmotion[device.device_network_id] = currtime
                
                thisDriver:call_with_delay(10, function()
                    device:emit_event(capabilities.motionSensor.motion.inactive())
                  end, 'Auto motion terminate')
              end
              
            -- Handle button adverts
            elseif advert.uuid == deviceid[device.device_network_id].uuid_button_single or
                   advert.uuid == deviceid[device.device_network_id].uuid_button_double or
                   advert.uuid == deviceid[device.device_network_id].uuid_button_triple or 
                   advert.uuid == deviceid[device.device_network_id].uuid_button_long then
            
              local lastpushed = lastbutton[device.device_network_id]
              local currtime = socket.gettime()
              
              if currtime > lastpushed + COOLDOWN_BUTTON then
            
                lastbutton[device.device_network_id] = currtime
            
                if advert.uuid == deviceid[device.device_network_id].uuid_button_single then
                  device:emit_event(capabilities.button.button.pushed({state_change = true}))
                  
                elseif advert.uuid == deviceid[device.device_network_id].uuid_button_double then
                  device:emit_event(capabilities.button.button.double({state_change = true}))  
                  
                elseif advert.uuid == deviceid[device.device_network_id].uuid_button_triple then
                  device:emit_event(capabilities.button.button.pushed_3x({state_change = true}))
                  
                elseif advert.uuid == deviceid[device.device_network_id].uuid_button_long then
                  device:emit_event(capabilities.button.button.held({state_change = true}))
                end
              end
            end
          end
                    
          if advert.type == TYPE_TLM then
            
            if advert.vbatt ~= nil then
              local battpercent = utils.batteryPercentCR2032(advert.vbatt)
              if device.state_cache.main.battery.battery.value ~= battpercent then
                device:emit_event(capabilities.battery.battery(battpercent))
              end
            end
            if advert.temp ~= nil then
              if device.state_cache.main.temperatureMeasurement.temperature.value ~= advert.temp then
                device:emit_event(capabilities.temperatureMeasurement.temperature({value=advert.temp, unit='C'}))
              end
            end
            if advert.rssi ~= nil then
              if device.state_cache.main.signalStrength.rssi.value ~= advert.rssi then
                device:emit_event(capabilities.signalStrength.rssi(advert.rssi))
              end
            end
            -- TODO:  add code for additional sensor data (humidity, contact, etc)
            --device:emit_event(capabilities.contactSensor.contact.open())
            --device:emit_event(capabilities.relativeHumidityMeasurement.humidity(value))  
          end
        end
          
      end -- next advert
    end -- next device
    
  end
end

return	{
					process_message = process_message
				}
