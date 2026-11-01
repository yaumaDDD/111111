WoundSystemDuplicateClientDeathMemory = WoundSystemDuplicateClientDeathMemory or {}

local function WoundSystemClientEnabled()
    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

hook.Remove("CalcView", "00_WoundSystem_UnconsciousEyeView")
hook.Remove("CalcView", "zz_WoundSystem_UnconsciousEyeView")

local function WoundSystem_RemoveDuplicateClientDeathRagdollEntity(ragdoll)
    if not IsValid(ragdoll) then return end

    ragdoll:SetNoDraw(true)
    if ragdoll.IsClientside and ragdoll:IsClientside() then
        ragdoll:Remove()
    end
end

function WoundSystem_ShouldSuppressDuplicateClientDeathRagdoll(ent)
    if not IsValid(ent) or not ent:IsPlayer() then return false end

    local idx = ent:EntIndex()
    local hasUnconsciousRagdoll = IsValid(ent:GetNWEntity("WoundSystemUnconsciousRagdoll"))
    local isWoundSystemUnconscious = ent:GetNWBool("WoundSystemUnconscious", false) or ent:GetNoDraw()

    if hasUnconsciousRagdoll or isWoundSystemUnconscious then
        WoundSystemDuplicateClientDeathMemory[idx] = CurTime() + 6
        return true
    end

    return (WoundSystemDuplicateClientDeathMemory[idx] or 0) > CurTime()
end

hook.Add("Think", "WoundSystem_RememberUnconsciousPlayersForDeathRagdolls", function()
    if not WoundSystemClientEnabled() then return end

    for _, ply in ipairs(player.GetAll()) do
        WoundSystem_ShouldSuppressDuplicateClientDeathRagdoll(ply)
    end
end)

hook.Add("CreateClientsideRagdoll", "WoundSystem_RemoveDuplicateClientDeathRagdoll", function(ent, ragdoll)
    if not WoundSystemClientEnabled() then return end
    if not IsValid(ent) or not ent:IsPlayer() or not IsValid(ragdoll) then return end
    if not WoundSystem_ShouldSuppressDuplicateClientDeathRagdoll(ent) then return end

    WoundSystem_RemoveDuplicateClientDeathRagdollEntity(ragdoll)
end)

if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI._Loaded then return end

WoundSystem = WoundSystem or {}
WoundSystem.HealthGUI = WoundSystem.HealthGUI or {}
WoundSystem.HealthGUI._Loaded = true

WoundSystem.HealthGUI.ClickerDebugConVar = GetConVar("woundsys_clicker_debug")
    or CreateClientConVar("woundsys_clicker_debug", "0", true, false, "Print WoundSystem screen clicker ownership changes.", 0, 1)

function WoundSystem.HealthGUI.ClickerDebugEnabled()
    local cvar = WoundSystem.HealthGUI.ClickerDebugConVar
    return cvar and cvar:GetBool()
end

function WoundSystem.HealthGUI.ClickerDebugLog(message)
    if not WoundSystem.HealthGUI.ClickerDebugEnabled() then return end
    MsgC(Color(90, 220, 150), "[WoundSystem clicker] ", color_white, tostring(message), "\n")
end

if not WoundSystem.NormalizeItemId and file.Exists("woundsystem/shared/sh_core.lua", "LUA") then
    include("woundsystem/shared/sh_core.lua")
end

if not WoundSystem.Statuses and file.Exists("woundsystem/shared/sh_limb_statuses.lua", "LUA") then
    include("woundsystem/shared/sh_limb_statuses.lua")
end

if not WoundSystem.Items and file.Exists("woundsystem/shared/sh_medical_items.lua", "LUA") then
    include("woundsystem/shared/sh_medical_items.lua")
end

local function CorruptUIText(text)
    if WoundSystem.TextCorruption and WoundSystem.TextCorruption.ForUI then
        return WoundSystem.TextCorruption.ForUI(text)
    end

    return tostring(text or "")
end

local PaddedMaterialInfo = {}
local ActivePaddedMaterial = nil

local function PaddedPath(matPath)
    return string.gsub(matPath, "%.png$", "_padded.png")
end

local function PaddedMaterial(matPath, flags)
    local paddedPath = PaddedPath(matPath)
    local hasPadded = file.Exists("materials/" .. paddedPath, "GAME")
    local mat = Material(hasPadded and paddedPath or matPath, flags)
    local pad = hasPadded and 1 or 0

    PaddedMaterialInfo[mat] = {
        pad = pad,
        sourceW = math.max(mat:Width() - (pad * 2), 1),
        sourceH = math.max(mat:Height() - (pad * 2), 1),
        textureW = math.max(mat:Width(), 1),
        textureH = math.max(mat:Height(), 1)
    }
    return mat
end

local DeathScreen = {
    isDead = false,
    deathTime = 0,
    deathType = "normal",
    deathScreenStarted = false,
    deathScreenImageDelay = 1,
    deathEcgHoldTime = 1,
    clickDebounce = false
}
local spawnVisualGraceUntil = CurTime() + 3

WoundSystem.HealthGUI.DeathScreenActive = false
WoundSystemDeathScreenActive = false

local function SetDeathScreenActive(active)
    DeathScreen.isDead = active == true
    if not DeathScreen.isDead then
        DeathScreen.deathScreenStarted = false
    end
    WoundSystem.HealthGUI.DeathScreenActive = DeathScreen.isDead
    WoundSystemDeathScreenActive = DeathScreen.isDead
end

WoundSystem.HealthGUI.LifecycleSeq = WoundSystem.HealthGUI.LifecycleSeq or 0
WoundSystem.HealthGUI.IgnoreLifecycleAtOrBefore = WoundSystem.HealthGUI.IgnoreLifecycleAtOrBefore or 0
WoundSystem.HealthGUI.SpawnClearUntil = WoundSystem.HealthGUI.SpawnClearUntil or 0

function WoundSystem.HealthGUI.ReadOptionalUInt(bits, fallback)
    if not net.BytesLeft then return fallback end

    local bytesLeft, bitsLeft = net.BytesLeft()
    if (bitsLeft or 0) >= bits or (bytesLeft or 0) * 8 >= bits then
        return net.ReadUInt(bits)
    end

    return fallback
end

function WoundSystem.HealthGUI.NoteLifecycle(seq)
    seq = tonumber(seq)
    if not seq then return end
    if seq > (WoundSystem.HealthGUI.LifecycleSeq or 0) then
        WoundSystem.HealthGUI.LifecycleSeq = seq
    end
end

function WoundSystem.HealthGUI.NoteLocalRespawn()
    local cutoff = WoundSystem.HealthGUI.LifecycleSeq or 0
    if cutoff <= 0 then cutoff = 1 end

    WoundSystem.HealthGUI.IgnoreLifecycleAtOrBefore = math.max(WoundSystem.HealthGUI.IgnoreLifecycleAtOrBefore or 0, cutoff)
    WoundSystem.HealthGUI.SpawnClearUntil = CurTime() + 3
end

function WoundSystem.HealthGUI.IsSpawnVisualGraceActive()
    return CurTime() < math.max(spawnVisualGraceUntil or 0, WoundSystem.HealthGUI.SpawnClearUntil or 0)
end

function WoundSystem.HealthGUI.ShouldIgnoreLifecycleMessage(seq, activeState)
    seq = tonumber(seq)

    if seq then
        local cutoff = WoundSystem.HealthGUI.IgnoreLifecycleAtOrBefore or 0
        if activeState and seq <= cutoff then
            return true
        end

        WoundSystem.HealthGUI.NoteLifecycle(seq)
    end

    if activeState and CurTime() < (WoundSystem.HealthGUI.SpawnClearUntil or 0) then
        local ply = LocalPlayer()
        if IsValid(ply) and ply:Alive()
            and not ply:GetNWBool("WoundSystemUnconscious", false)
            and not ply:GetNoDraw()
            and (not seq or seq <= (WoundSystem.HealthGUI.IgnoreLifecycleAtOrBefore or 0)) then
            return true
        end
    end

    return false
end

function WoundSystem.HealthGUI.IsExternalMenuOpen()
    if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return true end
    if gui and gui.IsConsoleVisible and gui.IsConsoleVisible() then return true end
    if IsValid(g_ContextMenu) and g_ContextMenu:IsVisible() then return true end
    if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then return true end

    return false
end

function WoundSystem.HealthGUI.SetScreenClickerOwned(enabled, reason)
    reason = tostring(reason or "unspecified")
    WoundSystem.HealthGUI.LastScreenClickerReason = (enabled and "enable: " or "disable: ") .. reason
    WoundSystem.HealthGUI.LastScreenClickerTime = CurTime()
    WoundSystem.HealthGUI.LastScreenClickerTrace = debug and debug.traceback and debug.traceback("", 2) or nil

    if enabled then
        if WoundSystem.HealthGUI.IsExternalMenuOpen() then
            WoundSystem.HealthGUI.ScreenClickerOwned = false
            WoundSystem.HealthGUI.ClickerDebugLog("skipped enable (external menu): " .. reason)
            return
        end

        WoundSystem.HealthGUI.ScreenClickerOwned = true
        gui.EnableScreenClicker(true)
        WoundSystem.HealthGUI.ClickerDebugLog(WoundSystem.HealthGUI.LastScreenClickerReason)
        return
    end

    if not WoundSystem.HealthGUI.ScreenClickerOwned then return end

    WoundSystem.HealthGUI.ScreenClickerOwned = false

    if WoundSystem.HealthGUI.IsExternalMenuOpen() then
        WoundSystem.HealthGUI.ClickerDebugLog(WoundSystem.HealthGUI.LastScreenClickerReason .. " preserved external menu")
        return
    end

    gui.EnableScreenClicker(false)
    WoundSystem.HealthGUI.ClickerDebugLog(WoundSystem.HealthGUI.LastScreenClickerReason)
end

function WoundSystem.HealthGUI.ForceReleaseScreenClicker(preserveExternalMenu, reason)
    reason = tostring(reason or "force_release")
    WoundSystem.HealthGUI.LastScreenClickerReason = "force release: " .. reason
    WoundSystem.HealthGUI.LastScreenClickerTime = CurTime()
    WoundSystem.HealthGUI.LastScreenClickerTrace = debug and debug.traceback and debug.traceback("", 2) or nil
    WoundSystem.HealthGUI.ScreenClickerOwned = false

    if preserveExternalMenu and WoundSystem.HealthGUI.IsExternalMenuOpen() then
        WoundSystem.HealthGUI.ClickerDebugLog(WoundSystem.HealthGUI.LastScreenClickerReason .. " preserved external menu")
        return
    end

    if gui and gui.EnableScreenClicker then
        gui.EnableScreenClicker(false)
    end

    WoundSystem.HealthGUI.ClickerDebugLog(WoundSystem.HealthGUI.LastScreenClickerReason)
end

function WoundSystem.HealthGUI.DelayedRespawnCursorRelease(reason)
    local function release()
        local ply = LocalPlayer()
        if IsValid(ply) and not ply:Alive() then return end
        if IsValid(ply) and ply:Alive() and DeathScreen.isDead then
            SetDeathScreenActive(false)
            DeathScreen.deathScreenStarted = false
            DeathScreen.clickDebounce = false
        end
        if WoundSystemHealthHUDOpen then return end
        if WoundSystemWorldDrag and WoundSystemWorldDrag.active then return end
        if WoundSystemIsAnyWoundMinigameActive and WoundSystemIsAnyWoundMinigameActive() then return end

        WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, reason or "respawn_delayed")
    end

    release()
    timer.Simple(0, release)
    timer.Simple(0.05, release)
    timer.Simple(0.25, release)
    timer.Simple(0.75, release)
end

net.Receive("WoundSystem_PlayerDied", function()
    if not WoundSystemClientEnabled() then return end

    local incomingDeathType = net.ReadString()
    local lifecycleSeq = WoundSystem.HealthGUI.ReadOptionalUInt(24, nil)
    if WoundSystem and WoundSystem.DebugDeath then
        print("[WoundSystem Death] Client received WoundSystem_PlayerDied type=", incomingDeathType, "lifecycleSeq=", tostring(lifecycleSeq), "localAlive=", tostring(LocalPlayer() and LocalPlayer():Alive()))
    end
    if WoundSystem.HealthGUI.ShouldIgnoreLifecycleMessage(lifecycleSeq, true) then return end

    local alreadyShowingDeathScreen = DeathScreen.isDead and DeathScreen.deathScreenStarted
    SetDeathScreenActive(true)
    if not alreadyShowingDeathScreen then
        DeathScreen.deathTime = CurTime()
    end
    DeathScreen.deathType = incomingDeathType
    DeathScreen.deathScreenStarted = alreadyShowingDeathScreen
    DeathScreen.clickDebounce = false
    
    -- Free the cursor so the player can click the screen
    WoundSystem.HealthGUI.SetScreenClickerOwned(true, "death_screen")
end)

local function SetGuiMaterial(mat)
    ActivePaddedMaterial = PaddedMaterialInfo[mat]
    surface.SetMaterial(mat)
end

local function DrawRectInt(x, y, w, h)
    x, y = tonumber(x) or 0, tonumber(y) or 0
    w, h = tonumber(w) or 0, tonumber(h) or 0

    local info = ActivePaddedMaterial
    if info then
        local padX = info.pad * (w / info.sourceW)
        local padY = info.pad * (h / info.sourceH)
        surface.DrawTexturedRect(math.Round(x - padX), math.Round(y - padY), math.Round(w + (padX * 2)), math.Round(h + (padY * 2)))
        return
    end

    surface.DrawTexturedRect(math.Round(x), math.Round(y), math.Round(w), math.Round(h))
end

local function RemapPaddedU(info, u)
    return (info.pad + (u * info.sourceW)) / info.textureW
end

local function RemapPaddedV(info, v)
    return (info.pad + (v * info.sourceH)) / info.textureH
end

local function DrawRectUVInt(x, y, w, h, u1, v1, u2, v2)
    x, y = tonumber(x) or 0, tonumber(y) or 0
    w, h = tonumber(w) or 0, tonumber(h) or 0

    local info = ActivePaddedMaterial
    if info then
        local fullU = (u1 == 0 and u2 == 1) or (u1 == 1 and u2 == 0)
        local fullV = (v1 == 0 and v2 == 1) or (v1 == 1 and v2 == 0)
        if fullU and fullV then
            local padX = info.pad * (w / info.sourceW)
            local padY = info.pad * (h / info.sourceH)
            surface.DrawTexturedRectUV(math.Round(x - padX), math.Round(y - padY), math.Round(w + (padX * 2)), math.Round(h + (padY * 2)), u1, v1, u2, v2)
            return
        end

        u1, u2 = RemapPaddedU(info, u1), RemapPaddedU(info, u2)
        v1, v2 = RemapPaddedV(info, v1), RemapPaddedV(info, v2)
    end

    surface.DrawTexturedRectUV(math.Round(x), math.Round(y), math.Round(w), math.Round(h), u1, v1, u2, v2)
end
local function SetScissorRectInt(x1, y1, x2, y2, enabled)
    render.SetScissorRect(math.floor(x1 or 0), math.floor(y1 or 0), math.ceil(x2 or 0), math.ceil(y2 or 0), enabled)
end

local function PixelSnapFill(mat, fillAmount, vertical)
    fillAmount = math.Clamp(tonumber(fillAmount) or 0, 0, 1)

    local info = PaddedMaterialInfo[mat]
    local pixelCount = info and (vertical and info.sourceH or info.sourceW) or 1
    pixelCount = math.max(math.floor(pixelCount or 1), 1)

    return math.Clamp(math.floor(fillAmount * pixelCount + 0.5) / pixelCount, 0, 1)
end

WoundSystem.Client = WoundSystem.Client or {}
WoundSystem.Client.PaddedMaterial = PaddedMaterial
WoundSystem.Client.SetGuiMaterial = SetGuiMaterial
WoundSystem.Client.DrawRectInt = DrawRectInt
WoundSystem.Client.DrawRectUVInt = DrawRectUVInt
WoundSystem.Client.PixelSnapFill = PixelSnapFill
WoundSystem.Client.IsEnabled = WoundSystemClientEnabled

local CVars = {
    LowEndMode = CreateClientConVar("woundsys_lowend_mode", "0", true, false, "Reduce expensive WoundSystem client visuals.", 0, 1),
    VisualQuality = CreateClientConVar("woundsys_visual_quality", "2", true, false, "WoundSystem visual quality: 0 low, 1 medium, 2 full.", 0, 2),
    UIScale = CreateClientConVar("woundsys_ui_scale", "1", true, false, "Scale WoundSystem health UI.", 0.6, 1.6),
    PainVisualStrength = CreateClientConVar("woundsys_pain_visual_strength", "1", true, false, "Scale WoundSystem pain screen effects.", 0, 2),
    FurBloodModels = CreateClientConVar("woundsys_fur_blood_models", "1", true, false, "Draw synced blood overlay on player models.", 0, 1),
    FurBloodAlpha = CreateClientConVar("woundsys_fur_blood_alpha", "0.1", true, false, "Maximum alpha for player model blood overlay.", 0, 0.5),
    FurBloodRegionClip = CreateClientConVar("woundsys_fur_blood_region_clip", "0", true, false, "Use rough clipped body regions for fur blood. Disabled by default to avoid animation slicing.", 0, 1),
    AudioMaster = GetConVar("woundsys_audio_master"),
    TinnitusVolume = GetConVar("woundsys_tinnitus_volume"),
}

function WoundSystem.Client.GetVisualQuality()
    return math.Clamp(CVars.VisualQuality:GetInt(), 0, 2)
end

function WoundSystem.Client.IsLowEndMode()
    return CVars.LowEndMode:GetBool() or WoundSystem.Client.GetVisualQuality() <= 0
end

function WoundSystem.Client.IsVisualVisible(kind, entOrPos, radius)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end

    local pos
    if isvector(entOrPos) then
        pos = entOrPos
    elseif IsValid(entOrPos) then
        pos = entOrPos.WorldSpaceCenter and entOrPos:WorldSpaceCenter() or entOrPos:GetPos()
    end
    if not pos then return false end

    radius = tonumber(radius) or 0
    local eyePos = EyePos()
    local toPos = pos - eyePos
    local lenSqr = toPos:LengthSqr()
    if lenSqr > 0.001 then
        local forward = EyeAngles():Forward()
        local dot = forward:Dot(toPos / math.sqrt(lenSqr))
        if dot < -0.08 then return false end
    end

    local screen = pos:ToScreen()
    local margin = WoundSystem.Client.IsLowEndMode() and 96 or 256
    margin = margin + radius
    return screen.visible
        and screen.x >= -margin
        and screen.x <= ScrW() + margin
        and screen.y >= -margin
        and screen.y <= ScrH() + margin
end

local function LowEndMode()
    return WoundSystem.Client.IsLowEndMode and WoundSystem.Client.IsLowEndMode() or false
end

local function UIScale()
    local scale = math.Clamp(CVars.UIScale:GetFloat(), 0.6, 1.6)
    if ScrH() <= 600 then
        return scale * 0.72
    elseif ScrH() <= 768 then
        return scale * 0.86
    end
    return scale
end

local function GetBloodRGB()
    local cvR = GetConVar("woundsys_blood_r")
    local cvG = GetConVar("woundsys_blood_g")
    local cvB = GetConVar("woundsys_blood_b")
    local r = cvR and cvR:GetInt() or 255
    local g = cvG and cvG:GetInt() or 236
    local b = cvB and cvB:GetInt() or 58
    return math.Clamp(r, 0, 255), math.Clamp(g, 0, 255), math.Clamp(b, 0, 255)
end

local function IsAlienBloodColor()
    local cvBloodColor = GetConVar("woundsys_blood_color")
    local mode = string.lower(string.Trim(cvBloodColor and cvBloodColor:GetString() or "alien_yellow"))
    if mode == "red" then return false end
    if mode == "alien_yellow" then return true end
    local r, g, b = GetBloodRGB()
    return not (r > 130 and g < 60 and b < 60)
end

local function CreateFurBloodOverlayMaterial(prefix, index, texturePath)
    return CreateMaterial("WoundSystem_" .. prefix .. "BloodModelOverlayV2_" .. index, "VertexLitGeneric", {
        ["$basetexture"] = texturePath,
        ["$basetexturetransform"] = "center .5 .5 scale .333 .333 rotate " .. ((index - 1) * 17) .. " translate 0 0",
        ["$model"] = "1",
        ["$translucent"] = "1",
        ["$vertexalpha"] = "1",
        ["$vertexcolor"] = "1",
        ["$nocull"] = "1",
        ["$ignorez"] = "0"
    })
end

local furBloodOverlayMatsYellow = {}
local furBloodOverlayMatsRed = {}
local redFurBloodAltPath = Material("decals/blood2"):IsError() and "decals/blood1" or "decals/blood2"
for i = 1, 6 do
    furBloodOverlayMatsYellow[i] = CreateFurBloodOverlayMaterial("Alien", i, "decals/yblood" .. i)
    furBloodOverlayMatsRed[i] = CreateFurBloodOverlayMaterial("Red", i, (i % 2 == 0) and redFurBloodAltPath or "decals/blood1")
end

local function ActiveFurBloodOverlayMaterial(index)
    local mats = IsAlienBloodColor() and furBloodOverlayMatsYellow or furBloodOverlayMatsRed
    return mats[index or 1] or mats[1]
end

local function FurBloodUiColors(alpha)
    local r, g, b = GetBloodRGB()
    return Color(math.floor(r * 0.45), math.floor(g * 0.45), math.floor(b * 0.45), alpha), Color(r, g, b, alpha)
end

local drawingFurBloodOverlay = false
local furBloodVisualRegions = {
    { id = "head", normalizer = 10 },
    { id = "torso", normalizer = 20 },
    { id = "leftArm", normalizer = 30 },
    { id = "rightArm", normalizer = 30 },
    { id = "leftLeg", normalizer = 30 },
    { id = "rightLeg", normalizer = 30 }
}

local function CanDrawModelFurBlood(ent, source)
    source = IsValid(source) and source or ent

    if not CVars.FurBloodModels:GetBool() or LowEndMode() then return 0 end
    if not IsValid(ent) or not IsValid(source) then return 0 end
    if ent:IsPlayer() and not ent:Alive() then return 0 end
    if ent == LocalPlayer() and not ent:ShouldDrawLocalPlayer() then return 0 end
    if ActiveFurBloodOverlayMaterial(1):IsError() then return 0 end
    if WoundSystem.Client.IsVisualVisible and not WoundSystem.Client.IsVisualVisible("fur_blood", ent, 64) then return 0 end

    return 1
end

local function GetModelFurBloodAlpha(ent, source)
    source = IsValid(source) and source or ent
    if CanDrawModelFurBlood(ent, source) <= 0 then return 0 end

    local totalBlood = source:GetNWFloat("WoundSystemFurBlood", 0)
    if totalBlood <= 0.05 then return 0 end

    return math.Clamp(totalBlood / 75, 0, 1) * math.Clamp(CVars.FurBloodAlpha:GetFloat(), 0, 0.5)
end

local function GetRegionFurBloodAlpha(source, region)
    local amount = source:GetNWFloat("WoundSystemFurBlood_" .. region.id, 0)
    if amount <= 0.05 then return 0 end

    return math.Clamp(amount / region.normalizer, 0, 1) * math.Clamp(CVars.FurBloodAlpha:GetFloat(), 0, 0.5)
end

local function GetModelBonePos(ent, boneName, fallback)
    local boneId = ent:LookupBone(boneName)
    if not boneId then return fallback end

    local pos = ent:GetBonePosition(boneId)
    if not pos then return fallback end

    return pos
end

local function PushClipPlane(normal, point)
    render.PushCustomClipPlane(normal, normal:Dot(point))
end

local function FurBloodPassCount(amountFrac)
    amountFrac = math.Clamp(amountFrac or 0, 0, 1)
    if amountFrac >= 0.95 then return 6 end
    if amountFrac >= 0.85 then return 5 end
    if amountFrac >= 0.72 then return 4 end
    if amountFrac >= 0.55 then return 3 end
    if amountFrac >= 0.32 then return 2 end
    return 1
end

local function FurBloodPassAlpha(alpha, passIndex)
    if passIndex <= 1 then return alpha end
    return alpha * math.Clamp(0.78 - (passIndex - 2) * 0.11, 0.32, 0.78)
end

local function DrawFurBloodOverlayPass(ent, alpha, planes, amountFrac)
    local oldClipping = render.EnableClipping(true)

    for _, plane in ipairs(planes) do
        PushClipPlane(plane.normal, plane.point)
    end

    local passCount = FurBloodPassCount(amountFrac)

    for i = 1, passCount do
        local mat = ActiveFurBloodOverlayMaterial(i)
        local passAlpha = FurBloodPassAlpha(alpha, i)

        render.MaterialOverride(mat)
        render.SetBlend(passAlpha)
        render.SetColorModulation(1, 1, 1)
        ent:DrawModel()
    end

    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    render.MaterialOverride(nil)

    for _ = 1, #planes do
        render.PopCustomClipPlane()
    end

    render.EnableClipping(oldClipping)
end

local function BuildFurBloodRegionPlanes(ent)
    local up = ent:GetUp()
    local right = ent:GetRight()
    local origin = ent:GetPos()
    local pelvis = GetModelBonePos(ent, "ValveBiped.Bip01_Pelvis", origin + up * 36)
    local spine = GetModelBonePos(ent, "ValveBiped.Bip01_Spine2", origin + up * 52)
    local head = GetModelBonePos(ent, "ValveBiped.Bip01_Head1", origin + up * 72)
    local neckPlane = head - up * 10
    local waistPlane = pelvis + up * 8
    local sidePlane = spine

    return {
        head = {
            { normal = up, point = neckPlane }
        },
        torso = {
            { normal = -up, point = neckPlane },
            { normal = up, point = waistPlane }
        },
        leftArm = {
            { normal = -right, point = sidePlane },
            { normal = up, point = waistPlane }
        },
        rightArm = {
            { normal = right, point = sidePlane },
            { normal = up, point = waistPlane }
        },
        leftLeg = {
            { normal = -right, point = sidePlane },
            { normal = -up, point = waistPlane }
        },
        rightLeg = {
            { normal = right, point = sidePlane },
            { normal = -up, point = waistPlane }
        }
    }
end

local function DrawFurBloodOverlayEntity(ent, source)
    if drawingFurBloodOverlay then return end

    source = IsValid(source) and source or ent
    if CanDrawModelFurBlood(ent, source) <= 0 then return end

    local totalAlpha = GetModelFurBloodAlpha(ent, source)
    if totalAlpha <= 0 then return end

    drawingFurBloodOverlay = true
        if CVars.FurBloodRegionClip:GetBool() then
            local regionPlanes = BuildFurBloodRegionPlanes(ent)
            local drewRegion = false

            for _, region in ipairs(furBloodVisualRegions) do
                local alpha = GetRegionFurBloodAlpha(source, region)
                local planes = regionPlanes[region.id]
                if alpha > 0 and planes then
                    local amountFrac = math.Clamp(source:GetNWFloat("WoundSystemFurBlood_" .. region.id, 0) / region.normalizer, 0, 1)
                    DrawFurBloodOverlayPass(ent, alpha, planes, amountFrac)
                    drewRegion = true
                end
            end

            if drewRegion then
                drawingFurBloodOverlay = false
                return
            end
        end

        do
            local totalFrac = math.Clamp(source:GetNWFloat("WoundSystemFurBlood", 0) / 75, 0, 1)
            local passCount = FurBloodPassCount(totalFrac)
            for i = 1, passCount do
                local passAlpha = FurBloodPassAlpha(totalAlpha, i)
                render.MaterialOverride(ActiveFurBloodOverlayMaterial(i))
                render.SetBlend(passAlpha)
                render.SetColorModulation(1, 1, 1)
                ent:DrawModel()
            end
            render.SetColorModulation(1, 1, 1)
            render.SetBlend(1)
            render.MaterialOverride(nil)
        end
    drawingFurBloodOverlay = false
end

hook.Add("PostPlayerDraw", "WoundSystem_FurBloodModelOverlay", function(ply)
    DrawFurBloodOverlayEntity(ply, ply)
end)

