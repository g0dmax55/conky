-- SSH Remote Bandwidth Graph - Lua/Cairo for Conky
-- Draws scrolling red gradient graphs matching the local network monitor style

ssh_history = ssh_history or {}
local MAX_POINTS = 400

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

    local ok, cairo = pcall(require, 'cairo')
    if not ok or type(cairo) ~= 'table' then return end
    local ok_xlib, cairo_xlib = pcall(require, 'cairo_xlib')

    local surface_create = cairo.xlib_surface_create or (type(cairo_xlib) == 'table' and cairo_xlib.surface_create) or _G.cairo_xlib_surface_create
    local create = cairo.create or _G.cairo_create
    if not surface_create or not create then return end

    local cs = surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        conky_window.width,
        conky_window.height
    )
    local cr = create(cs)

    local set_source_rgba = cairo.set_source_rgba or _G.cairo_set_source_rgba
    local set_line_width = cairo.set_line_width or _G.cairo_set_line_width
    local rectangle = cairo.rectangle or _G.cairo_rectangle
    local stroke = cairo.stroke or _G.cairo_stroke
    local save = cairo.save or _G.cairo_save
    local clip = cairo.clip or _G.cairo_clip
    local pattern_create_linear = cairo.pattern_create_linear or _G.cairo_pattern_create_linear
    local pattern_add_color_stop_rgba = cairo.pattern_add_color_stop_rgba or _G.cairo_pattern_add_color_stop_rgba
    local set_source = cairo.set_source or _G.cairo_set_source
    local fill = cairo.fill or _G.cairo_fill
    local pattern_destroy = cairo.pattern_destroy or _G.cairo_pattern_destroy
    local restore = cairo.restore or _G.cairo_restore
    local destroy = cairo.destroy or _G.cairo_destroy
    local surface_destroy = cairo.surface_destroy or _G.cairo_surface_destroy

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
        set_source_rgba(cr, 0.6, 0.6, 0.6, 0.3)
        set_line_width(cr, 1)
        rectangle(cr, g.x + 6, g.y, g.width, g.height)
        stroke(cr)

        -- Draw filled graph area
        local num_points = #ssh_history[i]
        local step = g.width / MAX_POINTS

        save(cr)
        rectangle(cr, g.x + 6, g.y, g.width, g.height)
        clip(cr)

        -- Draw bars with red gradient (440000 -> FF0000)
        for j = 1, num_points do
            local val = ssh_history[i][j]
            if val > 0 then
                local bar_height = (val / 100) * g.height
                local bar_x = g.x + 6 + (j - 1) * step

                local pat = pattern_create_linear(0, g.y + g.height, 0, g.y + g.height - bar_height)
                pattern_add_color_stop_rgba(pat, 0, 0.267, 0, 0, 0.9)
                pattern_add_color_stop_rgba(pat, 1, 1, 0, 0, 0.9)
                set_source(cr, pat)

                rectangle(cr, bar_x, g.y + g.height - bar_height, step + 0.5, bar_height)
                fill(cr)

                pattern_destroy(pat)
            end
        end

        restore(cr)
    end

    destroy(cr)
    surface_destroy(cs)
end
