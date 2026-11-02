-- GLASS SHARD MINIGAME - RU: осколки стекла с пинцетом, боль растёт при неудачах до обморока
-- Fixed: correct PNG, working hover/click, light-bump shards everywhere via woundbridge

if WoundSystemGlassMinigame and WoundSystemGlassMinigame._Loaded then
    if IsValid(WoundSystemGlassMinigame.overlay) then
        WoundSystemGlassMinigame.overlay:Remove()
    end
    hook.Remove("OnScreenSizeChanged", "WoundSystem_GlassResize")
    hook.Remove("Think", "WoundSystem_GlassInput")
    hook.Remove("ShutDown", "WoundSystem_GlassCleanup")
end

if not (WoundSystem and WoundSystem.MinigameClip) and file.Exists("woundsystem/client/minigames/cl_clip.lua", "LUA") then
    include("woundsystem/client/minigames/cl_clip.lua")
    include("woundsystem/client/minigames/sh_handphysics.lua")
end

local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")
local DevMinigameCfg = include("woundsystem/client/minigames/minigame_dev_config.lua") or {}

WoundSystemGlassMinigame = WoundSystemGlassMinigame or {}
local MG = WoundSystemGlassMinigame
MG._Loaded = true

-- CORRECT PNG per RU: use shrapnelminigame assets (exist in workshop), not dislocation
local path = "casunknown-images/shrapnelminigame/"
local shrapnelPath = path
local matBackground = Material(path .. "minigameShrapnel.png")
local matShard = Material(path .. "shrapnelpiece.png")
if matShard:IsError() then matShard = Material(path .. "shrapnelpiece_red.png") end
-- hand / tweezers mats (exist in shrapnel pack)
local matHandIdle = Material(path .. "handGraspIdle1.png")
local matHandClick = Material(path .. "handGraspClick.png")
local matTweezersIdle = Material(path .. "handTweezersIdle.png")
local matTweezersClick = Material(path .. "handTweezersClick.png")
if matTweezersIdle:IsError() then matTweezersIdle = matHandIdle end
if matTweezersClick:IsError() then matTweezersClick = matHandClick end

-- fallback if background missing (should not, but keep)
if matBackground:IsError() then
    matBackground = Material("casunknown-images/dislocationminigame/dislocationBoneBase.png")
end
if matShard:IsError() then
    -- ultimate fallback: reuse dislocation bone move (visible, not water)
    matShard = Material("casunknown-images/dislocationminigame/dislocationBoneMove.png")
end

-- config similar to dislocation but tuned for glass shard
local DEFAULT_CONFIG = {
    Scale = 0.95,
    CenterOffsetX = 0,
    CenterOffsetY = 0,
    HandScale = 1.0,
    PainShakeX = 120,
    PainShakeY = 40,
}

local function GetCfg()
    local cfg = DevMinigameCfg.glass or DevMinigameCfg.dislocation or {}
    local out = table.Copy(DEFAULT_CONFIG)
    for k,v in pairs(cfg) do out[k]=v end
    return out
end

-- state
MG.active = MG.active or false
MG.sessionId = MG.sessionId or 0
MG.limbId = MG.limbId or nil
MG.overlay = MG.overlay or nil
MG.handScreenX = MG.handScreenX or ScrW()*0.5
MG.handScreenY = MG.handScreenY or ScrH()*0.5
MG.handScreenVelX = MG.handScreenVelX or 0
MG.handScreenVelY = MG.handScreenVelY or 0
MG._hp_acc = MG._hp_acc or 0
MG.openTime = MG.openTime or 0
MG.failCount = MG.failCount or 0

local activeLimb = nil
local failCount = 0
local holding = false
local shardX, shardY = 0,0
local shardGrabbed = false
local finishPulse = 0
local boardCenterX, boardCenterY = ScrW()*0.5, ScrH()*0.5
local finishOffX, finishOffY = 340, -220  -- relative to board center (top-right)
local trayW, trayH = 96, 72

local function AddLocalPain(amount)
    net.Start("WoundSystem_GlassPain")
        net.WriteFloat(amount)
        net.WriteString(activeLimb or "hand_R")
    net.SendToServer()
end

local function ResetShardPos()
    local r = 78
    shardX = math.Rand(-r, r)
    shardY = math.Rand(-r, r)
    shardGrabbed = false
end

local function GetTrayPos()
    return boardCenterX + finishOffX, boardCenterY + finishOffY
end

local function GetShardScreenPos()
    return boardCenterX + shardX, boardCenterY + shardY
end

local function DestroyOverlay()
    if IsValid(MG.overlay) then MG.overlay:Remove() end
    MG.overlay = nil
end

function CloseGlass()
    DestroyOverlay()
    activeLimb = nil
    holding = false
    shardGrabbed = false
    MG.active = false
    MG.overlay = nil
    hook.Remove("Think", "WoundSystem_GlassInput")
    hook.Remove("OnScreenSizeChanged", "WoundSystem_GlassResize")
    gui.EnableScreenClicker(false)
end