hook.Add("PostDrawTranslucentRenderables", "WoundSystem_FurBloodRagdollOverlay", function()
    if drawingFurBloodOverlay or not CVars.FurBloodModels:GetBool() or LowEndMode() then return end

    local now = CurTime()
    WoundSystem.FurBloodRagdollCache = WoundSystem.FurBloodRagdollCache or {
        nextScan = 0,
        entries = {}
    }

    local cache = WoundSystem.FurBloodRagdollCache
    if now >= (cache.nextScan or 0) then
        cache.nextScan = now + 0.25
        cache.entries = {}

        for _, className in ipairs({"prop_ragdoll", "hl2mp_ragdoll"}) do
            for _, ragdoll in ipairs(ents.FindByClass(className)) do
                local owner = ragdoll:GetNWEntity("WoundSystemOwner")
                if IsValid(owner) and (ragdoll:GetNWBool("WoundSystemUnconsciousRagdoll", false) or ragdoll:GetNWBool("WoundSystemDeadUnconsciousBody", false) or ragdoll:GetNWBool("WoundSystemDeathRagdoll", false)) then
                    local source = (ragdoll:GetNWBool("WoundSystemDeadUnconsciousBody", false) or ragdoll:GetNWBool("WoundSystemDeathRagdoll", false)) and ragdoll or owner
                    cache.entries[#cache.entries + 1] = {ragdoll = ragdoll, source = source}
                end
            end
        end
    end

    for _, entry in ipairs(cache.entries or {}) do
        if IsValid(entry.ragdoll) and IsValid(entry.source) then
            DrawFurBloodOverlayEntity(entry.ragdoll, entry.source)
        end
    end
end)

surface.CreateFont("CrunchyTechFont", { font = "Perfect DOS VGA 437", size = 18 })
surface.CreateFont("CrunchyTechFontBold", { font = "Perfect DOS VGA 437", size = 24 })

-- Tooltip Fonts
surface.CreateFont("RetroTooltipTitle", { font = "Retro Gaming", size = 20, weight = 600, antialias = false })
surface.CreateFont("RetroTooltipDesc", { font = "Retro Gaming", size = 20, weight = 400, antialias = false })

local path = "casunknown-images/"
local Mat = {
    woundbg = PaddedMaterial(path .. "other/woundpanel.png"),
    compback = PaddedMaterial(path .. "other/computerback.png"),
    screenStatic = PaddedMaterial(path .. "screen/screenstatic.png"),
    screenSmallStatic = PaddedMaterial(path .. "screen/screensmallstatic.png"),
    depressionOverlay = PaddedMaterial(path .. "screen/depressionoverlay.png"),
    criticalPiece = PaddedMaterial(path .. "screen/criticalpanelpiece.png"),
    newdeath = PaddedMaterial(path .. "screen/newdeath.png"),
    newdeathviolent = PaddedMaterial(path .. "screen/newdeathviolent.png"),
    newdeathdrowning = PaddedMaterial(path .. "screen/newdeathdrowning.png"),
    resultspage = PaddedMaterial(path .. "screen/resultspage.png"),
    barBrain = PaddedMaterial(path .. "screen/barbrain.png"),
    barBlood = PaddedMaterial(path .. "screen/barblood.png"),
    barFood = PaddedMaterial(path .. "screen/barfood.png"),
    barThirst = PaddedMaterial(path .. "screen/barwater.png"),
    barThermometer = PaddedMaterial(path .. "screen/barthermometer.png"),
    barLimb = PaddedMaterial(path .. "screen/barlimb.png"),
    barHemothorax = PaddedMaterial(path .. "screen/hemothoraxfill.png"),
    lungFill = PaddedMaterial(path .. "screen/lungfill.png"),
    barForce = PaddedMaterial(path .. "screen/barForce.png"),
    unconsciousVignette = Material("casunknown-images/screen/unconsciousvignette.png", "smooth noclamp"),
    gradientR = Material("vgui/gradient-r"),
    gradUp = Material("vgui/gradient-u"),
    gradDown = Material("vgui/gradient-d"),
    gradLeft = Material("vgui/gradient-l"),
    gradRight = Material("vgui/gradient-r")
}

WoundSystemHealthGuiMats = WoundSystemHealthGuiMats or {}
WoundSystemHealthGuiMats.woundbg = Mat.woundbg
WoundSystemHealthGuiMats.compback = Mat.compback
WoundSystemHealthGuiMats.screenStatic = Mat.screenStatic
WoundSystemHealthGuiMats.screenSmallStatic = Mat.screenSmallStatic
WoundSystemHealthGuiMats.barBrain = Mat.barBrain
WoundSystemHealthGuiMats.barBlood = Mat.barBlood
WoundSystemHealthGuiMats.barFood = Mat.barFood
WoundSystemHealthGuiMats.barThirst = Mat.barThirst
WoundSystemHealthGuiMats.barThermometer = Mat.barThermometer
WoundSystemHealthGuiMats.barLimb = Mat.barLimb
WoundSystemHealthGuiMats.barHemothorax = Mat.barHemothorax
WoundSystemHealthGuiMats.lungFill = Mat.lungFill
WoundSystemHealthGuiMats.barForce = Mat.barForce
WoundSystemPaddedMaterialInfo = PaddedMaterialInfo


-- Define it globally or file-scoped at the top of your client file
blindEyeSide = blindEyeSide or 1

-- Randomize it when the player first spawns or respawns
local function RandomizeBlindEye()
    blindEyeSide = (math.random() > 0.5) and 1 or -1
end

-- Hook 1: Runs when the client initially spawns into the map
hook.Add("InitPostEntity", "WoundSystem_InitialEyeSide", function()
    RandomizeBlindEye()
end)

-- Hook 2: Runs on the client every time a player respawns
hook.Add("PlayerSpawn", "WoundSystem_RespawnEyeSide", function(ply)
    if hg and hg.override and hg.override[ply] then return end -- Z-City fake-ragdoll get-up, not a real respawn
    -- Crucial check: Only change the variable if the spawning player is YOU
    if ply == LocalPlayer() then
        WoundSystem.HealthGUI.NoteLocalRespawn()
        SetDeathScreenActive(false)
        spawnVisualGraceUntil = CurTime() + 3
        if WoundSystemScreenFX and WoundSystemScreenFX.ResetVisualState then
            WoundSystemScreenFX.ResetVisualState()
        end
        WoundSystem.HealthGUI.DelayedRespawnCursorRelease("spawn_eye_side")
        RandomizeBlindEye()
    end
end)


if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
end

if not (WoundSystemDislocationMinigame and WoundSystemDislocationMinigame._Loaded) and file.Exists("woundsystem/client/minigames/cl_dislocation.lua", "LUA") then
    include("woundsystem/client/minigames/cl_dislocation.lua")
end

if not (WoundSystemBandageMinigame and WoundSystemBandageMinigame._Loaded) and file.Exists("woundsystem/client/minigames/cl_bandage.lua", "LUA") then
    include("woundsystem/client/minigames/cl_bandage.lua")
end

if not (WoundSystemSyringeMinigame and WoundSystemSyringeMinigame._Loaded) and file.Exists("woundsystem/client/minigames/cl_syringe.lua", "LUA") then
    include("woundsystem/client/minigames/cl_syringe.lua")
end

if not (WoundSystemAEDMinigame and WoundSystemAEDMinigame._Loaded) and file.Exists("woundsystem/client/minigames/cl_aed.lua", "LUA") then
    include("woundsystem/client/minigames/cl_aed.lua")
end

-- Glass shards live in the Z-City bridge, not in the WoundSystem limb state (no shrapnel field).
if not (WoundSystemShrapnelMinigame and WoundSystemShrapnelMinigame._Loaded) and file.Exists("woundsystem/client/minigames/cl_shrapnel.lua", "LUA") then
    include("woundsystem/client/minigames/cl_shrapnel.lua")
end

WoundSystemGlassShards = WoundSystemGlassShards or {}
net.Receive("WoundSystem_GlassStatus", function()
    local shards = {}
    local count = net.ReadUInt(5)
    for _ = 1, count do
        local limbId = net.ReadString()
        shards[limbId] = net.ReadUInt(4)
    end
    WoundSystemGlassShards = shards
end)

local DynamicFontCache = {}

function WoundSystemGetFont(baseFontName, scale)
    scale = scale or 1.0
    local quantScale = math.Round(scale * 20) * 0.05
    if quantScale == 1.0 then return baseFontName end

    local fontKey = baseFontName .. "_" .. math.floor(quantScale * 100)
    if not DynamicFontCache[fontKey] then
        local baseSizes = {
            TechScannerFont = 33,
            TechScannerSmall = 25,
            TechScannerMedium = 30,
            CrunchyTechFont = 18,
            CrunchyTechFontBold = 24,
            RetroTooltipTitle = 20,
            RetroTooltipDesc = 20,
            RetroMinigameGuide = 18,
            WoundSystemAEDStatus = 36
        }
        local baseFonts = {
            TechScannerFont = "I pixel u Regular",
            TechScannerSmall = "I pixel u Regular",
            TechScannerMedium = "I pixel u Regular",
            CrunchyTechFont = "Perfect DOS VGA 437",
            CrunchyTechFontBold = "Perfect DOS VGA 437",
            RetroTooltipTitle = "Retro Gaming",
            RetroTooltipDesc = "Retro Gaming",
            RetroMinigameGuide = "Retro Gaming",
            WoundSystemAEDStatus = "Retro Gaming"
        }
        local baseWeight = {
            TechScannerFont = 500,
            TechScannerSmall = 500,
            TechScannerMedium = 500,
            CrunchyTechFont = 400,
            CrunchyTechFontBold = 700,
            RetroTooltipTitle = 600,
            RetroTooltipDesc = 400,
            RetroMinigameGuide = 500,
            WoundSystemAEDStatus = 400
        }

        local baseSize = baseSizes[baseFontName] or 25
        local newSize  = math.Clamp(math.Round(baseSize * quantScale), 8, 72)
        local fontName = baseFonts[baseFontName] or "I pixel u Regular"

        surface.CreateFont(fontKey, {
            font      = fontName,
            size      = newSize,
            weight    = baseWeight[baseFontName] or 500,
            antialias = false,
            extended  = true
        })
        DynamicFontCache[fontKey] = true
    end

    return fontKey
end

surface.CreateFont("TechScannerFont", {
    font      = "I pixel u Regular",
    size      = 33,
    weight    = 500,
    antialias = false,
    extended  = true
})

surface.CreateFont("TechScannerSmall", {
    font      = "I pixel u Regular",
    size      = 25,
    weight    = 500,
    antialias = false,
    extended  = true
})

surface.CreateFont("TechScannerMedium", {
    font      = "I pixel u Regular",
    size      = 30,
    weight    = 500,
    antialias = false,
    extended  = true
})

local iconPath = path .. "icons/"
local bottomuiPath = path .. "bottomui/"
local Icons
WoundSystemBloodIconMaterialCache = WoundSystemBloodIconMaterialCache or {}

function WoundSystemRedBloodEnabled()
    local cvBloodColor = GetConVar("woundsys_blood_color")
    return string.lower(string.Trim(cvBloodColor and cvBloodColor:GetString() or "alien_yellow")) == "red"
end

function WoundSystemCachedPaddedMaterial(matPath)
    if not WoundSystemBloodIconMaterialCache[matPath] then
        WoundSystemBloodIconMaterialCache[matPath] = PaddedMaterial(matPath)
    end

    return WoundSystemBloodIconMaterialCache[matPath]
end

function WoundSystemBloodVariantMaterial(defaultPath, redPath)
    if WoundSystemRedBloodEnabled() and redPath and file.Exists("materials/" .. redPath, "GAME") then
        return WoundSystemCachedPaddedMaterial(redPath)
    end

    return WoundSystemCachedPaddedMaterial(defaultPath)
end

function WoundSystemRefreshBloodIconMaterials()
    if WoundSystemHealthGuiMats then
        WoundSystemHealthGuiMats.barHemothorax = WoundSystemBloodVariantMaterial(path .. "screen/hemothoraxfill.png", path .. "screen/hemothoraxfill_red.png")
    end

    if not Icons then return end

    Icons.disfiguredExpWound = WoundSystemBloodVariantMaterial(iconPath .. "disfiguredExpWound.png", iconPath .. "disfiguredexpwound_red.png")
    Icons.injection = WoundSystemBloodVariantMaterial(iconPath .. "injectionWound.png", iconPath .. "injectionwound_red.png")
    Icons.eyeGone = WoundSystemBloodVariantMaterial(iconPath .. "eyeGoneExpWound.png", iconPath .. "eyegoneexpwound_red.png")
end

Icons = {
    smallbleed = PaddedMaterial(iconPath .. "smallbleeding.png"),
    smallbleed_bandaged = PaddedMaterial(iconPath .. "smallbleedingbandaged.png"),
    midbleed = PaddedMaterial(iconPath .. "midbleeding.png"),
    midbleed_bandaged = PaddedMaterial(iconPath .. "midbleedingbandaged.png"),
    strongbleed = PaddedMaterial(iconPath .. "strongbleed.png"),
    strongbleed_bandaged = PaddedMaterial(iconPath .. "strongbleedbandaged.png"),
    extremebleed = PaddedMaterial(iconPath .. "bleeding.png"),
    extremebleed_bandaged = PaddedMaterial(iconPath .. "bleedingbandaged.png"),
    infection_up = PaddedMaterial(iconPath .. "infectionup.png"),
    infection_down = PaddedMaterial(iconPath .. "infectiondown.png"),
    infectionneutral = PaddedMaterial(iconPath .. "infection.png"),
    disinfected = PaddedMaterial(iconPath .. "disinfected.png"),
    dislocate = PaddedMaterial(iconPath .. "dislocatedbone.png"),
    disfiguredExpWound = WoundSystemBloodVariantMaterial(iconPath .. "disfiguredExpWound.png", iconPath .. "disfiguredexpwound_red.png"),
    fracture = PaddedMaterial(iconPath .. "fracturedbone.png"),
	fracture2 = PaddedMaterial(bottomuiPath .. "fracturedbone.png"),
    injection = WoundSystemBloodVariantMaterial(iconPath .. "injectionWound.png", iconPath .. "injectionwound_red.png"),
    bloodbagfill = PaddedMaterial(path .. "items/bloodbagfill.png"),
    eyeGone = WoundSystemBloodVariantMaterial(iconPath .. "eyeGoneExpWound.png", iconPath .. "eyegoneexpwound_red.png"),
    selfHarmWound = WoundSystemBloodVariantMaterial("casunknown-images/selfharm/selfHarmWound.png", "casunknown-images/selfharm/selfHarmWound.png"),
    suicideWound = WoundSystemBloodVariantMaterial("casunknown-images/selfharm/suicideWound.png", "casunknown-images/selfharm/suicideWound.png"),
    limbbleedouter = PaddedMaterial(bottomuiPath .. "limbbleedouter.png"),
    limbbleed = PaddedMaterial(bottomuiPath .. "limbbleed.png"),
    uiPoint = PaddedMaterial(path .. "screen/uiPoint.png"),
    -- glass shard sprite (shared with the glass minigame); no shrapnel status icon remains
    glass = PaddedMaterial("casunknown-images/shrapnelminigame/shrapnelpiece.png")
}

if cvars and cvars.AddChangeCallback then
    cvars.AddChangeCallback("woundsys_blood_color", WoundSystemRefreshBloodIconMaterials, "WoundSystem_BloodIconMaterials")
end

local StatusIconCache = {}

local function GetStatusIconMaterial(statusData)
    if not statusData or not statusData.icon or statusData.icon == "" then return nil end

    local icon = statusData.icon
    if not StatusIconCache[icon] then
        StatusIconCache[icon] = PaddedMaterial(icon)
    end

    return StatusIconCache[icon]
end

local function GetStatusIconColor(statusData, alpha, statusValue)
    if statusData and statusData.id == "TOURNIQUET" then
        local elapsed = math.Clamp((tonumber(statusValue) or 0) / 540, 0, 1)
        return Color(255, 255 - (180 * elapsed), 255 - (180 * elapsed), alpha)
    end

    local color = statusData and statusData.color
    if color then
        return Color(color.r or color[1] or 255, color.g or color[2] or 255, color.b or color[3] or 255, alpha)
    end

    return Color(255, 255, 255, alpha)
end

function WoundSystem.Client.GetBloodBagFillColor(alpha)
    local r, g, b = GetBloodRGB()
    return Color(r, g, b, alpha or 255)
end

function WoundSystem.Client.IsBloodBagTool(toolName)
    return ((WoundSystem.NormalizeItemId and WoundSystem.NormalizeItemId(toolName)) or string.upper(tostring(toolName or ""))) == "BLOOD BAG"
end

function WoundSystem.Client.DrawBloodBagItemIcon(slotData, x, y, w, h, pct, alpha)
    pct = WoundSystem.Client.PixelSnapFill(Icons.bloodbagfill, pct, true)
    alpha = tonumber(alpha) or 255

    if Icons.bloodbagfill and not Icons.bloodbagfill:IsError() and pct > 0 then
        SetGuiMaterial(Icons.bloodbagfill)
        local fillColor = WoundSystem.Client.GetBloodBagFillColor(alpha)
        surface.SetDrawColor(fillColor.r, fillColor.g, fillColor.b, fillColor.a)
        DrawRectUVInt(x, y + (h * (1 - pct)), w, h * pct, 0, 1 - pct, 1, 1)
    end

    if slotData and slotData.mat and not slotData.mat:IsError() then
        SetGuiMaterial(slotData.mat)
        surface.SetDrawColor(255, 255, 255, alpha)
        DrawRectInt(x, y, w, h)
    end
end

-- ==========================================
-- LIMB UI CONFIG
-- ==========================================
WoundSystemLimbUIConfig = {
    IconSpread = {
        Collapsed = 0.2,
        Selected = 1.0,
        HoverBoost = 0.25,
        SmoothSpeed = 5,
        StepX = 50,
        StepY = 0.2
    },
    ActionPoint = {
        Width = 180,
        Height = 60,
        OffsetX = 0,
        OffsetY = -60,
        HoverScale = 1,
        LerpSpeed = 4,
        Alpha = 255,
        HoverAlpha = 255,
        ActiveAlpha = 255,
        TextEnabled = true,
        TextFont = "RetroTooltipDesc",
        TextOffsetX = -85,
        TextOffsetY = -20,
        TextColor = Color(255, 255, 255, 255),
        TextHoverColor = Color(255, 255, 255, 255),
        TextActiveColor = Color(255, 255, 255, 255),
        Actions = {
            TOURNIQUET = {
                Text = "REMOVE TOURNIQUET",
                TooltipKey = "removetourniquet",
                Width = 215,
                Height = 60,
                OffsetX = 0,
                OffsetY = -60,
                TextOffsetX = -103,
                TextOffsetY = -20
            },
            SPLINTED = {
                Text = "REMOVE SPLINT",
                TooltipKey = "removesplint",
                Width = 170,
                Height = 60,
                OffsetX = 0,
                OffsetY = -60,
                TextOffsetX = -78,
                TextOffsetY = -20
            },
            GLASS = {
                Text = "REMOVE GLASS",
                TooltipKey = "removeglass",
                Width = 180,
                Height = 60,
                OffsetX = 0,
                OffsetY = -60,
                TextOffsetX = -85,
                TextOffsetY = -20
            },
            DISLOCATION = {
                Text = "FIX DISLOCATION",
                TooltipKey = "fixdislocation",
                Width = 195,
                Height = 60,
                OffsetX = 0,
                OffsetY = -60,
                TextOffsetX = -92,
                TextOffsetY = -20
            }
        }
    },
    Fracture = {
        X = 190, Y = 83, -- Position relative to the limb panel origin
        Width = 60, Height = 82,
        TextOffsetX = -25, TextOffsetY = 32
    },
    Bleed = {
        X = 250, Y = 100,
        OuterWidth = 94, OuterHeight = 68,
        InnerWidth = 30, InnerHeight = 49,
        InnerOffsetX = 59, InnerOffsetY = 14, -- Inner bar relative to outer
        TextOffsetX = 51, TextOffsetY = 10,
        FillThreshold = 1 -- When the bleed bar stops filling up
    }
}

-- ==========================================
-- LUNG UI CONFIG
-- ==========================================
WoundSystemLungConfig = {
    Width = 19,                 -- Width of a SINGLE lung
    Height = 43,                -- Height of the lungs
    OffsetX = 33.5,               -- X Position on the tablet (Center point between lungs)
    OffsetY = 340,              -- Y Position on the tablet (Top of the lungs)
    Distance = 20,               -- Space between the left and right lung
    Color = Color(255, 255, 255, 255),
    FillFromBottom = true,      -- If true, fills from bottom going up (depletes vertically down).
    UseStamina = true,          -- NEW: If true, uses Stamina.
    UseRespiratoryRate = false,  -- If true (and UseStamina is false), uses Respiratory Rate. If both false, uses Blood Oxygen.
    
    -- FULL ORIENTATION CONTROL
    FlipLeftHorizontal = false,  -- Flips the LEFT lung horizontally (Left <-> Right)
    FlipLeftVertical = false,   -- Flips the LEFT lung vertically (Upside down)
    FlipRightHorizontal = true,-- Flips the RIGHT lung horizontally
    FlipRightVertical = false   -- Flips the RIGHT lung vertically
}

-- ==========================================
-- MEDICAL TOOL DURABILITY & TOOLTIP CONTENT
-- ==========================================
WoundSystemMedToolConfig = (WoundSystem.Items and WoundSystem.Items.BuildLegacyToolConfig and WoundSystem.Items.BuildLegacyToolConfig()) or {
    ["BRUISE KIT"] = { 
        max = 100, 
        title = "Bruise kit", 
        desc = "A combination of drugs and other medicines, made to \naid muscle healing. Increases muscle/skin health and \nhighly aids dislocations. Doesn't affect bleeding." 
    },
    ["DISINFECTANT"] = { 
        max = 200, 
        title = "Disinfectant", 
        desc = "A 0.2L plastic bottle with a spray nozzle on it. Can \nspray up to 10ml of liquid at a time."
    },
    ["GAUZE"] = { 
        max = 100, 
        title = "Dressing", 
        desc = "A roll of dressing with a bandage, used to slow down \nbleeding, stabilize fractures and aid skin healing. Has \nno effect on muscle health."
    },
	
	["INJECTION"] = { 
		max = 10, -- Example durability
		title = "Chest drain", 
		desc = "Used to drain fluid from the thorax. Reduces \nhemothorax, reusable after some time. Only usable \non the chest." 
	}
}

-- ==========================================
-- TOOLTIP VISUAL CONFIGURATION
-- ==========================================
WoundSystemTooltipStyle = {
    backgroundColor   = Color(10, 10, 11, 245), -- Greyish Black
    titleColor         = Color(255,255,255),   -- Main text color (and parentheses)
    descriptionColor   = Color(120, 120, 120),   -- Body text color
    
    cursorOffsetX      = 0,
    cursorOffsetY      = 0,
    
    tabPaddingX        = 0,  -- Horizontal distance from text to edge (Header)
    tabPaddingY        = 2,   -- Vertical distance from text to edge (Header)
    
    bodyPaddingX       = 1,  -- Horizontal distance from text to edge (Body)
    bodyPaddingY       = 2,  -- Vertical distance from text to edge (Body)
    
    lineSpacing        = 16,  -- Space between lines of description
    headerBodyGap      = 0,   -- Space between tab and body (0 is flush)
    
    fontTitle          = "RetroTooltipTitle",
    fontDesc           = "RetroTooltipDesc"
}

WoundSystemCasTooltipText = {
    hpbrainhealth = {"Brain integrity", ""},
    hpconsciousness = {"Consciousness", ""},
    hppain = {"Total pain", "Max. pain from all limbs"},
    hpbloodvolume = {"Blood volume", "Total blood volume in the body. You can lose about half of it before succumbing."},
    hpbleedspeed = {"Total bleeding speed", ""},
    hpoxygenamount = {"SpO2", "Oxygen concentration in the bloodstream. Will slowly cause complications below 80%."},
    hpimmunity = {"Immunity", "Your body's ability to fight off infections.\nLow immunity makes infections progress even when disinfected."},
    hptemperature = {"Core temperature", "Hypothermia becomes lethal at around 28 degrees, and hyperthermia at 42."},
    hpsickness = {"Sickness", ""},
    hphappiness = {"Mood", ""},
    hphunger = {"Hunger", ""},
    hpthirst = {"Thirst", ""},
    hpweight = {"Body mass", ""},
    hpstamina = {"Stamina", "Physical exertion"},
    hprr = {"Respiratory rate", ""},
    hpenergy = {"Energy", "How sleepy you are\nYou can sleep below 35% energy"},
    hpheartrate = {"Heart rate", "How fast your heart is beating. Make sure this number doesn't reach 0."},
    hppressure = {"Blood pressure", "Systolic and diastolic pressure. It should stay around 120/80."},
    hpecg = {"ECG", "Basic visualization of your heart rhythm.\nYou should worry if it ever looks more like a sinewave than a heartbeat."},
    hpradiation = {"Radiation sickness", ""},
    hpselectedlimb = {"Selected limb", ""},
    hpskinhealth = {"Skin health", "The barrier against infections and bleeding.\n\nWill heal much slower below 10"},
    hpmusclehealth = {"Muscle health", "The vitality and strength of the limb.\n\nWill heal much slower below 10"},
    hplimbinjury = {"Time to heal injury", ""},
    hpinfection = {"Limb infection", ""},
    hplimbpain = {"Limb pain", ""},
    hplimbbleed = {"Limb bleeding", ""},
    hplimbforce = {"Limb strength", "The limb's total ability to move and exert force"},
    removetourniquet = {"Remove tourniquet", ""},
    removesplint = {"Remove splint", "Take off the splint from the limb"},
    fixdislocation = {"Fix dislocation", "Try to correct the dislocation by hand"},
    removeglass = {"Remove glass", "Pull the glass shards out of the limb"}
}

if WoundSystem.CAS3Locale and WoundSystem.CAS3Locale.ApplyHealthTooltips then
    WoundSystem.CAS3Locale.ApplyHealthTooltips(WoundSystemCasTooltipText)
end

WoundSystemQueuedWoundTooltip = WoundSystemQueuedWoundTooltip or {active = false, priority = -1}
WoundSystemTooltipAnim = WoundSystemTooltipAnim or {key = "", scale = 0.1}

function WoundSystemTooltipText(localeKey)
    local entry = WoundSystemCasTooltipText[localeKey]
    if not entry then return tostring(localeKey or ""), "" end
    return entry[1] or "", entry[2] or ""
end

function WoundSystemResetTooltipQueue()
    WoundSystemQueuedWoundTooltip.active = false
    WoundSystemQueuedWoundTooltip.priority = -1
    WoundSystemQueuedWoundTooltip.key = nil
    WoundSystemQueuedWoundTooltip.title = nil
    WoundSystemQueuedWoundTooltip.desc = nil
    WoundSystemQueuedWoundTooltip.opts = nil
end

function WoundSystemQueueDirectTooltip(key, title, desc, priority, opts)
    priority = priority or 0
    if not title or title == "" or priority < (WoundSystemQueuedWoundTooltip.priority or -1) then return false end

    WoundSystemQueuedWoundTooltip.active = true
    WoundSystemQueuedWoundTooltip.priority = priority
    WoundSystemQueuedWoundTooltip.key = key or title
    WoundSystemQueuedWoundTooltip.title = title
    WoundSystemQueuedWoundTooltip.desc = desc or ""
    WoundSystemQueuedWoundTooltip.opts = opts
    return true
end

function WoundSystemQueueLocaleTooltip(localeKey, x, y, w, h, mx, my, priority)
    if mx < x or mx > x + w or my < y or my > y + h then return false end

    local title, desc = WoundSystemTooltipText(localeKey)
    return WoundSystemQueueDirectTooltip(localeKey, title, desc, priority or 0)
end

function WoundSystemTooltipLines(text)
    text = CorruptUIText(text or "")
    if text == "" then return {""} end
    return string.Explode("\n", text)
end

function WoundSystemDrawCasTooltip(title, desc, mx, my, key, opts)
    title = tostring(title or "")
    if title == "" then return end

    local style = WoundSystemTooltipStyle
    local scale = (ScrH() / 1080) * UIScale()
    local margin = 30 * scale
    local dt = RealFrameTime and RealFrameTime() or FrameTime()
    key = tostring(key or title)

    if WoundSystemTooltipAnim.key ~= key then
        WoundSystemTooltipAnim.key = key
        WoundSystemTooltipAnim.scale = (opts and opts.noPop) and 1 or 0.1
    end

    if opts and opts.noPop then
        WoundSystemTooltipAnim.scale = 1
    else
        WoundSystemTooltipAnim.scale = Lerp(math.Clamp(dt * 24, 0, 1), WoundSystemTooltipAnim.scale or 0.1, 1)
    end
    local popScale = math.Clamp(WoundSystemTooltipAnim.scale or 1, 0.1, 1)

    local titleText = CorruptUIText(title)
    local durPct = opts and opts.durPct
    local durText = durPct and (math.Round(math.Clamp(durPct, 0, 1) * 100) .. "%") or nil
    local headerFullText = durText and (titleText .. " (" .. durText .. ")") or titleText
    local descLines = WoundSystemTooltipLines(desc)

    local titleFont = WoundSystemGetFont(style.fontTitle, scale)
    local descFont  = WoundSystemGetFont(style.fontDesc, scale)
    local lineSpacing = math.max(12, math.Round(style.lineSpacing * scale))

    surface.SetFont(titleFont)
    local tW, tH = surface.GetTextSize(headerFullText)

    surface.SetFont(descFont)
    local maxDescW = 0
    for _, line in ipairs(descLines) do
        maxDescW = math.max(maxDescW, surface.GetTextSize(line))
    end

    local tabW = tW + (style.tabPaddingX * 2 * scale)
    local tabH = tH + (style.tabPaddingY * 2 * scale)
    local bodyW = math.max(tabW + (style.bodyPaddingX * 2 * scale), maxDescW + (style.bodyPaddingX * 2 * scale))
    local bodyH = (#descLines * lineSpacing) + (style.bodyPaddingY * 2 * scale) + (10 * scale)
    local totalH = tabH + (style.headerBodyGap * scale) + bodyH

    local offsetX = opts and opts.offsetX
    local offsetY = opts and opts.offsetY
    local tipX = (mx or 0) + (offsetX ~= nil and offsetX or style.cursorOffsetX or 0)
    local tipY = (my or 0) + (offsetY ~= nil and offsetY or style.cursorOffsetY or 0)

    if tipX + bodyW * popScale > ScrW() - margin then tipX = ScrW() - margin - bodyW * popScale end
    if tipY + totalH * popScale > ScrH() - margin then tipY = ScrH() - margin - totalH * popScale end
    tipX = math.max(margin, tipX)
    tipY = math.max(margin, tipY)

    local pushedMatrix = false
    if cam and cam.PushModelMatrix and Matrix then
        local matrix = Matrix()
        matrix:Translate(Vector(tipX, tipY, 0))
        matrix:Scale(Vector(popScale, popScale, 1))
        matrix:Translate(Vector(-tipX, -tipY, 0))
        cam.PushModelMatrix(matrix, true)
        pushedMatrix = true
    end

    surface.SetDrawColor(style.backgroundColor.r, style.backgroundColor.g, style.backgroundColor.b, style.backgroundColor.a)
    surface.DrawRect(tipX, tipY, tabW, tabH)
    surface.DrawRect(tipX, tipY + tabH + (style.headerBodyGap * scale), bodyW, bodyH)

    surface.SetFont(titleFont)
    local currentX = tipX + (style.tabPaddingX * scale)
    draw.SimpleText(titleText, titleFont, currentX, tipY + (style.tabPaddingY * scale), style.titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    if durText then
        currentX = currentX + surface.GetTextSize(titleText)
        draw.SimpleText(" (", titleFont, currentX, tipY + (style.tabPaddingY * scale), style.titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        currentX = currentX + surface.GetTextSize(" (")

        local durColor = HSVToColor(math.Clamp(durPct or 0, 0, 1) * 120, 0.8, 0.9)
        draw.SimpleText(durText, titleFont, currentX, tipY + (style.tabPaddingY * scale), durColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        currentX = currentX + surface.GetTextSize(durText)
        draw.SimpleText(")", titleFont, currentX, tipY + (style.tabPaddingY * scale), style.titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local startY = tipY + tabH + (style.headerBodyGap * scale) + (style.bodyPaddingY * scale)
    for i, line in ipairs(descLines) do
        draw.SimpleText(line, descFont, tipX + (style.bodyPaddingX * scale), startY + ((i - 1) * lineSpacing), style.descriptionColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    if pushedMatrix then
        cam.PopModelMatrix()
    end
end

function WoundSystemDrawQueuedTooltip(mx, my)
    if not WoundSystemQueuedWoundTooltip.active then
        WoundSystemTooltipAnim.key = ""
        WoundSystemTooltipAnim.scale = 0.1
        return
    end

    WoundSystemDrawCasTooltip(WoundSystemQueuedWoundTooltip.title, WoundSystemQueuedWoundTooltip.desc, mx, my, WoundSystemQueuedWoundTooltip.key, WoundSystemQueuedWoundTooltip.opts)
end

WoundSystem.Client.TooltipText = WoundSystemTooltipText
WoundSystem.Client.QueueDirectTooltip = WoundSystemQueueDirectTooltip
WoundSystem.Client.QueueLocaleTooltip = WoundSystemQueueLocaleTooltip
WoundSystem.Client.ResetTooltipQueue = WoundSystemResetTooltipQueue
WoundSystem.Client.DrawQueuedTooltip = WoundSystemDrawQueuedTooltip

local PlayerLimbs = {}
local defaultLimbState = { 
    skin = 100, 
    muscle = 100, 
    muscleStrength = 1,
    pain = 0, 
    bleed = 0, 
    infection = 0,
    infectionSpeed = 0, 
    disinfectTime = 0,
    dislocated = false,
    broken = false, 
    dislocationTimer = 0,
    boneHealTimer = 0,
    temperature = 37,
    oxygen = 100,
    stress = 0,
    isBandaged = false,
    dismembered = false,
    furBloodAmount = 0,
    bandageMinigameSpeedMult = 1,
    customStatuses = {}
}

local CardioState = {
    hemothorax = 0,
    heartRate = 70,
    respiratoryRate = 100,
    bloodPressure = 120,
    bloodOxygen = 98,
    fibrillationProgress = 0,
    cardioShock = 0,
    adrenaline = 0,
    temperature = 37,
    avgPain = 0,
    immunity = 100,
    brainHealth = 100,
    consciousness = 100,
    unconscious = false,
    stamina = 100,
    hunger = 100,
    thirst = 100,
    energy = 100,
    weightOffset = 0,
    bloodViscosity = 0,
    radiationSickness = 0,
    wetness = 0,
    totalBleedSpeed = 0,
    sicknessAmount = 0,
    septicShock = 0,
    hearingLoss = 0,
    strokeAmount = 0,
    hasPulmonaryEmbolism = false,
    dirtyness = 0,
    traumaAmount = 0,
    clawHealth = 100,
    clawRegrowTime = 0,
    caffeinated = 0,
    badSleepAmount = 0,
    venomCurrent = 0,
    overdoseIndex = 0,
    painShock = 0,
    opiateHappiness = 0,
    antidepressantHappiness = 0,
    opiateAmount = 0,
    opiateReception = 0,
    actualOpiateReception = 0,
    opiateTolerance = 0,
    lastStandTime = 0,
    focusedLevel = 0,
    horrifiedLevel = 0,
    overEncumberance = 0,
    brainGrowSickness = 0,
    sleeping = false,
    disfigured = false,
    eyeGone = false,
    bothEyesGone = false,
    onHardStimulants = false,
    impairedSpeech = false,
    mindWipe = false
}

local PlayerStats = {
    STR = 9,
    RES = 8,
    INT = 7,
    consciousness = 100
}

WoundSystemClientState = WoundSystemClientState or {}
WoundSystemClientState.PlayerLimbs = PlayerLimbs

-- Muscle health accessors (C# muscleHealth per limb, synced via WoundSystem_UpdateLimb)
-- Usage: WoundSystem.GetLimbMuscleHealth("thorax")  /  WoundSystem.GetAllLimbMuscleHealth()
WoundSystemClientState.Cardio = CardioState
WoundSystemClientState.PlayerStats = PlayerStats

local function ResetSpawnNeutralBodyState()
    for k in pairs(PlayerLimbs) do
        PlayerLimbs[k] = table.Copy(defaultLimbState)
    end

    CardioState.bloodVolume = 100
    CardioState.internalBleeding = 0
    CardioState.hemothorax = 0
    CardioState.heartRate = 70
    CardioState.respiratoryRate = 100
    CardioState.bloodPressure = 120
    CardioState.bloodOxygen = 98
    CardioState.fibrillationProgress = 0
    CardioState.cardioShock = 0
    CardioState.adrenaline = 0
    CardioState.temperature = 37
    CardioState.avgPain = 0
    CardioState.brainHealth = 100
    CardioState.consciousness = 100
    CardioState.unconscious = false
    CardioState.stamina = 100
    CardioState.hunger = 100
    CardioState.thirst = 100
    CardioState.energy = 100
    CardioState.wetness = 0
    CardioState.totalBleedSpeed = 0
    CardioState.sicknessAmount = 0
    CardioState.septicShock = 0
    CardioState.strokeAmount = 0
    CardioState.hasPulmonaryEmbolism = false
    CardioState.dirtyness = 0
    CardioState.traumaAmount = 0
    CardioState.caffeinated = 0
    CardioState.badSleepAmount = 0
    CardioState.venomCurrent = 0
    CardioState.overdoseIndex = 0
    CardioState.painShock = 0
    CardioState.opiateAmount = 0
    CardioState.opiateReception = 0
    CardioState.actualOpiateReception = 0
    CardioState.focusedLevel = 0
    CardioState.horrifiedLevel = 0
    CardioState.overEncumberance = 0
    CardioState.brainGrowSickness = 0
    CardioState.sleeping = false
    CardioState.disfigured = false
    CardioState.eyeGone = false
    CardioState.bothEyesGone = false
    CardioState.onHardStimulants = false
    CardioState.impairedSpeech = false
    CardioState.mindWipe = false
    PlayerStats.STR = 9
    PlayerStats.RES = 8
    PlayerStats.INT = 7
    PlayerStats.consciousness = 100
    WoundSystemClientState.Happiness = 0
end

local function ClientBleedingSpeedMultiplier()
    local vis = tonumber(CardioState.bloodViscosity) or 0
    local remapped = ((vis + 100) / 100) * (-0.01) + 0.01
    return 0.01 + math.Clamp(remapped, 0, 1)
end

local function ClientLimbBleedRate(state)
    if not state then return 0 end
    if state.blockedBleeding then return 0 end
    return math.max((tonumber(state.bleed) or 0) * ClientBleedingSpeedMultiplier(), 0)
end

WoundSystemHealthHUDOpen = WoundSystemHealthHUDOpen or false
WoundSystemSelectedLimbId = WoundSystemSelectedLimbId or nil
WoundSystemNextHealthPanelCriticalAlert = WoundSystemNextHealthPanelCriticalAlert or 0
WoundSystemActiveUISounds = WoundSystemActiveUISounds or {}
WoundSystemNextUISound = WoundSystemNextUISound or {}

local function PlayLoudUISound(soundPath, volume, minInterval)
    soundPath = tostring(soundPath or "")
    if soundPath == "" then return end

    local now = CurTime()
    minInterval = tonumber(minInterval) or 0
    if now < (WoundSystemNextUISound[soundPath] or 0) then return end
    WoundSystemNextUISound[soundPath] = now + minInterval

    volume = math.Clamp(tonumber(volume) or 1, 0, 10)

    local active = WoundSystemActiveUISounds[soundPath]
    if IsValid(active) then
        active:Stop()
        WoundSystemActiveUISounds[soundPath] = nil
    end

    sound.PlayFile("sound/" .. soundPath, "noblock noplay 2d", function(station)
        if IsValid(station) then
            WoundSystemActiveUISounds[soundPath] = station
            station:SetVolume(volume)
            station:Play()
        else
            surface.PlaySound(soundPath)
        end
    end)
end

local function GetToolConfig(toolName)
    if WoundSystem.Items and WoundSystem.Items.Get then
        local item = WoundSystem.Items.Get(toolName)
        if item then return item end
    end

    return WoundSystemMedToolConfig and WoundSystemMedToolConfig[toolName]
end

local function GetToolMax(toolName)
    local cfg = GetToolConfig(toolName)
    return (cfg and cfg.max) or 100
end

local function RefreshToolSlotVisual(slot)
    if not slot or slot.type ~= "tool" then return slot end

    if WoundSystem.Items and WoundSystem.Items.AttachClientVisual then
        WoundSystem.Items.AttachClientVisual(slot, PaddedMaterial)
    end

    if not slot.mat and slot.icon then
        slot.mat = PaddedMaterial(slot.icon)
    end

    return slot
end

local function CreateToolSlot(toolName, durability)
    if WoundSystem.Items and WoundSystem.Items.CreateSlot then
        local slot = WoundSystem.Items.CreateSlot(toolName, durability)
        if slot and slot.type ~= "empty" then
            return RefreshToolSlotVisual(slot)
        end
    end

    return RefreshToolSlotVisual({ type = "tool", toolName = toolName, durability = durability or GetToolMax(toolName), pw = 30, ph = 30 })
end

local function BuildDefaultInventory()
    if WoundSystem.Items and WoundSystem.Items.BuildDefaultInventory then
        return WoundSystem.Items.BuildDefaultInventory(PaddedMaterial)
    end

    return {
        [1] = { type = "tool", toolName = "BRUISE KIT", durability = 100, pw = 18, ph = 30, mat = PaddedMaterial(path .. "items/bruisekit.png") },
        [2] = { type = "tool", toolName = "DISINFECTANT", durability = 200, pw = 18, ph = 36, mat = PaddedMaterial(path .. "items/disinfectant.png") },
        [3] = { type = "tool", toolName = "GAUZE", durability = 100, pw = 24, ph = 24, mat = PaddedMaterial(path .. "items/gauze.png") },
        [4] = { type = "weapon" },
        [5] = { type = "empty" }
    }
end

WoundSystemInventorySlots = WoundSystemInventorySlots or BuildDefaultInventory()
for _, slot in pairs(WoundSystemInventorySlots) do
    RefreshToolSlotVisual(slot)
end

local function ApplySyncedInventorySlot(slotIdx, kind, toolName, durability)
    if kind == 1 then
        WoundSystemInventorySlots[slotIdx] = CreateToolSlot(toolName, durability)
        return
    end

    if kind == 2 then
        WoundSystemInventorySlots[slotIdx] = { type = "weapon" }
        return
    end

    WoundSystemInventorySlots[slotIdx] = { type = "empty" }
end

net.Receive("WoundSystem_SyncInventory", function()
    for i = 1, 5 do
        local kind = net.ReadUInt(2)
        if kind == 1 then
            ApplySyncedInventorySlot(i, kind, net.ReadString(), net.ReadFloat())
        else
            ApplySyncedInventorySlot(i, kind)
        end
    end

    -- temporary slot of a Z-City SWEP minigame (index 6, never drawn in the inventory)
    if net.ReadBool() then
        ApplySyncedInventorySlot(6, 1, net.ReadString(), net.ReadFloat())
    else
        WoundSystemInventorySlots[6] = nil
    end
end)

local function RequestInventoryMove(fromIdx, toIdx, op)
    net.Start("WoundSystem_InventoryMove")
        net.WriteUInt(fromIdx, 3)
        net.WriteUInt(toIdx, 3)
        net.WriteUInt(op, 3)
    net.SendToServer()
end

WoundSystem.Client = WoundSystem.Client or {}
WoundSystem.Client.RequestInventoryMove = RequestInventoryMove

WoundSystemDragState = WoundSystemDragState or { active = false, slotIdx = nil, startTime = 0, startX = 0, startY = 0 }

-- ECG buffer
local ECG = {
    points = 340,
    buffer = {},
    writeIndex = 1,
    lastTime = 0,
    currentHeartPhase = 0,
    lastVal = 0,
    lastBeatPhase = 0,
    hasPlayedAsystoleSound = false,
    asystoleSound = nil,
    asystoleVolume = 0.55
}
for i = 1, ECG.points do ECG.buffer[i] = 0 end

local function GetAsystoleVolume()
    local master = CVars.AudioMaster and CVars.AudioMaster:GetFloat() or 1
    local tinVol = CVars.TinnitusVolume and CVars.TinnitusVolume:GetFloat() or 1
    return ECG.asystoleVolume * math.Clamp(master, 0, 2) * math.Clamp(tinVol, 0, 2)
end

local function GetHearingMuffle()
    local severity = math.Clamp((CardioState.hearingLoss or 0) / 100, 0, 1)
    return 1 - (severity * 0.85), 100 * (1 - (severity * 0.18))
end

local GUIState = {
    selectedLimbData = nil,
    lastMouseState = false,
    lastRightMouseState = false,
    HoverAnims = {},
    LimbIconSpreadAnims = {},
    LastHoverStates = {},
    InfectionIconLatched = {},
    weaponIconCache = {},
    SlotClickTimes = {},
    SlotDropState = {},
    SlotDragHoverAnims = {0, 0, 0, 0, 0},
    unconsciousRagdoll = nil,
    unconsciousEyeAttachment = 0,
    hudOpen = false,
    lastKeyStatus = false,
    openTime = 0,
    cachedVitals = "100cm | 18y | #00000",
    targetHrvOffset = 0,
    currentHrvOffset = 0,
    hrvNextChange = 0,
    lastRagdollRequest = 0,
    EyeViewDisabled = false,
    forceClearRagdollCameraUntil = 0,
    wasHidingViewModel = false,
    blockSize = 12,
    staticCache = {},
    HudLimbShakeScratch = {},
    HudLimbScreenPointScratch = {},
    HudIconScratch = {},
    HudZeroShake = {x = 0, y = 0}
}

WoundSystemPrettyLimbNames = {
    head = "Head",
    thorax = "Thorax",
    abdomen = "Abdomen",
    arm_R = "Right Arm",
    forearm_R = "Right Forearm",
    hand_R = "Right Hand",
    arm_L = "Left Arm",
    forearm_L = "Left Forearm",
    hand_L = "Left Hand",
    thigh_R = "Right Thigh",
    crus_R = "Right Crus",
    foot_R = "Right Foot",
    thigh_L = "Left Thigh",
    crus_L = "Left Crus",
    foot_L = "Left Foot"
}

function WoundSystemPrettyLimbName(limbId)
    local name = WoundSystemPrettyLimbNames[limbId] or string.gsub(string.gsub(tostring(limbId or ""), "_", " "), "(%a)([%w_']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end)
    return string.upper(name)
end

function WoundSystemIsAnyWoundMinigameActive()
    local minigames = {
        WoundSystemDislocationMinigame,
        WoundSystemBandageMinigame,
        WoundSystemSyringeMinigame,
        WoundSystemAEDMinigame,
        WoundSystemShrapnelMinigame,
        WoundSystemSelfHarmMinigame
    }

    for _, minigame in ipairs(minigames) do
        if minigame and minigame.IsActive and minigame.IsActive() then
            return true
        end
    end

    return false
end

local function CloseWoundMinigames(reason)
    local minigames = {
        WoundSystemDislocationMinigame,
        WoundSystemBandageMinigame,
        WoundSystemSyringeMinigame,
        WoundSystemAEDMinigame,
        WoundSystemSelfHarmMinigame
    }

    for _, minigame in ipairs(minigames) do
        if minigame and minigame.RequestClose then
            minigame.RequestClose(reason or "hud_closed")
        end
    end
end

local function ShouldShowInfectionIndicator(limbId, infection)
    infection = tonumber(infection) or 0

    if infection >= 25 then
        GUIState.InfectionIconLatched[limbId] = true
    elseif infection < 1 then
        GUIState.InfectionIconLatched[limbId] = nil
    end

    return GUIState.InfectionIconLatched[limbId] == true and infection >= 1
end

local function RequestDislocationMinigameStart(limbId, slotIdx)
    if not limbId or limbId == "" then return end

    if WoundSystemDislocationMinigame and WoundSystemDislocationMinigame.RequestStart then
        WoundSystemDislocationMinigame.RequestStart(limbId, slotIdx)
        return
    end

    net.Start("WoundSystem_DislocationStart")
        net.WriteString(limbId)
        net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

-- Glass shards: the session is owned by the Z-City bridge (sv_woundbridge.lua)
local function RequestGlassMinigameStart(limbId, slotIdx)
    if not limbId or limbId == "" then return end

    if WoundSystemShrapnelMinigame and WoundSystemShrapnelMinigame.RequestStart then
        WoundSystemShrapnelMinigame.RequestStart(limbId, slotIdx)
        return
    end

    net.Start("WoundSystem_GlassStart")
        net.WriteString(limbId)
        net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

local function IsBandageTreatable(state)
    return state and (state.bleed > 0 or state.skin < 100 or state.broken or state.dislocated)
end

local function RequestRemoveLimbStatus(limbId, statusId)
    if not limbId or limbId == "" or not statusId or statusId == "" then return end

    net.Start("WoundSystem_RemoveLimbStatus")
        net.WriteString(limbId)
        net.WriteString(statusId)
    net.SendToServer()
end

local function RequestSyringeMinigameStart(limbId, slotIdx)
    if not limbId or limbId == "" then return end

    if WoundSystemSyringeMinigame and WoundSystemSyringeMinigame.RequestStart then
        WoundSystemSyringeMinigame.RequestStart(limbId, slotIdx)
        return
    end

    net.Start("WoundSystem_SyringeStart")
    net.WriteString(limbId)
    net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

local function RequestAEDMinigameStart(limbId, slotIdx)
    if WoundSystemAEDMinigame and WoundSystemAEDMinigame.RequestStart then
        WoundSystemAEDMinigame.RequestStart(limbId, slotIdx)
        return
    end

    net.Start("WoundSystem_AEDStart")
        net.WriteString(limbId)
        net.WriteUInt(slotIdx or 0, 3)
    net.SendToServer()
end

local function BandageEffectsCanTreat(state, effects, bodyEffects)
    if not state then return false end

    if type(bodyEffects) == "table" and next(bodyEffects) ~= nil then return true end
    if type(effects) ~= "table" then return false end

    for key, amount in pairs(effects) do
        if type(amount) ~= "number" then continue end
        if key == "bleed" and amount < 0 and (state.bleed or 0) > 0 then return true end
        if key == "bandageSlowAmount" and amount > 0 and (state.bleed or 0) > 0 then return true end
        if (key == "skin" or key == "skinHealAmount") and amount > 0 and (state.skin or 100) < 100 then return true end
        if key == "muscle" and amount > 0 and (state.muscle or 100) < 100 then return true end
        if key == "pain" and amount < 0 and (state.pain or 0) > 0 then return true end
        if (key == "infection" or key == "infectionAmount" or key == "infectionSpeed") and amount < 0 and ((state.infection or 0) > 0 or (state.infectionSpeed or 0) > 0) then return true end
        if key == "disinfectTime" and amount > 0 then return true end
        if key == "boneHealTimer" and amount < 0 and state.broken then return true end
        if key == "dislocationTimer" and amount < 0 and state.dislocated then return true end
        if key == "furBloodAmount" and amount < 0 and (state.furBloodAmount or 0) > 0 then return true end
    end

    return false
end

local function IsBandageMinigameTreatable(toolName, state)
    local itemId = WoundSystem.NormalizeItemId and WoundSystem.NormalizeItemId(toolName) or string.upper(tostring(toolName or ""))
    local item = GetToolConfig(itemId)
    local use = item and item.use
    local bandage = type(use and use.bandage) == "table" and use.bandage or nil

    if use and use.minigame == "bandage" then
        if use.allowUnwounded ~= false and (not bandage or bandage.allowUnwounded ~= false) then return true end
        if use.requireBleed and state and (state.bleed or 0) <= 0 then return false end
        if use.allowUnwounded or (bandage and bandage.allowUnwounded) then return true end

        local effects = bandage and bandage.effects or use.bandageEffects
        local bodyEffects = bandage and bandage.bodyEffects or use.bandageBodyEffects
        if effects or bodyEffects then
            return BandageEffectsCanTreat(state, effects, bodyEffects)
        end
    end

    if itemId == "BRUISE KIT" then
        return state and ((state.skin or 100) < 100 or (state.muscle or 100) < 100 or (state.pain or 0) > 0 or state.dislocated)
    end

    return IsBandageTreatable(state)
end

local function EmptyInventorySlot(slotIdx)
    if slotIdx and WoundSystemInventorySlots[slotIdx] then
        WoundSystemInventorySlots[slotIdx] = { type = "empty" }
    end
end

local function SendRegisteredToolUse(toolName, limbId, slotIdx)
    net.Start("WoundSystem_UseMedicalItem")
        net.WriteUInt(slotIdx, 3)
        net.WriteString(toolName)
        net.WriteString(limbId)
    net.SendToServer()
end

local function UseMedicalToolOnLimb(tool, slotIdx, limbId)
    if not tool or tool.type ~= "tool" or not limbId or not slotIdx then return false end

    local state = PlayerLimbs[limbId]
    local item = GetToolConfig(tool.toolName)
    local use = item and item.use

    if use and WoundSystem.Items and WoundSystem.Items.LimbAllowed and not WoundSystem.Items.LimbAllowed(use, limbId) then
        return false
    end

    if use and use.minigame == "bandage" then
        if IsBandageMinigameTreatable(tool.toolName, state) and tool.durability > (use.minDurability or 0) then
            if WoundSystemBandageMinigame and WoundSystemBandageMinigame.RequestStart then
                WoundSystemBandageMinigame.RequestStart(limbId, slotIdx)
            end
            return true
        end

        return false
    end

    if use and use.minigame == "syringe" then
        local minDur = use.minDurability or 0.01
        if tool.durability > minDur then
            RequestSyringeMinigameStart(limbId, slotIdx)
            return true
        end

        return false
    end

    if use and use.minigame == "aed" then
        local minDur = use.minDurability or 2
        if tool.durability > minDur then
            RequestAEDMinigameStart(limbId, slotIdx)
            return true
        end

        return false
    end

    if use and use.minigame == "dislocation" then
        local minDur = use.minDurability or 0
        if state and state.dislocated and tool.durability > minDur then
            RequestDislocationMinigameStart(limbId, slotIdx)
            return true
        end

        return false
    end

    if use then
        local maxDur = GetToolMax(tool.toolName)
        local minDur = use.minDurability or use.durabilityCost or 0

        if use.requireFull and tool.durability < maxDur then return false end
        if tool.durability < minDur then return false end

        SendRegisteredToolUse(tool.toolName, limbId, slotIdx)
        return true
    end

    if tool.toolName == "GAUZE" and IsBandageTreatable(state) and tool.durability > 0 then
        if WoundSystemBandageMinigame and WoundSystemBandageMinigame.RequestStart then
            WoundSystemBandageMinigame.RequestStart(limbId, slotIdx)
        end
        return true
    elseif tool.toolName == "BRUISE KIT" and tool.durability >= 10 then
        SendRegisteredToolUse(tool.toolName, limbId, slotIdx)
        return true
    elseif tool.toolName == "DISINFECTANT" and tool.durability >= 10 then
        SendRegisteredToolUse(tool.toolName, limbId, slotIdx)
        return true
    elseif tool.toolName == "INJECTION" and tool.durability >= 10 then
        SendRegisteredToolUse(tool.toolName, limbId, slotIdx)
        return true
    end

    return false
end

local Blueprint = {
    { name = "foot",   distX = 30.5,  offsetY = 143,   size = 2, paired = true,  order = 1 },
    { name = "crus",   distX = 30.5,  offsetY = 94,    size = 2, paired = true,  order = 2 },
    { name = "thigh",  distX = 30.5,  offsetY = 30,    size = 2, paired = true,  order = 3 },
    { name = "abdomen", distX = 0,     offsetY = -35,   size = 2, paired = false, order = 4 },
    { name = "thorax",  distX = 0,     offsetY = -97.5, size = 2, paired = false, order = 5 },
    { name = "arm",     distX = 64,    offsetY = -107,  size = 2, paired = true,  order = 5 }, 
    { name = "forearm", distX = 133,   offsetY = -102,  size = 2, paired = true,  order = 6 },
    { name = "hand",    distX = 194,   offsetY = -102,  size = 2, paired = true,  order = 7 },
    { name = "head",    distX = 0,     offsetY = -175,  size = 2, paired = false, order = 8 },
}

local Limbs = {}
for _, part in ipairs(Blueprint) do
    local m = PaddedMaterial(path .. "middle/" .. part.name .. "middle.png")
    local o = PaddedMaterial(path .. "outlines/" .. part.name .. "outline.png")
    local texturePadding = 1
    
    local function add(flip, ox, netName)
        table.insert(Limbs, {
            id = netName,
            matM = m,
            matO = o,
            texturePadding = texturePadding,
            sourceW = math.max(o:Width() - (texturePadding * 2), 1),
            sourceH = math.max(o:Height() - (texturePadding * 2), 1),
            ox = ox,
            oy = part.offsetY,
            flip = flip,
            size = part.size,
            order = part.order
        })
        PlayerLimbs[netName] = table.Copy(defaultLimbState)
        GUIState.HoverAnims[netName] = 0 
        GUIState.LastHoverStates[netName] = false 
    end
    if part.paired then
        add(false, -part.distX, part.name .. "_R")
        add(true, part.distX, part.name .. "_L")
    else add(false, part.distX, part.name) end
end

hook.Add("InitPostEntity", "CacheVitals", function()
    local sid = LocalPlayer():SteamID64() or "76561197960287930"
    GUIState.cachedVitals = (sid:sub(16, 17) + 100) .. "cm | " .. sid:sub(9, 10) .. "y | #" .. sid:sub(11, 15)
end)

net.Receive("WoundSystem_UpdateLimb", function()
    local hitLimb = net.ReadString()
    if hitLimb == "RESET_ALL" then
        for k, v in pairs(PlayerLimbs) do
            PlayerLimbs[k] = table.Copy(defaultLimbState)
        end
        CardioState.bloodVolume = 100
        CardioState.internalBleeding = 0
        CardioState.hemothorax = 0
        CardioState.heartRate = 70
        CardioState.respiratoryRate = 100
        CardioState.bloodPressure = 120
        CardioState.bloodOxygen = 98
        CardioState.fibrillationProgress = 0
        CardioState.cardioShock = 0
        CardioState.adrenaline = 0
        CardioState.temperature = 37
        CardioState.avgPain = 0
        CardioState.immunity = 100
        CardioState.brainHealth = 100
        CardioState.consciousness = 100
        CardioState.unconscious = false
        CardioState.stamina = 100
        CardioState.hunger = 100
        CardioState.thirst = 100
        CardioState.energy = 100
        CardioState.weightOffset = 0
        CardioState.bloodViscosity = 0
        CardioState.radiationSickness = 0
        CardioState.wetness = 0
        CardioState.totalBleedSpeed = 0
        CardioState.sicknessAmount = 0
        CardioState.septicShock = 0
        CardioState.hearingLoss = 0
        CardioState.strokeAmount = 0
        CardioState.hasPulmonaryEmbolism = false
        CardioState.dirtyness = 0
        CardioState.traumaAmount = 0
        CardioState.clawHealth = 100
        CardioState.clawRegrowTime = 0
        CardioState.caffeinated = 0
        CardioState.badSleepAmount = 0
        CardioState.venomCurrent = 0
        CardioState.overdoseIndex = 0
        CardioState.painShock = 0
        CardioState.opiateHappiness = 0
        CardioState.antidepressantHappiness = 0
        CardioState.opiateAmount = 0
        CardioState.opiateReception = 0
        CardioState.actualOpiateReception = 0
        CardioState.opiateTolerance = 0
        CardioState.lastStandTime = 0
        CardioState.focusedLevel = 0
        CardioState.horrifiedLevel = 0
        CardioState.overEncumberance = 0
        CardioState.brainGrowSickness = 0
        CardioState.sleeping = false
        CardioState.disfigured = false
        CardioState.eyeGone = false
        CardioState.bothEyesGone = false
        CardioState.onHardStimulants = false
        CardioState.impairedSpeech = false
        CardioState.mindWipe = false

        GUIState.selectedLimbData = nil
		
        return
    end

    if not PlayerLimbs[hitLimb] then return end
    local state = PlayerLimbs[hitLimb]
    state.skin = net.ReadFloat()
    state.muscle = net.ReadFloat()
    state.pain = net.ReadFloat()
    state.bleed = net.ReadFloat()
    state.infection = net.ReadFloat()
    state.infectionSpeed = net.ReadFloat()
    state.disinfectTime = net.ReadFloat()
    state.broken = net.ReadBool()     
    state.dislocated = net.ReadBool() 
    state.dislocationTimer = net.ReadFloat()
    state.boneHealTimer = net.ReadFloat()
    state.muscleStrength = net.ReadFloat()
    state.isBandaged = net.ReadBool()
	state.hasInjection = net.ReadBool()
    state.furBloodAmount = net.ReadFloat()
	state.eyes = net.ReadUInt(3)
	state.dismembered = net.ReadBool()
    state.bandageMinigameSpeedMult = net.ReadFloat()
    if WoundSystem.Statuses and WoundSystem.Statuses.ReadNet then
        WoundSystem.Statuses.ReadNet(state)
    else
        state.customStatuses = {}
        local statusCount = net.ReadUInt(5)
        for _ = 1, statusCount do
            net.ReadString()
            local kind = net.ReadUInt(2)
            if kind == 1 then
                net.ReadFloat()
            elseif kind == 2 then
                net.ReadString()
            else
                net.ReadBool()
            end
        end
    end

    if GUIState.selectedLimbData and GUIState.selectedLimbData.id == hitLimb then
        GUIState.selectedLimbData.state = state
    end
end)

local function LerpColor(t, c1, c2)
    return Color(Lerp(t, c1.r, c2.r), Lerp(t, c1.g, c2.g), Lerp(t, c1.b, c2.b), Lerp(t, c1.a or 255, c2.a or 255))
end

WoundSystem.InjuryHealColor = function(timerValue, alpha)
    local severity = math.Clamp((tonumber(timerValue) or 0) / 100, 0, 1)
    return LerpColor(severity, Color(255, 255, 255, alpha or 255), Color(255, 0, 0, alpha or 255))
end

local function InfectionStatusColor(infection, alpha)
    local t = math.Clamp((infection or 0) / 100, 0, 1)
    return Color(
        Lerp(t, 255, 142),
        Lerp(t, 255, 0),
        Lerp(t, 255, 178),
        alpha or 255
    )
end

local function GetDisplayedInfectionSpeed(state)
    local infectionSpeed = tonumber(state and state.infectionSpeed) or 0
    if infectionSpeed == 0 then return 0 end

    local cardio = (WoundSystemClientState and WoundSystemClientState.Cardio) or CardioState or {}
    local immunityMult = math.Clamp(2.0 - ((tonumber(cardio.immunity) or 100) / 100), 0.2, 2.0)

    if (tonumber(state.disinfectTime) or 0) > 0 then
        immunityMult = immunityMult - 1.7
    end

    return 7.2 * immunityMult * infectionSpeed
end

local function DrawSprite(mat, cx, cy, scaleMult, flip, color, texturePadding)
    ActivePaddedMaterial = nil
    surface.SetMaterial(mat)
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    local pad = texturePadding or 0
    local sourceW = math.max(mat:Width() - (pad * 2), 1)
    local sourceH = math.max(mat:Height() - (pad * 2), 1)
    local drawW = mat:Width() * scaleMult
    local drawH = mat:Height() * scaleMult
    local drawX = cx - ((sourceW * scaleMult) / 2) - (pad * scaleMult)
    local drawY = cy - ((sourceH * scaleMult) / 2) - (pad * scaleMult)

    DrawRectUVInt(drawX, drawY, drawW, drawH, flip and 1 or 0, 0, flip and 0 or 1, 1)
end

-- GUIState.hudOpen in GUIState
-- GUIState.lastKeyStatus in GUIState
-- GUIState.openTime in GUIState

if not GetConVar("woundsys_woundview_key") then
    CreateClientConVar("woundsys_woundview_key", tostring(KEY_T or 20), true, true, "Key used to open and close the wound view.")
end


local function WoundViewKeyDown()
    local _wvk = GetConVar("woundsys_woundview_key")
    local rawKey = string.Trim(_wvk and _wvk:GetString() or "")
    local numericKey = tonumber(rawKey)
    if numericKey then
        return input.IsKeyDown(numericKey)
    end

    local keyName = string.upper(rawKey)
    if keyName == "" then keyName = "T" end

    local keyCode = _G["KEY_" .. keyName] or _G[keyName]
    if not keyCode and string.len(keyName) == 1 then
        keyCode = _G["KEY_" .. keyName]
    end

    return input.IsKeyDown(keyCode or KEY_T)
end

hook.Add("Think", "ToggleHUDInput", function()
	local ply = LocalPlayer()
    local modEnabled = WoundSystemClientEnabled()
    local isAlive = IsValid(ply) and ply:Alive()
    local isUnconscious = CardioState.unconscious
        or (IsValid(ply) and ply:GetNWBool("WoundSystemUnconscious", false))

    if GUIState.hudOpen and (not modEnabled or isUnconscious or not isAlive) then
        GUIState.hudOpen = false
        if not DeathScreen.isDead then
            WoundSystem.HealthGUI.SetScreenClickerOwned(false, "hud_forced_closed")
        end
        CloseWoundMinigames("hud_closed")
    end

    if not modEnabled then
        GUIState.lastKeyStatus = WoundViewKeyDown()
        WoundSystemHealthHUDOpen = false
        return
    end

    if GUIState.hudOpen and (not GUIState.openTime or GUIState.openTime <= 0 or GUIState.openTime > CurTime() + 1) then
        GUIState.openTime = CurTime()
    end
	
	if vgui.GetKeyboardFocus() ~= nil or WoundSystem.HealthGUI.IsExternalMenuOpen() then
        if GUIState.hudOpen then
            WoundSystem.HealthGUI.SetScreenClickerOwned(false, "external_menu_open")
        end
        WoundSystemHealthHUDOpen = GUIState.hudOpen
        return
    end
    local isDown = WoundViewKeyDown()
    if isDown and not GUIState.lastKeyStatus then
        if GUIState.hudOpen or (not isUnconscious and isAlive) then
            GUIState.hudOpen = not GUIState.hudOpen
            if GUIState.hudOpen then 
                GUIState.openTime = CurTime() 
                WoundSystem.HealthGUI.SetScreenClickerOwned(true, "hud_toggle_open")
                surface.PlaySound("woundon.ogg")
            else
                if WoundSystemWorldDrag and WoundSystemWorldDrag.active then
                    WoundSystemCancelWorldItemDrag(false)
                else
                    WoundSystem.HealthGUI.SetScreenClickerOwned(false, "hud_toggle_close")
                end
                CloseWoundMinigames("hud_closed")
            end
        end
    end
    GUIState.lastKeyStatus = isDown
    WoundSystemHealthHUDOpen = GUIState.hudOpen

    if GUIState.hudOpen and not WoundSystem.HealthGUI.IsExternalMenuOpen() then
        WoundSystem.HealthGUI.SetScreenClickerOwned(true, "hud_open_hold")
    elseif not DeathScreen.isDead and not (WoundSystemWorldDrag and WoundSystemWorldDrag.active)
        and not (WoundSystemIsAnyWoundMinigameActive and WoundSystemIsAnyWoundMinigameActive()) then
        -- (a minigame started by a Z-City SWEP owns the cursor without the health HUD being open)
        WoundSystem.HealthGUI.SetScreenClickerOwned(false, "hud_closed_hold")
    end
end)

-- A minigame started by a Z-City SWEP (temporary slot 6) takes over the controls: no walking, jumping, shooting or
-- weapon switching while it is open (the server enforces the same in sv_health.lua).
hook.Add("StartCommand", "WoundSystem_ExternalMinigameControls", function(ply, cmd)
    if ply ~= LocalPlayer() then return end

    local b, s, g = WoundSystemBandageMinigame, WoundSystemSyringeMinigame, WoundSystemShrapnelMinigame
    local active = (b and b.IsActive and b.IsActive() and b.slotIdx == 6)
        or (s and s.IsActive and s.IsActive() and s.slotIdx == 6)
        or (g and g.IsActive and g.IsActive() and g.external)
    if not active then
        WoundSystem.ExternalMinigameViewAng = nil
        return
    end

    -- the view stays where it was (the cursor is used for the minigame)
    WoundSystem.ExternalMinigameViewAng = WoundSystem.ExternalMinigameViewAng or cmd:GetViewAngles()
    cmd:SetViewAngles(WoundSystem.ExternalMinigameViewAng)
    cmd:SetMouseX(0)
    cmd:SetMouseY(0)

    cmd:ClearMovement()
    cmd:RemoveKey(bit.bor(IN_ATTACK, IN_ATTACK2, IN_JUMP, IN_DUCK, IN_USE, IN_RELOAD, IN_SPEED, IN_WALK, IN_ZOOM))
    cmd:SetImpulse(0)
    cmd:SetWeaponSelect(0)
    cmd:SetMouseWheel(0)
end)

function WoundSystem.OpenHealthHUD()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    if CardioState.unconscious or ply:GetNWBool("WoundSystemUnconscious", false) then return end

    GUIState.hudOpen = true
    GUIState.openTime = CurTime()
    WoundSystemHealthHUDOpen = true
    WoundSystem.HealthGUI.SetScreenClickerOwned(true, "hud_toggle_open")
    surface.PlaySound("woundon.ogg")
end

function WoundSystem.CloseHealthHUD()
    GUIState.hudOpen = false
    WoundSystemHealthHUDOpen = false
    if WoundSystemWorldDrag and WoundSystemWorldDrag.active then
        WoundSystemCancelWorldItemDrag(false)
    else
        WoundSystem.HealthGUI.SetScreenClickerOwned(false, "hud_toggle_close")
    end
    CloseWoundMinigames("hud_closed")
end

function WoundSystem.ToggleHealthHUD()
    if GUIState.hudOpen then
        WoundSystem.CloseHealthHUD()
    else
        WoundSystem.OpenHealthHUD()
    end
end

concommand.Add("woundsys_open_panel", function()
    WoundSystem.ToggleHealthHUD()
end)

list.Set("DesktopWindows", "WoundSystemHealth", {
    title = "Health Panel",
    icon = "casunknown-images/de_weh.png",
    width = 100,
    height = 100,
    onewindow = true,
    init = function(icon, window)
        if IsValid(window) then window:Remove() end
        if IsValid(g_ContextMenu) then
            g_ContextMenu:Close()
        end
        gui.EnableScreenClicker(false)
        timer.Simple(0.05, function()
            if WoundSystem and WoundSystem.ToggleHealthHUD then
                WoundSystem.ToggleHealthHUD()
            end
        end)
    end
})

hook.Add("SpawnMenuOpen", "WoundSystem_ReleaseClickerForSpawnMenu", function()
    WoundSystem.HealthGUI.SetScreenClickerOwned(false, "spawn_menu_open")
end)

hook.Add("SpawnMenuClosed", "WoundSystem_RestoreClickerAfterSpawnMenu", function()
    if not GUIState.hudOpen then
        WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "spawn_menu_closed")
        return
    end

    if not WoundSystem.HealthGUI.IsExternalMenuOpen() then
        WoundSystem.HealthGUI.SetScreenClickerOwned(true, "spawn_menu_closed_hud_open")
    end
end)

hook.Add("OnContextMenuOpen", "WoundSystem_ReleaseClickerForContextMenu", function()
    WoundSystem.HealthGUI.SetScreenClickerOwned(false, "context_menu_open")
end)

hook.Add("OnContextMenuClose", "WoundSystem_RestoreClickerAfterContextMenu", function()
    if not GUIState.hudOpen then
        WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "context_menu_closed")
        return
    end

    if not WoundSystem.HealthGUI.IsExternalMenuOpen() then
        WoundSystem.HealthGUI.SetScreenClickerOwned(true, "context_menu_closed_hud_open")
    end
end)

local function WoundSystemPlayerUsesUnconsciousBody(ply)
    if not IsValid(ply) then return false end
    return ply:GetNWBool("WoundSystemUnconscious", false)
        or IsValid(ply:GetNWEntity("WoundSystemUnconsciousRagdoll"))
        or ply:GetNoDraw()
end

hook.Add("ShouldDrawLocalPlayer", "WoundSystem_HideUnconsciousBody", function(ply)
    if not WoundSystemClientEnabled() then return end
    if hg and hg.WoundBridge and hg.WoundBridge.IsEnabled() then return end -- Z-City owns the body/camera
    if WoundSystemPlayerUsesUnconsciousBody(ply) then return false end
end)

hook.Add("PrePlayerDraw", "WoundSystem_HideUnconsciousBody", function(ply)
    if not WoundSystemClientEnabled() then return end
    if hg and hg.WoundBridge and hg.WoundBridge.IsEnabled() then return end -- Z-City owns the body/camera
    if WoundSystemPlayerUsesUnconsciousBody(ply) then return true end
end)

hook.Add("Think", "WoundSystem_ScreenClickerWatchdog", function()
    if not (WoundSystem and WoundSystem.HealthGUI) then return end

    local ply = LocalPlayer()
    if WoundSystemClientEnabled() and IsValid(ply) and ply:Alive() and DeathScreen.isDead then
        SetDeathScreenActive(false)
        DeathScreen.deathScreenStarted = false
        DeathScreen.clickDebounce = false
        WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "watchdog_alive_deathscreen")
        return
    end

    local shouldOwn = DeathScreen.isDead
        or GUIState.hudOpen
        or WoundSystemHealthHUDOpen
        or (WoundSystemWorldDrag and WoundSystemWorldDrag.active)
        or (WoundSystemIsAnyWoundMinigameActive and WoundSystemIsAnyWoundMinigameActive())

    if not WoundSystem.HealthGUI.ScreenClickerOwned then
        if WoundSystem.HealthGUI.ClickerDebugEnabled() and vgui.CursorVisible() and not shouldOwn and not gui.IsGameUIVisible() and not gui.IsConsoleVisible() and not vgui.GetKeyboardFocus() then
            WoundSystem.HealthGUI.NextForeignClickerWarn = WoundSystem.HealthGUI.NextForeignClickerWarn or 0
            if CurTime() >= WoundSystem.HealthGUI.NextForeignClickerWarn then
                WoundSystem.HealthGUI.NextForeignClickerWarn = CurTime() + 1
                WoundSystem.HealthGUI.ClickerDebugLog("cursor visible but WoundSystem does not own it")
            end
        end
        return
    end

    if shouldOwn then return end

    if WoundSystemClientEnabled() and IsValid(ply) and ply:Alive() then
        WoundSystem.HealthGUI.ForceReleaseScreenClicker(true, "watchdog_stale_owned")
    else
        WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "watchdog_stale_owned_dead")
    end
end)

local function ClickerDebugStatus()
    local focus = vgui.GetKeyboardFocus()
    local ply = LocalPlayer()
    local minigameActive = WoundSystemIsAnyWoundMinigameActive and WoundSystemIsAnyWoundMinigameActive() or false
    local fields = {
        "owned=" .. tostring(WoundSystem.HealthGUI.ScreenClickerOwned == true),
        "cursor=" .. tostring(vgui.CursorVisible()),
        "healthHUD=" .. tostring(WoundSystemHealthHUDOpen == true),
        "hudOpen=" .. tostring(GUIState.hudOpen == true),
        "deadScreen=" .. tostring(DeathScreen.isDead == true),
        "worldDrag=" .. tostring(WoundSystemWorldDrag and WoundSystemWorldDrag.active or false),
        "minigame=" .. tostring(minigameActive),
        "gameUI=" .. tostring(gui.IsGameUIVisible()),
        "console=" .. tostring(gui.IsConsoleVisible()),
        "focus=" .. tostring(IsValid(focus) and focus:GetClassName() or "none"),
        "alive=" .. tostring(IsValid(ply) and ply:Alive() or false),
        "lastReason=" .. tostring(WoundSystem.HealthGUI.LastScreenClickerReason or "none"),
        "lastTime=" .. string.format("%.2f", tonumber(WoundSystem.HealthGUI.LastScreenClickerTime or 0) or 0)
    }

    return table.concat(fields, " | ")
end

concommand.Add("woundsys_clicker_status", function()
    MsgC(Color(90, 220, 150), "[WoundSystem clicker] ", color_white, ClickerDebugStatus(), "\n")
    if WoundSystem.HealthGUI.LastScreenClickerTrace then
        MsgC(Color(90, 220, 150), "[WoundSystem clicker trace]\n", color_white, tostring(WoundSystem.HealthGUI.LastScreenClickerTrace), "\n")
    end
end)

concommand.Add("woundsys_clicker_release", function()
    WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "manual_console_release")
    MsgC(Color(90, 220, 150), "[WoundSystem clicker] ", color_white, "manual release sent | ", ClickerDebugStatus(), "\n")
end)

-- Add these tracking variables to your file's global/local scope area
-- GUIState.targetHrvOffset in GUIState
-- GUIState.currentHrvOffset in GUIState
-- GUIState.hrvNextChange in GUIState

local function IsLocalAsystole(ply)
    if not IsValid(ply) then return false end
    if CurTime() < (spawnVisualGraceUntil or 0) then return false end

    local fibProgress = CardioState.fibrillationProgress or 0
    return (CardioState.heartRate or 70) <= 0
        or fibProgress >= 100
        or not ply:Alive()
        or ply:Health() <= 0
end

local function UpdateAsystoleSound()
    local ply = LocalPlayer()
    local isAsystole = IsLocalAsystole(ply)

    if isAsystole and not ECG.hasPlayedAsystoleSound then
        ECG.hasPlayedAsystoleSound = true

        if IsValid(ECG.asystoleSound) then
            ECG.asystoleSound:Stop()
            ECG.asystoleSound = nil
        end

        sound.PlayFile("sound/flatline.ogg", "noblock noplay 2d", function(station)
            if IsValid(station) then
                ECG.asystoleSound = station
                local muffleVol, mufflePitch = GetHearingMuffle()
                station:SetVolume(GetAsystoleVolume() * muffleVol)
                station:SetPlaybackRate(mufflePitch / 100)
                station:Play()
            else
                surface.PlaySound("flatline.ogg")
            end
        end)
    elseif not isAsystole then
        ECG.hasPlayedAsystoleSound = false
        if IsValid(ECG.asystoleSound) then
            ECG.asystoleSound:Stop()
            ECG.asystoleSound = nil
        end
    elseif isAsystole and IsValid(ECG.asystoleSound) then
        local muffleVol, mufflePitch = GetHearingMuffle()
        ECG.asystoleSound:SetVolume(GetAsystoleVolume() * muffleVol)
        ECG.asystoleSound:SetPlaybackRate(mufflePitch / 100)
    end
end

hook.Add("Think", "WoundSystem_AsystoleSound", UpdateAsystoleSound)

hook.Add("Think", "WoundSystem_CalculateECG", function()
    local curT = CurTime()
    if ECG.lastTime == 0 then ECG.lastTime = curT end
    local dt = curT - ECG.lastTime
    ECG.lastTime = curT

    if dt > 0.5 then dt = 0.5 end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- -------------------------------------------------------------
    -- FEATURE 1: HEART RATE VARIABILITY (HRV)
    -- -------------------------------------------------------------
    local hr = CardioState.heartRate > 0 and CardioState.heartRate or 10
    
    if curT > GUIState.hrvNextChange then
        local hrvIntensity = math.Clamp((150 - hr) / 100, 0.05, 1.0)
        GUIState.targetHrvOffset = math.Rand(-2.5, 2.5) * hrvIntensity
        GUIState.hrvNextChange = curT + math.Rand(0.15, 0.35)
    end
    
    GUIState.currentHrvOffset = Lerp(dt * 8, GUIState.currentHrvOffset, GUIState.targetHrvOffset)
    
    local liveHr = math.Clamp(hr + GUIState.currentHrvOffset, 10, 250)
    local beatDuration = 60 / liveHr
    
    local fibProgress = CardioState.fibrillationProgress or 0
    local fibRatio = math.Clamp(fibProgress / 100, 0, 1)
	
	local cardio = WoundSystemClientState and WoundSystemClientState.Cardio
	local bloodOxygen = cardio and (cardio.bloodOxygen or cardio.bloodOxygenAmount) or (CardioState and CardioState.bloodOxygen) or 100
	local bloodPressure = cardio and (cardio.bloodPressure or cardio.pressure) or (CardioState and CardioState.bloodPressure) or 120
	local fibrillationProgress = cardio and cardio.fibrillationProgress or (CardioState and CardioState.fibrillationProgress) or 0
	local bloodVolume = cardio and cardio.bloodVolume or (CardioState and CardioState.bloodVolume) or 100
	local totalBleedSpeed = cardio and (cardio.totalBleedSpeed or cardio.bleedSpeed) or (CardioState and CardioState.totalBleedSpeed) or 0
	local septicShock = cardio and (cardio.septicShock or cardio.septicShockAmount) or (CardioState and CardioState.septicShock) or 0
	local temperature = cardio and cardio.temperature or (CardioState and CardioState.temperature) or 37

    local isAsystole = IsLocalAsystole(ply)
    local criticalPulse = ((bloodOxygen < 50)
        or (bloodPressure < 70)
        or (fibrillationProgress > 60)
        or ((bloodVolume < 30) and (totalBleedSpeed > 0.02))
        or (septicShock > 82.5)
        or (temperature < 27)
        or (temperature > 41.5))
        and not isAsystole

    local ecgDurationVisible = 2.5 
    local pointsPerSecond = ECG.points / ecgDurationVisible
    local pointsToMove = dt * pointsPerSecond

    local oldIndex = ECG.writeIndex
    ECG.writeIndex = ((ECG.writeIndex + pointsToMove - 1) % ECG.points) + 1
    
    local startIdx = math.floor(oldIndex)
    local endIdx = math.floor(ECG.writeIndex)

    if startIdx ~= endIdx then
        local totalSteps = (endIdx - startIdx)
        if totalSteps < 0 then totalSteps = totalSteps + ECG.points end
        
        for i = 1, totalSteps do
            local writePos = (startIdx + i - 1) % ECG.points + 1
            local timeOffset = (i / totalSteps) * dt
            local evalTime = (curT - dt) + timeOffset
            
            local rawPhase = ((ECG.currentHeartPhase + (timeOffset / beatDuration)) % 1.0)
            
            -- NEW: Non-linear phase curving. Makes the beat 'snap' aggressively.
            local pixelHeartPhase = math.pow(rawPhase, 1.15)
            
            -- Audio Execution
            if not isAsystole then
                if ECG.lastBeatPhase < 0.165 and pixelHeartPhase >= 0.165 then
                    local heartSound = "heartthump.ogg"
                    local vol = 0
                    
                    if WoundSystemHealthHUDOpen then
                        vol = 1.0
                        if liveHr >= 120 then
                            vol = math.Clamp(1.0 + ((liveHr - 120) / 60) * 0.5, 1.0, 1.5)
                        end
                    else
                        if liveHr >= 80 then
                            vol = math.Clamp((liveHr - 80) / 20, 0, 1)
                            if liveHr >= 120 then
                                vol = math.Clamp(1.0 + ((liveHr - 120) / 60) * 0.5, 1.0, 1.5)
                            end
                        end
                    end

                    if liveHr >= 125 then
                        heartSound = "heartthump-heavy.ogg"
                    elseif criticalPulse then
                        heartSound = "heartthump-heavy-monitor.ogg"
                    elseif (bloodOxygen < 60) or (bloodPressure < 80) or (fibrillationProgress > 60) or (bloodVolume < 50 and totalBleedSpeed > 2) then
                        heartSound = "heartthump-heavy-monitor.ogg"
                    end

                    if vol > 0 then
                        local muffleVol, mufflePitch = GetHearingMuffle()
                        ply:EmitSound(heartSound, 75, math.Round(mufflePitch), vol * muffleVol, CHAN_AUTO)
                    end
                end
            end
            ECG.lastBeatPhase = pixelHeartPhase

            -- -------------------------------------------------------------
            -- FEATURE 2: ORGANIC BASELINE WANDER (No more perfect sines)
            -- -------------------------------------------------------------
            local breath = math.sin(evalTime * 1.5) * 0.03
            local drift = math.sin(evalTime * 0.3) * 0.015
            local baselineWander = breath + drift
            
            local noiseIntensity = isAsystole and 0.003 or 0.006
            local muscleNoise = math.Rand(-noiseIntensity, noiseIntensity)

            -- -------------------------------------------------------------
            -- FEATURE 3: DYNAMIC QRS VOLTAGE DECAY
            -- -------------------------------------------------------------
            local voltageLoss = 1.0
            if liveHr > 160 then
                voltageLoss = math.Clamp(1.0 - ((liveHr - 160) / 90), 0.4, 1.0)
            end

            -- NEW: Deterministic Randomness for QRS variation
            -- This creates a +/- 6% variance in spike height that stays stable for the whole beat
            local beatNumber = math.floor(evalTime / beatDuration)
            local beatVariation = 1.0 + (math.sin(beatNumber * 123.45) * 0.06)

            -- -------------------------------------------------------------
            -- FEATURE 4: ORGANIC WAVEFORM MORPHOLOGY
            -- -------------------------------------------------------------
            local normalVal = 0
            local phase = pixelHeartPhase

            if phase > 0.05 and phase <= 0.12 then
                -- P Wave: Small bump
                normalVal = math.sin((phase - 0.05) / 0.07 * math.pi) * 0.08
            
            elseif phase > 0.14 and phase <= 0.22 then
                -- QRS Complex
                if phase < 0.155 then
                    -- Q Dip
                    local t = (phase - 0.14) / 0.015
                    normalVal = -0.10 * t
                elseif phase < 0.175 then
                    -- R Spike: Uses 'beatVariation' to inject organic randomness
                    local t = (phase - 0.155) / 0.02
                    normalVal = -0.10 + (1.1 * voltageLoss * beatVariation) * (1 - math.abs(t * 2 - 1))
                else
                    -- S Dip
                    local t = (phase - 0.175) / 0.045
                    normalVal = -0.20 * (1 - t) 
                end
            
            elseif phase > 0.28 and phase <= 0.48 then
                -- T Wave: Asymmetrical
                local t = (phase - 0.28) / 0.20
                normalVal = 0.16 * math.sin(math.pow(t, 1.5) * math.pi)
            end

            -- Fibrillation Wave Synthesis
            local pixelFibVal = 0
            if fibRatio > 0 then
                local t = evalTime * 18 
                pixelFibVal = (math.sin(t) * 0.25) + (math.sin(t * 1.73) * 0.15) + (math.cos(t * 2.31) * 0.20) + math.Rand(-0.05, 0.05)
                pixelFibVal = pixelFibVal * Lerp(fibRatio, 1.2, 0.4)
            end

            -- Final Assembler
            local finalVal = 0
            if isAsystole then
                -- Flatline with subtle tracking fuzz
                finalVal = math.sin(evalTime * 0.5) * 0.003 + math.Rand(-0.004, 0.004)
            else
                local blendStrength = math.pow(fibRatio, 2) 
                finalVal = Lerp(blendStrength, normalVal, pixelFibVal) + baselineWander + muscleNoise
            end

            ECG.buffer[writePos] = finalVal
            ECG.lastVal = finalVal
        end
        
        ECG.currentHeartPhase = (ECG.currentHeartPhase + (dt / beatDuration)) % 1.0
    end
end)

GUIState.unconsciousRagdoll = GUIState.unconsciousRagdoll or NULL
-- GUIState.lastRagdollRequest in GUIState

local function ResolveUnconsciousRagdoll(ply)
    if not IsValid(ply) then return NULL end

    local feedback = WoundSystem and WoundSystem.MultiplayerFeedback
    local ragdollPending = feedback and feedback.GetRagdollPending and feedback.GetRagdollPending()

    if not ragdollPending
        and ply:Alive()
        and not ply:GetNWBool("WoundSystemUnconscious", false)
        and not CardioState.unconscious
        and not ply:GetNoDraw() then
        GUIState.unconsciousRagdoll = NULL
        GUIState.unconsciousEyeAttachment = 0

        if feedback then
            feedback.ragdollActive = false
            feedback.ragdollEntity = NULL
            feedback.ragdollPendingUntil = 0
        end

        return NULL
    end

    if feedback and feedback.ragdollActive and IsValid(feedback.ragdollEntity) then
        if feedback.ragdollEntity ~= GUIState.unconsciousRagdoll then
            GUIState.unconsciousEyeAttachment = 0
        end

        GUIState.unconsciousRagdoll = feedback.ragdollEntity
        return GUIState.unconsciousRagdoll
    end

    local nwRagdoll = ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
    if IsValid(nwRagdoll) then
        if nwRagdoll ~= GUIState.unconsciousRagdoll then
            GUIState.unconsciousEyeAttachment = 0
        end

        GUIState.unconsciousRagdoll = nwRagdoll
        return nwRagdoll
    end

    if ply:Alive()
        and not ply:GetNWBool("WoundSystemUnconscious", false)
        and not CardioState.unconscious
        and not ply:GetNoDraw() then
        GUIState.unconsciousRagdoll = NULL
        GUIState.unconsciousEyeAttachment = 0
        if feedback then
            feedback.ragdollActive = false
            feedback.ragdollEntity = NULL
            feedback.ragdollPendingUntil = 0
        end
        return NULL
    end

    return IsValid(GUIState.unconsciousRagdoll) and GUIState.unconsciousRagdoll or NULL
end

WoundSystem.Health = WoundSystem.Health or {}
function WoundSystem.Health.GetCurrentCharacter(ply)
    if not IsValid(ply) then return nil end

    local ragdoll = ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
    if ply == LocalPlayer() and not IsValid(ragdoll) then
        ragdoll = ResolveUnconsciousRagdoll(ply)
    end

    if IsValid(ragdoll) then
        return ragdoll
    end

    local deathRagdoll = ply:GetNWEntity("WoundSystemDeathRagdoll")
    if IsValid(deathRagdoll) then
        return deathRagdoll
    end

    return ply
end
WoundSystem.GetCurrentCharacter = WoundSystem.Health.GetCurrentCharacter

local function IsWoundSystemRagdollCameraActive(ply)
    if not WoundSystemClientEnabled() then return false end
    if not IsValid(ply) then return false end
    local blend = WoundSystem.HealthGUI and WoundSystem.HealthGUI.RagdollCameraBlend
    if ply == LocalPlayer() and blend and blend.mode == "out" and WoundSystem.HealthGUI.IsRagdollCameraBlendActive and WoundSystem.HealthGUI.IsRagdollCameraBlendActive() then return true end
    local feedback = WoundSystem and WoundSystem.MultiplayerFeedback
    local ragdollPending = feedback and feedback.GetRagdollPending and feedback.GetRagdollPending()

    if ply:Alive()
        and CurTime() < (WoundSystem.HealthGUI.SpawnClearUntil or 0)
        and not ply:GetNWBool("WoundSystemUnconscious", false)
        and not ply:GetNoDraw() then
        return false
    end

    if ply:Alive()
        and not ply:GetNWBool("WoundSystemUnconscious", false)
        and not CardioState.unconscious
        and not ply:GetNoDraw()
        and not ragdollPending then
        return false
    end

    local ragdoll = ResolveUnconsciousRagdoll(ply)
    return ragdollPending or IsValid(ragdoll)
end

local ForceClearRagdollCameraState
WoundSystem.HealthGUI.RagdollCameraBlend = {
    active = false,
    mode = nil,
    ragdoll = NULL,
    startPos = nil,
    startAng = nil,
    started = 0,
    duration = 0,
    settledRagdoll = NULL
}

function WoundSystem.HealthGUI.IsRagdollCameraBlendActive()
    local ragdollCameraBlend = WoundSystem.HealthGUI.RagdollCameraBlend
    return ragdollCameraBlend.active and CurTime() < ((ragdollCameraBlend.started or 0) + (ragdollCameraBlend.duration or 0))
end

function WoundSystem.HealthGUI.StartRagdollCameraBlend(mode, startPos, startAng, ragdoll, duration)
    local ragdollCameraBlend = WoundSystem.HealthGUI.RagdollCameraBlend
    ragdollCameraBlend.active = true
    ragdollCameraBlend.mode = mode
    ragdollCameraBlend.ragdoll = IsValid(ragdoll) and ragdoll or NULL
    ragdollCameraBlend.startPos = startPos and Vector(startPos.x or startPos[1] or 0, startPos.y or startPos[2] or 0, startPos.z or startPos[3] or 0) or Vector(0, 0, 0)
    ragdollCameraBlend.startAng = startAng and Angle(startAng.p or startAng[1] or 0, startAng.y or startAng[2] or 0, startAng.r or startAng[3] or 0) or Angle(0, 0, 0)
    ragdollCameraBlend.started = CurTime()
    ragdollCameraBlend.duration = math.max(tonumber(duration) or 0, 0.01)
    ragdollCameraBlend.settledRagdoll = NULL
end

function WoundSystem.HealthGUI.StopRagdollCameraBlend()
    local ragdollCameraBlend = WoundSystem.HealthGUI.RagdollCameraBlend
    ragdollCameraBlend.active = false
    ragdollCameraBlend.mode = nil
    ragdollCameraBlend.ragdoll = NULL
    ragdollCameraBlend.startPos = nil
    ragdollCameraBlend.startAng = nil
    ragdollCameraBlend.started = 0
    ragdollCameraBlend.duration = 0
end

function WoundSystem.HealthGUI.ApplyRagdollCameraBlend(targetPos, targetAng)
    local ragdollCameraBlend = WoundSystem.HealthGUI.RagdollCameraBlend
    if not WoundSystem.HealthGUI.IsRagdollCameraBlendActive() then
        if ragdollCameraBlend.mode == "in" then
            ragdollCameraBlend.settledRagdoll = ragdollCameraBlend.ragdoll
        end
        WoundSystem.HealthGUI.StopRagdollCameraBlend()
        return targetPos, targetAng
    end

    local frac = math.Clamp((CurTime() - (ragdollCameraBlend.started or 0)) / math.max(ragdollCameraBlend.duration or 0.01, 0.01), 0, 1)
    frac = math.ease and math.ease.OutCubic and math.ease.OutCubic(frac) or (1 - ((1 - frac) * (1 - frac) * (1 - frac)))

    if frac >= 1 then
        if ragdollCameraBlend.mode == "in" then
            ragdollCameraBlend.settledRagdoll = ragdollCameraBlend.ragdoll
        end
        WoundSystem.HealthGUI.StopRagdollCameraBlend()
        return targetPos, targetAng
    end

    local startPos = ragdollCameraBlend.startPos or targetPos
    return startPos + ((targetPos - startPos) * frac), LerpAngle(frac, ragdollCameraBlend.startAng or targetAng, targetAng)
end

function WoundSystem.IsRagdollCameraActiveClient(ply)
    if not WoundSystemClientEnabled() then return false end
    return IsWoundSystemRagdollCameraActive(IsValid(ply) and ply or LocalPlayer())
end

function WoundSystem.ReceiveRagdollState(_, active, ragdoll)
    if not WoundSystemClientEnabled() then
        if ForceClearRagdollCameraState then ForceClearRagdollCameraState() end
        return
    end

    GUIState.unconsciousRagdoll = active and IsValid(ragdoll) and ragdoll or NULL
    GUIState.unconsciousEyeAttachment = 0
    if active then
        WoundSystem.HealthGUI.RagdollCameraBlend.settledRagdoll = NULL
        WoundSystem.HealthGUI.StopRagdollCameraBlend()
    end
end

net.Receive("WoundSystem_UnconsciousRagdoll", function()
    if not WoundSystemClientEnabled() then
        if ForceClearRagdollCameraState then ForceClearRagdollCameraState() end
        return
    end

    local ent = net.ReadEntity()
    local lifecycleSeq = WoundSystem.HealthGUI.ReadOptionalUInt(24, nil)
    if WoundSystem.HealthGUI.ShouldIgnoreLifecycleMessage(lifecycleSeq, IsValid(ent)) then return end

    local feedback = WoundSystem and WoundSystem.MultiplayerFeedback
    if feedback and (feedback.ragdollSeq or 0) > 0 then return end

    GUIState.unconsciousRagdoll = IsValid(ent) and ent or NULL
    GUIState.unconsciousEyeAttachment = 0
    if IsValid(ent) then
        WoundSystem.HealthGUI.RagdollCameraBlend.settledRagdoll = NULL
        WoundSystem.HealthGUI.StopRagdollCameraBlend()
    end
end)

local function GetUnconsciousCameraTransform(ragdoll)
    if not IsValid(ragdoll) then return nil end

    local frameNumber = FrameNumber and FrameNumber() or -1
    WoundSystem.UnconsciousCameraCache = WoundSystem.UnconsciousCameraCache or {}
    local cache = WoundSystem.UnconsciousCameraCache
    if cache.frame == frameNumber and cache.ragdoll == ragdoll and cache.pos and cache.ang then
        return cache.pos, cache.ang
    end

    ragdoll:SetupBones()

    local function StoreTransform(viewPos, viewAng)
        if not viewPos or not viewAng then return nil end

        cache.frame = frameNumber
        cache.ragdoll = ragdoll
        cache.pos = viewPos
        cache.ang = viewAng

        return viewPos, viewAng
    end

    if GUIState.unconsciousEyeAttachment <= 0 then
        GUIState.unconsciousEyeAttachment = ragdoll:LookupAttachment("eyes")
    end

    if GUIState.unconsciousEyeAttachment and GUIState.unconsciousEyeAttachment > 0 then
        local attachData = ragdoll:GetAttachment(GUIState.unconsciousEyeAttachment)
        if attachData and attachData.Pos and attachData.Ang then
            local viewAng = attachData.Ang
            viewAng.roll = 0
            return StoreTransform(attachData.Pos, viewAng)
        end
    end

    local headBone = ragdoll:LookupBone("ValveBiped.Bip01_Head1")
    if headBone then
        local matrix = ragdoll:GetBoneMatrix(headBone)
        if matrix then
            local viewPos = matrix:GetTranslation()
            local viewAng = matrix:GetAngles()
            viewAng:RotateAroundAxis(viewAng:Forward(), 90)
            viewAng:RotateAroundAxis(viewAng:Right(), -90)
            viewAng.roll = 0
            viewPos = viewPos + (viewAng:Forward() * 6)
            return StoreTransform(viewPos, viewAng)
        end
    end

    local physId = ragdoll:TranslateBoneToPhysBone(headBone or 0)
    local phys = ragdoll:GetPhysicsObjectNum(physId)
    if IsValid(phys) then
        local viewAng = phys:GetAngles()
        viewAng.roll = 0
        return StoreTransform(phys:GetPos(), viewAng)
    end

    local fallbackAng = ragdoll:GetAngles()
    fallbackAng.roll = 0
    return StoreTransform(ragdoll:GetPos() + Vector(0, 0, 10), fallbackAng)
end

local function WoundSystemUnconsciousEyeView(ply, pos, angles, fov)
    if not WoundSystemClientEnabled() then return end
    if hg and hg.WoundBridge and hg.WoundBridge.IsEnabled() then return end -- Z-City fake camera is used
    if ply ~= LocalPlayer() or not IsValid(ply) then return end
    if not IsWoundSystemRagdollCameraActive(ply) then return end

    local ragdoll = ResolveUnconsciousRagdoll(ply)
    if not IsValid(ragdoll) then
        local blend = WoundSystem.HealthGUI.RagdollCameraBlend
        if blend.mode == "out" and WoundSystem.HealthGUI.IsRagdollCameraBlendActive() then
            local targetPos = pos or ply:EyePos()
            local targetAng = angles or ply:EyeAngles()
            local viewPos, viewAng = WoundSystem.HealthGUI.ApplyRagdollCameraBlend(targetPos, targetAng)

            return {
                origin = viewPos,
                angles = viewAng,
                fov = fov,
                drawviewer = false
            }
        end

        if CurTime() > GUIState.lastRagdollRequest + 0.5 then
            net.Start("WoundSystem_RequestRagdoll")
            net.SendToServer()
            GUIState.lastRagdollRequest = CurTime()
        end
        return
    end

    local viewPos, viewAng = GetUnconsciousCameraTransform(ragdoll)
    if not viewPos or not viewAng then return end

    local blend = WoundSystem.HealthGUI.RagdollCameraBlend
    if blend.active
        and blend.mode == "in"
        and blend.ragdoll == ragdoll
        and not WoundSystem.HealthGUI.IsRagdollCameraBlendActive() then
        blend.settledRagdoll = ragdoll
        WoundSystem.HealthGUI.StopRagdollCameraBlend()
    end

    if blend.settledRagdoll ~= ragdoll
        and (not WoundSystem.HealthGUI.IsRagdollCameraBlendActive() or blend.mode ~= "in" or blend.ragdoll ~= ragdoll) then
        WoundSystem.HealthGUI.StartRagdollCameraBlend("in", pos or ply:EyePos(), angles or ply:EyeAngles(), ragdoll, 0.2)
    end

    if blend.mode == "in" and WoundSystem.HealthGUI.IsRagdollCameraBlendActive() then
        viewPos, viewAng = WoundSystem.HealthGUI.ApplyRagdollCameraBlend(viewPos, viewAng)
    end

    return {
        origin = viewPos,
        angles = viewAng,
        fov = fov,
        drawviewer = false
    }
end

hook.Add("CalcView", "00_WoundSystem_UnconsciousEyeView", WoundSystemUnconsciousEyeView)
hook.Add("CalcView", "zz_WoundSystem_UnconsciousEyeView", WoundSystemUnconsciousEyeView)

local EyeViewHook
-- GUIState.EyeViewDisabled in GUIState
-- GUIState.forceClearRagdollCameraUntil in GUIState

hook.Add("Think", "WoundSystem_EyeViewCompat", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local unconscious = IsWoundSystemRagdollCameraActive(ply)

    local calcViews = hook.GetTable().CalcView
    if not calcViews then return end

    if unconscious and not GUIState.EyeViewDisabled then
        EyeViewHook = calcViews["EYEVIEW_CalcView"]

        if EyeViewHook then
            hook.Remove("CalcView", "EYEVIEW_CalcView")
            GUIState.EyeViewDisabled = true
        end

    elseif not unconscious and GUIState.EyeViewDisabled then
        if EyeViewHook then
            hook.Add("CalcView", "EYEVIEW_CalcView", EyeViewHook)
        end

        GUIState.EyeViewDisabled = false
    end
end)

hook.Add("Think", "WoundSystem_ResolveUnconsciousRagdoll", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    if IsWoundSystemRagdollCameraActive(ply) then
        ResolveUnconsciousRagdoll(ply)
    end
end)

-- GUIState.wasHidingViewModel in GUIState

ForceClearRagdollCameraState = function(ragdollSeq, lifecycleSeq)
    if WoundSystem.HealthGUI.ShouldIgnoreLifecycleMessage(lifecycleSeq, false) then return end

    ragdollSeq = tonumber(ragdollSeq)
    local feedback = WoundSystem and WoundSystem.MultiplayerFeedback
    if feedback and ragdollSeq and ragdollSeq < (feedback.ragdollSeq or 0) then return end

    local ply = LocalPlayer()
    local oldRagdoll = IsValid(GUIState.unconsciousRagdoll) and GUIState.unconsciousRagdoll or (IsValid(ply) and ply:GetNWEntity("WoundSystemUnconsciousRagdoll") or NULL)
    if IsValid(oldRagdoll) then
        local oldPos, oldAng = GetUnconsciousCameraTransform(oldRagdoll)
        if oldPos and oldAng then
            WoundSystem.HealthGUI.StartRagdollCameraBlend("out", oldPos, oldAng, oldRagdoll, 0.28)
        else
            WoundSystem.HealthGUI.StopRagdollCameraBlend()
        end
    elseif WoundSystem.HealthGUI.RagdollCameraBlend.mode ~= "out" then
        WoundSystem.HealthGUI.StopRagdollCameraBlend()
    end

    GUIState.unconsciousRagdoll = NULL
    GUIState.unconsciousEyeAttachment = 0
    GUIState.lastRagdollRequest = 0
    GUIState.hudOpen = false
    WoundSystemHealthHUDOpen = false
    WoundSystem.HealthGUI.SetScreenClickerOwned(false, "ragdoll_camera_clear")

    if feedback then
        if ragdollSeq then
            feedback.ragdollSeq = math.max(feedback.ragdollSeq or 0, ragdollSeq)
        end
        feedback.ragdollPendingUntil = 0
        feedback.ragdollActive = false
        feedback.ragdollEntity = NULL
    end

    if IsValid(ply) then
        ply:DrawViewModel(true)
    end

    GUIState.wasHidingViewModel = false

    if GUIState.EyeViewDisabled then
        if EyeViewHook then
            hook.Add("CalcView", "EYEVIEW_CalcView", EyeViewHook)
        end
        GUIState.EyeViewDisabled = false
    end
end

net.Receive("WoundSystem_ResetRagdollCamera", function()
    local ragdollSeq = WoundSystem.HealthGUI.ReadOptionalUInt(24, nil)
    local lifecycleSeq = WoundSystem.HealthGUI.ReadOptionalUInt(24, nil)
    ForceClearRagdollCameraState(ragdollSeq, lifecycleSeq)
end)

local function ShouldHideUnconsciousViewModel()
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end

    return IsWoundSystemRagdollCameraActive(ply)
end

hook.Add("PreDrawViewModel", "WoundSystem_HideUnconsciousViewModel", function(vm, ply)
    if ply == LocalPlayer() and ShouldHideUnconsciousViewModel() then
        return true
    end
end)

hook.Add("PrePlayerDraw", "WoundSystem_HideUnconsciousPlayerModel", function(ply)
    if hg and hg.WoundBridge and hg.WoundBridge.IsEnabled() then return end -- Z-City owns the body/camera
    if IsValid(ply) and IsWoundSystemRagdollCameraActive(ply) then
        return true
    end
end)

hook.Add("Think", "WoundSystem_ViewModelVisibility", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local shouldHide = ShouldHideUnconsciousViewModel()
    if shouldHide == GUIState.wasHidingViewModel then return end

    ply:DrawViewModel(not shouldHide)
    GUIState.wasHidingViewModel = shouldHide
end)

hook.Add("PlayerSpawn", "WoundSystem_RestoreViewModelOnSpawn", function(ply)
    if hg and hg.override and hg.override[ply] then return end -- Z-City fake-ragdoll get-up, not a real respawn
    if ply ~= LocalPlayer() then return end

    GUIState.forceClearRagdollCameraUntil = CurTime() + 1
    ForceClearRagdollCameraState()
end)

hook.Add("Think", "WoundSystem_PostSpawnRagdollCameraClear", function()
    if CurTime() > GUIState.forceClearRagdollCameraUntil then return end

    local ply = LocalPlayer()
    if IsValid(ply) and ply:Alive() and not ply:GetNWBool("WoundSystemUnconscious", false) and not CardioState.unconscious then
        ForceClearRagdollCameraState()
    end
end)

hook.Add("SetupMove", "WoundSystem_ClientUnconsciousPin", function(ply, mv, cmd)
    if ply ~= LocalPlayer() or not IsValid(ply) then return end
    if not IsWoundSystemRagdollCameraActive(ply) then return end

    mv:SetVelocity(Vector(0, 0, 0))
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
    cmd:SetUpMove(0)
end)

local function IsValidUnconsciousEyeRagdoll(ply, ragdoll)
    ragdoll = IsValid(ragdoll) and ragdoll or ResolveUnconsciousRagdoll(ply)
    if not IsValid(ply) or not IsValid(ragdoll) then return false end
    if not CardioState.unconscious then return false end
    if string.lower(ragdoll:GetModel() or "") ~= string.lower(ply:GetModel() or "") then return false end

    if GUIState.unconsciousEyeAttachment <= 0 then
        GUIState.unconsciousEyeAttachment = ragdoll:LookupAttachment("eyes")
    end

    return GUIState.unconsciousEyeAttachment and GUIState.unconsciousEyeAttachment > 0
end

local UnconsciousFX = {
    InitialBrainHealth = 100,
    WasUnconscious = false,
    SmoothedBlackoutAlpha = 0,
    SmoothedDeathFade = 0,
    SmoothedUiAlpha = 0,
    CircleAlpha = 0,
    CircleIsBrainDying = false,
    SmoothedPieRatio = 0
}

local function HasDeathScreenVisualState()
    return DeathScreen.isDead
        or DeathScreen.deathScreenStarted
        or DeathScreen.clickDebounce
        or WoundSystemDeathScreenActive == true
        or (WoundSystem.HealthGUI and WoundSystem.HealthGUI.DeathScreenActive == true)
        or (UnconsciousFX.SmoothedBlackoutAlpha or 0) > 0.01
        or (UnconsciousFX.SmoothedDeathFade or 0) > 0.001
        or (UnconsciousFX.SmoothedUiAlpha or 0) > 0.001
        or (UnconsciousFX.CircleAlpha or 0) > 0.001
end

local function ClearDeathScreenVisualState()
    local hadVisualState = HasDeathScreenVisualState()

    SetDeathScreenActive(false)
    DeathScreen.deathScreenStarted = false
    DeathScreen.clickDebounce = false
    UnconsciousFX.SmoothedBlackoutAlpha = 0
    UnconsciousFX.SmoothedDeathFade = 0
    UnconsciousFX.SmoothedUiAlpha = 0
    UnconsciousFX.SmoothedPieRatio = 0
    UnconsciousFX.CircleAlpha = 0
    UnconsciousFX.CircleIsBrainDying = false
    if hadVisualState then
        WoundSystem.HealthGUI.SetScreenClickerOwned(false, "spawned_and_alive")
    end
end

local function SmoothVisualValue(current, target, speed)
    local dt = RealFrameTime and RealFrameTime() or FrameTime()
    return Lerp(1 - math.exp(-math.max(dt, 0) * speed), current or 0, target or 0)
end

local function DrawArcLine(x, y, radius, thickness, startAngle, endAngle, step, color)
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    for a = startAngle, endAngle, step do
        local nextA = a + step
        if nextA > endAngle then nextA = endAngle end
        if a == nextA then break end

        local a1 = math.rad(a)
        local a2 = math.rad(nextA)
        
        local poly = {
            { x = x + math.sin(a1) * radius, y = y - math.cos(a1) * radius },
            { x = x + math.sin(a2) * radius, y = y - math.cos(a2) * radius },
            { x = x + math.sin(a2) * (radius - thickness), y = y - math.cos(a2) * (radius - thickness) },
            { x = x + math.sin(a1) * (radius - thickness), y = y - math.cos(a1) * (radius - thickness) }
        }
        surface.DrawPoly(poly)
    end
end

local function DrawUnconsciousEcg(cx, cy, ecgW, ecgH, color)
    local stepX = ecgW / ECG.points
    local renderEcgX, renderEcgY = cx - (ecgW / 2), cy
    local gapSize = math.floor(ECG.points * -0.2)
    local head = math.floor(ECG.writeIndex)

    local prevX, prevY
    for i = 1, ECG.points do
        local dist = (i - head) % ECG.points
        local age = (ECG.points - dist) % ECG.points

        if dist < gapSize then
            prevX, prevY = nil, nil
            continue
        end

        local lifeFade = 1 - math.pow((age / ECG.points), 1.2)
        local px = renderEcgX + (i - 1) * stepX
        local distFromCenter = math.abs(px - cx) / (ecgW / 2)
        local edgeFade = math.Clamp(1 - math.pow(distFromCenter, 2), 0, 1)
        local pointAlpha = color.a * lifeFade * edgeFade
        local py = renderEcgY - ((ECG.buffer[i] or 0) * ecgH * 0.4)

        if prevX and pointAlpha > 2 then
            surface.SetDrawColor(color.r, color.g, color.b, pointAlpha)
            surface.DrawLine(prevX, prevY, px, py)
            surface.DrawLine(prevX, prevY - 1, px, py - 1)
            surface.DrawLine(prevX, prevY + 1, px, py + 1)
            surface.DrawLine(prevX, prevY - 2, px, py - 2)
            surface.DrawLine(prevX, prevY + 2, px, py + 2)
        end
        prevX, prevY = px, py
    end
end

local function DrawDeathBackgroundVisuals(elapsed)
    local scrW, scrH = ScrW(), ScrH()
    local blackAlpha = math.Clamp((elapsed or 0) / 0.25, 0, 1) * 255

    surface.SetDrawColor(0, 0, 0, blackAlpha)
    surface.DrawRect(0, 0, scrW, scrH)

    local vignetteAlpha = math.Clamp(blackAlpha, 0, 220)
    if vignetteAlpha > 0 and Mat.unconsciousVignette and not Mat.unconsciousVignette:IsError() then
        surface.SetDrawColor(255, 255, 255, vignetteAlpha)
        surface.SetMaterial(Mat.unconsciousVignette)
        surface.DrawTexturedRect(0, 0, scrW, scrH)
    end
end

local function DrawDeathTopEcg(elapsed)
    elapsed = elapsed or 0
    if elapsed < DeathScreen.deathScreenImageDelay or elapsed > DeathScreen.deathScreenImageDelay + DeathScreen.deathEcgHoldTime then return end

    local fadeOut = 1 - math.Clamp((elapsed - DeathScreen.deathScreenImageDelay) / DeathScreen.deathEcgHoldTime, 0, 1)
    if fadeOut <= 0 then return end

    local scrH = ScrH()
    local cx, cy = ScrW() / 2, scrH / 2
    local radius = scrH * 0.1875
    local ecgW, ecgH = radius * 1.4 + 20, radius * 0.6
    DrawUnconsciousEcg(cx, cy, ecgW, ecgH, Color(255, 255, 255, 220 * fadeOut))
end

hook.Add("PlayerSpawn", "WoundSystem_ResetSpawnVisualState", function(ply)
    if hg and hg.override and hg.override[ply] then return end -- Z-City fake-ragdoll get-up, not a real respawn
    if ply ~= LocalPlayer() then return end

    spawnVisualGraceUntil = CurTime() + 3
    WoundSystem.HealthGUI.SpawnClearUntil = math.max(WoundSystem.HealthGUI.SpawnClearUntil or 0, spawnVisualGraceUntil)
    ResetSpawnNeutralBodyState()

    UnconsciousFX.WasUnconscious = false
    UnconsciousFX.InitialBrainHealth = 100
    UnconsciousFX.SmoothedBlackoutAlpha = 0
    UnconsciousFX.SmoothedDeathFade = 0
    UnconsciousFX.SmoothedUiAlpha = 0
    UnconsciousFX.SmoothedPieRatio = 0
    UnconsciousFX.CircleAlpha = 0
    UnconsciousFX.CircleIsBrainDying = false
    ECG.hasPlayedAsystoleSound = false

    if IsValid(ECG.asystoleSound) then
        ECG.asystoleSound:Stop()
        ECG.asystoleSound = nil
    end

    if WoundSystemScreenFX and WoundSystemScreenFX.ResetVisualState then
        WoundSystemScreenFX.ResetVisualState()
    end

    WoundSystem.HealthGUI.DelayedRespawnCursorRelease("spawn_visual_state")
end)

net.Receive("WoundSystem_ClearDeathScreen", function()
    ClearDeathScreenVisualState()
    WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "clear_death_screen")
end)

local function DrawConsciousnessBlackout()
    if not WoundSystemClientEnabled() then
        if HasDeathScreenVisualState() then
            ClearDeathScreenVisualState()
        end
        return
    end

    local ply = LocalPlayer()
    local isGrace = (CurTime() < (spawnVisualGraceUntil or 0)) or (WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive())
    if isGrace then
        UnconsciousFX.CircleAlpha = 0
        UnconsciousFX.SmoothedUiAlpha = 0
        UnconsciousFX.SmoothedBlackoutAlpha = 0
        UnconsciousFX.SmoothedPieRatio = 0
        UnconsciousFX.SmoothedDeathFade = 0
        return
    end

    local unconsciousThreshold = 20
    local lowConsciousThreshold = 70
    local unconsciousBlackAlpha = 0.965 * 255
    local isDead = not IsValid(ply) or not ply:Alive()
    local isUnconscious = not DeathScreen.isDead and ((CardioState.unconscious or false) or (IsValid(ply) and ply:GetNWBool("WoundSystemUnconscious", false)))

    -- Persist the blackout through the actual death so there is no visual gap
    if DeathScreen.isDead then
        isUnconscious = true
    end

    local consciousness = CardioState.consciousness or 100
    local brainHealth = CardioState.brainHealth or 100
    local isBrainDying = ((CardioState.bloodPressure or 120) < 10 and consciousness < 5) or brainHealth <= 1

    if isUnconscious and not UnconsciousFX.WasUnconscious then
        UnconsciousFX.InitialBrainHealth = brainHealth
        UnconsciousFX.SmoothedPieRatio = math.Clamp(consciousness / unconsciousThreshold, 0, 1)
    end
    UnconsciousFX.WasUnconscious = isUnconscious

    local targetAlpha = 0

    if consciousness < lowConsciousThreshold then
        targetAlpha = Lerp(math.Clamp((lowConsciousThreshold - consciousness) / (lowConsciousThreshold - unconsciousThreshold), 0, 1), 0, unconsciousBlackAlpha)
    end
    if isUnconscious or consciousness < unconsciousThreshold then
        targetAlpha = math.max(targetAlpha, unconsciousBlackAlpha)
    end
    if DeathScreen.isDead then
        targetAlpha = 255
    end

    UnconsciousFX.SmoothedBlackoutAlpha = SmoothVisualValue(UnconsciousFX.SmoothedBlackoutAlpha, targetAlpha, DeathScreen.isDead and 1.15 or 0.72)

    if isBrainDying and brainHealth <= 1.0 then
        UnconsciousFX.SmoothedDeathFade = SmoothVisualValue(UnconsciousFX.SmoothedDeathFade, 1, 1.05)
    elseif not isUnconscious then
        UnconsciousFX.SmoothedDeathFade = SmoothVisualValue(UnconsciousFX.SmoothedDeathFade, 0, 1.35)
    end

    local finalBlackoutAlpha = math.max(UnconsciousFX.SmoothedBlackoutAlpha, UnconsciousFX.SmoothedDeathFade * 255)

    if finalBlackoutAlpha > 0 then
        if not (DeathScreen.isDead and DeathScreen.deathScreenStarted) then
            surface.SetDrawColor(0, 0, 0, finalBlackoutAlpha)
            surface.DrawRect(0, 0, ScrW(), ScrH())
        end
    end

    local uiShouldShow = isUnconscious and not DeathScreen.isDead and not isGrace

    if uiShouldShow then
        UnconsciousFX.SmoothedUiAlpha = SmoothVisualValue(UnconsciousFX.SmoothedUiAlpha, 1, 0.75)
    else
        UnconsciousFX.SmoothedUiAlpha = 0
    end

    if UnconsciousFX.SmoothedUiAlpha <= 0 then
        UnconsciousFX.CircleAlpha = 0
        return
    end

    local deathUiFadeOut = 1 - UnconsciousFX.SmoothedDeathFade
    local masterAlpha = UnconsciousFX.SmoothedUiAlpha * deathUiFadeOut

    if masterAlpha > 0 then
        surface.SetDrawColor(255, 255, 255, 255 * masterAlpha)
        surface.SetMaterial(Mat.unconsciousVignette)
        surface.DrawTexturedRect(0, 0, ScrW(), ScrH())

        local targetFillRatio = 0

        if isBrainDying then
            targetFillRatio = math.Clamp(brainHealth / 100, 0, 1)
        else
            targetFillRatio = math.Clamp(consciousness / unconsciousThreshold, 0, 1)
        end
        
        targetFillRatio = math.Clamp(targetFillRatio, 0, 1)

        UnconsciousFX.SmoothedPieRatio = SmoothVisualValue(UnconsciousFX.SmoothedPieRatio, targetFillRatio, 1.7)
    end

    UnconsciousFX.CircleAlpha = masterAlpha
    UnconsciousFX.CircleIsBrainDying = isBrainDying
end

local function DrawUnconsciousCircleForeground()
    local isGrace = (CurTime() < (spawnVisualGraceUntil or 0)) or (WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive())
    if isGrace or UnconsciousFX.CircleAlpha <= 0.001 then return end

    local cx, cy = ScrW() / 2, ScrH() / 2
    local radius = ScrH() * 0.1875
    local thickness = ScrH() * 0.009
    local alpha = 255 * UnconsciousFX.CircleAlpha
    local uiColor = UnconsciousFX.CircleIsBrainDying and Color(220, 40, 40, alpha) or Color(255, 255, 255, alpha)

    draw.NoTexture()

    local endAngle = 360 * UnconsciousFX.SmoothedPieRatio
    if endAngle > 1 then
        DrawArcLine(cx, cy, radius, thickness, 0, endAngle, 2, uiColor)
    end

    DrawUnconsciousEcg(cx, cy, radius * 1.4 + 20, radius * 0.6, uiColor)
end

hook.Add("PostDrawHUD", "zz_WoundSystem_UnconsciousCircleForeground", DrawUnconsciousCircleForeground)

-- ==========================================
-- CRITICAL VITALS WARNING PANEL
-- ==========================================
-- All tunables live here — change size, position,
-- timing, and colours without touching the logic.
local CriticalPanelConfig = {
    -- Anchor position as a fraction of screen size
    -- (0 = top/left edge, 0.5 = center, 1 = bottom/right edge)
    AnchorX       = 0.5,    -- Centered horizontally
    AnchorY       = 0.92,   -- 75% down (halfway between middle and bottom)

    -- Panel image dimensions (pixels at 1080p — auto-scaled)
    PanelWidth    = 320,
    PanelHeight   = 80,

    -- Text vertical nudge from the panel's center (positive = down)
    TextOffsetY   = -1,

    -- Spacing between the two text lines (scaled with resolution)
    LineGap       = -2,

    -- Flash / swap timing (seconds)
    -- Full cycle = (FlashOn + FlashOff) * 2 = 1.0 s
    --   0.00–0.25  message A visible
    --   0.25–0.50  hidden
    --   0.50–0.75  message B visible
    --   0.75–1.00  hidden
    FlashOn       = 0.15,
    FlashOff      = 0.15,

    -- Appearance
    Font          = "TechScannerFont",
    TextColor     = Color(255, 86, 106),
    PanelColor    = Color(255, 255, 255, 255),
}

local CriticalAlertMessages = {
    {"VITAL SIGNS", "CRITICAL"},
    {"TERMINATION", "IMMINENT"},
    {"SEEK MEDICAL", "ATTENTION"}
}

local function IsCasStyleCriticallyDying(cardio)
    cardio = cardio or CardioState

    local head = PlayerLimbs and PlayerLimbs.head
    local headMuscle = head and (head.muscle or head.muscleHealth or 100) or 100

    return ((cardio.totalBleedSpeed or 0) > 0.02 and (cardio.bloodVolume or 100) < 30)
        or (cardio.bloodOxygen or 100) < 50
        or ((cardio.hunger or 100) < 0 and headMuscle < 25)
        or (cardio.septicShock or 0) > 82.5
        or (cardio.temperature or 37) < 27
        or (cardio.temperature or 37) > 41.5
        or (cardio.fibrillationProgress or 0) > 60
        or (cardio.bloodPressure or 120) < 70
end

function WoundSystemDrawCriticalVitalsWarning()
    local cardio = CardioState

    local isCritical = IsCasStyleCriticallyDying(cardio)
    if not isCritical then return end

    if WoundSystemHealthHUDOpen and CurTime() >= (WoundSystemNextHealthPanelCriticalAlert or 0) then
        WoundSystemNextHealthPanelCriticalAlert = CurTime() + 1.6
        PlayLoudUISound("healthpanel-alert.ogg", 3.4, 1.55)
    end

    local cfg   = CriticalPanelConfig
    local scale = (ScrH() / 1080) * UIScale()
    local scrW, scrH = ScrW(), ScrH()

    -- 2. Draw Background Panel (Always visible)
    local panelW = cfg.PanelWidth  * scale
    local panelH = cfg.PanelHeight * scale
    local panelX = (scrW * cfg.AnchorX) - (panelW / 2)
    local panelY = (scrH * cfg.AnchorY) - (panelH / 2)

    SetGuiMaterial(Mat.criticalPiece)
    surface.SetDrawColor(cfg.PanelColor)
    DrawRectInt(panelX, panelY, panelW, panelH)

    local isFlashVisible = math.sin(CurTime() * 20) > 0
    local messageIdx = math.floor(CurTime()) % #CriticalAlertMessages + 1

    if isFlashVisible then
        local line1, line2 = CriticalAlertMessages[messageIdx][1], CriticalAlertMessages[messageIdx][2]

        surface.SetFont(cfg.Font)
        local _, fontH   = surface.GetTextSize("A")
        local lineGap    = cfg.LineGap * scale
        local totalTextH = (fontH * 2) + lineGap

        local textCX = scrW * cfg.AnchorX
        local textCY = (scrH * cfg.AnchorY) + (cfg.TextOffsetY * scale)
        local startY = textCY - (totalTextH / 2)

        draw.SimpleText(line1, cfg.Font, textCX, startY, cfg.TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(line2, cfg.Font, textCX, startY + fontH + lineGap, cfg.TextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end


local function ClearHudScratch()
    for key in pairs(GUIState.HudLimbShakeScratch) do
        GUIState.HudLimbShakeScratch[key].x = 0
        GUIState.HudLimbShakeScratch[key].y = 0
    end
    table.Empty(GUIState.HudLimbScreenPointScratch)
    for _, icons in pairs(GUIState.HudIconScratch) do
        table.Empty(icons)
    end
end

local function AddHudIcon(items, mat, color, scale)
    if not mat or mat:IsError() then return end

    local index = #items + 1
    local item = items[index]
    if not item then
        item = {}
        items[index] = item
    end

    item.mat = mat
    item.color = color
    item.scale = scale or 1
end

local function BleedPhaseColor(rate, alpha)
    rate = tonumber(rate) or 0
    alpha = alpha or 255

    local p1 = Color(255, 255, 255, alpha)
    local p2 = Color(255, 232, 45, alpha)
    local p3 = Color(105, 0, 0, alpha)

    if rate <= 0.08 then
        return LerpColor(math.Clamp((rate - 0.01) / 0.07, 0, 1), p1, p2)
    end

    return LerpColor(math.Clamp((rate - 0.08) / 0.67, 0, 1), p2, p3)
end

local function GetBleedHudIcon(state, alpha)
    if not state then return nil end

    local rate = ClientLimbBleedRate(state)
    if rate <= 0.01 then return nil end

    local bandaged = state.isBandaged == true
    local mat
    if rate < 0.05 then
        mat = bandaged and Icons.smallbleed_bandaged or Icons.smallbleed
    elseif rate < 0.35 then
        mat = bandaged and Icons.midbleed_bandaged or Icons.midbleed
    elseif rate < 0.9 then
        mat = bandaged and Icons.extremebleed_bandaged or Icons.extremebleed
    else
        mat = bandaged and Icons.strongbleed_bandaged or Icons.strongbleed
    end

    return mat, BleedPhaseColor(rate, alpha)
end

WoundSystemActionButtonPos = WoundSystemActionButtonPos or {x = nil, y = nil}

function WoundSystemDrawLimbActionPoint(limbId, state, pointPos, bX, bY, scale, dollScale, mx, my, isClicking, lastMouseState, minigameActive)
    local actionStatus = nil

    if state.customStatuses and state.customStatuses["TOURNIQUET"] then
        actionStatus = "TOURNIQUET"
    elseif state.customStatuses and state.customStatuses["SPLINTED"] then
        actionStatus = "SPLINTED"
    elseif (WoundSystemGlassShards[limbId] or 0) > 0 then
        actionStatus = "GLASS"
    elseif state.dislocated then
        actionStatus = "DISLOCATION"
    end

    if not actionStatus then return end
    if actionStatus == "DISLOCATION" and not state.dislocated then return end

    local pointCfg = WoundSystemLimbUIConfig.ActionPoint or {}
    local actionCfg = (pointCfg.Actions and pointCfg.Actions[actionStatus]) or {}
    local pointW = (actionCfg.Width or pointCfg.Width or pointCfg.Size or 32) * scale
    local pointH = (actionCfg.Height or pointCfg.Height or pointCfg.Size or 32) * scale
    local targetCenterX = pointPos and (pointPos.x + ((actionCfg.OffsetX or pointCfg.OffsetX or 34) * dollScale)) or (bX + (285 * scale))
    local targetCenterY = pointPos and (pointPos.y + ((actionCfg.OffsetY or pointCfg.OffsetY or -60) * dollScale)) or (bY + (164 * scale))
    local dt = RealFrameTime and RealFrameTime() or FrameTime()
    local lerpT = math.Clamp(dt * (actionCfg.LerpSpeed or pointCfg.LerpSpeed or 4), 0, 1)

    local actionButtonPos = WoundSystemActionButtonPos
    if not actionButtonPos.x or not actionButtonPos.y then
        actionButtonPos.x = targetCenterX
        actionButtonPos.y = targetCenterY
    else
        actionButtonPos.x = Lerp(lerpT, actionButtonPos.x, targetCenterX)
        actionButtonPos.y = Lerp(lerpT, actionButtonPos.y, targetCenterY)
    end

    local pointCenterX = actionButtonPos.x
    local pointCenterY = actionButtonPos.y
    local pointX = pointCenterX - (pointW * 0.5)
    local pointY = pointCenterY - (pointH * 0.5)
    local hoveringPoint = mx >= pointX and mx <= (pointX + pointW) and my >= pointY and my <= (pointY + pointH)
    if hoveringPoint then GUIState.actionPointHovered = true end
    local pointAlpha = minigameActive and (pointCfg.ActiveAlpha or 90) or (hoveringPoint and (pointCfg.HoverAlpha or 255) or (pointCfg.Alpha or 190))
    local pulseScale = hoveringPoint and (pointCfg.HoverScale or 1.12) or 1
    local drawW = pointW * pulseScale
    local drawH = pointH * pulseScale

    render.SetScissorRect(0, 0, 0, 0, false)
    SetGuiMaterial(Icons.uiPoint)
    surface.SetDrawColor(255, 255, 255, pointAlpha)
    DrawRectInt(pointCenterX - (drawW * 0.5), pointCenterY - (drawH * 0.5), drawW, drawH)

    if pointCfg.TextEnabled ~= false then
        local textColor = minigameActive and (pointCfg.TextActiveColor or Color(86, 221, 132, 120)) or (hoveringPoint and (pointCfg.TextHoverColor or Color(86, 255, 162, 255)) or (pointCfg.TextColor or Color(47, 224, 129, 255)))
        draw.SimpleText(actionCfg.Text or pointCfg.Text or "", actionCfg.TextFont or pointCfg.TextFont or "CrunchyTechFont", pointCenterX + ((actionCfg.TextOffsetX or pointCfg.TextOffsetX or 38) * scale), pointCenterY + ((actionCfg.TextOffsetY or pointCfg.TextOffsetY or -7) * scale), textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    if hoveringPoint then
        local tipTitle, tipDesc = WoundSystemTooltipText(actionCfg.TooltipKey or "")
        WoundSystemQueueDirectTooltip("action_" .. actionStatus, tipTitle, tipDesc, 35)
    end

    if hoveringPoint and isClicking and not GUIState.lastMouseState and not minigameActive then
        if actionStatus == "DISLOCATION" then
            RequestDislocationMinigameStart(limbId)
        elseif actionStatus == "GLASS" then
            RequestGlassMinigameStart(limbId)
        else
            RequestRemoveLimbStatus(limbId, actionStatus)
        end
    end
end

hook.Add("HUDPaint", "WoundDollAndPanel", function()
    if not WoundSystemClientEnabled() then
        WoundSystemDragState.active = false
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    DrawConsciousnessBlackout()
    if not ply:Alive() then return end

    if not GUIState.hudOpen then 
        WoundSystemDragState.active = false
        return 
    end 

    local scale = (ScrH() / 1080) * UIScale()
    local origSimpleText = draw.SimpleText
    local function SimpleTextScaled(text, font, x, y, color, alignX, alignY)
        local scaledFont = WoundSystemGetFont(font, scale)
        return origSimpleText(text, scaledFont, x, y, color, alignX, alignY)
    end
    local draw = setmetatable({ SimpleText = SimpleTextScaled }, { __index = draw })
    local mats = WoundSystemHealthGuiMats
    local dollScale = 1.5 * scale 
    local centerX, centerY = ScrW() / 2, (ScrH() / 2) + (20 * scale)
    local mx, my = gui.MousePos()
    local isClicking = input.IsMouseDown(MOUSE_LEFT)
    local isRightClicking = input.IsMouseDown(MOUSE_RIGHT)
    local isMiddleClicking = input.IsMouseDown(MOUSE_MIDDLE)
    local minigameActive = WoundSystemIsAnyWoundMinigameActive()
    local hoveredLimbId = nil

    WoundSystemResetTooltipQueue()
    
    local animProgress = math.Clamp((CurTime() - GUIState.openTime) / 0.2, 0, 1)
    local smoothProgress = 1 - math.pow(1 - animProgress, 3) 
    
    SetGuiMaterial(mats.woundbg)
    surface.SetDrawColor(255, 255, 255, math.Clamp(animProgress * 2, 0, 1) * 150)
    DrawRectInt(0, 0, ScrW(), ScrH())

    ClearHudScratch()
    local limbShakes = GUIState.HudLimbShakeScratch
    local limbScreenPoints = GUIState.HudLimbScreenPointScratch
    for _, limb in ipairs(Limbs) do
        local state = PlayerLimbs[limb.id]
        local rx, ry = 0, 0
        if state and not state.dismembered and (state.pain or 0) > 0 then
            local painFactor = state.pain * 0.02 * dollScale
            rx = math.random(-100, 100) * 0.01 * painFactor
            ry = math.random(-100, 100) * 0.01 * painFactor
        end
        local shake = limbShakes[limb.id]
        if not shake then
            shake = {x = 0, y = 0}
            limbShakes[limb.id] = shake
        end
        shake.x = rx
        shake.y = ry
    end

    for _, limb in ipairs(Limbs) do
        local limbAlpha = math.Clamp((CurTime() - (GUIState.openTime + (limb.order * 0.03))) * 8, 0, 1) * 255

        if limbAlpha > 0 then
            local state = PlayerLimbs[limb.id]
            if not state then continue end
            if state.dismembered then
                if GUIState.selectedLimbData and GUIState.selectedLimbData.id == limb.id then
                    GUIState.selectedLimbData = nil
                end
                continue
            end
            
            local scaleMult = dollScale * limb.size
            local shake = limbShakes[limb.id] or GUIState.HudZeroShake
            local baseCx = centerX + (limb.ox * dollScale)
            local baseCy = centerY + (limb.oy * dollScale)
            local cx = baseCx + shake.x
            local cy = baseCy + shake.y
            local screenPoint = limbScreenPoints[limb.id]
            if not screenPoint then
                screenPoint = {}
                limbScreenPoints[limb.id] = screenPoint
            end
            screenPoint.x = baseCx
            screenPoint.y = baseCy
            local trueW = (limb.sourceW or limb.matO:Width()) * scaleMult
            local trueH = (limb.sourceH or limb.matO:Height()) * scaleMult

            local isHovering = mx > (cx - trueW/2) and mx < (cx + trueW/2) and my > (cy - trueH/2) and my < (cy + trueH/2)
            
            if isHovering and not minigameActive then
                hoveredLimbId = limb.id
                if not GUIState.selectedLimbData or GUIState.selectedLimbData.id ~= limb.id then
                    GUIState.selectedLimbData = { id = limb.id, state = state }
                end
            end

            if isHovering and not GUIState.LastHoverStates[limb.id] then
                GUIState.HoverAnims[limb.id] = 0.5 
            end
            
            GUIState.HoverAnims[limb.id] = math.Approach(GUIState.HoverAnims[limb.id], 0, FrameTime() * 1.25)
            GUIState.LastHoverStates[limb.id] = isHovering

            local baseOutline = Color(255, (state.skin * 0.01) * 255, (state.skin * 0.01) * 255, limbAlpha)
            local darknessColor = Color(0, 0, 0, limbAlpha) 
            
            local finalOutline = LerpColor(GUIState.HoverAnims[limb.id], baseOutline, darknessColor)
            local isUnchipped = (function()
                local cvForce = GetConVar("woundsys_force_unchipped")
                if cvForce and cvForce:GetBool() then return true end
                local cvChip = GetConVar("woundsys_moodles_medical_chip")
                if cvChip and not cvChip:GetBool() then return true end
                return false
            end)()

            local middleColor
            if isUnchipped then
                if (state.pain or 0) > 80 then
                    local flashAlpha = math.abs(math.sin(RealTime() * 8)) * limbAlpha
                    middleColor = Color(255, 0, 0, flashAlpha)
                else
                    middleColor = Color(0, 0, 0, 0)
                end
            else
                if (state.muscle or 100) < 10 then
                    local flashAlpha = math.abs(math.sin(RealTime() * 8)) * limbAlpha
                    middleColor = Color(255, 0, 0, flashAlpha)
                else
                    middleColor = Color((1 - ((state.muscle or 100) * 0.01)) * 255, 0, 0, limbAlpha)
                end
            end
            
            local finalMiddle = LerpColor(GUIState.HoverAnims[limb.id], middleColor, darknessColor)
            -- local furBlood = math.Clamp((state.furBloodAmount or 0) / 10, 0, 1)
            -- if furBlood > 0 then
            --     local furMiddle, furOutline = FurBloodUiColors(limbAlpha)
            --     finalMiddle = LerpColor(furBlood * 0.55, finalMiddle, furMiddle)
            --     finalOutline = LerpColor(furBlood * 0.35, finalOutline, furOutline)
            -- end

            local injectionMat = nil
            local injectionColor = Color(255, 255, 255, limbAlpha)
            if WoundSystem.Statuses and WoundSystem.Statuses.GetActive then
                for _, status in ipairs(WoundSystem.Statuses.GetActive(state)) do
                    if status.id == "INJECTION" or status.id == "SYRINGE_WOUND" then
                        injectionMat = GetStatusIconMaterial(status.data) or Icons.injection
                        injectionColor = GetStatusIconColor(status.data, limbAlpha, status.value)
                        break
                    end
                end
            end
            if state.hasInjection and not injectionMat then
                injectionMat = Icons.injection
            end
            if injectionMat and not injectionMat:IsError() then
                screenPoint.injectionMat = injectionMat
                screenPoint.injectionColor = injectionColor
                screenPoint.injectionScale = 1.5 * dollScale
            end

            DrawSprite(limb.matM, cx, cy, scaleMult, limb.flip, finalMiddle, limb.texturePadding)
            DrawSprite(limb.matO, cx, cy, scaleMult, limb.flip, finalOutline, limb.texturePadding)

            -- Head wound overlays: draw on the doll itself so the sprites keep their own colors.
            if limb.id == "head" then
                if CardioState.disfigured then
                    local matDisfiguredStatus = Icons.disfiguredExpWound
                    if matDisfiguredStatus and not matDisfiguredStatus:IsError() then
                        DrawSprite(matDisfiguredStatus, cx, cy, scaleMult, false, Color(255, 255, 255, limbAlpha))
                    end
                end

                local matEyeStatus = Icons.eyeGone
                if state.eyes and matEyeStatus and not matEyeStatus:IsError() then
                    if state.eyes == 1 then
                        local shouldFlip = (blindEyeSide == -1)
                        DrawSprite(matEyeStatus, cx, cy, scaleMult, shouldFlip, Color(255, 255, 255, limbAlpha))
                    elseif state.eyes == 0 then
                        DrawSprite(matEyeStatus, cx, cy, scaleMult, false, Color(255, 255, 255, limbAlpha))
                        DrawSprite(matEyeStatus, cx, cy, scaleMult, true, Color(255, 255, 255, limbAlpha))
                    end
                end
            end

            if (state.skin or 100) < 95 then
                if state.hasSelfHarmWound and Icons.selfHarmWound and not Icons.selfHarmWound:IsError() then
                    DrawSprite(Icons.selfHarmWound, cx, cy, scaleMult, false, Color(255, 255, 255, limbAlpha))
                end
                if state.hasSuicideWound and Icons.suicideWound and not Icons.suicideWound:IsError() then
                    DrawSprite(Icons.suicideWound, cx, cy, scaleMult, false, Color(255, 255, 255, limbAlpha))
                end
            end
        end
    end

    for _, limb in ipairs(Limbs) do
        local point = limbScreenPoints[limb.id]
        if not point or not point.injectionMat or point.injectionMat:IsError() then continue end

        point.injectionColor = point.injectionColor or color_white
        point.injectionW = point.injectionMat:Width() * (point.injectionScale or (1.5 * dollScale))
        point.injectionH = point.injectionMat:Height() * (point.injectionScale or (1.5 * dollScale))

        SetGuiMaterial(point.injectionMat)
        surface.SetDrawColor(point.injectionColor.r, point.injectionColor.g, point.injectionColor.b, point.injectionColor.a)
        DrawRectInt(point.x - (point.injectionW * 0.5), point.y - (point.injectionH * 0.5), point.injectionW, point.injectionH)
    end

    for _, limb in ipairs(Limbs) do
        local limbAlpha = math.Clamp((CurTime() - (GUIState.openTime + (limb.order * 0.03))) * 8, 0, 1) * 255
        
        if limbAlpha > 0 then
            local state = PlayerLimbs[limb.id]
            if not state or state.dismembered then continue end
            
            local shake = limbShakes[limb.id] or GUIState.HudZeroShake
            local cx = centerX + (limb.ox * dollScale) + shake.x
            local cy = centerY + (limb.oy * dollScale) + shake.y

            local iconScaleMult = 1.5 * dollScale
            local iconItems = GUIState.HudIconScratch[limb.id]
            if not iconItems then
                iconItems = {}
                GUIState.HudIconScratch[limb.id] = iconItems
            end

            if not isUnchipped then
                if state.broken then
                    AddHudIcon(iconItems, Icons.fracture, WoundSystem.InjuryHealColor(state.boneHealTimer, limbAlpha))
                end

                if state.dislocated then
                    AddHudIcon(iconItems, Icons.dislocate, WoundSystem.InjuryHealColor(state.dislocationTimer, limbAlpha))
                end
            end

            if WoundSystem.Statuses and WoundSystem.Statuses.GetActive then
                for _, status in ipairs(WoundSystem.Statuses.GetActive(state)) do
                    if status.id == "INJECTION" or status.id == "SYRINGE_WOUND" then
                        continue
                    end

                    local mat = GetStatusIconMaterial(status.data)
                    if mat and not mat:IsError() then
                        AddHudIcon(iconItems, mat, GetStatusIconColor(status.data, limbAlpha, status.value))
                    end
                end
            end

            if ShouldShowInfectionIndicator(limb.id, state.infection) then
                local infectionColor = InfectionStatusColor(state.infection, limbAlpha)
                local displayedInfectionSpeed = GetDisplayedInfectionSpeed(state)

                if displayedInfectionSpeed > 0 then
                    AddHudIcon(iconItems, Icons.infection_up, infectionColor)
                elseif displayedInfectionSpeed < 0 then
                    AddHudIcon(iconItems, Icons.infection_down, infectionColor)
                else
                    AddHudIcon(iconItems, Icons.infectionneutral, infectionColor)
                end
            end

            if state.disinfectTime > 0 and not isUnchipped then
                local maxD = math.max(240, state.disinfectTime)
                local pct = math.Clamp(state.disinfectTime / maxD, 0, 1)
                
                local val = 255
                if pct > 0.5 then
                    val = 255
                elseif pct > 0.1 then
                    val = Lerp((pct - 0.1) / 0.4, 100, 255)
                else
                    val = Lerp(pct / 0.1, 30, 100)
                end
                
                local alpha = limbAlpha
                if state.disinfectTime < 30 then
                    alpha = alpha * (0.6 + math.sin(CurTime() * 10) * 0.4)
                end

                AddHudIcon(iconItems, Icons.disinfected, Color(val, val, val, alpha))
            end

            local glassCount = WoundSystemGlassShards[limb.id] or 0
            if glassCount > 0 and Icons.glass and not Icons.glass:IsError() then
                AddHudIcon(iconItems, Icons.glass, Color(150, 205, 235, limbAlpha))
            end

            local bleedMat, bleedColor = GetBleedHudIcon(state, limbAlpha)
            if bleedMat then
                AddHudIcon(iconItems, bleedMat, bleedColor)
            end

            local spreadCfg = WoundSystemLimbUIConfig.IconSpread or {}
            local selectedSpread = (GUIState.selectedLimbData and GUIState.selectedLimbData.id == limb.id) and 1 or 0
            local hoverSpread = math.Clamp(GUIState.HoverAnims[limb.id] or 0, 0, 1)
            local currentSpread = GUIState.LimbIconSpreadAnims[limb.id] or 0
            local smoothSpeed = spreadCfg.SmoothSpeed or 5
            currentSpread = Lerp(math.Clamp(FrameTime() * smoothSpeed, 0, 1), currentSpread, selectedSpread)
            GUIState.LimbIconSpreadAnims[limb.id] = currentSpread

            local collapsedSpread = spreadCfg.Collapsed or 0.2
            local selectedOpenSpread = spreadCfg.Selected or 1
            local hoverBoost = spreadCfg.HoverBoost or 0.25
            local spread = (Lerp(currentSpread, collapsedSpread, selectedOpenSpread) + (hoverSpread * hoverBoost)) * dollScale
            local count = #iconItems

            for i, item in ipairs(iconItems) do
                local mat = item.mat
                local iconScale = iconScaleMult * (item.scale or 1)
                local matW = mat:Width() * iconScale
                local matH = mat:Height() * iconScale
                local stepX = spreadCfg.StepX or 50
                local stepY = spreadCfg.StepY or 0.2
                local num = ((i - 1) * stepX - (count - 1) * (stepX * 0.5)) * spread
                local iX = cx + num - (matW / 2)
                local iY = cy + (num * stepY) - (matH / 2)
                local color = item.color

                SetGuiMaterial(mat)
                surface.SetDrawColor(color.r, color.g, color.b, color.a)
                DrawRectInt(iX, iY, matW, matH)
            end
        end
    end

    local panelX = 20 * scale
    local panelW, panelH = 475 * scale, 810 * scale
    local panelCenterY = (20 * scale) + (panelH / 2) 
    local currentPanelH = panelH * smoothProgress
    
    SetGuiMaterial(mats.compback)
    surface.SetDrawColor(255, 255, 255, 255)
    DrawRectInt(panelX, panelCenterY - (currentPanelH / 2), panelW, currentPanelH)
    
    if smoothProgress > 0.05 then
        local textX, textY = panelX + (25 * scale), (20 * scale) + (25 * scale)
        render.SetScissorRect(panelX, panelCenterY - (currentPanelH / 2), panelX + panelW, panelCenterY + (currentPanelH / 2), true)
            
            SetGuiMaterial(mats.screenStatic)
            surface.SetDrawColor(255, 255, 255, 255)
            DrawRectInt(panelX + (12 * scale), textY - (-50 * scale), 380 * scale, 470 * scale)

            draw.SimpleText("UNI-HEALTH v2.03", "TechScannerFont", textX + (48 * scale), textY + (43 * scale), Color(86, 221, 132))
            draw.SimpleText(LocalPlayer():Nick():upper(), "TechScannerFont", textX + (-8 * scale), textY + (-18 * scale), Color(86, 221, 132))
            
            local bloodPressureAsystole = CardioState.bloodPressure * 0.66
            local radiationGy = (CardioState.radiationSickness or 0) * 0.3
            
            -- Blood Oxygen and Heart Rate
            draw.SimpleText(math.Round(CardioState.bloodOxygen) .. "%", "TechScannerSmall", textX + (330 * scale), textY + (427 * scale), Color(86, 221, 132), TEXT_ALIGN_RIGHT)
            draw.SimpleText(math.Round(CardioState.heartRate) .. " | " .. math.Round(CardioState.bloodPressure) .. "/" .. math.Round(bloodPressureAsystole), "TechScannerSmall", textX + (23 * scale), textY + (427 * scale), Color(86, 221, 132), TEXT_ALIGN_LEFT)
			draw.SimpleText(math.Round(CardioState.respiratoryRate * 0.25) .. "/m", "TechScannerSmall", textX + (3 * scale), textY + (388 * scale), Color(86, 221, 132), TEXT_ALIGN_LEFT)
			draw.SimpleText("gy", "TechScannerSmall", textX + (353 * scale), textY + (383 * scale), Color(86, 221, 132), TEXT_ALIGN_RIGHT)
			draw.SimpleText(string.format("%.1f", radiationGy), "TechScannerSmall", textX + (330 * scale), textY + (383 * scale), Color(86, 221, 132), TEXT_ALIGN_RIGHT)
            WoundSystemQueueLocaleTooltip("hpoxygenamount", textX + (260 * scale), textY + (414 * scale), 95 * scale, 32 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hpheartrate", textX + (12 * scale), textY + (414 * scale), 75 * scale, 32 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hppressure", textX + (84 * scale), textY + (414 * scale), 145 * scale, 32 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hprr", textX + (-4 * scale), textY + (374 * scale), 85 * scale, 32 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hpradiation", textX + (275 * scale), textY + (374 * scale), 85 * scale, 32 * scale, mx, my, 10)

            -- Temperature text and Bar
            local tempVal = string.format("%.1f", CardioState.temperature) .. "'c"
            draw.SimpleText(tempVal, "TechScannerSmall", textX + (255 * scale), textY + (178 * scale), Color(47, 224, 129), TEXT_ALIGN_LEFT)
			
            -- Brain Health Bar
			local brainPct = WoundSystem.Client.PixelSnapFill(mats.barBrain, (CardioState.brainHealth or 100) / 100, false)

			local brainBarW = 289 * scale
			local brainBarH = 6 * scale
			local brainBarX = textX + (59 * scale)
			local brainBarY = textY + (83 * scale)

			-- Background
			surface.SetDrawColor(0, 0, 0, 0)
			surface.DrawRect(brainBarX, brainBarY, brainBarW, brainBarH)

			-- Fill
			SetGuiMaterial(mats.barBrain)
			surface.SetDrawColor(255, 255, 255, 255)

			DrawRectUVInt(
				brainBarX,
				brainBarY,
				brainBarW * brainPct,
				brainBarH,
				0,
				0,
				brainPct,
				1
			)
            
            WoundSystemQueueLocaleTooltip("hpbrainhealth", textX + (46 * scale), textY + (78 * scale), 120 * scale, 32 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hpconsciousness", textX + (225 * scale), textY + (78 * scale), 130 * scale, 32 * scale, mx, my, 10)

            local tPct = WoundSystem.Client.PixelSnapFill(mats.barThermometer, (CardioState.temperature - 28) * 0.08, true)
            local tBarW, tBarH = 19 * scale, 82 * scale
            local tBarX, tBarY = textX + (331 * scale), textY + (160 * scale)
            surface.SetDrawColor(255, 255, 255, 255)
            SetGuiMaterial(mats.barThermometer)
            DrawRectUVInt(tBarX, tBarY + (tBarH * (1 - tPct)), tBarW, tBarH * tPct, 0, 1 - tPct, 1, 1)
            WoundSystemQueueLocaleTooltip("hptemperature", textX + (246 * scale), textY + (157 * scale), 110 * scale, 95 * scale, mx, my, 10)

            -- Hemothorax bar
            local hPct = WoundSystem.Client.PixelSnapFill(mats.barHemothorax, (CardioState.hemothorax or 0) / 100, true)
            if hPct > 0 then
                local hInfo = WoundSystemPaddedMaterialInfo[mats.barHemothorax]
                local hBarW, hBarH = (25 * 2.5) * scale, (18 * 2.5) * scale
                local hBarX, hBarY = textX + (2 * scale), textY + (339 * scale) 
                local hDrawPadX = hInfo and (hInfo.pad * (hBarW / hInfo.sourceW)) or 0
                local hDrawPadY = hInfo and (hInfo.pad * (hBarH / hInfo.sourceH)) or 0
                
                local snappedPct = hPct
                local clipY = hBarY + (hBarH * (1 - snappedPct))
                
                local scX1 = panelX
                local scY1 = panelCenterY - (currentPanelH / 2)
                local scX2 = panelX + panelW
                local scY2 = panelCenterY + (currentPanelH / 2)
                
                local finalX1 = math.max(scX1, hBarX - hDrawPadX)
                local finalY1 = math.max(scY1, clipY)
                local finalX2 = math.min(scX2, hBarX + hBarW + hDrawPadX)
                local finalY2 = math.min(scY2, hBarY + hBarH + hDrawPadY)
                
                if finalY1 < finalY2 then
                    SetScissorRectInt(finalX1, finalY1, finalX2, finalY2, true)
                    
                    surface.SetDrawColor(255, 255, 255, 255)
                    SetGuiMaterial(mats.barHemothorax)
                    DrawRectInt(hBarX, hBarY, hBarW, hBarH)
                    
                    SetScissorRectInt(scX1, scY1, scX2, scY2, true)
                end
            end

            -- ==========================================
            -- 🫁 LUNG FILL BARS
            -- ==========================================
            local lCfg = WoundSystemLungConfig
            local l_w = lCfg.Width * scale
            local l_h = lCfg.Height * scale
            local l_space = lCfg.Distance * scale
            local l_baseX = textX + (lCfg.OffsetX * scale)
            local l_baseY = textY + (lCfg.OffsetY * scale)

            -- Updated to use the new UseStamina flag
            local lungValue = CardioState.bloodOxygen
            if lCfg.UseStamina then
                lungValue = CardioState.stamina or 100
            elseif lCfg.UseRespiratoryRate then
                lungValue = CardioState.respiratoryRate or 100
            end
            local lungPct = math.Clamp(lungValue / 100, 0, 1)

            -- NEW: Split percentage between left and right lungs
            -- Right lung drains first (from 100% to 50% of total stamina)
            local rightLungPct = WoundSystem.Client.PixelSnapFill(mats.lungFill, (lungPct - 0.5) * 2, true)
            -- Left lung drains second (from 50% to 0% of total stamina)
            local leftLungPct = WoundSystem.Client.PixelSnapFill(mats.lungFill, lungPct * 2, true)

            local leftX = l_baseX - (l_space / 2) - l_w
            local rightX = l_baseX + (l_space / 2)

            -- Configurable Flip Coordinates
            local lU1 = lCfg.FlipLeftHorizontal and 1 or 0
            local lU2 = lCfg.FlipLeftHorizontal and 0 or 1
            local lV1 = lCfg.FlipLeftVertical and 1 or 0
            local lV2 = lCfg.FlipLeftVertical and 0 or 1

            local rU1 = lCfg.FlipRightHorizontal and 1 or 0
            local rU2 = lCfg.FlipRightHorizontal and 0 or 1
            local rV1 = lCfg.FlipRightVertical and 1 or 0
            local rV2 = lCfg.FlipRightVertical and 0 or 1

            SetGuiMaterial(mats.lungFill)

            -- Background Silhouettes (Draws full size, permanently dark)
            surface.SetDrawColor(0, 0, 0, 0)
            DrawRectUVInt(leftX, l_baseY, l_w, l_h, lU1, lV1, lU2, lV2)
            DrawRectUVInt(rightX, l_baseY, l_w, l_h, rU1, rV1, rU2, rV2)

            -- Ensure we don't draw outside the main panel bounds during the slide-up animation
            local pScX1 = panelX
            local pScY1 = panelCenterY - (currentPanelH / 2)
            local pScX2 = panelX + panelW
            local pScY2 = panelCenterY + (currentPanelH / 2)

            -- Calculate Scissor Box for the LEFT Lung
            local l_scX1, l_scY1, l_scX2, l_scY2
            if lCfg.FillFromBottom then
                l_scX1 = leftX
                l_scY1 = l_baseY + l_h * (1 - leftLungPct)
                l_scX2 = leftX + l_w
                l_scY2 = l_baseY + l_h
            else
                l_scX1 = leftX
                l_scY1 = l_baseY
                l_scX2 = leftX + l_w
                l_scY2 = l_baseY + l_h * leftLungPct
            end

            local finalLX1 = math.max(l_scX1, pScX1)
            local finalLY1 = math.max(l_scY1, pScY1)
            local finalLX2 = math.min(l_scX2, pScX2)
            local finalLY2 = math.min(l_scY2, pScY2)

            if finalLY1 < finalLY2 and finalLX1 < finalLX2 then
                -- Apply the custom intersection scissor for the LEFT lung
                render.SetScissorRect(finalLX1, finalLY1, finalLX2, finalLY2, true)
                surface.SetDrawColor(lCfg.Color.r, lCfg.Color.g, lCfg.Color.b, lCfg.Color.a)
                DrawRectUVInt(leftX, l_baseY, l_w, l_h, lU1, lV1, lU2, lV2)
            end

            -- Calculate Scissor Box for the RIGHT Lung
            local r_scX1, r_scY1, r_scX2, r_scY2
            if lCfg.FillFromBottom then
                r_scX1 = rightX
                r_scY1 = l_baseY + l_h * (1 - rightLungPct)
                r_scX2 = rightX + l_w
                r_scY2 = l_baseY + l_h
            else
                r_scX1 = rightX
                r_scY1 = l_baseY
                r_scX2 = rightX + l_w
                r_scY2 = l_baseY + l_h * rightLungPct
            end

            local finalRX1 = math.max(r_scX1, pScX1)
            local finalRY1 = math.max(r_scY1, pScY1)
            local finalRX2 = math.min(r_scX2, pScX2)
            local finalRY2 = math.min(r_scY2, pScY2)

            if finalRY1 < finalRY2 and finalRX1 < finalRX2 then
                -- Apply the custom intersection scissor for the RIGHT lung
                render.SetScissorRect(finalRX1, finalRY1, finalRX2, finalRY2, true)
                surface.SetDrawColor(lCfg.Color.r, lCfg.Color.g, lCfg.Color.b, lCfg.Color.a)
                DrawRectUVInt(rightX, l_baseY, l_w, l_h, rU1, rV1, rU2, rV2)
            end

            -- Restore the main UI panel scissor rect!
            render.SetScissorRect(pScX1, pScY1, pScX2, pScY2, true)
            WoundSystemQueueLocaleTooltip(lCfg.UseStamina and "hpstamina" or "hpoxygenamount", leftX - (8 * scale), l_baseY - (8 * scale), (l_w * 2) + l_space + (16 * scale), l_h + (16 * scale), mx, my, 10)
            -- ==========================================

            -- Systemic pain
            local painDisplay = math.Clamp(math.Round(CardioState.avgPain or 0), 0, 100)
            draw.SimpleText(painDisplay .. "%", "TechScannerFont", textX + (335 * scale), textY + (119 * scale), Color(86, 221, 132), TEXT_ALIGN_RIGHT)
            WoundSystemQueueLocaleTooltip("hppain", textX + (246 * scale), textY + (106 * scale), 110 * scale, 36 * scale, mx, my, 10)
            
            -- Immunity
            local currentImmunity = math.Round(CardioState.immunity or 100)
            local immColor = Color(47, 224, 129)
            local happiness = LocalPlayer():GetNWFloat("WoundSystem_Happiness", 0)
            draw.SimpleText(currentImmunity .. "%", "TechScannerSmall", textX + (215 * scale), textY + (125 * scale), immColor, TEXT_ALIGN_RIGHT)
			draw.SimpleText(math.Round(happiness, 1), "TechScannerFont", textX + (320 * scale), textY + (250 * scale), Color(86, 221, 132), TEXT_ALIGN_RIGHT)
            WoundSystemQueueLocaleTooltip("hpimmunity", textX + (140 * scale), textY + (112 * scale), 95 * scale, 32 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hphappiness", textX + (245 * scale), textY + (238 * scale), 105 * scale, 34 * scale, mx, my, 10)
            if WoundSystemDrawMoodIcon then
                WoundSystemDrawMoodIcon(textX + (325 * scale), textY + (252 * scale), scale)
            end
			draw.SimpleText(math.Round(math.Clamp(CardioState.energy or 100, 0, 100)) .. "%", "TechScannerFont", textX + (320 * scale), textY + (285 * scale), Color(86, 221, 132), TEXT_ALIGN_RIGHT)
			draw.SimpleText(math.Round(math.Clamp(CardioState.sicknessAmount or 0, 0, 100)) .. "%", "TechScannerFont", textX + (60 * scale), textY + (250 * scale), Color(86, 221, 132), TEXT_ALIGN_LEFT)
			draw.SimpleText("52.5kg", "TechScannerFont", textX + (60 * scale), textY + (282 * scale), Color(86, 221, 132), TEXT_ALIGN_LEFT)
            WoundSystemQueueLocaleTooltip("hpenergy", textX + (245 * scale), textY + (275 * scale), 105 * scale, 34 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hpsickness", textX + (40 * scale), textY + (238 * scale), 90 * scale, 34 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hpweight", textX + (40 * scale), textY + (275 * scale), 110 * scale, 34 * scale, mx, my, 10)

            local brainHealth = math.Round(CardioState.brainHealth or 100)
            local consciousness = math.Round(CardioState.consciousness or 100)
            local brainColor = CardioState.unconscious and Color(47, 224, 129) or Color(47, 224, 129)
            draw.SimpleText(brainHealth, "TechScannerFont", textX + (55 * scale), textY + (90 * scale), brainColor, TEXT_ALIGN_LEFT)
            draw.SimpleText(consciousness .. "%", "TechScannerFont", textX + (335 * scale), textY + (93 * scale), brainColor, TEXT_ALIGN_RIGHT)
            
            local bloodPct = LocalPlayer():GetNWFloat("BloodAmount", 100)
            local liters = 2.5 + (bloodPct * 0.025)
            local bloodLiters = string.format("%.2f" .. "l", liters)
            
            draw.SimpleText(bloodLiters, "TechScannerSmall", textX + (45 * scale), textY + (125 * scale), Color(86, 221, 132))
            WoundSystemQueueLocaleTooltip("hpbloodvolume", textX + (35 * scale), textY + (112 * scale), 130 * scale, 32 * scale, mx, my, 10)
			local totalDrain = CardioState.totalBleedSpeed or 0

			if totalDrain > 0.01 then
				local totalDrainText = string.format("%.2fl/m", totalDrain)
				draw.SimpleText(totalDrainText, "TechScannerSmall", textX + (45 * scale), textY + (155 * scale), Color(86, 221, 132))
			end
            WoundSystemQueueLocaleTooltip("hpbleedspeed", textX + (35 * scale), textY + (145 * scale), 150 * scale, 32 * scale, mx, my, 10)

            local vitalsX = textX + (-8 * scale)
            local vitalsY = textY + (7 * scale)
            draw.SimpleText(GUIState.cachedVitals, "TechScannerSmall", vitalsX, vitalsY, Color(86, 221, 132))

            -- Render sweep

            local ecgW, ecgH = 340 * scale, 120 * scale
            local renderEcgX, renderEcgY = textX + (5 * scale), textY + (500 * scale)
            local stepX = ecgW / ECG.points
            WoundSystemQueueLocaleTooltip("hpecg", renderEcgX, renderEcgY - (ecgH * 0.55), ecgW, ecgH, mx, my, 10)
            
            -- Made the gap slightly larger so the fade out doesn't hit a hard wall
            local gapSize = math.floor(ECG.points * -0.2) 
            local head = math.floor(ECG.writeIndex)
            local fibRatio = math.Clamp((CardioState.fibrillationProgress or 0) / 100, 0, 1)

            local prevX, prevY
            for i = 1, ECG.points do
                local readIdx = i
                
                -- dist: distance forward from the write head (0 = head, increasing forward)
                local dist = (i - head) % ECG.points
                
                -- age: how old the pixel is (0 = brand new, ECG.points = oldest)
                local age = (ECG.points - dist) % ECG.points
                
                -- Gap logic (immediately in front of the head)
                if dist < gapSize then
                    prevX, prevY = nil, nil
                    continue 
                end
                
                -- NEW: Phasing / Comet Tail Fade
                -- Using math.pow creates a curve so it stays visible longer, then fades out smoothly
                local lifeFade = 1 - math.pow((age / ECG.points), 1.2)
                local pointAlpha = 255 * lifeFade
                
                local px = renderEcgX + (i - 1) * stepX
                local py = renderEcgY - (ECG.buffer[readIdx] * ecgH * 0.4)
                
                if prevX then 
                    local r = fibRatio > 0.6 and Lerp((fibRatio - 0.6) * 2.5, 47, 255) or 47
                    local g = fibRatio > 0.6 and Lerp((fibRatio - 0.6) * 2.5, 224, 50) or 224
                    local b = fibRatio > 0.6 and Lerp((fibRatio - 0.6) * 2.5, 129, 50) or 129
                    
                    -- BASE THICK LINE (5 passes total instead of 3)
                    surface.SetDrawColor(r, g, b, pointAlpha)
                    surface.DrawLine(prevX, prevY, px, py)
                    surface.DrawLine(prevX, prevY - 1, px, py - 1)
                    surface.DrawLine(prevX, prevY + 1, px, py + 1)
                    surface.DrawLine(prevX, prevY - 2, px, py - 2) -- Thicker!
                    surface.DrawLine(prevX, prevY + 2, px, py + 2) -- Thicker!
                    
                    -- NEW: FRONT GLOW EFFECT (Bloom)
                    -- If the point is in the newest 15% of the line, draw a wide, semi-transparent aura around it
                    local glowRange = ECG.points * 0.15
                    if age < glowRange then
                        local glowAlpha = (1 - (age / glowRange)) * 80 -- Max 80 alpha for a soft bloom
                        surface.SetDrawColor(r, g, b, glowAlpha * lifeFade)
                        
                        -- Draw outer passes for the "glow"
                        surface.DrawLine(prevX, prevY - 3, px, py - 3)
                        surface.DrawLine(prevX, prevY + 3, px, py + 3)
                        surface.DrawLine(prevX, prevY - 4, px, py - 4)
                        surface.DrawLine(prevX, prevY + 4, px, py + 4)
                    end
                end
                prevX, prevY = px, py
            end

            local bScrX, bScrY = panelX + (10 * scale), panelCenterY + (180 * scale)
            SetGuiMaterial(mats.screenSmallStatic)
            surface.SetDrawColor(255, 255, 255, 255)
            DrawRectInt(bScrX, bScrY, 380 * scale, 185 * scale)
            
            local bX, bY = bScrX + (30 * scale), bScrY + (20 * scale)
            local pct = WoundSystem.Client.PixelSnapFill(mats.barBlood, liters / 5, true)
            local barW = 8 * scale
            local barH = 53 * scale
            local startX = bX + (-13 * scale)
            local startY = bY + (-455 * scale) 

            SetGuiMaterial(mats.barBlood)
            surface.SetDrawColor(255, 255, 255, 255)
            DrawRectUVInt(startX, startY + (barH - (barH * pct)), barW, barH * pct, 0, 1 - pct, 1, 1)    
			
            local barW = 150 * scale
            local barH = 4.3 * scale
            local foodX, foodY = bX + (16 * scale), bY + (-339 * scale)
            local thirstX, thirstY = bX + (16 * scale), bY + (-370 * scale)
            local thirstValue = math.Clamp(CardioState.thirst or 100, 0, 100)
            local hungerValue = math.Clamp(CardioState.hunger or 100, 0, 100)
            local thirstPct = WoundSystem.Client.PixelSnapFill(mats.barThirst, thirstValue / 100, false)
            local hungerPct = WoundSystem.Client.PixelSnapFill(mats.barFood, hungerValue / 100, false)

            surface.SetDrawColor(0, 0, 0, 0)
            surface.DrawRect(thirstX, thirstY, barW, barH) 
            surface.SetDrawColor(47, 224, 129, 255)
            surface.DrawRect(thirstX, thirstY, math.Round(barW * thirstPct), math.Round(barH))

            surface.SetDrawColor(0, 0, 0, 0)
            surface.DrawRect(foodX, foodY, barW, barH)
            surface.SetDrawColor(47, 224, 129, 255)
            surface.DrawRect(foodX, foodY, math.Round(barW * hungerPct), math.Round(barH))

			draw.SimpleText(math.Round(thirstValue), "TechScannerFont", bX + (205 * scale), bY + (-388 * scale), Color(86, 221, 132), TEXT_ALIGN_CENTER)
			draw.SimpleText(math.Round(hungerValue), "TechScannerFont", bX + (240 * scale), bY + (-355 * scale), Color(86, 221, 132), TEXT_ALIGN_CENTER)
            WoundSystemQueueLocaleTooltip("hpthirst", thirstX, thirstY - (12 * scale), 260 * scale, 34 * scale, mx, my, 10)
            WoundSystemQueueLocaleTooltip("hphunger", foodX, foodY - (12 * scale), 260 * scale, 34 * scale, mx, my, 10)
			
			

            if GUIState.selectedLimbData then
                local s = GUIState.selectedLimbData.state
                draw.SimpleText(WoundSystemPrettyLimbName(GUIState.selectedLimbData.id), "TechScannerFont", bScrX + (180 * scale), bScrY + (-3 * scale), Color(86, 221, 132), TEXT_ALIGN_CENTER)
                WoundSystemQueueLocaleTooltip("hpselectedlimb", bScrX + (70 * scale), bScrY + (-8 * scale), 230 * scale, 32 * scale, mx, my, 10)

                local barW = 264 * scale
                local barH = 8.7 * scale
                local skinX, skinY = bX + (-14 * scale), bY + (53 * scale)
                local muscX, muscY = bX + (-14 * scale), bY + (24 * scale)
                local skinPct = WoundSystem.Client.PixelSnapFill(mats.barLimb, (s.skin or 0) / 100, false)
                local musclePct = WoundSystem.Client.PixelSnapFill(mats.barLimb, (s.muscle or 0) / 100, false)

                surface.SetDrawColor(0, 0, 0, 0)
                surface.DrawRect(skinX, skinY, barW, barH) 
                SetGuiMaterial(mats.barLimb)
                surface.SetDrawColor(255, 255, 255, 255)
                DrawRectUVInt(skinX, skinY, barW * skinPct, barH, 0, 0, skinPct, 1)

                surface.SetDrawColor(0, 0, 0, 0)
                surface.DrawRect(muscX, muscY, barW, barH)
                SetGuiMaterial(mats.barLimb)
                surface.SetDrawColor(255, 255, 255, 255)
                DrawRectUVInt(muscX, muscY, barW * musclePct, barH, 0, 0, musclePct, 1)              

                local painText = (s.pain and s.pain > 0) and tostring(math.Round(s.pain)) or "-"
                local infectionText = ShouldShowInfectionIndicator(GUIState.selectedLimbData.id, s.infection) and tostring(math.Round(s.infection)) or "-"

                draw.SimpleText(painText, "TechScannerFont", bX + (90 * scale), bY + (114 * scale), Color(86, 221, 132))
                draw.SimpleText(infectionText, "TechScannerFont", bX + (90 * scale), bY + (80 * scale), Color(86, 221, 132))
				draw.SimpleText(math.Round(s.muscle), "TechScannerFont", bX + (288 * scale), bY + (10 * scale), Color(86, 221, 132), TEXT_ALIGN_CENTER)
				draw.SimpleText(math.Round(s.skin), "TechScannerFont", bX + (288 * scale), bY + (38 * scale), Color(86, 221, 132), TEXT_ALIGN_CENTER)
                WoundSystemQueueLocaleTooltip("hpmusclehealth", muscX, muscY - (8 * scale), (barW + 70 * scale), 28 * scale, mx, my, 10)
                WoundSystemQueueLocaleTooltip("hpskinhealth", skinX, skinY - (8 * scale), (barW + 70 * scale), 28 * scale, mx, my, 10)
                WoundSystemQueueLocaleTooltip("hplimbpain", bX + (80 * scale), bY + (104 * scale), 80 * scale, 34 * scale, mx, my, 10)
                WoundSystemQueueLocaleTooltip("hpinfection", bX + (80 * scale), bY + (70 * scale), 100 * scale, 34 * scale, mx, my, 10)
                
                local uiCfg = WoundSystemLimbUIConfig
                
                -- Fracture/Dislocation UI
                if s.broken or s.dislocated then
                    local fCfg = uiCfg.Fracture
                    local fX = bX + (fCfg.X * scale)
                    local fY = bY + (fCfg.Y * scale)
                    
                    SetGuiMaterial(Icons.fracture2)
                    surface.SetDrawColor(255, 255, 255, 255)
                    DrawRectInt(fX, fY, fCfg.Width * scale, fCfg.Height * scale)
                    WoundSystemQueueLocaleTooltip("hplimbinjury", fX, fY, fCfg.Width * scale, fCfg.Height * scale, mx, my, 10)
                    
                    local timerVal = s.broken and (s.boneHealTimer or 0) or (s.dislocationTimer or 0)
					if timerVal > 0 then
						-- Get the exact speed multipliers matching your server's default ConVars
						-- (Or use GetConVar("woundsys_bone_heal_speed"):GetFloat() if synced)
						local healSpeed = s.broken and 0.043 or 0.07

						-- Convert the raw arbitrary server "units" into actual real-world seconds
						local realSecondsLeft = timerVal / healSpeed

						-- Now break down the TRUE real-world seconds into minutes and seconds
						local mins = math.floor(realSecondsLeft / 60)
						local secs = math.floor(realSecondsLeft % 60)
						
						-- Draw the multiline text (unchanged, but now updates every 1 real second!)
						local tX = fX + (fCfg.TextOffsetX * scale)
						local tY = fY + (fCfg.TextOffsetY * scale)
						
						draw.SimpleText(mins .. "m", "TechScannerFont", tX, tY, Color(86, 221, 132), TEXT_ALIGN_LEFT)
						draw.SimpleText(secs .. "s", "TechScannerFont", tX, tY + (20 * scale), Color(86, 221, 132), TEXT_ALIGN_LEFT)
					end
                end
				draw.SimpleText(math.Round(s.muscleStrength * 100),  "TechScannerFont", 78 * scale, 687 * scale, Color(86, 221, 132), TEXT_ALIGN_CENTER)				
				local tPct = WoundSystem.Client.PixelSnapFill(mats.barForce, (s.muscleStrength or 0) / 1, true)
				local tBarW, tBarH = 56 * scale, 55 * scale
				local tBarX, tBarY = 47 * scale, 722 * scale
				surface.SetDrawColor(255, 255, 255, 255)
				SetGuiMaterial(mats.barForce)
				DrawRectUVInt(tBarX, tBarY + (tBarH * (1 - tPct)), tBarW, tBarH * tPct, 0, 1 - tPct, 1, 1)				
                WoundSystemQueueLocaleTooltip("hplimbforce", tBarX, tBarY - (30 * scale), 95 * scale, (tBarH + 35 * scale), mx, my, 10)
			
                -- Bleed UI
                if s.bleed > 0.1 then
                    local bCfg = uiCfg.Bleed
                    local blX = bX + (bCfg.X * scale)
                    local blY = bY + (bCfg.Y * scale)
                    
                    SetGuiMaterial(Icons.limbbleedouter)
                    surface.SetDrawColor(255, 255, 255, 255)
                    DrawRectInt(blX, blY, bCfg.OuterWidth * scale, bCfg.OuterHeight * scale)
                    
                    local bleedRate = ClientLimbBleedRate(s)
                    -- Fill from bottom based on bleed rate against FillThreshold
                    local fillPct = WoundSystem.Client.PixelSnapFill(Icons.limbbleed, bleedRate / bCfg.FillThreshold, true)
                    
                    if fillPct > 0 then
                        local inW = bCfg.InnerWidth * scale
                        local inH = bCfg.InnerHeight * scale
                        local inX = blX + (bCfg.InnerOffsetX * scale)
                        local inY = blY + (bCfg.InnerOffsetY * scale)
                        
                        SetGuiMaterial(Icons.limbbleed)
                        surface.SetDrawColor(255, 255, 255, 255)
                        DrawRectUVInt(inX, inY + (inH * (1 - fillPct)), inW, inH * fillPct, 0, 1 - fillPct, 1, 1)
                    end
                    
                    local tX = blX + (bCfg.TextOffsetX * scale)
                    local tY = blY + (bCfg.TextOffsetY * scale)
                    
                    local rateStr = string.format("%.2f", bleedRate)
                    draw.SimpleText(rateStr, "TechScannerMedium", tX, tY, Color(86, 221, 132), TEXT_ALIGN_RIGHT)

                    draw.SimpleText("l/m", "TechScannerMedium", tX, tY + (17 * scale), Color(86, 221, 132), TEXT_ALIGN_RIGHT)
                    WoundSystemQueueLocaleTooltip("hplimbbleed", blX, blY, bCfg.OuterWidth * scale, bCfg.OuterHeight * scale, mx, my, 10)
                end

                WoundSystemDrawLimbActionPoint(GUIState.selectedLimbData.id, s, limbScreenPoints[GUIState.selectedLimbData.id], bX, bY, scale, dollScale, mx, my, isClicking, GUIState.lastMouseState, minigameActive)
            end
        
        render.SetScissorRect(0, 0, 0, 0, false)
        
        -- (the WoundSystem inventory panel was removed: items are the Z-City SWEPs)
    end

    WoundSystemSelectedLimbId = GUIState.selectedLimbData and GUIState.selectedLimbData.id or nil

    -- A click on an empty spot (not on a limb, the action button, the info panel or a minigame) closes the wound view
    do
        local overPanel = mx >= panelX and mx <= panelX + panelW and my >= (20 * scale) and my <= (20 * scale) + panelH
        local ownsClick = hoveredLimbId or GUIState.actionPointHovered or overPanel
            or minigameActive or (WoundSystemWorldDrag and WoundSystemWorldDrag.active)
            or (WoundSystem.HealthGUI.IsExternalMenuOpen and WoundSystem.HealthGUI.IsExternalMenuOpen())
        if isClicking and not GUIState.lastMouseState and not ownsClick and CurTime() - (GUIState.openTime or 0) > 0.3 then
            WoundSystem.CloseHealthHUD()
        end
    end

    GUIState.actionPointHovered = false
    GUIState.lastMouseState = isClicking
    GUIState.lastRightMouseState = isRightClicking
    WoundSystemWorldDrag = WoundSystemWorldDrag or { active = false, ent = nil }
    WoundSystemWorldDrag.lastMiddleMouseState = isMiddleClicking

    WoundSystemDrawQueuedTooltip(mx, my)

    -- Draw critical vitals warning on top of everything
    WoundSystemDrawCriticalVitalsWarning()
end, HOOK_LOW)

net.Receive("WoundSystem_UpdateCardio", function()
    CardioState.bloodVolume = net.ReadFloat()
    CardioState.internalBleeding = net.ReadFloat()
    CardioState.hemothorax = net.ReadFloat()
    CardioState.heartRate = net.ReadFloat()
    CardioState.bloodPressure = net.ReadFloat()
    CardioState.bloodOxygen = net.ReadFloat()
    CardioState.fibrillationProgress = net.ReadFloat()
    CardioState.cardioShock = net.ReadFloat()
    CardioState.adrenaline = net.ReadFloat()
    CardioState.temperature = net.ReadFloat() 
    CardioState.avgPain = net.ReadFloat()
    CardioState.immunity = net.ReadFloat()
    CardioState.respiratoryRate = net.ReadFloat()
    CardioState.brainHealth = net.ReadFloat()
    CardioState.consciousness = net.ReadFloat()
    CardioState.unconscious = net.ReadBool()
	CardioState.stamina = net.ReadFloat()
    CardioState.bloodViscosity = net.ReadFloat()
    CardioState.radiationSickness = net.ReadFloat()
    CardioState.wetness = net.ReadFloat()
    CardioState.totalBleedSpeed = net.ReadFloat()
    CardioState.sicknessAmount = net.ReadFloat()
    CardioState.hearingLoss = net.ReadFloat()
    CardioState.strokeAmount = net.ReadFloat()
    CardioState.hasPulmonaryEmbolism = net.ReadBool()
    CardioState.hunger = net.ReadFloat()
    CardioState.thirst = net.ReadFloat()
    CardioState.energy = net.ReadFloat()
    CardioState.weightOffset = net.ReadFloat()
    CardioState.septicShock = net.ReadFloat()
    CardioState.dirtyness = net.ReadFloat()
    CardioState.traumaAmount = net.ReadFloat()
    CardioState.clawHealth = net.ReadFloat()
    CardioState.clawRegrowTime = net.ReadFloat()
    CardioState.caffeinated = net.ReadFloat()
    CardioState.badSleepAmount = net.ReadFloat()
    CardioState.venomCurrent = net.ReadFloat()
    CardioState.overdoseIndex = net.ReadFloat()
    CardioState.painShock = net.ReadFloat()
    CardioState.opiateHappiness = net.ReadFloat()
    CardioState.antidepressantHappiness = net.ReadFloat()
    CardioState.opiateAmount = net.ReadFloat()
    CardioState.opiateReception = net.ReadFloat()
    CardioState.actualOpiateReception = net.ReadFloat()
    CardioState.opiateTolerance = net.ReadFloat()
    CardioState.lastStandTime = net.ReadFloat()
    CardioState.focusedLevel = net.ReadFloat()
    CardioState.horrifiedLevel = net.ReadFloat()
    CardioState.overEncumberance = net.ReadFloat()
    CardioState.brainGrowSickness = net.ReadFloat()
    CardioState.sleeping = net.ReadBool()
    CardioState.disfigured = net.ReadBool()
    CardioState.eyeGone = net.ReadBool()
    CardioState.bothEyesGone = net.ReadBool()
    CardioState.onHardStimulants = net.ReadBool()
    CardioState.impairedSpeech = net.ReadBool()
    CardioState.mindWipe = net.ReadBool()
    local lifecycleSeq = WoundSystem.HealthGUI.ReadOptionalUInt(24, nil)
    PlayerStats.STR = WoundSystem.HealthGUI.ReadOptionalUInt(8, PlayerStats.STR or 9)
    PlayerStats.RES = WoundSystem.HealthGUI.ReadOptionalUInt(8, PlayerStats.RES or 8)
    PlayerStats.INT = WoundSystem.HealthGUI.ReadOptionalUInt(8, PlayerStats.INT or 7)
    PlayerStats.consciousness = CardioState.consciousness or 100

    if WoundSystem.HealthGUI.ShouldIgnoreLifecycleMessage(lifecycleSeq, CardioState.unconscious) then
        local ply = LocalPlayer()
        if IsValid(ply) and ply:Alive() then
            ResetSpawnNeutralBodyState()
            if WoundSystemScreenFX and WoundSystemScreenFX.ResetVisualState then
                WoundSystemScreenFX.ResetVisualState()
            end
        end

        ForceClearRagdollCameraState(nil, lifecycleSeq)
        return
    end

    UpdateAsystoleSound()
end)

-- ==========================================
-- WORLD ITEM INTERACTION (TOOLTIP & DRAGGING)
-- ==========================================

WoundSystemWorldDrag = WoundSystemWorldDrag or { active = false, ent = nil }
WoundSystemWorldTooltipEnt = nil
WoundSystemWorldItemReach = 190
WoundSystemWorldItemGrabKeyConVar = GetConVar("woundsys_worlditem_grab_key") or CreateClientConVar("woundsys_worlditem_grab_key", tostring(KEY_E or 11), true, true, "Key used to grab world medical items while looking at them.")
WoundSystemLastWorldItemGrabKeyStatus = false

function WoundSystemWorldItemGrabKeyCode()
    local rawKey = string.Trim(WoundSystemWorldItemGrabKeyConVar:GetString() or "")
    local numericKey = tonumber(rawKey)
    if numericKey then return numericKey end

    local keyName = string.upper(rawKey)
    if keyName == "" then keyName = "E" end

    local keyCode = _G["KEY_" .. keyName] or _G[keyName]
    if not keyCode and string.len(keyName) == 1 then
        keyCode = _G["KEY_" .. keyName]
    end

    return keyCode or KEY_E
end

function WoundSystemIsWorldMedicalEnt(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if class ~= "item_healthvial" and class ~= "item_healthkit" then return false end
    return ent:GetNWString("WoundSystem_WorldTool", "") ~= ""
end

function WoundSystemFindReachableWorldMedicalItem(ply)
    if not IsValid(ply) then return nil end

    local startPos = ply:EyePos()
    local tr = util.TraceLine({
        start = startPos,
        endpos = startPos + (ply:GetAimVector() * WoundSystemWorldItemReach),
        filter = ply,
        mask = MASK_SOLID
    })

    if WoundSystemIsWorldMedicalEnt(tr.Entity) then
        return tr.Entity
    end

    return nil
end

function WoundSystemCancelWorldItemDrag(playSound)
    if not (WoundSystemWorldDrag and WoundSystemWorldDrag.active) then return false end

    if IsValid(WoundSystemWorldDrag.ent) then
        WoundSystemWorldDrag.ent:SetNoDraw(false)
    end

    WoundSystemWorldDrag.active = false
    WoundSystemWorldDrag.ent = nil
    WoundSystemWorldDrag.mouseButton = nil
    WoundSystemWorldDrag.keyGrab = nil
    WoundSystem.HealthGUI.SetScreenClickerOwned(WoundSystemHealthHUDOpen, "world_drag_cancel")

    if playSound then
        surface.PlaySound("click.ogg")
    end

    return true
end

function WoundSystem.HealthGUI.ResetLocalRespawnInput(reason)
    GUIState.hudOpen = false
    GUIState.openTime = 0
    WoundSystemHealthHUDOpen = false

    if WoundSystemDragState then
        WoundSystemDragState.active = false
        WoundSystemDragState.slotIdx = nil
    end

    if WoundSystemWorldDrag then
        if IsValid(WoundSystemWorldDrag.ent) then
            WoundSystemWorldDrag.ent:SetNoDraw(false)
        end

        WoundSystemWorldDrag.active = false
        WoundSystemWorldDrag.ent = nil
        WoundSystemWorldDrag.mouseButton = nil
        WoundSystemWorldDrag.keyGrab = nil
    end

    WoundSystemWorldTooltipEnt = nil

    if CloseWoundMinigames then
        CloseWoundMinigames(reason or "respawn")
    end

    if ForceClearRagdollCameraState then
        ForceClearRagdollCameraState()
    end

    if ClearDeathScreenVisualState then
        ClearDeathScreenVisualState()
    else
        SetDeathScreenActive(false)
    end

    if input then
        GUIState.lastMouseState = input.IsMouseDown and input.IsMouseDown(MOUSE_LEFT) or false
        GUIState.lastRightMouseState = input.IsMouseDown and input.IsMouseDown(MOUSE_RIGHT) or false
        GUIState.lastKeyStatus = WoundViewKeyDown()
        WoundSystemLastWorldItemGrabKeyStatus = WoundSystemWorldItemGrabKeyCode and input.IsKeyDown and input.IsKeyDown(WoundSystemWorldItemGrabKeyCode()) or false
    end

    WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "reset_local_respawn_input")
    WoundSystem.HealthGUI.DelayedRespawnCursorRelease(reason or "respawn")
end

function WoundSystemStartWorldItemDrag(ent, mouseButton, keyGrab)
    if not IsValid(ent) then return false end
    local toolName = ent:GetNWString("WoundSystem_WorldTool", "")
    if toolName == "" then return false end

    WoundSystemWorldDrag.active = true
    WoundSystemWorldDrag.ent = ent
    WoundSystemWorldDrag.mouseButton = mouseButton
    WoundSystemWorldDrag.keyGrab = keyGrab == true
    ent:SetNoDraw(true)
    WoundSystem.HealthGUI.SetScreenClickerOwned(true, "world_item_drag_start")
    surface.PlaySound("miniclick.ogg")
    return true
end

hook.Add("HUDPaintBackground", "WoundSystem_DrawManualStatic", function()
    if not WoundSystemClientEnabled() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local head = PlayerLimbs and PlayerLimbs["head"]
    if not head or head.eyes ~= 1 then return end

    local w, h = ScrW(), ScrH()
    local halfW = w / 2
    local curTime = CurTime()
    
    -- ADJUST THIS: Shift strength away from the center
    local xOffsetVal = 100 
    
    -- DYNAMIC SPLIT DIRECTION:
    -- If blindEyeSide is 1 (Right): split is at center + 100
    -- If blindEyeSide is -1 (Left): split is at center - 100
    local targetSplitX = halfW + (xOffsetVal * blindEyeSide)

    -- 1. Draw the solid black background on the blind side
    surface.SetDrawColor(0, 0, 0, 255)
    if blindEyeSide == 1 then
        -- Blind Right: Draw from split to the right edge
        surface.DrawRect(targetSplitX, 0, w - targetSplitX, h)
    else
        -- Blind Left: Draw from 0 up to the split point
        surface.DrawRect(0, 0, targetSplitX, h)
    end

    if LowEndMode() then return end

    -- 2. Draw manual static loop
    for x = 0, w, GUIState.blockSize do 
        -- Determine if this X coordinate is inside the pure blind zone
        local isInside = false
        if blindEyeSide == 1 then
            isInside = x >= targetSplitX
        else
            isInside = x <= targetSplitX
        end

        -- Render/cache frequency logic
        local interval = isInside and 0.3 or 0.1

        -- Only run layout calculations if we are in the static's reach
        local isWithinStaticRange = false
        if blindEyeSide == 1 then
            isWithinStaticRange = x >= (targetSplitX - (GUIState.blockSize * 10))
        else
            isWithinStaticRange = x <= (targetSplitX + (GUIState.blockSize * 10))
        end

        if isWithinStaticRange then
            if not GUIState.staticCache[x] or (curTime - GUIState.staticCache[x].lastUpdate >= interval) then
                GUIState.staticCache[x] = { lastUpdate = curTime, blocks = {} }
                
                for y = 0, h, GUIState.blockSize do
                    local shouldDraw = true
                    
                    -- Leak/feathering logic for the edge gradient blocks
                    if not isInside then
                        local dist = math.abs(targetSplitX - x) / GUIState.blockSize
                        local chance = (dist <= 2 and 0.9) or (dist <= 4 and 0.7) or (dist <= 6 and 0.5) or (dist <= 8 and 0.1) or 0
                        if math.random() > chance then shouldDraw = false end
                    end
                    
                    GUIState.staticCache[x].blocks[y] = shouldDraw and math.random(1, 20) or nil
                end
            end

            -- Paint cached static blocks
            for y, val in pairs(GUIState.staticCache[x].blocks) do
                surface.SetDrawColor(val, val, val, 255)
                surface.DrawRect(x, y, GUIState.blockSize, GUIState.blockSize)
            end
        end
    end

    -- 3. Draw the organic gradient fades (Flipped depending on side)
    surface.SetDrawColor(0, 0, 0, 255)
    
    if blindEyeSide == 1 then
        -- Fading out to the right side
        SetGuiMaterial(Mat.gradientR)  -- gradient-r
        surface.DrawTexturedRect(targetSplitX - 380, 0, w * 0.2, h)
        
        SetGuiMaterial(Mat.gradientL) -- gradient-l
        surface.DrawTexturedRect(targetSplitX, 0, w * 0.2, h)
    else
        -- Fading out to the left side
        SetGuiMaterial(Mat.gradientL) -- Invert materials for left split
        surface.DrawTexturedRect(targetSplitX, 0, w * 0.2, h)
        
        SetGuiMaterial(Mat.gradientR) 
        surface.DrawTexturedRect(targetSplitX - (w * 0.2), 0, w * 0.2, h)
    end
end, HOOK_LOW)

-- Ensure the cache exists so the loop doesn't error on the first frame
if not GUIState.staticCache then GUIState.staticCache = {} end

hook.Add("HUDPaintBackground", "WoundSystem_FullStatic", function()
    if not WoundSystemClientEnabled() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local head = PlayerLimbs and PlayerLimbs["head"]
    -- Only run if eyes are 0 (total blindness)
    if not head or head.eyes ~= 0 then return end

    local w, h = ScrW(), ScrH()
    local curTime = CurTime()
    
    -- GUIState.blockSize of 10-12 gives a good balance between "grit" and performance
    local blockSize = 18 
    local alpha = 230 

    if LowEndMode() then
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, w, h)
        return
    end
    
    -- Draw across the whole screen
    for x = 0, w, GUIState.blockSize do 
        -- Update static frequency: 0.1s ensures constant jittery motion
        if not GUIState.staticCache[x] or (curTime - (GUIState.staticCache[x].lastUpdate or 0) >= 0.05) then
            GUIState.staticCache[x] = { lastUpdate = curTime, blocks = {} }
            
            for y = 0, h, GUIState.blockSize do
                -- Higher numbers = brighter static
                GUIState.staticCache[x].blocks[y] = math.random(0, 100) 
            end
        end

        -- Render the blocks with Additive Blending
		-- Render the blocks with Multiplicative Blending
		for y, val in pairs(GUIState.staticCache[x].blocks) do
			-- Convert the random value (0-50) to a normalized 0-1 brightness
			-- We map 50 to a brighter value for better contrast
			local brightness = val / 50 
			
			-- Set the color: White means "don't change the background", 
			-- Darker values will "darken" the background.
			-- To make it "brighten" in light areas, we use a different blend:
			surface.SetDrawColor(val * 2, val * 2, val * 2, alpha)
			
			-- BLEND_DST_COLOR / BLEND_SRC_COLOR creates a "Screen" or "Soft Light" effect
			-- This makes the static look like it's part of the scene's lighting
			render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_SRC_COLOR, BLENDFUNC_ADD)
			
			surface.DrawRect(x, y, GUIState.blockSize, GUIState.blockSize)
			
			render.OverrideBlend(false)
		end
    end
end, HOOK_LOW)

WoundSystemScreenFX = WoundSystemScreenFX or {}

function WoundSystemScreenFX.GetCasStyleTotalHappiness()
    local ply = LocalPlayer()
    if not IsValid(ply) then return 0 end

    local total = (WoundSystemClientState and WoundSystemClientState.Happiness)
    if total == nil then
        total = ply:GetNWFloat("WoundSystem_Happiness", 0)
    end

    return math.Clamp(tonumber(total) or 0, -100, 100)
end

function WoundSystemScreenFX.SmoothCasScreenValue(field, target, speed)
    local dt = RealFrameTime and RealFrameTime() or FrameTime()
    WoundSystemScreenFX[field] = Lerp(math.Clamp(dt * speed, 0, 1), WoundSystemScreenFX[field] or target or 0, target or 0)
    return WoundSystemScreenFX[field]
end

function WoundSystemScreenFX.UpdateConditionOverlayVisuals()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or (WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive()) then
        WoundSystemScreenFX.depressionOverlayIntensity = WoundSystemScreenFX.SmoothCasScreenValue("depressionOverlayIntensity", 0, 2)
        WoundSystemScreenFX.dirtyLensIntensity = WoundSystemScreenFX.SmoothCasScreenValue("dirtyLensIntensity", 0, 5)
        return WoundSystemScreenFX.depressionOverlayIntensity, WoundSystemScreenFX.dirtyLensIntensity
    end

    local sadSmooth = WoundSystemScreenFX.SmoothCasScreenValue("sadSmooth", WoundSystemScreenFX.GetCasStyleTotalHappiness(), 0.5)
    local insanity = math.Clamp(sadSmooth * -0.01, 0, 1)
    WoundSystemScreenFX.depressionOverlayIntensity = insanity

    local dirtyTarget = math.Clamp((CardioState.dirtyness or 0) * 0.01, 0, 1)
    local dirtySmooth = WoundSystemScreenFX.SmoothCasScreenValue("dirtSmooth", dirtyTarget, 5)
    WoundSystemScreenFX.dirtyLensIntensity = dirtySmooth

    return WoundSystemScreenFX.depressionOverlayIntensity, WoundSystemScreenFX.dirtyLensIntensity
end



-- Cache the materials

hook.Add("HUDPaintBackground", "WoundSystem_BlindVignette", function()
    if not WoundSystemClientEnabled() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    local head = PlayerLimbs and PlayerLimbs["head"]
    local eyes = head and head.eyes or 2

    if eyes == 0 then
        local w = ScrW()
        local h = ScrH()
        local thickness = 800 
        
        surface.SetDrawColor(0, 0, 0, 255)
        
        -- Top: Use gradient-u (fades from bottom to top)
        SetGuiMaterial(Mat.gradUp)
        surface.DrawTexturedRect(0, 0, w, thickness)
        
        -- Bottom: Use gradient-d (fades from top to bottom)
        SetGuiMaterial(Mat.gradDown)
        surface.DrawTexturedRect(0, h - thickness, w, thickness)
        
        -- Left: Use gradient-l (fades from right to left)
        SetGuiMaterial(Mat.gradLeft)
        surface.DrawTexturedRect(0, 0, thickness, h)
        
        -- Right: Use gradient-r (fades from left to right)
        SetGuiMaterial(Mat.gradRight)
        surface.DrawTexturedRect(w - thickness, 0, thickness, h)
    end
end, HOOK_LOW)

hook.Add("PostDrawSkyBox", "WoundSystem_BlackSkybox", function()
    if not WoundSystemClientEnabled() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    local head = PlayerLimbs and PlayerLimbs["head"]
    local eyes = head and head.eyes or 2

    if eyes == 0 then
        -- This draws a black box covering the entire skybox view
        cam.Start2D()
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, ScrW(), ScrH())
        cam.End2D()
    end
end, HOOK_LOW)

WoundSystemScreenFX.blindnessDistance = 70.37

function WoundSystemScreenFX.ApplyBlindnessFog()
    if not WoundSystemClientEnabled() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local head = PlayerLimbs and PlayerLimbs["head"]
    local eyes = head and head.eyes or 2

    if eyes == 0 then
        render.FogMode(MATERIAL_FOG_LINEAR)
        render.FogStart(0)
        render.FogEnd(WoundSystemScreenFX.blindnessDistance or 70.37)
        render.FogMaxDensity(1)
        render.FogColor(0, 0, 0)
        return true
    end
end
hook.Add("SetupWorldFog", "WoundSystem_WorldFog", WoundSystemScreenFX.ApplyBlindnessFog)
hook.Add("SetupSkyboxFog", "WoundSystem_SkyFog", WoundSystemScreenFX.ApplyBlindnessFog)

-- This hook now handles both Greyscale and Bloom, with an explicit 
-- reset command to clear effects immediately upon death.
hook.Add("RenderScreenspaceEffects", "WoundSystem_BlindEffects", function()
    if not WoundSystemClientEnabled() then return end
    if LowEndMode() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    local ply = LocalPlayer()
    
    -- 1. Check if the player is alive and needs effects
    local head = PlayerLimbs and PlayerLimbs["head"]
    local eyes = head and head.eyes or 2
    
    -- 2. If the player is DEAD or NOT BLIND, we must clear the effects
    if not IsValid(ply) or not ply:Alive() or eyes ~= 0 then
        -- Force-clear Bloom by setting all values to 0
        DrawBloom(0, 0, 0, 0, 0, 0, 0, 0, 0)
        
        -- Reset ColorModify to normal colors
        DrawColorModify({
            ["$pp_colour_contrast"] = 1,
            ["$pp_colour_colour"] = 1,
            ["$pp_colour_brightness"] = 0
        })
        return
    end

    -- 3. If the player IS alive and blind, apply the effects
    local colorMod = {
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = 0,
        ["$pp_colour_contrast"] = 1.5,
        ["$pp_colour_colour"] = 0,     -- Pure Greyscale
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0
    }
    DrawColorModify(colorMod)

    -- Apply Bloom for the "sickly" effect
    DrawBloom(0, 0.3, 9, 9, 1, 1, 1, 1, 1)
end, HOOK_HIGH)
hook.Add("RenderScreenspaceEffects", "WoundSystem_ChromaticAberration", function()
    if not WoundSystemClientEnabled() then return end
    if LowEndMode() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    local head = PlayerLimbs and PlayerLimbs["head"]
    local eyes = head and head.eyes or 2

    if eyes == 0 then
        -- This uses the engine's built-in chromatic aberration effect.
        -- We can pass a strength value. The higher the number, the more intense the color splitting.
        -- To make it feel "sickly," we can set this to a higher intensity.
        DrawBloom(0, .3, 9, 9, 1, 1, 1, 1, 1) -- Optional: add a bit of bloom to make it "glow"

    end
end, HOOK_HIGH)

hook.Add("PlayerSpawn", "WoundSystem_ResetDeathScreen", function(ply)
    if hg and hg.override and hg.override[ply] then return end -- Z-City fake-ragdoll get-up, not a real respawn
    if ply == LocalPlayer() then
        WoundSystem.HealthGUI.NoteLocalRespawn()
        WoundSystem.HealthGUI.ResetLocalRespawnInput("respawn")
    end
end)

hook.Add("HUDPaint", "WoundSystem_DeathScreenDisplay", function()
    if not WoundSystemClientEnabled() then
        if HasDeathScreenVisualState() then
            ClearDeathScreenVisualState()
        end
        return
    end

    local ply = LocalPlayer()
    if IsValid(ply) and ply:Alive() and DeathScreen.isDead then
        ClearDeathScreenVisualState()
        WoundSystem.HealthGUI.ForceReleaseScreenClicker(false, "deathscreen_alive_clear")
        return
    end

    if IsValid(ply) and not ply:Alive() and not DeathScreen.isDead then
        SetDeathScreenActive(true)
        DeathScreen.deathTime = CurTime()
        DeathScreen.deathType = "normal"
        DeathScreen.deathScreenStarted = true
        DeathScreen.clickDebounce = false
        UnconsciousFX.SmoothedBlackoutAlpha = 255
        WoundSystem.HealthGUI.SetScreenClickerOwned(true, "deathscreen_dead_fallback")
    end

    if not DeathScreen.isDead then return end
    if not DeathScreen.deathScreenStarted then
        if UnconsciousFX.SmoothedBlackoutAlpha < (0.965 * 255) and CurTime() - DeathScreen.deathTime < 5 then
            return
        end

        DeathScreen.deathScreenStarted = true
        DeathScreen.deathTime = CurTime()
    end

    local elapsed = CurTime() - DeathScreen.deathTime
    local scrW, scrH = ScrW(), ScrH()

    DrawDeathBackgroundVisuals(elapsed)

    -- 1. Quick transition before the actual death screen material fades in.
    if elapsed < DeathScreen.deathScreenImageDelay then
        DrawDeathTopEcg(elapsed)
        return
    end

    -- 2. Slowly show the true death screen over 5 seconds
    local fadeElapsed = elapsed - DeathScreen.deathScreenImageDelay
    local screenAlpha = math.Clamp(fadeElapsed / 5, 0, 1) * 255

    -- Determine which material to draw
    local activeMat = Mat.newdeath
    if DeathScreen.deathType == "violent" then
        activeMat = Mat.newdeathviolent
    elseif DeathScreen.deathType == "drowning" then
        activeMat = Mat.newdeathdrowning
    end

    if activeMat and not activeMat:IsError() then
        -- Leverage your PaddedMaterial wrapper configuration
        WoundSystem.Client.SetGuiMaterial(activeMat)
        surface.SetDrawColor(255, 255, 255, screenAlpha)
        
        -- Stretches to completely cover the screen space
        WoundSystem.Client.DrawRectInt(0, 0, scrW, scrH)
    end

    DrawDeathTopEcg(elapsed)

    -- 3. Click anywhere on the death screen to trigger respawn
    if input.IsMouseDown(MOUSE_LEFT) then
        -- Adding a brief 1-second delay from death to prevent instant accidental click-throughs
        if not DeathScreen.clickDebounce and fadeElapsed >= 1.0 then 
            DeathScreen.clickDebounce = true
            SetDeathScreenActive(false)
            WoundSystem.HealthGUI.SetScreenClickerOwned(false, "deathscreen_think_not_dead")
            
            net.Start("WoundSystem_PlayerRespawnRequest")
            net.SendToServer()
        end
    else
        DeathScreen.clickDebounce = false
    end
end, HOOK_HIGH)


-- ==========================================
-- SETUP
-- ==========================================
WoundSystemScreenFX = WoundSystemScreenFX or {}
WoundSystemScreenFX.testVignetteCache = WoundSystemScreenFX.testVignetteCache or {}
WoundSystemScreenFX.matGradUp = WoundSystemScreenFX.matGradUp or Material("vgui/gradient-u")
WoundSystemScreenFX.matGradDown = WoundSystemScreenFX.matGradDown or Material("vgui/gradient-d")
WoundSystemScreenFX.matGradLeft = WoundSystemScreenFX.matGradLeft or Material("vgui/gradient-l")
WoundSystemScreenFX.matGradRight = WoundSystemScreenFX.matGradRight or Material("vgui/gradient-r")
WoundSystemScreenFX.lastViewAng = WoundSystemScreenFX.lastViewAng or Angle(0, 0, 0)
WoundSystemScreenFX.swayX = WoundSystemScreenFX.swayX or 0
WoundSystemScreenFX.swayY = WoundSystemScreenFX.swayY or 0
WoundSystemScreenFX.painPulseVisual = WoundSystemScreenFX.painPulseVisual or 0
WoundSystemScreenFX.painDistortionVisual = WoundSystemScreenFX.painDistortionVisual or 0
WoundSystemScreenFX.painSmooth = WoundSystemScreenFX.painSmooth or 0
WoundSystemScreenFX.painbeatTime = WoundSystemScreenFX.painbeatTime or 0
WoundSystemScreenFX.lastVisualSeverityFrame = WoundSystemScreenFX.lastVisualSeverityFrame or -1
WoundSystemScreenFX.pixelVignetteSmooth = WoundSystemScreenFX.pixelVignetteSmooth or 0
WoundSystemScreenFX.lowOxygenVisual = WoundSystemScreenFX.lowOxygenVisual or 0
WoundSystemScreenFX.lastLowOxygenFrame = WoundSystemScreenFX.lastLowOxygenFrame or -1
WoundSystemScreenFX.bloodLossVisual = WoundSystemScreenFX.bloodLossVisual or 0
WoundSystemScreenFX.lastBloodLossFrame = WoundSystemScreenFX.lastBloodLossFrame or -1
WoundSystemScreenFX.consciousnessBlurVisual = WoundSystemScreenFX.consciousnessBlurVisual or 0
WoundSystemScreenFX.lastConsciousnessBlurFrame = WoundSystemScreenFX.lastConsciousnessBlurFrame or -1
WoundSystemScreenFX.opiateVisual = WoundSystemScreenFX.opiateVisual or 0
WoundSystemScreenFX.withdrawalVisual = WoundSystemScreenFX.withdrawalVisual or 0
WoundSystemScreenFX.lastDrugVisualFrame = WoundSystemScreenFX.lastDrugVisualFrame or -1
WoundSystemScreenFX.lastDrawChannelFrame = WoundSystemScreenFX.lastDrawChannelFrame or -1
WoundSystemScreenFX.drawPainPulse = WoundSystemScreenFX.drawPainPulse or 0
WoundSystemScreenFX.drawPainDistortion = WoundSystemScreenFX.drawPainDistortion or 0
WoundSystemScreenFX.drawLowOxygen = WoundSystemScreenFX.drawLowOxygen or 0
WoundSystemScreenFX.drawBloodLoss = WoundSystemScreenFX.drawBloodLoss or 0
WoundSystemScreenFX.drawConsciousnessBlur = WoundSystemScreenFX.drawConsciousnessBlur or 0
WoundSystemScreenFX.drawOpiateVisual = WoundSystemScreenFX.drawOpiateVisual or 0
WoundSystemScreenFX.drawWithdrawalVisual = WoundSystemScreenFX.drawWithdrawalVisual or 0
WoundSystemScreenFX.drawPixelStatic = WoundSystemScreenFX.drawPixelStatic or 0

function WoundSystemScreenFX.ResetVisualState()
    WoundSystemScreenFX.painPulseVisual = 0
    WoundSystemScreenFX.painDistortionVisual = 0
    WoundSystemScreenFX.painSmooth = 0
    WoundSystemScreenFX.painbeatTime = 0
    WoundSystemScreenFX.pixelVignetteSmooth = 0
    WoundSystemScreenFX.lowOxygenVisual = 0
    WoundSystemScreenFX.bloodLossVisual = 0
    WoundSystemScreenFX.consciousnessBlurVisual = 0
    WoundSystemScreenFX.opiateVisual = 0
    WoundSystemScreenFX.withdrawalVisual = 0
    WoundSystemScreenFX.drawPainPulse = 0
    WoundSystemScreenFX.drawPainDistortion = 0
    WoundSystemScreenFX.drawLowOxygen = 0
    WoundSystemScreenFX.drawBloodLoss = 0
    WoundSystemScreenFX.drawConsciousnessBlur = 0
    WoundSystemScreenFX.drawOpiateVisual = 0
    WoundSystemScreenFX.drawWithdrawalVisual = 0
    WoundSystemScreenFX.drawPixelStatic = 0
    WoundSystemScreenFX.depressionOverlayIntensity = 0
    WoundSystemScreenFX.dirtyLensIntensity = 0
    WoundSystemScreenFX.sadSmooth = 0
    WoundSystemScreenFX.dirtSmooth = 0
    WoundSystemScreenFX._CamHunger = 0
    WoundSystemScreenFX._CamThirst = 0
    WoundSystemScreenFX._CamSickness = 0
    WoundSystemScreenFX._CamCold = 0
    WoundSystemScreenFX._CamOverheat = 0
    WoundSystemScreenFX._CamDirty = 0
    WoundSystemScreenFX._CamWet = 0
    WoundSystemScreenFX._CamStimulant = 0
    WoundSystemScreenFX._PlayerCameraChannels = nil
    WoundSystemScreenFX.lastVisualSeverityFrame = -1
    WoundSystemScreenFX.lastLowOxygenFrame = -1
    WoundSystemScreenFX.lastBloodLossFrame = -1
    WoundSystemScreenFX.lastConsciousnessBlurFrame = -1
    WoundSystemScreenFX.lastDrugVisualFrame = -1
    WoundSystemScreenFX.lastDrawChannelFrame = -1
end

function WoundSystemScreenFX.Smooth(current, target, riseSpeed, fallSpeed)
    local speed = ((target or 0) > (current or 0)) and riseSpeed or fallSpeed
    local dt = RealFrameTime and RealFrameTime() or FrameTime()
    return Lerp(1 - math.exp(-math.max(dt, 0) * speed), current or 0, target or 0)
end

function WoundSystemScreenFX.UpdateDrawChannels(painPulse, painDistortion, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual)
    local frameNumber = FrameNumber and FrameNumber() or -1
    if frameNumber == WoundSystemScreenFX.lastDrawChannelFrame then
        return WoundSystemScreenFX.drawPainPulse,
            WoundSystemScreenFX.drawPainDistortion,
            WoundSystemScreenFX.drawLowOxygen,
            WoundSystemScreenFX.drawBloodLoss,
            WoundSystemScreenFX.drawConsciousnessBlur,
            WoundSystemScreenFX.drawOpiateVisual,
            WoundSystemScreenFX.drawWithdrawalVisual,
            WoundSystemScreenFX.drawPixelStatic
    end

    WoundSystemScreenFX.lastDrawChannelFrame = frameNumber
    WoundSystemScreenFX.drawPainPulse = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawPainPulse, painPulse or 0, 5.2, 3.1)
    WoundSystemScreenFX.drawPainDistortion = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawPainDistortion, painDistortion or 0, 3.4, 2.2)
    WoundSystemScreenFX.drawLowOxygen = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawLowOxygen, lowOxygen or 0, 2.0, 1.35)
    WoundSystemScreenFX.drawBloodLoss = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawBloodLoss, bloodLoss or 0, 1.75, 1.15)
    WoundSystemScreenFX.drawConsciousnessBlur = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawConsciousnessBlur, consciousnessBlur or 0, 2.15, 1.45)
    WoundSystemScreenFX.drawOpiateVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawOpiateVisual, opiateVisual or 0, 1.65, 1.05)
    WoundSystemScreenFX.drawWithdrawalVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawWithdrawalVisual, withdrawalVisual or 0, 2.1, 1.2)

    local staticTarget = math.max(math.Clamp(((painPulse or 0) - 0.28) / 0.72, 0, 1), (withdrawalVisual or 0) * 0.55)
    staticTarget = staticTarget * staticTarget * (3 - 2 * staticTarget)
    WoundSystemScreenFX.pixelVignetteSmooth = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.pixelVignetteSmooth, staticTarget, 2.0, 1.35)
    WoundSystemScreenFX.drawPixelStatic = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.drawPixelStatic, WoundSystemScreenFX.pixelVignetteSmooth, 2.6, 1.7)

    return WoundSystemScreenFX.drawPainPulse,
        WoundSystemScreenFX.drawPainDistortion,
        WoundSystemScreenFX.drawLowOxygen,
        WoundSystemScreenFX.drawBloodLoss,
        WoundSystemScreenFX.drawConsciousnessBlur,
        WoundSystemScreenFX.drawOpiateVisual,
        WoundSystemScreenFX.drawWithdrawalVisual,
        WoundSystemScreenFX.drawPixelStatic
