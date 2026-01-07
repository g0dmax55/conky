-- Conky Lua script for ASUS Fan Percent bar
-- Reads directly from sysfs to avoid spawning shell processes (zero flicker)

local io = require("io")
local os = require("os")

local hwmon_path = nil

function get_hwmon_path()
    -- Iterate hwmon0 to hwmon20 to find 'asus'
    for i = 0, 20 do
        local path = "/sys/class/hwmon/hwmon" .. i
        local name_file = io.open(path .. "/name", "r")
        if name_file then
            local name = name_file:read("*all")
            name_file:close()
            -- Trim whitespace
            name = name:gsub("%s+", "")
            if name == "asus" then
                hwmon_path = path
                return
            end
        end
    end
end

function get_fan_percent(fan_num)
    if not hwmon_path then
        get_hwmon_path()
    end
    
    if not hwmon_path then
        return 0 -- Failed to find asus sensor
    end
    
    local file_path = hwmon_path .. "/fan" .. fan_num .. "_input"
    local f = io.open(file_path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local rpm = tonumber(content)
        if rpm then
            -- Max RPM is approx 6800
            local pct = (rpm * 100) / 6800
            if pct > 100 then pct = 100 end
            return math.floor(pct)
        end
    end
    
    return 0
end

function conky_fan_percent_1()
    return get_fan_percent("1")
end

function conky_fan_percent_2()
    return get_fan_percent("2")
end
