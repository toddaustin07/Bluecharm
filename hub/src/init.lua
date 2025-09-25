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

  Driver to support Bluecharm/Bluetooth beacon reporting through MQTT broker
  
--]]

-- Edge libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local cosock = require "cosock"
local socket = require "cosock.socket"          -- just for time
local log = require "log"

local procmsg = require "procmessages"
local sub = require "subscriptions"
local cmd = require "cmdhandlers"
local mqtt = require "mqtt"
local utils = require "utility"

local presencetimers = {}

-- Global variables
thisDriver = {}               -- used in the MQTT client module: TODO- pass it in at initialization
DEVICE_SUB_TOPICS = {}        -- store list of MQTT topics needed to be subscribed-to for each device
SUBSCRIBED_TOPICS = {}        -- store list of subscribed topics for each device
client = nil                  -- MQTT broker client object
client_reset_inprogress = false
creator_device = {}           -- master device object
deviceid = {}                 -- stores uuid possibilities + dmac for each device
lastseen =  {}

typemeta =  {
              ['BCU1']         = { ['supported'] = false,   ['profile'] = 'bcu1_v1',       ['created'] = 0, },
              ['BCU1Pro']      = { ['supported'] = false,   ['profile'] = 'bcu1pro_v1',    ['created'] = 0, },
              ['BC04P']        = { ['supported'] = false,   ['profile'] = 'bc04p_v1',      ['created'] = 0, },
              ['BC05']         = { ['supported'] = false,   ['profile'] = 'bc05_v1',       ['created'] = 0, },
              ['BCS1']         = { ['supported'] = false,   ['profile'] = 'bcs1_v1',       ['created'] = 0, },
              ['BC011']        = { ['supported'] = false,   ['profile'] = 'bc011_v1',      ['created'] = 0, },
              ['BC011Pro']     = { ['supported'] = false,   ['profile'] = 'bc011pro_v1',   ['created'] = 0, },
              ['BCB2']         = { ['supported'] = false,   ['profile'] = 'bcb2multi_v1',  ['created'] = 0, },
              ['BC021']        = { ['supported'] = true,    ['profile'] = 'bc021_v1',      ['created'] = 0, },
              ['BC021Pro']     = { ['supported'] = true,    ['profile'] = 'bc021_v1',      ['created'] = 0, },
              ['BC08']         = { ['supported'] = false,   ['profile'] = 'bc08_v1',       ['created'] = 0, },
              ['BC037']        = { ['supported'] = false,   ['profile'] = 'bc037_v1',      ['created'] = 0, },
              ['BC061']        = { ['supported'] = false,   ['profile'] = 'bc061_v1',      ['created'] = 0, },
              ['BC063']        = { ['supported'] = false,   ['profile'] = 'bc063_v1',      ['created'] = 0, },
              ['BC068']        = { ['supported'] = false,   ['profile'] = 'bc068_v1',      ['created'] = 0, },
              ['BC052']        = { ['supported'] = false,   ['profile'] = 'bc052_v1',      ['created'] = 0, },
              ['BC052SA']      = { ['supported'] = false,   ['profile'] = 'bc052sa_v1',    ['created'] = 0, },
            }

-- Module variables

local initialized = false
local clearcreatemsg_timer
local shutdown_requested = false

local MASTERPROFILE = 'bccreator_v1'
local MASTERLABEL = 'Bluecharm MQTT'

local CREATECAPID  = 'partyvoice23922.createbcv1'

-- Custom Capabilities
cap_createdev = capabilities[CREATECAPID]

cap_status = capabilities["partyvoice23922.status"]
cap_refresh = capabilities["partyvoice23922.refresh"]


local function schedule_subscribe()

  if client then
    sub.subscribe_all()
  else
    log.warn('Broker not yet connected')
    thisDriver:call_with_delay(2, schedule_subscribe)
  end
end


