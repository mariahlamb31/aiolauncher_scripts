-- This sample lists current system profiles and allows to restore any of it.
-- It also shows how to save and remove a named profile with the raw profiles API.

local TEMP_PROFILE = "script-sample-temp"
local actions = {}

local function add_line(lines, text, action)
    table.insert(lines, text)
    actions[#lines] = action
end

local function render()
    actions = {}

    local lines = {
        "Current profile: " .. tostring(profiles:current())
    }

    add_line(lines, "Save temp profile", { kind = "dump" })
    add_line(lines, "Remove temp profile", { kind = "remove" })

    local profs = profiles:list()
    for _, name in ipairs(profs or {}) do
        add_line(lines, tostring(name), { kind = "restore", name = name })
    end

    ui:show_lines(lines)
end

function on_resume()
    render()
end

function on_click(idx)
    local action = actions[idx]
    if not action then return end

    if action.kind == "dump" then
        profiles:dump(TEMP_PROFILE)
        ui:show_toast("Saved " .. TEMP_PROFILE)
    elseif action.kind == "remove" then
        ui:show_toast("Removed: " .. tostring(profiles:remove(TEMP_PROFILE)))
    elseif action.kind == "restore" then
        ui:show_toast("Restoring...")
        profiles:restore(action.name)
    end

    render()
end