end

-- ==========================================
-- SHARED UPDATE LOGIC
-- ==========================================
function WoundSystemScreenFX.GetClientPainVisualSource()
    local cardioPain = math.Clamp(CardioState.avgPain or 0, 0, 100)
    local maxLimbPain = 0
    local limbPainSum = 0
    local limbPainCount = 0

    for _, state in pairs(PlayerLimbs) do
        local limbPain = math.Clamp(tonumber(state and state.pain) or 0, 0, 100)
        if limbPain > 0 then
            maxLimbPain = math.max(maxLimbPain, limbPain)
            limbPainSum = limbPainSum + limbPain
            limbPainCount = limbPainCount + 1
        end
    end

    local limbAverage = limbPainCount > 0 and (limbPainSum / limbPainCount) or 0
    local feedback = WoundSystem and WoundSystem.MultiplayerFeedback
    local feedbackPain = feedback and feedback.GetPainBoost and math.Clamp(feedback.GetPainBoost(), 0, 100) or 0

    return math.max(cardioPain, maxLimbPain * 0.85, limbAverage, feedbackPain), cardioPain, maxLimbPain
end

function WoundSystemScreenFX.UpdatePainVisuals()
    local strength = math.Clamp(CVars.PainVisualStrength:GetFloat(), 0, 2)
    if FrameNumber then
        local frameNumber = FrameNumber()
        if frameNumber == WoundSystemScreenFX.lastVisualSeverityFrame then
            return WoundSystemScreenFX.painPulseVisual * strength, WoundSystemScreenFX.painDistortionVisual * strength
        end
        WoundSystemScreenFX.lastVisualSeverityFrame = frameNumber
    end

    local ply = LocalPlayer()
    
    if IsValid(ply) and ply:Alive() then
        local avgPain, cardioPain, maxLimbPain = WoundSystemScreenFX.GetClientPainVisualSource()
        WoundSystemScreenFX.lastPainVisualSource = avgPain
        WoundSystemScreenFX.lastPainVisualCardio = cardioPain
        WoundSystemScreenFX.lastPainVisualLimb = maxLimbPain
        WoundSystemScreenFX.painSmooth = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.painSmooth, avgPain, 4.5, 2.8)
        WoundSystemScreenFX.painbeatTime = WoundSystemScreenFX.painbeatTime + (RealFrameTime() * 7 * WoundSystemScreenFX.painSmooth * 0.01)

        local pulsedPain = math.max(0, WoundSystemScreenFX.painSmooth + math.sin(WoundSystemScreenFX.painbeatTime) * (WoundSystemScreenFX.painSmooth * 0.15))
        WoundSystemScreenFX.painPulseVisual = math.Clamp(pulsedPain / 100, 0, 1)
        WoundSystemScreenFX.painDistortionVisual = math.Clamp((WoundSystemScreenFX.painSmooth - 50) * 0.0025, 0, 1)
    else
        WoundSystemScreenFX.painPulseVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.painPulseVisual, 0, 1.0, 1.0)
        WoundSystemScreenFX.painDistortionVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.painDistortionVisual, 0, 1.0, 1.0)
        WoundSystemScreenFX.painSmooth = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.painSmooth, 0, 1.4, 1.4)
    end
    
    return WoundSystemScreenFX.painPulseVisual * strength, WoundSystemScreenFX.painDistortionVisual * strength