local function create_MQTT_client(device)

  local connect_args = {}
  connect_args.uri = device.preferences.broker
  connect_args.clean = true
  
  if device.preferences.userid ~= '' and device.preferences.password ~= '' then
    if device.preferences.userid ~= 'xxxxx' and device.preferences.password ~= 'xxxxx' then
      connect_args.username = device.preferences.userid
      connect_args.password = device.preferences.password
    end
  end

  SUBSCRIBED_TOPICS = {}

  -- create mqtt client
  client = mqtt.client(connect_args)

  client:on{
    connect = function(connack)
      if connack.rc ~= 0 then
        log.error ("connection to broker failed:", connack:reason_string(), connack)
        device:emit_event(cap_status.status('Failed to Connect to Broker'))
        client = nil
        return
      end
      log.info("Connected to MQTT broker:", connack) -- successful connection
      device:emit_event(cap_status.status('Connected to Broker'))
      client_reset_inprogress = false
      thisDriver:call_with_delay(1, schedule_subscribe)
    end,

    message = function(msg)
      assert(client:acknowledge(msg))

      procmsg.process_message(msg.topic, msg.payload)

    end,

    error = function(err)
      log.error("MQTT client error:", err)
      client = nil
    end,
  }

  return client

end


function init_mqtt(device)

  if client_reset_inprogress == true then; return; end
  
  if device == nil then; device = creator_device; end       -- needed if invoked via driver:call_with_delay() method

  if device.preferences.broker == '192.168.1.xxx' or
     device.preferences.userid == 'xxxxx' or
     device.preferences.password == 'xxxxx' then

      log.warn ('Device settings not yet initialized')
      return
  end

  device:emit_event(cap_status.status('Connecting...'))
  
  -- If already connected, then unsubscribe all and shutdown
  if client then
    log.debug ('Unsubscribing all and disconnecting current client...')
    
    sub.unsubscribe_all()

    local rc, err = client:disconnect()
    if rc == false then
      log.error ('\tDisconnect failed with err:', err)
    elseif rc == true then
      log.debug ('\tDisconnected from broker')
    end
  end

  client = create_MQTT_client(device)

  if client and (device:get_field('client_thread') ~= true) then
  
  -- Run MQTT loop in separate thread

    cosock.spawn(function()
      device:set_field('client_thread', true)
      
      while true do
        local ok, err = mqtt.run_sync(client)
        client = nil
        if ok == false then
          log.warn ('MQTT run_sync returned: ', err)
          if shutdown_requested == true then
            device:emit_event(cap_status.status('Driver shutdown'))
            return
          end
          if string.lower(err):find('connection refused', 1, 'plaintext') or (err == "closed") or 
             string.lower(err):find('no route to host', 1, 'plaintext') then
            device:emit_event(cap_status.status('Reconnecting...'))
            client_reset_inprogress = true
            -- pause, then try to create new mqtt client
            cosock.socket.sleep(15)
            log.info ('Attempting to reconnect to broker...')
            client = create_MQTT_client(device)
          else
            break
          end
        else
          log.error ('Unexpected return from MQTT client:', ok, err)
        end
      end
      
      device:set_field('client_thread', false)
    end, 'MQTT synch mode')

    
  elseif client == nil then
    log.error ('Create MQTT Client failed')
    thisDriver:call_with_delay(15, init_mqtt)
  end
end


-- This function run periodicly to check when last beacon was received
local function presencecheck(device)

  local currtime = socket.gettime()
  local elapsed = socket.gettime() - lastseen[device.device_network_id]
  log.info('PERIODIC CHECK:  Seconds since last reported presence: ', math.floor(elapsed * 10 + 0.5) / 10)

  if device.state_cache.main.presenceSensor.presence.value == 'present' then
    if elapsed > device.preferences.notpresenttimeout then
      -- Device not present for longer than configured wait time
      device:emit_event(capabilities.presenceSensor.presence('not present'))
    end
  end

end


local function store_uuids(device)

  local uuid = device.preferences.uuid:gsub("[:-]", "")
    
  local uuid_motion = utils.incrementHexSmall(uuid,1)  
    
  local uuid_button_single = incrementHexSmall(uuid,5)
  local uuid_button_double = incrementHexSmall(uuid,6)
  local uuid_button_triple = incrementHexSmall(uuid,7)
  local uuid_button_long   = incrementHexSmall(uuid,8)

  deviceid[device.device_network_id] = { ['dmac'] = device.preferences.dmac:gsub("[:-]", ""),
                                         ['uuid'] = uuid,
                                         ['uuid_motion'] =  uuid_motion,
                                         ['uuid_button_single'] = uuid_button_single,
                                         ['uuid_button_double'] = uuid_button_double,
                                         ['uuid_button_triple'] = uuid_button_triple,
                                         ['uuid_button_long']   = uuid_button_long }
