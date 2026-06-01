-- type = "widget"
-- name = "Recorder playback API example"
-- description = "Records audio, plays it back, shares it, deletes it, and requests transcription"

local widget

local function first_record()
    local records = recorder:list()
    return records and records[1] or nil
end

local function status_text(result, action)
    if result and result.ok == false then
        ui:show_toast(action .. ": " .. tostring(result.error))
    end
end

local function render()
    local state = recorder:state()
    local record = first_record()
    local rows = {
        {"text", "<b>Recorder</b> " .. (state.active and "active" or "idle")},
        {"new_line", 1},
        {"text", "Permission: " .. tostring(state.has_permission)},
        {"new_line", 1},
        {"text", "Records: " .. tostring(state.records_count)},
        {"new_line", 1},
    }

    if record then
        table.insert(rows, {"text", "First: " .. record.name .. " (" .. tostring(record.duration) .. " ms)"})
    else
        table.insert(rows, {"text", "No records yet"})
    end

    table.insert(rows, {"new_line", 2})
    table.insert(rows, {"button", "Permission", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Start", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Stop first", {expand = true}})
    table.insert(rows, {"new_line", 2})
    table.insert(rows, {"button", "Play", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Stop play", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Transcribe", {expand = true}})
    table.insert(rows, {"new_line", 2})
    table.insert(rows, {"button", "Share", {expand = true}})
    table.insert(rows, {"spacer", 2})
    table.insert(rows, {"button", "Delete", {expand = true, color = "#B71C1C"}})

    widget = gui(rows)
    widget.render()
end

function on_resume()
    render()
end

function on_click(index)
    local item = widget and widget.ui and widget.ui[index]
    if not item or item[1] ~= "button" then return end

    local record = first_record()
    if item[2] == "Permission" then
        recorder:request_permission("on_recorder_permission")
    elseif item[2] == "Start" then
        status_text(recorder:start(), "start")
    elseif record and item[2] == "Stop first" then
        status_text(recorder:stop_record(record.id), "stop")
    elseif record and item[2] == "Play" then
        status_text(recorder:play(record.id), "play")
    elseif record and item[2] == "Stop play" then
        status_text(recorder:stop_play(record.id), "stop play")
    elseif record and item[2] == "Transcribe" then
        recorder:transcribe(record.id)
    elseif record and item[2] == "Share" then
        status_text(recorder:share(record.id), "share")
    elseif record and item[2] == "Delete" then
        status_text(recorder:delete(record.id), "delete")
    end
    render()
end

function on_recorder_permission(granted)
    ui:show_toast("Recorder permission: " .. tostring(granted))
    render()
end

function on_recorder_transcription(id, text, error)
    if error then
        ui:show_toast("Transcription failed: " .. error)
    else
        ui:show_text(text or "")
    end
end
