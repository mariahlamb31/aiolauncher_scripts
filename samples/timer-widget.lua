-- type = "widget"
-- name = "Timer list"
-- description = "Shows saved timers as a list. Tap to start."

local timers = {}

local function fmt_ms(ms)
    local secs = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
    local m = math.floor(secs / 60)
    return string.format("%d:%02d", m, secs - m * 60)
end

local function render()
    timers = timer:list()
    if type(timers) ~= "table" then timers = {} end

    local lines = {}
    for _, t in ipairs(timers) do
        if t.active then
            table.insert(lines, fmt_ms(t.current_ms) .. " / " .. fmt_ms(t.total_ms))
        else
            table.insert(lines, fmt_ms(t.total_ms))
        end
    end
    table.insert(lines, "Stop all")

    ui:show_lines(lines)
end

function on_load()
    render()
end

function on_click(idx)
    if idx == #timers + 1 then
        timer:stop_all()
    else
        local t = timers[idx]
        if t then timer:start(t.total_ms) end
    end
    render()
end

function on_tick()
    if timer:is_active() then
        render()
    end
end
