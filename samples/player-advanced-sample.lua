-- type = "widget"
-- name = "Advanced player API example"
-- description = "Shows permission state, seek controls, like action, and custom media actions"

local widget

local function render()
    local state = player:state()
    local actions = player:custom_actions()
    local rows = {
        {"text", "<b>Player</b> " .. (state.is_playing and "playing" or "paused")},
        {"new_line", 1},
        {"text", "Permission: " .. tostring(player:has_permission())},
        {"new_line", 1},
        {"text", "App: " .. tostring(state.package)},
        {"new_line", 1},
        {"text", "Song: " .. tostring(state.song)},
        {"new_line", 1},
        {"text", "Liked: " .. tostring(player:is_liked()) .. ", can like: " .. tostring(player:can_like())},
        {"new_line", 2},
        {"button", "Settings", {expand = true}},
        {"spacer", 2},
        {"button", "Open app", {expand = true}},
        {"new_line", 2},
        {"button", "-15s", {expand = true}},
        {"spacer", 2},
        {"button", "+15s", {expand = true}},
        {"spacer", 2},
        {"button", "+60s", {expand = true}},
        {"new_line", 2},
        {"button", "Like", {expand = true}},
    }

    if actions and actions[1] then
        table.insert(rows, {"spacer", 2})
        table.insert(rows, {"button", "Custom: " .. actions[1].title, {expand = true}})
    end

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

    if item[2] == "Settings" then
        player:open_permission_settings()
    elseif item[2] == "Open app" then
        player:open_app()
    elseif item[2] == "-15s" then
        player:seek_minus_15s()
    elseif item[2] == "+15s" then
        player:seek_plus_15s()
    elseif item[2] == "+60s" then
        player:seek(60)
    elseif item[2] == "Like" then
        local result = player:like()
        if result and result.ok == false then ui:show_toast(result.error) end
    elseif string.find(item[2], "Custom:", 1, true) == 1 then
        local actions = player:custom_actions()
        if actions and actions[1] then
            local result = player:custom_action(actions[1].id)
            if result and result.ok == false then ui:show_toast(result.error) end
        end
    end
    render()
end
