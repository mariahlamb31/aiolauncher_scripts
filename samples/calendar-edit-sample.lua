-- type = "widget"
-- name = "Calendar edit API example"
-- description = "Creates, updates, shares, and deletes a calendar event"

local widget
local created_id

local function first_calendar_id()
    local calendars = calendar:calendars()
    if calendars == "permission_error" or not calendars or not calendars[1] then
        return nil
    end
    return calendars[1].id
end

local function show_status(result)
    if result and result.ok == false then
        ui:show_toast(tostring(result.error))
    elseif result and result.id then
        created_id = result.id
        ui:show_toast("Created event " .. tostring(created_id))
    end
end

local function render()
    local cal_id = first_calendar_id()
    local rows = {
        {"text", "<b>Calendar editor</b>"},
        {"new_line", 1},
        {"text", cal_id and ("Calendar id: " .. tostring(cal_id)) or "Calendar permission is needed"},
        {"new_line", 1},
        {"text", "Created id: " .. tostring(created_id or "none")},
        {"new_line", 2},
        {"button", "Permission", {expand = true}},
        {"spacer", 2},
        {"button", "Create", {expand = true}},
        {"new_line", 2},
        {"button", "Update", {expand = true}},
        {"spacer", 2},
        {"button", "Share", {expand = true}},
        {"spacer", 2},
        {"button", "Delete", {expand = true, color = "#B71C1C"}},
    }
    widget = gui(rows)
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

    if item[2] == "Permission" then
        calendar:request_permission("on_calendar_permission")
        return
    end

    if item[2] == "Create" then
        local cal_id = first_calendar_id()
        if not cal_id then
            calendar:request_permission("on_calendar_permission")
            return
        end
        local start_time = os.time() + 3600
        show_status(calendar:create_event({
            calendar_id = cal_id,
            title = "AIO script sample",
            description = "Created by a Lua script",
            begin_time = start_time,
            end_time = start_time + 1800,
            location = "AIO Launcher",
            all_day = false,
        }))
    elseif created_id and item[2] == "Update" then
        show_status(calendar:update_event({
            id = created_id,
            title = "AIO script sample updated",
            description = "Updated by a Lua script",
        }))
    elseif created_id and item[2] == "Share" then
        show_status(calendar:share_event(created_id))
    elseif created_id and item[2] == "Delete" then
        show_status(calendar:delete_event(created_id))
        created_id = nil
    end
    render()
end

function on_calendar_permission(granted)
    ui:show_toast("Calendar permission: " .. tostring(granted))
    render()
end