end


local function store_topics(device)

  if (device.preferences.subTopic ~= nil) and (device.preferences.gmacs ~= nil) then
    
    DEVICE_SUB_TOPICS[device.id] = {}
    for item in string.gmatch(device.preferences.gmacs, "([^,]+)") do
     
      table.insert(DEVICE_SUB_TOPICS[device.id], 
          string.format('%s/%s', device.preferences.subTopic, item:match("^%s*(.-)%s*$"):gsub("[:%-]", "")))
    end

    log.debug('Stored subscribe topics')
    utils.disptable(DEVICE_SUB_TOPICS, '  ', 3)
  end
end


local function init_attributes(device)

  if device:supports_capability_by_id('presenceSensor') then
    device:emit_event(capabilities.presenceSensor.presence('not present'))
  end
    
  if device:supports_capability_by_id('motionSensor') then
    device:emit_event(capabilities.motionSensor.motion('inactive'))
  end
  
  if device:supports_capability_by_id('button') then
    local supported_values =  {
                                  capabilities.button.button.pushed.NAME,
                                  capabilities.button.button.held.NAME,
                                  capabilities.button.button.double.NAME,
                                  capabilities.button.button.pushed_3x.NAME,
                                }
     device:emit_event(capabilities.button.supportedButtonValues(supported_values))
  end
  
  if device:supports_capability_by_id('battery') then
    device:emit_event(capabilities.battery.battery(0))
  end
  
  if device:supports_capability_by_id('signalStrength') then
    device:emit_event(capabilities.signalStrength.rssi(0))
    device:emit_event(capabilities.signalStrength.lqi(0))
  end
  
  if device:supports_capability_by_id('temperatureMeasurement') then
    device:emit_event(capabilities.temperatureMeasurement.temperature({value=20, unit='C'}))
  end
  
  if device:supports_capability_by_id('relativeHumidityMeasurement') then
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity(0))
  end
  
  if device:supports_capability_by_id('contactSensor') then
     device:emit_event(capabilities.contactSensor.water('open'))
  end

end

------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------

-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)

  log.debug(device.id .. ": " .. device.device_network_id .. "> INITIALIZING")
  
  if device.device_network_id:find('Master', 1, 'plaintext') then
  
    creator_device = device
    
    device:emit_event(cap_createdev.deviceType(' '))
    device:emit_event(cap_status.status('Not Connected'))
    
    initialized = true
    device:set_field('client_thread', false)
    init_mqtt(device)

  else  -- init beacon devices
      device:emit_event(cap_status.status('Not Subscribed'))
      lastseen[device.device_network_id] = socket.gettime()
      lastbutton[device.device_network_id] = 0
      lastmotion[device.device_network_id] = 0
      
      store_uuids(device)
      store_topics(device)
      
      -- Start periodic check for beacon device presence
      presencetimers[device.device_network_id] = driver:call_on_schedule(device.preferences.notpresenttimeout*.75, function()
          presencecheck(device)
        end, 'Periodic check')
  end
  
end


-- Called when device was just created in SmartThings
local function device_added (driver, device)

  log.info(device.id .. ": " .. device.device_network_id .. "> ADDED")

  if not device.device_network_id:find('Master', 1, 'plaintext') then

    init_attributes(device)

    creator_device:emit_event(cap_createdev.deviceType('Device created'))
    
    clearcreatemsg_timer = driver:call_with_delay(10, function()
        clearcreatemsg_timer = nil
        creator_device:emit_event(cap_createdev.deviceType(' ', { visibility = { displayed = false }}))
      end
    )

  end
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  log.info ('Device doConfigure lifecycle invoked')

end


-- Called when device was deleted via mobile app
local function device_removed(driver, device)

  log.warn(device.id .. ": " .. device.device_network_id .. "> removed")

  if not device.device_network_id:find('Master', 1, 'plaintext') then
    local topiclist = sub.get_subscribed_topics_for_device(device)

    if #topiclist > 0 then
      for _, topic in ipairs(topiclist) do
        sub.unsubscribe(topic, device.id)
      end
    end
    
    driver:cancel_timer(presencetimers[device.device_network_id])
    deviceid[device.device_network_id] = nil
    
  else
    if client then
      sub.unsubscribe_all()
      shutdown_requested = true
      client:disconnect()
    end
    initialized = false
  end

  local devicelist = driver:get_devices()

  if #devicelist == 0 then
    if client then
      shutdown_requested = true
      client:disconnect()
    end
  end

