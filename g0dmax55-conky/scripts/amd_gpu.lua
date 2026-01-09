-- Conky Lua script for AMD GPU stats
-- Reads directly from sysfs to avoid spawning shell processes (zero flicker)

local io = require("io")

function conky_amd_vram_used()
    local f = io.open("/sys/class/drm/card0/device/mem_info_vram_used", "r")
    if f then
        local content = f:read("*all")
        f:close()
        local bytes = tonumber(content)
        if bytes then
            return math.floor(bytes / 1048576)
        end
    end
    return 0
end

function conky_amd_vram_total()
    local f = io.open("/sys/class/drm/card0/device/mem_info_vram_total", "r")
    if f then
        local content = f:read("*all")
        f:close()
        local bytes = tonumber(content)
        if bytes then
            return math.floor(bytes / 1048576)
        end
    end
    return 0
end

function conky_amd_gpu_percent()
    local f = io.open("/sys/class/drm/card0/device/gpu_busy_percent", "r")
    if f then
        local content = f:read("*all")
        f:close()
        local pct = tonumber(content)
        if pct then
            return pct
        end
    end
    return 0
end

function conky_amd_vram_percent()
    local used_f = io.open("/sys/class/drm/card0/device/mem_info_vram_used", "r")
    local total_f = io.open("/sys/class/drm/card0/device/mem_info_vram_total", "r")

    if used_f and total_f then
        local used_c = used_f:read("*all")
        local total_c = total_f:read("*all")
        
        used_f:close()
        total_f:close()

        local used = tonumber(used_c)
        local total = tonumber(total_c)

        if used and total and total > 0 then
            return math.floor((used / total) * 100)
        end
    else
        if used_f then used_f:close() end
        if total_f then total_f:close() end
    end
    return 0
end
