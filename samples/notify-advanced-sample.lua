-- type = "widget"
-- name = "Notification actions API example"
-- description = "Opens notification settings, snoozes notifications, and replies to remote-input actions"

local widget

local function first_action_with_input(notification)
    for _, action in ipairs(notification.actions or {}) do
        if action.have_input then return action end
    end
    return nil
end

local function render()
    local list = notify:list()
    local first = list and list[1] or nil
    local rows = {
        {"text", "<b>Notifications</b>"},
        {"new_line", 1},
        {"text", "Permission: " .. tostring(notify:has_permission())},
        {"new_line", 1},
        {"text", first and (first.title .. " / " .. first.text) or "No notifications"},
        {"new_line", 2},
        {"button", "Settings", {expand = true}},
        {"spacer", 2},
        {"button", "Open first", {expand = true}},
        {"spacer", 2},
        {"button", "Snooze first", {expand = true}},
        {"new_line", 2},
        {"button", "Reply OK", {expand = true}},
        {"spacer", 2},
        {"button", "Close first", {expand = true, color = "#B71C1C"}},
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

function on_notifications_updated()
    render()
end

function on_click(index)
    local item = widget and widget.ui and widget.ui[index]
    if not item or item[1] ~= "button" then return end

    local first = notify:list()[1]
    if item[2] == "Settings" then
        notify:open_permission_settings()
    elseif first and item[2] == "Open first" then
        notify:open(first.key)
    elseif first and item[2] == "Snooze first" then
        notify:snooze(first.key, 5 * 60 * 1000)
    elseif first and item[2] == "Reply OK" then
        local action = first_action_with_input(first)
        if action then
            local result = notify:reply(first.key, action.id, "OK")
            if result and result.ok == false then ui:show_toast(result.error) end
        else
            ui:show_toast("No reply action")
        end
    elseif first and item[2] == "Close first" then
        notify:close(first.key)
    end
end
