local current_line = "Current weather not loaded"
local daily_line = "Daily weather not loaded"
local hourly_lines = {}

local function day_key(item)
    return os.date("%Y-%m-%d", tonumber(item.time or 0) or 0)
end

local function hour_of_day(item)
    return tonumber(os.date("%H", tonumber(item.time or 0) or 0)) or 0
end

local function hourly_to_daily(hours)
    local days = {}
    local current_day = nil
    local current_key = nil
    local is_first_day = true

    for _, hour in ipairs(hours or {}) do
        local key = day_key(hour)
        local temp = tonumber(hour.temp or 0) or 0
        if current_day == nil or key ~= current_key then
            if current_day ~= nil then
                table.insert(days, current_day)
                is_first_day = false
            end
            current_key = key
            current_day = {
                time = hour.time,
                temp = hour.temp,
                temp_min = temp,
                temp_max = temp,
                icon_code = hour.icon_code,
                humidity = hour.humidity,
                pressure = hour.pressure,
                wind_speed = hour.wind_speed,
                wind_direction = hour.wind_direction,
                city = hour.city,
            }
        else
            if temp < (tonumber(current_day.temp_min) or temp) then current_day.temp_min = temp end
            if temp > (tonumber(current_day.temp_max) or temp) then current_day.temp_max = temp end
            if not is_first_day and hour_of_day(hour) == 12 then
                current_day.icon_code = hour.icon_code
            end
        end
    end

    if current_day ~= nil then
        table.insert(days, current_day)
    end

    return days
end

local function time_to_string(time)
    return os.date("%c", time)
end

local function weather_icon(icon_code, is_day)
    local icon = weather:icon(icon_code, is_day)
    if icon == nil or icon == "" then return "" end
    return "%%" .. icon .. "%% "
end

local function render()
    local lines = {
        current_line,
        daily_line,
    }

    for _, line in ipairs(hourly_lines) do
        table.insert(lines, line)
    end

    ui:show_lines(lines)
end

function on_alarm()
    weather:get_by_hour("weather_sample")
end

function on_weather_result_weather_sample(tab)
    hourly_lines = {}

    for _, v in ipairs(tab or {}) do
        table.insert(
            hourly_lines,
            weather_icon(v.icon_code, v.is_day) .. time_to_string(v.time) .. ": " .. tostring(v.temp) .. " C"
        )
    end

    local current = tab and tab[1]
    if current then
        current_line =
            weather_icon(current.icon_code, current.is_day) ..
            "Current: " .. tostring(current.temp) .. " C"
    else
        current_line = "No current weather"
    end

    local days = hourly_to_daily(tab)
    if days and days[1] then
        local day = days[1]
        daily_line =
            weather_icon(day.icon_code, day.is_day) ..
            "Today: " .. tostring(day.temp_min) .. ".." .. tostring(day.temp_max) .. " C"
    else
        daily_line = "No daily weather"
    end

    render()
end