local function CreateOverlay()
    DestroyOverlay()
    boardCenterX, boardCenterY = ScrW()*0.5, ScrH()*0.5
    local pnl = vgui.Create("DPanel")
    pnl:SetSize(ScrW(), ScrH())
    pnl:SetPos(0,0)
    pnl:SetMouseInputEnabled(true)
    pnl:SetKeyboardInputEnabled(false)
    pnl:MakePopup()
    pnl:SetPopupStayAtBack(false)
    pnl.Paint = function(self,w,h)
        local cfg = GetCfg()
        local cx, cy = w/2 + (cfg.CenterOffsetX or 0), h/2 + (cfg.CenterOffsetY or 0)
        boardCenterX, boardCenterY = cx, cy
        local trayX, trayY = GetTrayPos()

        -- dark backdrop
        surface.SetDrawColor(0,0,0,160)
        surface.DrawRect(0,0,w,h)

        -- pain vignette
        if failCount>0 then
            local a = math.Clamp(failCount*18,0,110)
            surface.SetDrawColor(120, 20, 20, a)
            surface.DrawRect(0,0,w,h)
        end

        -- board background (minigameShrapnel.png scaled)
        if not matBackground:IsError() then
            local bw, bh = 820*cfg.Scale, 520*cfg.Scale
            surface.SetMaterial(matBackground)
            surface.SetDrawColor(255,255,255,220)
            surface.DrawTexturedRect(cx - bw*0.5, cy - bh*0.5 + 30*cfg.Scale, bw, bh)
        else
            surface.SetDrawColor(40,40,40,180)
            surface.DrawRect(cx-420*cfg.Scale, cy-260*cfg.Scale, 840*cfg.Scale, 520*cfg.Scale)
        end

        -- shard
        local sx, sy = GetShardScreenPos()
        -- if grabbed, shard follows hand
        if shardGrabbed and holding then
            -- lerp shard to hand
            local lerp = 0.14
            shardX = Lerp(lerp, shardX, (MG.handScreenX - cx))
            shardY = Lerp(lerp, shardY, (MG.handScreenY - cy))
            sx, sy = GetShardScreenPos()
        end

        -- tray
        local pulse = CurTime() - finishPulse < 0.35
        if shardGrabbed then
            surface.SetDrawColor(pulse and 120 or 100, pulse and 255 or 100, pulse and 120 or 100, pulse and 150 or 90)
            surface.DrawRect(trayX- trayW*0.5, trayY - trayH*0.5, trayW, trayH)
            surface.SetDrawColor(200,200,200,180)
            surface.DrawOutlinedRect(trayX- trayW*0.5, trayY - trayH*0.5, trayW, trayH)
            if pulse then
                surface.SetDrawColor(120,255,120,90)
                surface.DrawRect(trayX- trayW*0.5, trayY - trayH*0.5, trayW, trayH)
            end
            draw.SimpleText("DROP HERE", "DefaultSmall", trayX, trayY+ trayH*0.5+10, Color(180,255,180,200), TEXT_ALIGN_CENTER)
        end

        -- shard sprite
        surface.SetMaterial(matShard)
        if shardGrabbed then
            surface.SetDrawColor(200,255,200,255)
        else
            surface.SetDrawColor(185,225,255,250)
        end
        local sw, sh = 54*cfg.Scale, 112*cfg.Scale
        -- draw shard with slight rotation when grabbed
        local ang = shardGrabbed and (CurTime()*70 % 360) or 18
        surface.DrawTexturedRectRotated(sx, sy, sw, sh, ang)

        -- hand / tweezers
        do
            local handMat = holding and matTweezersClick or matTweezersIdle
            if handMat:IsError() then handMat = holding and matHandClick or matHandIdle end
            surface.SetMaterial(handMat)
            -- pain shake on hand
            local shakeX = math.sin(CurTime()*17) * math.min(failCount*2.4, 16)
            local shakeY = math.cos(CurTime()*13) * math.min(failCount*1.3, 9)
            local hx = MG.handScreenX + shakeX
            local hy = MG.handScreenY + shakeY
            local hw, hh = 420*cfg.Scale*0.34*cfg.HandScale, 820*cfg.Scale*0.34*cfg.HandScale
            -- rotate slightly with velocity
            local angHand = (MG.handScreenVelX or 0)*0.18
            surface.SetDrawColor(255,255,255,255)
            surface.DrawTexturedRectRotated(hx, hy, hw, hh, angHand)
        end

        -- instructions
        draw.SimpleText("GLASS SHARD EXTRACTION - " .. (activeLimb or "?"), "DermaLarge", cx, 64, Color(255,255,255,255), TEXT_ALIGN_CENTER)
        draw.SimpleText(shardGrabbed and "Drag shard to tray (top-right) and release!" or "Click and hold to grab glass shard with tweezers", "Default", cx, 96, Color(210,230,255,255), TEXT_ALIGN_CENTER)
        if failCount>0 then
            draw.SimpleText("Mistakes: "..failCount.." - further errors cause fainting", "Default", cx, h-48, Color(255,120,120,255), TEXT_ALIGN_CENTER)
        end
        draw.SimpleText("ESC to close", "Default", w-84, 16, Color(200,200,200,200), TEXT_ALIGN_CENTER)
    end

    pnl.OnMousePressed = function(self, code)
        if code == MOUSE_LEFT then
            holding = true
            local cfg = GetCfg()
            local cx, cy = self:GetWide()/2 + (cfg.CenterOffsetX or 0), self:GetTall()/2 + (cfg.CenterOffsetY or 0)
            local sx, sy = GetShardScreenPos()
            local mx, my = gui.MousePos()
            -- also consider hand pos for hit
            local hx, hy = MG.handScreenX, MG.handScreenY
            local distMouse = math.sqrt((mx - sx)^2 + (my - sy)^2)
            local distHand = math.sqrt((hx - sx)^2 + (hy - sy)^2)
            local dist = math.min(distMouse, distHand)
            local grabRadius = 62*cfg.Scale
            if not shardGrabbed then
                if dist < grabRadius then
                    shardGrabbed = true
                    surface.PlaySound("physics/flesh/flesh_impact_hard1.wav")
                else
                    -- miss close to shard => pain
                    if dist < 120*cfg.Scale then
                        failCount = failCount+1
                        AddLocalPain(math.Rand(6,11))
                        surface.PlaySound("physics/body/body_medium_impact_soft"..math.random(3,7)..".wav")
                        if failCount >= 6 then
                            net.Start("WoundSystem_GlassFaint")
                                net.WriteString(activeLimb or "hand_R")
                            net.SendToServer()
                        end
                    end
                end
            else
                -- already grabbed, check drop at tray
                local trayX, trayY = GetTrayPos()
                local distTrayMouse = math.sqrt((mx - trayX)^2 + (my - trayY)^2)
                local distTrayHand = math.sqrt((hx - trayX)^2 + (hy - trayY)^2)
                local distF = math.min(distTrayMouse, distTrayHand)
                if distF < math.max(trayW, trayH)*0.7 then
                    finishPulse = CurTime()
                    surface.PlaySound("physics/flesh/flesh_impact_hard6.wav")
                    net.Start("WoundSystem_GlassSuccess")
                        net.WriteString(activeLimb or "hand_R")
                    net.SendToServer()
                    CloseGlass()
                else
                    -- dropped wrong place
                    failCount = failCount+1
                    AddLocalPain(math.Rand(8,13))
                    shardGrabbed = false
                    ResetShardPos()
                    surface.PlaySound("physics/body/body_medium_impact_soft"..math.random(1,7)..".wav")
                end
            end
        elseif code == MOUSE_RIGHT and shardGrabbed then
            -- right click to release back
            shardGrabbed = false
            ResetShardPos()
        end
    end
    pnl.OnMouseReleased = function(self, code)
        if code == MOUSE_LEFT then
            holding = false
            -- if grabbed, keep grabbed until they click tray (don't drop on release)
        end
    end
    MG.overlay = pnl
end

function OpenGlass(limbId)
    activeLimb = limbId or "hand_R"
    failCount = 0
    MG.active = true
    MG.limbId = activeLimb
    MG.failCount = 0
    MG.openTime = CurTime()
    MG.handScreenX = ScrW()*0.5
    MG.handScreenY = ScrH()*0.5
    MG.handScreenVelX = 0
    MG.handScreenVelY = 0
    MG._hp_acc = 0
    ResetShardPos()
    CreateOverlay()
    gui.EnableScreenClicker(true)

    hook.Add("Think", "WoundSystem_GlassInput", function()
        if not IsValid(MG.overlay) then return end
        local dt = RealFrameTime()
        -- update hand via shared physics with pain shake
        if HandPhysics and HandPhysics.Step then
            local painFactor = math.Clamp(failCount*0.14, 0, 1)
            HandPhysics.Step(MG, dt, {
                pain = painFactor,
                str = 2,
                conc = 100,
                shakeX = 90,
                shakeY = 36,
                maxLength = 75,
                responsiveness = 7,
            })
        else
            local mx, my = gui.MousePos()
            MG.handScreenX = Lerp(0.18, MG.handScreenX, mx)
            MG.handScreenY = Lerp(0.18, MG.handScreenY, my)
        end
        if input.IsKeyDown(KEY_ESCAPE) and CurTime() - MG.openTime > 0.4 then
            CloseGlass()
        end
    end)
    hook.Add("OnScreenSizeChanged", "WoundSystem_GlassResize", function()
        if IsValid(MG.overlay) then
            MG.overlay:SetSize(ScrW(), ScrH())
        end
        boardCenterX, boardCenterY = ScrW()*0.5, ScrH()*0.5
    end)
end

-- Net receivers
net.Receive("WoundSystem_GlassStart", function()
    local limbId = net.ReadString()
    OpenGlass(limbId)
end)

-- console command for radial menu
concommand.Add("woundsys_glass_extract", function(ply, cmd, args)
    local limb = args[1] or activeLimb or "hand_R"
    net.Start("WoundSystem_GlassRequest")
        net.WriteString(limb)
    net.SendToServer()
end)

concommand.Add("hg_extract_glass", function(_,_,args)
    RunConsoleCommand("woundsys_glass_extract", args[1] or "hand_R")
end)
