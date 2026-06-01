-- type = "widget"
-- name = "Phone permission callback example"
-- description = "Requests contacts permission with a named callback"

local function render()
    local contacts = phone:contacts()
    if contacts == "permission_error" then
        ui:show_buttons({"Request contacts permission"})
        return
    end

    local lines = {}
    for i, contact in ipairs(contacts or {}) do
        if i > 5 then break end
        table.insert(lines, contact.name .. " " .. tostring(contact.number or ""))
    end
    if #lines == 0 then table.insert(lines, "No contacts loaded") end
    ui:show_lines(lines)
end

function on_resume()
    render()
end

function on_click(index)
    if index == 1 then
        phone:request_permission("on_phone_permission")
    end
end

function on_phone_permission(granted)
    ui:show_toast("Contacts permission: " .. tostring(granted))
    render()
end

function on_contacts_loaded()
    render()
end
