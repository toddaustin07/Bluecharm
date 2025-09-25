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

  MQTT Device Driver - Subscriptions-related Functions

--]]

local log = require "log"
local utils = require "utility"


local function fetch_device(deviceid)

  local devicelist = thisDriver:get_devices()
  local targetlist = {}

  for _, device in ipairs(devicelist) do

    if device.id == deviceid then
      return device

    end
  end
  
end


local function get_subscribed_devices_for_topic(targettopic)

  local topicdevicelist = {}
  local devicelist = thisDriver:get_devices()

  if SUBSCRIBED_TOPICS[targettopic] then

    for _, deviceid in ipairs(SUBSCRIBED_TOPICS[targettopic].devices) do
        
      for _, device in ipairs(devicelist) do
        if device.id == deviceid then
          table.insert(topicdevicelist, device)
        end
      end
        
    end
  end
  
  return topicdevicelist

end


local function is_topic_subscribed(qtopic)

  if SUBSCRIBED_TOPICS[qtopic] then
    return true
  else
    return false
  end
end

local function is_device_subscribed(device, qtopic)

  local foundflag = false

  if SUBSCRIBED_TOPICS[qtopic] then

    for _, deviceid in ipairs(SUBSCRIBED_TOPICS[qtopic].devices) do
      if device.id == deviceid then
        foundflag = true
      end  
    end
  end
  
  return foundflag

end

local function get_subscribed_topics_for_device(device)

  local topiclist = {}
  local foundflag = false

  for topic, data in pairs(SUBSCRIBED_TOPICS) do
    for _, deviceid in ipairs(data.devices) do
      if deviceid == device.id then
        foundflag = true
      end
    end
   
    if foundflag then     
      table.insert(topiclist, topic)
    end
    foundflag = false
      
  end
    
  return topiclist
  
end


local function remove_device_from_subscriptions(topic, deviceid)

  if SUBSCRIBED_TOPICS[topic] then
  
    for i, id in ipairs(SUBSCRIBED_TOPICS[topic].devices) do
    
      if id == deviceid then
        table.remove(SUBSCRIBED_TOPICS[topic].devices, i)
        
        -- if no more devices, remove topic from the subscribed list
        if #SUBSCRIBED_TOPICS[topic].devices == 0 then
          SUBSCRIBED_TOPICS[topic] = nil
        end
        return
      end
    end
    
  else
    log.warn('Topic not found in SUBSCRIBED_TOPICS')
  end
    
end


local function subscribe_topic(device, subTopic)

  --SUBSCRIBED_TOPICS[subTopic] = { ['devices'] = {} }
  --table.insert(SUBSCRIBED_TOPICS[subTopic].devices, device.id)

  if is_topic_subscribed(subTopic) then
    log.debug ('Already subscribed to topic', subTopic)
    device:emit_event(cap_status.status('Subscribed'))
    if is_device_subscribed(device, subTopic) == false then
      table.insert(SUBSCRIBED_TOPICS[subTopic].devices, device.id)
    end
    
  else
    assert(client:subscribe{ topic=subTopic, qos=1, callback=function(suback)
      log.info(string.format("Subscribed to %s: %s", subTopic, suback))
      
      device:emit_event(cap_status.status('Subscribed'))
      SUBSCRIBED_TOPICS[subTopic] = { ['devices'] = {} }
      table.insert(SUBSCRIBED_TOPICS[subTopic].devices, device.id)
      
      log.debug('Post subscribe - SUBSCRIBED_TOPICS:')
      utils.disptable(SUBSCRIBED_TOPICS, '  ', 4)
      
    end})
  end

end


local function subscribe_all_topics_for_device(device)

  if DEVICE_SUB_TOPICS[device.id] then

    local topiclist = DEVICE_SUB_TOPICS[device.id]
    
    for _, topic in ipairs(topiclist) do
        subscribe_topic(device, topic)
    end
    
  else
    log.debug('No device entry in DEVICE_SUB_TOPICS', device.label)
  end

end


local function subscribe_all()

  local devicelist = thisDriver:get_devices()
  local delayval = 0
  
  for _, device in ipairs(devicelist) do
    if not device.device_network_id:find('Master', 1, 'plaintext') then
    
      if DEVICE_SUB_TOPICS[device.id] then
        thisDriver:call_with_delay(delayval, function()
            subscribe_all_topics_for_device(device)
          end)
        delayval = delayval + 1
        
      else
        log.error('No device entry in DEVICE_SUB_TOPICS')
      end
    end
  end
end


local function unsubscribe(topic, deviceid)   -- called without a deviceid will delete topic altogether

  if deviceid then
    remove_device_from_subscriptions(topic, deviceid)
  else
    SUBSCRIBED_TOPICS[topic] = nil
  end

  local numleft = 0
  if SUBSCRIBED_TOPICS[topic] then
    numleft = #SUBSCRIBED_TOPICS[topic].devices
  end
  log.debug('unsubscribe: devices left using topic', numleft)
  
  if numleft == 0 then      -- unsubscribe only if no more devices using this topic

    local rc, err = client:unsubscribe{ topic=topic, callback=function(unsuback)
          log.info("\t\tUnsubscribe callback:", unsuback)
      end}
      
    if rc == false then
      log.debug ('\tUnsubscribe failed with err:', err)
    else
      log.debug (string.format('\tUnsubscribed from %s', topic))
     
    end
  else
    log.debug (string.format('Subscription to <%s> still in use by another device', topic))
  end
  
  log.debug('Post UNsubscribe - SUBSCRIBED_TOPICS:')
  utils.disptable(SUBSCRIBED_TOPICS, '  ', 4)
  
end


local function unsubscribe_all_topics_for_device(device)

  local topiclist = get_subscribed_topics_for_device(device)
  
  log.debug('Unsubscribing all topics for device', device.label)
  utils.disptable(topiclist, '  ', 3)
  
  for _, topic in ipairs(topiclist) do
    unsubscribe(topic, device.id)
  end

end


local function unsubscribe_all()

  for topic, _ in pairs(SUBSCRIBED_TOPICS) do
    unsubscribe(topic)
  end

  SUBSCRIBED_TOPICS = {}

end


local function mqtt_subscribe(device)

  log.debug ('mqtt_subscribe: No action taken')

--[[
  if client then

    local id, topic = get_subscribed_topic_for_device(device)

    if topic then
      log.debug (string.format('Unsubscribing device <%s> from %s', device.label, topic))
      unsubscribe(id, topic)
    end

    subscribe_topic(device)
  end
--]]
end


return	{
          get_subscribed_devices_for_topic = get_subscribed_devices_for_topic,
          get_subscribed_topics_for_device = get_subscribed_topics_for_device,
          subscribe_topic = subscribe_topic,
          subscribe_all_topics_for_device = subscribe_all_topics_for_device,
          subscribe_all = subscribe_all,
          unsubscribe = unsubscribe,
          unsubscribe_all_topics_for_device = unsubscribe_all_topics_for_device,
					unsubscribe_all = unsubscribe_all,
          mqtt_subscribe = mqtt_subscribe,
				}