end

function WoundSystemScreenFX.UpdateLowOxygenVisual()
    if FrameNumber then
        local frameNumber = FrameNumber()
        if frameNumber == WoundSystemScreenFX.lastLowOxygenFrame then
            return WoundSystemScreenFX.lowOxygenVisual
        end
        WoundSystemScreenFX.lastLowOxygenFrame = frameNumber
    end

    local ply = LocalPlayer()
    local target = 0

    if IsValid(ply) and ply:Alive() then
        local oxygen = math.Clamp(CardioState.bloodOxygen or 100, 0, 100)
        target = math.Clamp((80 - oxygen) / 40, 0, 1)
        target = target * target * (3 - 2 * target)
    end

    WoundSystemScreenFX.lowOxygenVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.lowOxygenVisual, target, 1.4, 0.9)
    return WoundSystemScreenFX.lowOxygenVisual
end

function WoundSystemScreenFX.UpdateBloodLossVisual()
    if FrameNumber then
        local frameNumber = FrameNumber()
        if frameNumber == WoundSystemScreenFX.lastBloodLossFrame then
            return WoundSystemScreenFX.bloodLossVisual
        end
        WoundSystemScreenFX.lastBloodLossFrame = frameNumber
    end

    local ply = LocalPlayer()
    local target = 0

    if IsValid(ply) and ply:Alive() then
        local bloodVolume = math.Clamp(CardioState.bloodVolume or 100, -100, 100)
        target = math.Clamp((70 - bloodVolume) / 35, 0, 1)
        target = target * target * (3 - 2 * target)
    end

    WoundSystemScreenFX.bloodLossVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.bloodLossVisual, target, 1.1, 0.8)
    return WoundSystemScreenFX.bloodLossVisual
