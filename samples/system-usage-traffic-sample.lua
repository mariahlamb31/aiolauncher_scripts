-- type = "widget"
-- name = "System, usage, traffic API example"
-- description = "Shows battery temperature, brightness, app usage, and traffic counters"

local widget

local function bytes_text(bytes)
    local value = tonumber(bytes or 0) or 0
    if value > 1024 * 1024 * 1024 then
        return string.format("%.1f GiB", value / 1024 / 1024 / 1024)
    end
    if value > 1024 * 1024 then
        return string.format("%.1f MiB", value / 1024 / 1024)
    end
    return tostring(math.floor(value)) .. " B"
end

local function add_line(rows, text, color)
    table.insert(rows, {"text", text, {color = color or "#DDDDDD"}})
    table.insert(rows, {"new_line", 1})
end

local function build_rows()
    local rows = {}
    local battery = system:battery_info()
    local brightness = system:brightness_state()
    local usage_state = usage:state()
    local traffic_state = traffic:state()

    add_line(rows, "<b>System stats</b>", "#FFFFFF")
    add_line(rows, "Battery: " .. tostring(battery.percent) .. "%, temp " .. tostring(battery.temp) .. " C")
    add_line(rows, "Brightness: " .. string.format("%.0f", brightness.percent or 0) .. "%")

    if usage_state.has_permission then
        local stats = usage:stats({limit = 3})
        if type(stats) == "table" then
            add_line(rows, "Screen: " .. math.floor((stats.screen_time_seconds or 0) / 60) .. " min")
            for _, app in ipairs(stats.apps or {}) do
                add_line(rows, app.name .. ": " .. math.floor((app.time_seconds or 0) / 60) .. " min", "#B0BEC5")
            end
        end
    else
        add_line(rows, "Usage permission is missing", "#FFB74D")
    end

    if traffic_state.has_permission then
        local counters = traffic:counters()
        if type(counters) == "table" then
            add_line(rows, "Traffic today: " .. bytes_text(counters.today_used_bytes))
            add_line(rows, "Traffic period: " .. bytes_text(counters.period_used_bytes))
        end
    else
        add_line(rows, "Traffic permission is missing", "#FFB74D")
    end

    table.insert(rows, {"new_line", 1})
    table.insert(rows, {"button", "Usage permission", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Traffic permission", {expand = true}})
    return rows
end

local function render()
    widget = gui(build_rows())
    widget.render()
end

function on_load()
    render()
end

function on_resume()
    render()
end

function on_click(index)
    local item = widget and widget.ui and widget.ui[index]
    if not item or item[1] ~= "button" then return end

    if item[2] == "Usage permission" then
        usage:request_permission("on_usage_permission")
    elseif item[2] == "Traffic permission" then
        traffic:request_permission("on_traffic_permission")
    end
end

function on_usage_permission(granted)
    ui:show_toast("Usage permission: " .. tostring(granted))
    render()
end

function on_traffic_permission(granted)
    ui:show_toast("Traffic permission: " .. tostring(granted))
    render()
end
