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

  Bluecharm Gateway Device Driver - Utility functions

--]]

local log = require "log"

local function disptable(table, tab, maxlevels, currlevel)

	if not currlevel then; currlevel = 0; end
  currlevel = currlevel + 1
  for key, value in pairs(table) do
    if type(key) ~= 'table' then
      log.debug (tab .. '  ' .. key, value)
    else
      log.debug (tab .. '  ', key, value)
    end
    if (type(value) == 'table') and (currlevel < maxlevels) then
      disptable(value, '  ' .. tab, maxlevels, currlevel)
    end
  end
end


-- Battery level calculation based on 2032 battery reported mV value
--   Source:  ChatGPT :-)
--   Granular CR2032 discharge curve (room temp, light load)
--   voltage (V), percent (%). Tuned so ~2.996 V ≈ 99%.
local CR2032_CURVE = {
    {3.10,100},
    {3.05,100},
    {3.02,100},
    {3.00, 99},
    {2.98, 98},
    {2.96, 97},
    {2.94, 96},
    {2.92, 95},
    {2.90, 92},
    {2.88, 90},
    {2.86, 89},
    {2.84, 88},
    {2.82, 86},
    {2.80, 82},
    {2.78, 78},
    {2.76, 74},
    {2.74, 71},
    {2.72, 66},
    {2.70, 60},
    {2.68, 54},
    {2.66, 48},
    {2.64, 42},
    {2.62, 36},
    {2.60, 30},
    {2.58, 24},
    {2.56, 18},
    {2.54, 14},
    {2.52, 12},
    {2.50, 10},
    {2.48,  8},
    {2.46,  6},
    {2.44,  4},
    {2.42,  2},
    {2.40,  0}
}

local function batteryPercentCR2032(mv)
    local v = mv / 1000.0

    -- Clamp to ends
    if v >= CR2032_CURVE[1][1] then return 100 end
    if v <= CR2032_CURVE[#CR2032_CURVE][1] then return 0 end

    -- Find segment and interpolate
    for i = 1, #CR2032_CURVE - 1 do
        local vh, ph = CR2032_CURVE[i][1],   CR2032_CURVE[i][2]
        local vl, pl = CR2032_CURVE[i+1][1], CR2032_CURVE[i+1][2]
        if v <= vh and v >= vl then
            local t = (v - vl) / (vh - vl)
            local pct = pl + (ph - pl) * t
            return math.floor(pct + 0.5)  -- round to nearest %
        end
    end
    return 0
end

--[[ 
Examples
 2996 mV ≈ 2.996 V -> ~99%
 print(batteryPercentCR2032(2996))  -- ~99
 print(batteryPercentCR2032(3000))  -- 99
 print(batteryPercentCR2032(2800))  -- ~82
 print(batteryPercentCR2032(2500))  -- ~10
--]]


-- Function to numerically increment a large hex string; increment assumed small so applied to only last 4 hex digits
function incrementHexSmall(hexstr, inc)
  -- split into prefix and last 4 hex digits
  local prefix = hexstr:sub(1, -5)
  local suffix = hexstr:sub(-4)

  -- convert suffix to number
  local num = tonumber(suffix, 16)
  if not num then
    error("Invalid hex string: " .. tostring(hexstr))
  end

  -- add increment
  num = num + inc

  -- format back to 4 hex digits, uppercase, zero-padded
  local newSuffix = string.format("%04X", num % 0x10000)

  -- if it overflowed past 4 digits, adjust prefix
  if num >= 0x10000 then
    -- increment the prefix by 1 (recursively, to handle long carry)
    prefix = incrementHexSmall(prefix, 1)
  end

  return prefix .. newSuffix
end

return	{
          disptable = disptable,
          batteryPercentCR2032 = batteryPercentCR2032,
          incrementHexSmall = incrementHexSmall
				}