end

function WoundSystemScreenFX.UpdateConsciousnessBlurVisual()
    if FrameNumber then
        local frameNumber = FrameNumber()
        if frameNumber == WoundSystemScreenFX.lastConsciousnessBlurFrame then
            return WoundSystemScreenFX.consciousnessBlurVisual
        end
        WoundSystemScreenFX.lastConsciousnessBlurFrame = frameNumber
    end

    local ply = LocalPlayer()
    local target = 0

    if IsValid(ply) and ply:Alive() then
        local consciousness = math.Clamp(CardioState.consciousness or 100, 0, 100)
        target = math.Clamp((70 - consciousness) / 70, 0, 1)
        target = target * target * (3 - 2 * target)
    end

    WoundSystemScreenFX.consciousnessBlurVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.consciousnessBlurVisual, target, 1.6, 1.0)
    return WoundSystemScreenFX.consciousnessBlurVisual
end

function WoundSystemScreenFX.UpdateDrugVisuals()
    if FrameNumber then
        local frameNumber = FrameNumber()
        if frameNumber == WoundSystemScreenFX.lastDrugVisualFrame then
            return WoundSystemScreenFX.opiateVisual, WoundSystemScreenFX.withdrawalVisual
        end
        WoundSystemScreenFX.lastDrugVisualFrame = frameNumber
    end

    local ply = LocalPlayer()
    local opiateTarget = 0
    local withdrawalTarget = 0

    if IsValid(ply) and ply:Alive() then
        local actual = tonumber(CardioState.actualOpiateReception or CardioState.opiateReception or 0) or 0
        opiateTarget = math.Clamp(actual * 0.015, 0, 1)

        if actual < 0 then
            withdrawalTarget = -actual * 0.05
            if actual < -30 then
                withdrawalTarget = withdrawalTarget + -(actual + 30)
            end
            withdrawalTarget = math.Clamp(withdrawalTarget, 0, 1)
        end
    end

    WoundSystemScreenFX.opiateVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.opiateVisual, opiateTarget, 1.25, 0.75)
    WoundSystemScreenFX.withdrawalVisual = WoundSystemScreenFX.Smooth(WoundSystemScreenFX.withdrawalVisual, withdrawalTarget, 1.6, 0.9)
    return WoundSystemScreenFX.opiateVisual, WoundSystemScreenFX.withdrawalVisual
