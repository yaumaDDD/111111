WoundSystem = WoundSystem or {}

local Items = WoundSystem.Items or {}
Items.Stored = Items.Stored or {}
Items.Order = Items.Order or {}
WoundSystem.Items = Items

local function CopyData(data)
    return table.Copy and table.Copy(data) or data
end

function Items.Register(itemId, data)
    itemId = WoundSystem.NormalizeItemId(itemId)
    if itemId == "" then return end

    data = CopyData(data or {})
    data.id = itemId
    data.max = tonumber(data.max) or 100
    data.title = data.title or itemId
    data.desc = data.desc or ""
    data.pw = tonumber(data.pw) or 30
    data.ph = tonumber(data.ph) or 30
    if data.removeOnDepleted == nil then
        data.removeOnDepleted = true
    end

    if not Items.Stored[itemId] then
        table.insert(Items.Order, itemId)
    end

    Items.Stored[itemId] = data
    return data
end

function Items.Get(itemId)
    return Items.Stored[WoundSystem.NormalizeItemId(itemId)]
end

function Items.GetMax(itemId)
    local item = Items.Get(itemId)
    return item and item.max or 100
end

function Items.ShouldRemoveOnDepleted(itemId)
    local item = Items.Get(itemId)
    if not item then return true end
    return item.removeOnDepleted ~= false
end

function Items.CreateSlot(itemId, durability)
    local item = Items.Get(itemId)
    if not item then return { type = "empty" } end

    return {
        type = "tool",
        toolName = item.id,
        durability = durability ~= nil and durability or item.max,
        pw = item.pw,
        ph = item.ph,
        icon = item.icon
    }
end

function Items.AttachClientVisual(slot, materialFactory)
    if not slot or slot.type ~= "tool" then return slot end

    local item = Items.Get(slot.toolName)
    if not item then return slot end

    slot.toolName = item.id
    slot.pw = item.pw
    slot.ph = item.ph
    slot.icon = item.icon

    if CLIENT and materialFactory and item.icon then
        slot.mat = materialFactory(item.icon)
    end

    return slot
end

function Items.BuildDefaultInventory(materialFactory)
    local slots = {}

    for _, itemId in ipairs(Items.Order) do
        local item = Items.Get(itemId)
        if item and item.slot then
            slots[item.slot] = Items.AttachClientVisual(Items.CreateSlot(itemId), materialFactory)
        end
    end

    slots[4] = slots[4] or { type = "weapon" }
    slots[5] = slots[5] or { type = "empty" }

    for i = 1, 5 do
        slots[i] = slots[i] or { type = "empty" }
    end

    return slots
end

function Items.BuildLegacyToolConfig()
    local config = {}

    for _, itemId in ipairs(Items.Order) do
        local item = Items.Get(itemId)
        if item then
            config[item.id] = {
                max = item.max,
                title = item.title,
                desc = item.desc
            }
        end
    end

    return config
end

function Items.LimbAllowed(use, limbId)
    if not use or not use.validLimbs then return true end

    local validLimbs = use.validLimbs
    if validLimbs == "any" then return true end
    if validLimbs == "body" then return limbId == "body" or limbId == "head" end

    if type(validLimbs) == "string" then
        return limbId == validLimbs
    end

    if type(validLimbs) == "table" then
        if validLimbs[limbId] == true then return true end

        for _, allowedLimb in ipairs(validLimbs) do
            if allowedLimb == limbId then return true end
        end
    end

    return false
end
