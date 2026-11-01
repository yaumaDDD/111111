WoundSystem = WoundSystem or {}

local Statuses = WoundSystem.Statuses or {}
Statuses.Stored = Statuses.Stored or {}
Statuses.Order = Statuses.Order or {}
WoundSystem.Statuses = Statuses

local MAX_SYNCED_STATUSES = 31

local function NormalizeStatusId(statusId)
    if WoundSystem.NormalizeItemId then
        return WoundSystem.NormalizeItemId(statusId)
    end

    return string.upper(string.Trim(tostring(statusId or "")))
end

local function CopyData(data)
    return table.Copy and table.Copy(data) or data
end

function Statuses.Register(statusId, data)
    statusId = NormalizeStatusId(statusId)
    if statusId == "" then return end

    data = CopyData(data or {})
    data.id = statusId
    data.title = data.title or statusId
    data.desc = data.desc or ""
    data.type = data.type or "bool"
    data.order = tonumber(data.order) or (#Statuses.Order + 1)

    if not Statuses.Stored[statusId] then
        table.insert(Statuses.Order, statusId)
    end

    Statuses.Stored[statusId] = data
    table.sort(Statuses.Order, function(a, b)
        local aData = Statuses.Stored[a]
        local bData = Statuses.Stored[b]
        local aOrder = aData and aData.order or 0
        local bOrder = bData and bData.order or 0
        if aOrder == bOrder then return a < b end
        return aOrder < bOrder
    end)

    return data
end

function Statuses.Get(statusId)
    return Statuses.Stored[NormalizeStatusId(statusId)]
end

local function IsEmptyValue(data, value)
    if value == nil or value == false then return true end
    if data and (data.type == "number" or data.type == "timer") then
        return (tonumber(value) or 0) <= 0
    end

    return value == ""
end

function Statuses.Set(state, statusId, value)
    if not state then return false end

    statusId = NormalizeStatusId(statusId)
    if statusId == "" then return false end

    local data = Statuses.Get(statusId)
    if data and data.type == "timer" and value == true then
        value = tonumber(data.duration) or 1
    elseif data and (data.type == "number" or data.type == "timer") then
        value = tonumber(value) or 0
    elseif value == nil then
        value = true
    end

    state.customStatuses = state.customStatuses or {}

    if IsEmptyValue(data, value) then
        state.customStatuses[statusId] = nil
        return true
    end

    state.customStatuses[statusId] = value
    return true
end

function Statuses.Clear(state, statusId)
    if not state or not state.customStatuses then return false end

    statusId = NormalizeStatusId(statusId)
    if statusId == "" then return false end

    state.customStatuses[statusId] = nil
    return true
end

function Statuses.GetValue(state, statusId)
    if not state or not state.customStatuses then return nil end
    return state.customStatuses[NormalizeStatusId(statusId)]
end

function Statuses.Has(state, statusId)
    return not IsEmptyValue(Statuses.Get(statusId), Statuses.GetValue(state, statusId))
end

function Statuses.ApplyDefaultState(state)
    if not state then return state end
    state.customStatuses = state.customStatuses or {}
    return state
end

function Statuses.TickState(state, dt, ctx)
    if not state or not state.customStatuses then return end

    dt = tonumber(dt) or 0
    ctx = ctx or {}
    ctx.state = state

    for statusId, value in pairs(state.customStatuses) do
        local data = Statuses.Get(statusId)

        if data and type(data.tick) == "function" then
            local result = data.tick(ctx, value, dt)
            if result ~= nil then
                value = result
                state.customStatuses[statusId] = result
            end
        end

        if data and (data.type == "timer" or data.decay == "time") then
            local nextValue = (tonumber(value) or 0) - dt
            if nextValue <= 0 then
                state.customStatuses[statusId] = nil
                if type(data.onExpire) == "function" then
                    data.onExpire(ctx)
                end
            else
                state.customStatuses[statusId] = nextValue
            end
        end
    end
end

function Statuses.GetActive(state)
    local active = {}
    if not state or not state.customStatuses then return active end

    for _, statusId in ipairs(Statuses.Order) do
        local data = Statuses.Get(statusId)
        local value = state.customStatuses[statusId]
        if not IsEmptyValue(data, value) then
            table.insert(active, {
                id = statusId,
                data = data,
                value = value
            })
        end
    end

    return active
end

function Statuses.GetSnapshot(state)
    if not state or not state.customStatuses then return "" end

    local parts = {}
    for _, statusId in ipairs(Statuses.Order) do
        local data = Statuses.Get(statusId)
        local value = state.customStatuses[statusId]
        if not IsEmptyValue(data, value) then
            if type(value) == "number" then
                value = math.Round(value, data and data.networkDecimals or 2)
            end
            table.insert(parts, statusId .. "=" .. tostring(value))
        end
    end

    return table.concat(parts, ";")
end

function Statuses.WriteNet(state)
    if not SERVER then return end

    local active = Statuses.GetActive(state)
    local count = math.min(#active, MAX_SYNCED_STATUSES)
    net.WriteUInt(count, 5)

    for i = 1, count do
        local entry = active[i]
        local data = entry.data or {}
        local value = entry.value
        local kind = 0

        if data.type == "number" or data.type == "timer" or type(value) == "number" then
            kind = 1
        elseif data.type == "string" or type(value) == "string" then
            kind = 2
        end

        net.WriteString(entry.id)
        net.WriteUInt(kind, 2)

        if kind == 1 then
            net.WriteFloat(tonumber(value) or 0)
        elseif kind == 2 then
            net.WriteString(tostring(value or ""))
        else
            net.WriteBool(value ~= false)
        end
    end
end

function Statuses.ReadNet(state)
    if not CLIENT then return end
    if not state then return end

    state.customStatuses = {}

    local count = net.ReadUInt(5)
    for _ = 1, count do
        local statusId = NormalizeStatusId(net.ReadString())
        local kind = net.ReadUInt(2)
        local value

        if kind == 1 then
            value = net.ReadFloat()
        elseif kind == 2 then
            value = net.ReadString()
        else
            value = net.ReadBool()
        end

        if statusId ~= "" then
            state.customStatuses[statusId] = value
        end
    end
end