end

function WoundSystemScreenFX.HasMercShaders()
    return render
        and (
            render.DrawMercChromaticAberration
            or render.DrawMercRadialBlur
            or render.DrawMercBlur
            or render.DrawMercVignette
            or render.DrawMercFilmGrain
            or render.DrawMercFisheye
        )
end

function WoundSystemScreenFX.TryMercShader(fn, ...)
    if type(fn) ~= "function" then return false end

    local ok, err = pcall(fn, ...)
    if not ok then
        WoundSystemScreenFX.nextMercShaderWarn = WoundSystemScreenFX.nextMercShaderWarn or 0
        if CurTime() >= WoundSystemScreenFX.nextMercShaderWarn then
            WoundSystemScreenFX.nextMercShaderWarn = CurTime() + 5
            MsgC(Color(255, 170, 80), "[WoundSystem] Simple Custom Shaders call failed: " .. tostring(err) .. "\n")
        end
        return false
    end

    return true
end

function WoundSystemScreenFX.DrawMercCameraEffects(painPulse, painDistortion, lowOxygen, bloodLoss, focusPain, consciousnessBlur, opiateVisual, withdrawalVisual)
    if not WoundSystemScreenFX.HasMercShaders() then return false end
    opiateVisual = opiateVisual or 0
    withdrawalVisual = withdrawalVisual or 0
    local drew = false
    local drewWarp = false

    local tunnel = math.Clamp(math.max(lowOxygen * 0.75, bloodLoss, consciousnessBlur * 0.55, painDistortion * 0.45, opiateVisual * 0.34), 0, 1)
    if tunnel > 0.00005 then
        drew = WoundSystemScreenFX.TryMercShader(render.DrawMercVignette, 1 - (tunnel * 0.42), 0.045 + (tunnel * 0.10)) or drew
    end

    local blur = math.Clamp((lowOxygen * 0.11) + (bloodLoss * 0.075) + (consciousnessBlur * 0.14) + (opiateVisual * 0.09), 0, 0.30)
    if blur > 0.00005 then
        drew = WoundSystemScreenFX.TryMercShader(render.DrawMercBlur, blur) or drew
    end

    local radial = math.Clamp((bloodLoss * 0.085) + (lowOxygen * 0.065) + (consciousnessBlur * 0.050) + (painDistortion * 0.030) + (opiateVisual * 0.035), 0, 0.22)
    if radial > 0.00005 then
        local ok = WoundSystemScreenFX.TryMercShader(render.DrawMercRadialBlur, 0.5, 0.5, radial)
        drew = ok or drew
        drewWarp = ok or drewWarp
    end

    local fisheye = math.Clamp((consciousnessBlur * 0.20) + (lowOxygen * 0.13) + (opiateVisual * 0.11), 0, 0.34)
    if fisheye > 0.00005 then
        local ok = WoundSystemScreenFX.TryMercShader(render.DrawMercFisheye, fisheye)
        drew = ok or drew
        drewWarp = ok or drewWarp
    end

    local aberration = math.Clamp(((focusPain * 0.08) + (painDistortion * 0.42) + (lowOxygen * 0.08) + (withdrawalVisual * 0.26)) * 2, 0, 1)
    if aberration > 0.00005 then
        local ok = WoundSystemScreenFX.TryMercShader(render.DrawMercChromaticAberration, aberration, true)
        drew = ok or drew
        drewWarp = ok or drewWarp
    end

    local grain = math.Clamp((painPulse * 0.035) + (lowOxygen * 0.070) + (bloodLoss * 0.055) + (withdrawalVisual * 0.105), 0, 0.22)
    if grain > 0.00005 then
        local varianceTarget = Lerp(math.Clamp(grain / 0.22, 0, 1), 0, 0.75)
        WoundSystemScreenFX._MercFilmGrainVariance = WoundSystemScreenFX.Smooth(WoundSystemScreenFX._MercFilmGrainVariance or varianceTarget, varianceTarget, 8.0, 3.0)
        drew = WoundSystemScreenFX.TryMercShader(render.DrawMercFilmGrain, 2, 10, grain, 0, WoundSystemScreenFX._MercFilmGrainVariance) or drew
    end

    WoundSystemScreenFX.mercDrewLastFrame = drew
    return drewWarp
