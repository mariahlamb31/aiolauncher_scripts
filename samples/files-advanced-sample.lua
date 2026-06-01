-- type = "widget"
-- name = "Files API example"
-- description = "Lists script files and uses Android file picker/create-file APIs"

local export_text = "Hello from AIO Launcher scripts\n"
local last_lines = {}

local function render()
    local files_list = files:list()
    local stat = files:stat("sample.txt")
    local rows = {
        {"text", "<b>Files</b>"},
        {"new_line", 1},
        {"text", "Script files: " .. tostring(#files_list)},
        {"new_line", 1},
        {"text", "sample.txt exists: " .. tostring(stat.exists) .. ", size: " .. tostring(stat.size)},
        {"new_line", 1},
    }

    for _, line in ipairs(last_lines) do
        table.insert(rows, {"text", line, {color = "#B0BEC5"}})
        table.insert(rows, {"new_line", 1})
    end

    table.insert(rows, {"new_line", 1})
    table.insert(rows, {"button", "Write local", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Pick text", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Create export", {expand = true}})

    local widget = gui(rows)
    widget.render()
    return widget
end

local widget

function on_load()
    widget = render()
end

function on_resume()
    widget = render()
end

function on_click(index)
    local item = widget and widget.ui and widget.ui[index]
    if not item or item[1] ~= "button" then return end

    if item[2] == "Write local" then
        files:write("sample.txt", "Saved at " .. os.date())
        last_lines = {"Wrote sample.txt"}
    elseif item[2] == "Pick text" then
        files:pick_file("text/*")
    elseif item[2] == "Create export" then
        files:create_file("text/plain", "aio-export.txt")
    end
    widget = render()
end

function on_file_picked(uri, name)
    local content = files:read_uri(uri)
    last_lines = {"Picked: " .. tostring(name), "Chars: " .. tostring(content and #content or 0)}
    widget = render()
end

function on_file_created(uri, name)
    local ok = files:write_uri(uri, export_text)
    last_lines = {"Created: " .. tostring(name), "Write ok: " .. tostring(ok)}
    widget = render()
end
