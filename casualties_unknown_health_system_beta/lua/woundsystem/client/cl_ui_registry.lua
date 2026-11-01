if WoundSystem and WoundSystem.UI and WoundSystem.UI._Loaded then return end

WoundSystem = WoundSystem or {}

local UI = WoundSystem.UI or {}
UI.Elements = UI.Elements or {}
UI.Order = UI.Order or {}
UI._Loaded = true
WoundSystem.UI = UI

local function WoundSystemClientEnabled()
    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

function UI.RegisterElement(id, data)
    if not id or id == "" then return end
    if not data or not isfunction(data.draw) then return end

    if not UI.Elements[id] then
        table.insert(UI.Order, id)
    end

    data.id = id
    data.priority = tonumber(data.priority) or 100
    UI.Elements[id] = data

    table.sort(UI.Order, function(a, b)
        local left = UI.Elements[a]
        local right = UI.Elements[b]
        return (left and left.priority or 100) < (right and right.priority or 100)
    end)

    return data
end

function UI.RemoveElement(id)
    UI.Elements[id] = nil

    for index, existingId in ipairs(UI.Order) do
        if existingId == id then
            table.remove(UI.Order, index)
            break
        end
    end
end

function UI.GetContext()
    return {
        state = WoundSystemClientState,
        inventory = WoundSystemInventorySlots,
        selectedLimb = WoundSystemSelectedLimbId,
        hudOpen = WoundSystemHealthHUDOpen
    }
end

hook.Add("HUDPaint", "WoundSystem_UIRegistry", function()
    if not WoundSystemClientEnabled() then return end

    local context = UI.GetContext()

    for _, id in ipairs(UI.Order) do
        local element = UI.Elements[id]
        if element and (not element.shouldDraw or element.shouldDraw(context) ~= false) then
            element.draw(context)
        end
    end
end)