end

-- ==========================================
-- 1. POST-PROCESSING HOOK
-- ==========================================
hook.Add("RenderScreenspaceEffects", "WoundSystem_StaminaEffects", function()
    if not WoundSystemClientEnabled() then return end
    if LowEndMode() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    local stamina = CardioState.stamina or 100
    if stamina <= 50 then
        local factor = math.Clamp((50 - stamina) / 25, 0, 1) -- 0 at 50 stamina, 1 at 25 stamina
        if factor > 0 then
            local contrast = Lerp(factor, 0.5, 3.0)
            local distance = Lerp(factor, 0.2, 1.5)
            DrawSharpen(contrast, distance)
        end
    end
end)

hook.Add("RenderScreenspaceEffects", "WoundSystem_PostProcess", function()
    if not WoundSystemClientEnabled() then return end
    if LowEndMode() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then
        if WoundSystemScreenFX.ResetVisualState then
            WoundSystemScreenFX.ResetVisualState()
        end
        return
    end

    local painPulse, painDistortion = WoundSystemScreenFX.UpdatePainVisuals()
    local lowOxygen = WoundSystemScreenFX.UpdateLowOxygenVisual()
    local bloodLoss = WoundSystemScreenFX.UpdateBloodLossVisual()
    local consciousnessBlur = WoundSystemScreenFX.UpdateConsciousnessBlurVisual()
    local opiateVisual, withdrawalVisual = WoundSystemScreenFX.UpdateDrugVisuals()
    local depressionVisual, dirtyVisual = WoundSystemScreenFX.UpdateConditionOverlayVisuals()
    painPulse, painDistortion, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual = WoundSystemScreenFX.UpdateDrawChannels(painPulse, painDistortion, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual)

    local aberrationIntensity, aberrationDistort, aberrationFlip = 0, 0, 0
    if WoundSystemScreenFX.UpdateAberrationShaderVisuals then
        aberrationIntensity, aberrationDistort, aberrationFlip = WoundSystemScreenFX.UpdateAberrationShaderVisuals(painDistortion, lowOxygen)
    end

    local cameraEffectsActive = WoundSystemScreenFX.HasPlayerCameraEffects and WoundSystemScreenFX.HasPlayerCameraEffects(0.00005)
    local debugMode = WoundSystemScreenFX.GetScreenPassDebugMode and WoundSystemScreenFX.GetScreenPassDebugMode() or 0
    local conditionShaderActive = (depressionVisual or 0) > 0.00005 or (dirtyVisual or 0) > 0.00005
    local aberrationShaderActive = (aberrationIntensity or 0) > 0.00005 or math.abs(aberrationDistort or 0) > 0.00005 or (aberrationFlip or 0) > 0.00005
    local painChannelsActive = painPulse > 0.00005 or painDistortion > 0.00005 or lowOxygen > 0.00005 or bloodLoss > 0.00005 or consciousnessBlur > 0.00005 or opiateVisual > 0.00005 or withdrawalVisual > 0.00005
    local screenPassDebugActive = debugMode > 0
    if not painChannelsActive and not cameraEffectsActive and not conditionShaderActive and not aberrationShaderActive then return end
    local focusPain = math.Clamp((WoundSystemScreenFX.painSmooth - 30) / 70, 0, 1)

    local conditionDrew = false
    if WoundSystemScreenFX.DrawConditionCompositeShader then
        conditionDrew = WoundSystemScreenFX.DrawConditionCompositeShader(depressionVisual, dirtyVisual) or false
    end

    local aberrationDrew = false
    if WoundSystemScreenFX.DrawAberrationCompositeShader then
        aberrationDrew = WoundSystemScreenFX.DrawAberrationCompositeShader(aberrationIntensity, aberrationDistort, aberrationFlip) or false
    end

    local painDrew = false
    if WoundSystemScreenFX.DrawPainCompositeShader then
        painDrew = WoundSystemScreenFX.DrawPainCompositeShader(painPulse, painDistortion, focusPain, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual, depressionVisual, dirtyVisual) or false
    end

    if screenPassDebugActive and (conditionDrew or aberrationDrew or painDrew) then
        return
    end

    if painDrew or ((conditionDrew or aberrationDrew) and not painChannelsActive) then
        return
    end

    if WoundSystemScreenFX.DrawVanillaCameraEffects then
        WoundSystemScreenFX.DrawVanillaCameraEffects(painPulse, painDistortion, lowOxygen, bloodLoss, focusPain, consciousnessBlur, opiateVisual, withdrawalVisual)
    end

    local mercDrewWarp = WoundSystemScreenFX.DrawMercCameraEffects(painPulse, painDistortion, lowOxygen, bloodLoss, focusPain, consciousnessBlur, opiateVisual, withdrawalVisual)
    if mercDrewWarp then return end

    if painDistortion > 0.00005 or opiateVisual > 0.00005 or withdrawalVisual > 0.00005 then
        local pulse = math.sin(WoundSystemScreenFX.painbeatTime)
        local offset = (0.002 + (0.011 * painDistortion) + (0.004 * opiateVisual) + (0.008 * withdrawalVisual)) * (1 + pulse * 0.25)
        DrawToyTown(offset, ScrH() * 0.5)
    end
end)

