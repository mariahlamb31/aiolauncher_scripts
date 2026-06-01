-- type = "widget"
-- name = "App management API example"
-- description = "Shows app tables and calls raw app edit APIs without changing values"

local widget
local last_status = ""

local function first_app()
    local list = apps:apps("abc")
    return list and list[1] or nil
end

local function render()
    local app = first_app()
    local packages = apps:list("launch_count", true)
    local rows = {
        {"text", "<b>App management</b>"},
        {"new_line", 1},
        {"text", app and (app.name .. " / " .. app.pkg) or "No app found"},
        {"new_line", 1},
        {"text", "Visible packages from apps:list(): " .. tostring(packages and #packages or 0)},
        {"new_line", 1},
        {"text", last_status},
        {"new_line", 2},
        {"button", "Apply same values", {expand = true}},
        {"spacer", 2},
        {"button", "Edit dialog", {expand = true}},
    }
    widget = gui(rows)
    widget.render()
end

local function remember(result, name)
    if result and result.ok == false then
        last_status = name .. ": " .. tostring(result.error)
    else
        last_status = name .. ": ok"
    end
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

    local app = first_app()
    if not app then return end

    if item[2] == "Apply same values" then
        remember(apps:set_hidden(app.pkg, app.hidden), "set_hidden")
        remember(apps:set_category(app.pkg, app.category_id), "set_category")
        remember(apps:set_name(app.pkg, app.name), "set_name")
        remember(apps:set_color(app.pkg, app.color), "set_color")
        remember(apps:set_tags(app.pkg, app.tags or {}), "set_tags")
    elseif item[2] == "Edit dialog" then
        apps:show_edit_dialog(app.pkg)
    end
    render()
end

function on_apps_changed()
    render()
end
