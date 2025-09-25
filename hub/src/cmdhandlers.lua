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

  Bluecharm Beacon Device Driver - Capability Command handlers

--]]

local log = require "log"
local capabilities = require "st.capabilities"
local cosock = require "cosock"
local socket = require "cosock.socket"          -- just for time
local json = require "dkjson"

local subs = require "subscriptions"


local function handle_refresh(driver, device, command)

  log.info ('Refresh requested')

  if device.device_network_id:find('Master', 1, 'plaintext') then
    creator_device:emit_event(cap_createdev.deviceType(' ', { visibility = { displayed = false } }))
    init_mqtt(device)
  end

end


local function create_device(driver, dtype)

  if dtype then

    local PROFILE = typemeta[dtype].profile
    if PROFILE then
    
      local MFG_NAME = 'SmartThings Community'
      local MODEL = 'Bluecharm_' .. dtype
      local LABEL = 'Bluecharm ' .. dtype
      local ID = 'Bluecharm_' .. dtype .. '_' .. tostring(socket.gettime())

      log.info (string.format('Creating new beacon device: label=<%s>, id=<%s>', LABEL, ID))
      if clearcreatemsg_timer then
        driver:cancel_timer(clearcreatemsg_timer)
      end

      local create_device_msg = {
                                  type = "LAN",
                                  device_network_id = ID,
                                  label = LABEL,
                                  profile = PROFILE,
                                  manufacturer = MFG_NAME,
                                  model = MODEL,
                                  vendor_provided_label = LABEL,
                                }

      assert (driver:try_create_device(create_device_msg), "failed to create device")
    end
  end
end


local function handle_createdevice(driver, device, command)

  if command.args.value and (command.args.value ~= ' ') then
    log.debug("Device type selection: ", command.args.value)

    if typemeta[command.args.value].supported then

      device:emit_event(cap_createdev.deviceType('Creating device...'))

      create_device(driver, command.args.value)
    else
      
      device:emit_event(cap_createdev.deviceType('Not Supported'))
      driver:call_with_delay(3, function()
          device:emit_event(cap_createdev.deviceType(' ', { visibility = { displayed = false }}))
        end, 'Clear msg')
    end
      
  end
end


return  {
          handle_refresh = handle_refresh,
          handle_createdevice = handle_createdevice,
        }
        