end


local function handler_driverchanged(driver, device, event, args)

  log.debug ('*** Driver changed handler invoked ***')

end


local function shutdown_handler(driver, event)

  log.info ('*** Driver being shut down ***')

  if client then

    --sub.unsubscribe_all()

    shutdown_requested = true
    client:disconnect()
    creator_device:emit_event(cap_status.status('Driver Shutdown'))
    log.info("Disconnected from MQTT broker")
  end

end


local function handler_infochanged (driver, device, event, args)

  log.debug ('Info changed handler invoked')

  -- Did preferences change?
  if args.old_st_store.preferences then

    if device.device_network_id:find('Master', 1, 'plaintext') then

      -- Creator device preferences
      local ip_changed = false
      local uname_changed = false
      local pw_changed = false

      if args.old_st_store.preferences.userid ~= device.preferences.userid then
        uname_changed = true
      elseif args.old_st_store.preferences.password ~= device.preferences.password then
        pw_changed = true
      elseif args.old_st_store.preferences.broker ~= device.preferences.broker then
        log.info ('Broker URI changed to: ', device.preferences.broker)
        ip_changed = true
      end
      
      if ip_changed or uname_changed or pw_changed then
        if device.preferences.broker ~= '192.168.1.xxx' then
          init_mqtt(device)
        end
      end

    -- Beacon device preferences
    else
      if args.old_st_store.preferences.subTopic ~= device.preferences.subTopic or
         args.old_st_store.preferences.gmacs ~= device.preferences.gmacs then
         
        log.info ('Subscription preferences changed to: ')
        log.info (device.preferences.subTopic)
        log.info (device.preferences.gmacs)
        
        sub.unsubscribe_all_topics_for_device(device)
        device:emit_event(cap_status.status('Un-Subscribed'))
        
        store_topics(device)
        sub.subscribe_all_topics_for_device(device)
        
      elseif args.old_st_store.preferences.notpresenttimeout ~= device.preferences.notpresenttimeout then
        thisDriver:cancel_timer(presencetimers[device.device_network_id])
        presencetimers[device.device_network_id] = driver:call_on_schedule(device.preferences.notpresenttimeout*.75, function()
            presencecheck(device)
          end, 'Periodic check')
      
      elseif (args.old_st_store.preferences.dmac ~= device.preferences.dmac) or
             (args.old_st_store.preferences.uuid ~= device.preferences.uuid) then
        store_uuids(device)
      end
    end
  end
end


-- Create Primary Creator Device
local function discovery_handler(driver, _, should_continue)

  if not initialized then

    log.info("Creating Bluecharm Creator device")

    local MFG_NAME = 'SmartThings Community'
    local MODEL = 'BCCreatorV1'
    local VEND_LABEL = MASTERLABEL           --update; change for testing
    local ID = 'BCDev_Masterv1'               --change for testing
    local PROFILE = MASTERPROFILE           --update; change for testing

    -- Create master creator device

    local create_device_msg = {
                                type = "LAN",
                                device_network_id = ID,
                                label = VEND_LABEL,
                                profile = PROFILE,
                                manufacturer = MFG_NAME,
                                model = MODEL,
                                vendor_provided_label = VEND_LABEL,
                              }

    assert (driver:try_create_device(create_device_msg), "failed to create creator device")

    log.debug("Exiting device creation")

  else
    log.info ('Bluecharm Creator device already created')
  end
end


-----------------------------------------------------------------------
--        DRIVER MAINLINE: Build driver context table
-----------------------------------------------------------------------
thisDriver = Driver("Bluecharm Beacon Devices", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = handler_driverchanged,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  driver_lifecycle = shutdown_handler,
  capability_handlers = {
    [cap_createdev.ID] = {
      [cap_createdev.commands.setDeviceType.NAME] = cmd.handle_createdevice,
    },
    [cap_refresh.ID] = {
      [cap_refresh.commands.push.NAME] = cmd.handle_refresh,
    },
  }
})

log.info ('Bluecharm Beacon Device Driver V0.9 Started')

thisDriver:run()
