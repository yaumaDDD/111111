WoundSystem = WoundSystem or {}

if not GetConVar("woundsys_bodyuse_key") then
    CreateClientConVar("woundsys_bodyuse_key", tostring(KEY_F or 17), true, true, "Key used to take body-use medical items while crouching and holding them.")
end

local cvBodyUseKey = GetConVar("woundsys_bodyuse_key")
local lastBodyUseKeyStatus = false

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local function BodyUseKeyDown()
    local rawKey = string.Trim(cvBodyUseKey:GetString() or "")
    local numericKey = tonumber(rawKey)
    if numericKey then
        return input.IsKeyDown(numericKey)
    end

    local keyName = string.upper(rawKey)
    if keyName == "" then keyName = "F" end

    local keyCode = _G["KEY_" .. keyName] or _G[keyName]
    if not keyCode and string.len(keyName) == 1 then
        keyCode = _G["KEY_" .. keyName]
    end

    return input.IsKeyDown(keyCode or KEY_F)
end

local function GetToolConfig(toolName)
    return WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(toolName) or nil
end

local function GetToolMax(toolName)
    return WoundSystem.Items and WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(toolName) or 100
end

local function IsBodyUseTool(tool)
    if not tool or tool.type ~= "tool" then return false end

    local item = GetToolConfig(tool.toolName)
    local use = item and item.use
    return use and (use.bodyOnly == true or use.validLimbs == "body")
end

local function SendBodyToolUse(toolName, slotIdx)
    net.Start("WoundSystem_UseMedicalItem")
        net.WriteUInt(slotIdx, 3)
        net.WriteString(toolName)
        net.WriteString("body")
    net.SendToServer()
end

local function SendWorldBodyToolUse(ent)
    net.Start("WoundSystem_UseWorldMedicalItem")
        net.WriteEntity(ent)
    net.SendToServer()
end

local function UseMedicalToolOnBody(tool, slotIdx)
    if not IsBodyUseTool(tool) or not slotIdx then return false end

    local item = GetToolConfig(tool.toolName)
    local use = item and item.use
    local maxDur = GetToolMax(tool.toolName)
    local minDur = use and (use.minDurability or use.durabilityCost or 0) or 0

    if use and use.requireFull and (tool.durability or 0) < maxDur then return false end
    if (tool.durability or 0) < minDur then return false end

    SendBodyToolUse(tool.toolName, slotIdx)
    surface.PlaySound("miniclick.ogg")
    return true
end

local function UseWorldMedicalToolOnBody(ent)
    if not IsValid(ent) then return false end

    local toolName = ent:GetNWString("WoundSystem_WorldTool", "")
    local toolDurability = ent:GetNWFloat("WoundSystem_WorldToolDurability", 0)
    local tool = {
        type = "tool",
        toolName = toolName,
        durability = toolDurability
    }

    if not IsBodyUseTool(tool) then return false end

    local item = GetToolConfig(toolName)
    local use = item and item.use
    local maxDur = GetToolMax(toolName)
    local minDur = use and (use.minDurability or use.durabilityCost or 0) or 0

    if use and use.requireFull and toolDurability < maxDur then return false end
    if toolDurability < minDur then return false end

    SendWorldBodyToolUse(ent)
    surface.PlaySound("miniclick.ogg")
    return true
end

hook.Add("Think", "WoundSystem_BodyUseHeldItemInput", function()
    local ply = LocalPlayer()
    local keyDown = BodyUseKeyDown()
    if not WoundSystemClientEnabled() then
        lastBodyUseKeyStatus = keyDown
        return
    end

    if not (IsValid(ply) and ply:Alive()) then
        lastBodyUseKeyStatus = keyDown
        return
    end

    local holdingInventoryItem = WoundSystemDragState and WoundSystemDragState.active and input.IsMouseDown(MOUSE_RIGHT)
    local crouching = (ply.Crouching and ply:Crouching()) or ply:KeyDown(IN_DUCK)
    if holdingInventoryItem and crouching and keyDown and not lastBodyUseKeyStatus then
        local slotIdx = WoundSystemDragState.slotIdx
        local tool = slotIdx and WoundSystemInventorySlots and WoundSystemInventorySlots[slotIdx]
        if UseMedicalToolOnBody(tool, slotIdx) then
            WoundSystemDragState.active = false
            WoundSystemDragState.slotIdx = nil
        end
    elseif WoundSystemWorldDrag and WoundSystemWorldDrag.active and crouching and keyDown and not lastBodyUseKeyStatus then
        local ent = WoundSystemWorldDrag.ent
        if UseWorldMedicalToolOnBody(ent) then
            WoundSystemWorldDrag.active = false
            WoundSystemWorldDrag.mouseButton = nil
            if IsValid(ent) then
                ent:SetNoDraw(false)
            end
            if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
                WoundSystem.HealthGUI.SetScreenClickerOwned(WoundSystemHealthHUDOpen, "body_item_use_finish")
            else
                gui.EnableScreenClicker(WoundSystemHealthHUDOpen)
            end
        end
    end

    lastBodyUseKeyStatus = keyDown
end)
