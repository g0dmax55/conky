-- SSH Remote Bandwidth Graph - Lua/Cairo for Conky
-- Draws scrolling red gradient graphs matching the local network monitor style

-- Store history for scrolling effect
ssh_history = ssh_history or {}
local MAX_POINTS = 400

-- Read a value from cache file
local function read_cache(path)
    local f = io.open(path, "r")
    if f then
        local val = f:read("*all")
        f:close()
        val = val and val:match("^%s*(%d+)") or "0"
        return tonumber(val) or 0
    end
    return 0
end

function conky_draw_ssh_graphs()
    if conky_window == nil then return end

    -- Try loading cairo 
    local status, err = pcall(function() require 'cairo' end)

    local cs = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height
    )
    local cr = cairo_create(cs)

    -- Graph configuration
    local graphs = {
        {
            cache_file = "/tmp/.g0dmax55_conky_remote_ssh_rx_rate",
            x = 0, y = 62,
            width = 388, height = 35,
        },
        {
            cache_file = "/tmp/.g0dmax55_conky_remote_ssh_tx_rate",
            x = 0, y = 145,
            width = 388, height = 35,
        }
    }

    for i, g in ipairs(graphs) do
        -- Initialize history buffer
        if not ssh_history[i] then
            ssh_history[i] = {}
            for j = 1, MAX_POINTS do
                ssh_history[i][j] = 0
            end
        end

        -- Read current percentage value (0-100)
        local pct = read_cache(g.cache_file)
        if pct > 100 then pct = 100 end

        -- Push new value, shift history left
        table.insert(ssh_history[i], pct)
        if #ssh_history[i] > MAX_POINTS then
            table.remove(ssh_history[i], 1)
        end

        -- Draw border
        cairo_set_source_rgba(cr, 0.6, 0.6, 0.6, 0.3)
        cairo_set_line_width(cr, 1)
        cairo_rectangle(cr, g.x + 6, g.y, g.width, g.height)
        cairo_stroke(cr)

        -- Draw filled graph area
        local num_points = #ssh_history[i]
        local step = g.width / MAX_POINTS

        cairo_save(cr)
        cairo_rectangle(cr, g.x + 6, g.y, g.width, g.height)
        cairo_clip(cr)

        -- Draw bars with red gradient (440000 -> FF0000)
        for j = 1, num_points do
            local val = ssh_history[i][j]
            if val > 0 then
                local bar_height = (val / 100) * g.height
                local bar_x = g.x + 6 + (j - 1) * step

                local pat = cairo_pattern_create_linear(0, g.y + g.height, 0, g.y + g.height - bar_height)
                cairo_pattern_add_color_stop_rgba(pat, 0, 0.267, 0, 0, 0.9)
                cairo_pattern_add_color_stop_rgba(pat, 1, 1, 0, 0, 0.9)
                cairo_set_source(cr, pat)

                cairo_rectangle(cr, bar_x, g.y + g.height - bar_height, step + 0.5, bar_height)
                cairo_fill(cr)

                cairo_pattern_destroy(pat)
            end
        end

        cairo_restore(cr)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