-- ==========================================
-- 2. BACKGROUND HUD PAINT HOOK
-- ==========================================
hook.Add("HUDPaintBackground", "WoundSystem_VignetteVisuals", function()
    if not WoundSystemClientEnabled() then return end
    if WoundSystem.HealthGUI.IsSpawnVisualGraceActive and WoundSystem.HealthGUI.IsSpawnVisualGraceActive() then return end

    -- We already updated pain visuals in the Render hook, 
    -- but we call it here to ensure the value is up to date for this frame.
    local painPulse, painDistortion = WoundSystemScreenFX.UpdatePainVisuals()
    local lowOxygen = WoundSystemScreenFX.UpdateLowOxygenVisual()
    local bloodLoss = WoundSystemScreenFX.UpdateBloodLossVisual()
    local consciousnessBlur = WoundSystemScreenFX.UpdateConsciousnessBlurVisual()
    local opiateVisual, withdrawalVisual = WoundSystemScreenFX.UpdateDrugVisuals()
    local staticSeverity
    painPulse, painDistortion, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual, staticSeverity = WoundSystemScreenFX.UpdateDrawChannels(painPulse, painDistortion, lowOxygen, bloodLoss, consciousnessBlur, opiateVisual, withdrawalVisual)
    if painPulse <= 0.00005 and painDistortion <= 0.00005 and staticSeverity <= 0.00005 and lowOxygen <= 0.00005 and bloodLoss <= 0.00005 and consciousnessBlur <= 0.00005 and opiateVisual <= 0.00005 and withdrawalVisual <= 0.00005 then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local w, h = ScrW(), ScrH()
    local curTime = CurTime()
    local pad = 60
    local painShaderActive = WoundSystemScreenFX.PainCompositeShaderDrewThisFrame and WoundSystemScreenFX.PainCompositeShaderDrewThisFrame()

    -- Parallax Sway Logic
    local currentAng = ply:EyeAngles()
    local dAng = currentAng - WoundSystemScreenFX.lastViewAng
    dAng:Normalize()
    WoundSystemScreenFX.lastViewAng = currentAng

    local swaySeverity = math.max(math.Clamp((WoundSystemScreenFX.painSmooth - 30) / 70, 0, 1), painDistortion)
    local targetSwayX = math.Clamp(dAng.y * 15, -40 * swaySeverity, 40 * swaySeverity)
    local targetSwayY = math.Clamp(-dAng.p * 15, -40 * swaySeverity, 40 * swaySeverity)

    WoundSystemScreenFX.swayX = Lerp(math.Clamp(FrameTime() * 5, 0, 1), WoundSystemScreenFX.swayX, targetSwayX)
    WoundSystemScreenFX.swayY = Lerp(math.Clamp(FrameTime() * 5, 0, 1), WoundSystemScreenFX.swayY, targetSwayY)

    if not painShaderActive then
        surface.SetDrawColor(140, 10, 10, 165 * painPulse)
        local pulseSpeed = Lerp(painPulse, 2, 8)
        local throb = math.sin(curTime * pulseSpeed)
        local currentScale = Lerp(painPulse, 0.14, 0.38) * (1 + (throb * 0.1))

        local gradSizeH = h * currentScale
        local gradSizeW = w * currentScale

        surface.SetMaterial(WoundSystemScreenFX.matGradUp)
        surface.DrawTexturedRect(-pad, -pad, w + (pad * 2), gradSizeH + pad - WoundSystemScreenFX.swayY)
        surface.SetMaterial(WoundSystemScreenFX.matGradDown)
        surface.DrawTexturedRect(-pad, h - gradSizeH - WoundSystemScreenFX.swayY, w + (pad * 2), gradSizeH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradLeft)
        surface.DrawTexturedRect(-pad, -pad, gradSizeW + pad - WoundSystemScreenFX.swayX, h + (pad * 2))
        surface.SetMaterial(WoundSystemScreenFX.matGradRight)
        surface.DrawTexturedRect(w - gradSizeW - WoundSystemScreenFX.swayX, -pad, gradSizeW + pad, h + (pad * 2))
    end

    if lowOxygen > 0.00005 then
        surface.SetDrawColor(24, 34, 58, 145 * lowOxygen)
        local oxyScale = Lerp(lowOxygen, 0.18, 0.48)
        local oxyH = h * oxyScale
        local oxyW = w * oxyScale

        surface.SetMaterial(WoundSystemScreenFX.matGradUp)
        surface.DrawTexturedRect(-pad, -pad, w + (pad * 2), oxyH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradDown)
        surface.DrawTexturedRect(-pad, h - oxyH, w + (pad * 2), oxyH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradLeft)
        surface.DrawTexturedRect(-pad, -pad, oxyW + pad, h + (pad * 2))
        surface.SetMaterial(WoundSystemScreenFX.matGradRight)
        surface.DrawTexturedRect(w - oxyW, -pad, oxyW + pad, h + (pad * 2))
    end

    if bloodLoss > 0.00005 then
        surface.SetDrawColor(28, 0, 0, 175 * bloodLoss)
        local bloodScale = Lerp(bloodLoss, 0.12, 0.52)
        local bloodH = h * bloodScale
        local bloodW = w * bloodScale

        surface.SetMaterial(WoundSystemScreenFX.matGradUp)
        surface.DrawTexturedRect(-pad, -pad, w + (pad * 2), bloodH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradDown)
        surface.DrawTexturedRect(-pad, h - bloodH, w + (pad * 2), bloodH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradLeft)
        surface.DrawTexturedRect(-pad, -pad, bloodW + pad, h + (pad * 2))
        surface.SetMaterial(WoundSystemScreenFX.matGradRight)
        surface.DrawTexturedRect(w - bloodW, -pad, bloodW + pad, h + (pad * 2))
    end

    if opiateVisual > 0.00005 then
        surface.SetDrawColor(18, 34, 46, 115 * opiateVisual)
        local drugScale = Lerp(opiateVisual, 0.16, 0.44)
        local drugH = h * drugScale
        local drugW = w * drugScale

        surface.SetMaterial(WoundSystemScreenFX.matGradUp)
        surface.DrawTexturedRect(-pad, -pad, w + (pad * 2), drugH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradDown)
        surface.DrawTexturedRect(-pad, h - drugH, w + (pad * 2), drugH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradLeft)
        surface.DrawTexturedRect(-pad, -pad, drugW + pad, h + (pad * 2))
        surface.SetMaterial(WoundSystemScreenFX.matGradRight)
        surface.DrawTexturedRect(w - drugW, -pad, drugW + pad, h + (pad * 2))
    end

    if withdrawalVisual > 0.00005 then
        local flicker = 0.82 + (math.sin(curTime * 19) * 0.18)
        surface.SetDrawColor(125, 18, 12, 82 * withdrawalVisual * flicker)
        local withdrawalScale = Lerp(withdrawalVisual, 0.10, 0.36)
        local withdrawalH = h * withdrawalScale
        local withdrawalW = w * withdrawalScale

        surface.SetMaterial(WoundSystemScreenFX.matGradUp)
        surface.DrawTexturedRect(-pad, -pad, w + (pad * 2), withdrawalH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradDown)
        surface.DrawTexturedRect(-pad, h - withdrawalH, w + (pad * 2), withdrawalH + pad)
        surface.SetMaterial(WoundSystemScreenFX.matGradLeft)
        surface.DrawTexturedRect(-pad, -pad, withdrawalW + pad, h + (pad * 2))
        surface.SetMaterial(WoundSystemScreenFX.matGradRight)
        surface.DrawTexturedRect(w - withdrawalW, -pad, withdrawalW + pad, h + (pad * 2))
    end

    if LowEndMode() then return end

    if staticSeverity <= 0.00005 or painShaderActive then return end

    local centerH, centerV = w / 2, h / 2
    local maxRadius = math.sqrt(centerH^2 + centerV^2)
    local gridStep = 10

    for x = -pad, w + pad, gridStep do
        local refreshInterval = 0.015
        local jitter = math.random() * 0.004

        if not WoundSystemScreenFX.testVignetteCache[x] or (curTime - (WoundSystemScreenFX.testVignetteCache[x].lastUpdate or 0) >= (refreshInterval + jitter)) then
            local yOffset = math.random(-gridStep / 2, gridStep / 2)
            WoundSystemScreenFX.testVignetteCache[x] = { lastUpdate = curTime, yOffset = yOffset, blocks = {} }

            for y = -pad, h + pad, gridStep do
                local distToCenter = math.Distance(x, y + yOffset, centerH, centerV)
                local spawnChance = ((distToCenter / maxRadius) ^ Lerp(staticSeverity, 4.2, 2.5)) * staticSeverity * 1.15

                if math.random() < spawnChance then
                    WoundSystemScreenFX.testVignetteCache[x].blocks[y] = {
                        size = math.floor(Lerp(staticSeverity, 6, Lerp(distToCenter / maxRadius, 10, 20)))
                    }
                end
            end
        end

        for y, blockData in pairs(WoundSystemScreenFX.testVignetteCache[x].blocks) do
            surface.SetDrawColor(math.random(200, 255), 0, 0, 215 * staticSeverity)
            surface.DrawRect(x + WoundSystemScreenFX.swayX, y + WoundSystemScreenFX.testVignetteCache[x].yOffset + WoundSystemScreenFX.swayY, blockData.size, blockData.size)
        end
    end

end, HOOK_HIGH)

