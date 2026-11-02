-- GLASS SHARD MINIGAME - RU: осколки стекла с пинцетом, боль растёт при неудачах до обморока
-- Reuses dislocation hand physics + standard png per RU requirement

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

-- KEEP STANDARD PNG per RU: use same dislocation png + shrapnel png if present
local path = "casunknown-images/dislocationminigame/"
local shrapnelPath = "casunknown-images/"
local matBoneBase = Material(path .. "dislocationBoneBase.png")
local matBoneGhost = Material(path .. "dislocationBoneGhost.png")
local matBoneMove = Material(path .. "dislocationBoneMove.png")
local matHandIdle = Material(path .. "handgraspidle1.png")
local matHandClick = Material(path .. "handgraspclick.png")
-- fallback for shard visual: use small shrapnel icon if exists, else reuse bone
local matShard = Material(shrapnelPath .. "minigameshrapnel.png")
if matShard:IsError() then matShard = matBoneMove end

-- same config as dislocation for feel
local DEFAULT_CONFIG = {
    Scale = 0.95,
    CenterOffsetX = 0,
    CenterOffsetY = 0,
    BoneBaseWidth = 552,
    BoneBaseHeight = 324,
    BoneBaseOffsetX = -900,
    BoneBaseOffsetY = 0,
    BoneBaseRotation = 0,
    BoneBaseAlpha = 235,
    BoneGhostWidth = 1220,
    BoneGhostHeight = 356,
    BoneGhostOffsetX = -25,
    BoneGhostOffsetY = 0,
    BoneGhostRotation = 0,
    BoneGhostAlpha = 95,
    BoneMoveWidth = 1292,
    BoneMoveHeight = 480,
    BoneMoveOffsetX = 0,
    BoneMoveOffsetY = 0,
    BoneMoveRotation = 0,
    BoneMoveAlpha = 255,
    BoneHitboxWidthFactor = 2.4,
    BoneHitboxHeightFactor = 0.5,
    HandWidth = 512,
    HandHeight = 1260,
    HandScale = 3,
    HandOffsetX = 300,
    HandOffsetY = 1200,
    HandHitOffsetX = 0,
    HandHitOffsetY = 0,
    HandPivotX = 0.4,
    HandPivotY = 0.1,
    HandRotation = 0,
    HandAlpha = 210,
    PainShakeX = 120,
    PainShakeY = 40,
    HandMaxLength = 75,
    BoneVisualFollowSpeed = 16,
    HitPulseTime = 0.16
}

local FINISH_X = 421.82
local FINISH_Y = 229.82

local function GetCfg()
    local cfg = DevMinigameCfg.glass or DevMinigameCfg.dislocation or {}
    local out = table.Copy(DEFAULT_CONFIG)
    for k,v in pairs(cfg) do out[k]=v end
    return out
end

local activeLimb = nil
local sim = nil -- HandPhysics instance
local startTime = 0
local failCount = 0
local totalTime = 0
local holding = false
local shardX, shardY = 0,0
local shardGrabbed = false
local finishPulse = 0

-- Pain escalation only during minigame on failures per RU
local function AddLocalPain(amount)
    -- send to server to increment actual limb pain
    net.Start("WoundSystem_GlassPain")
        net.WriteFloat(amount)
        net.WriteString(activeLimb or "hand_R")
    net.SendToServer()
    -- local pain shake intensifies
    local shake = math.min(0.6, 0.08 + failCount * 0.07)
    if WoundSystem and WoundSystem.MinigameClip then
        -- handled via painShake in draw
    end
end

local function ResetShardPos()
    -- place shard near bone center with small random offset like bone fragment
    local r = 48
    shardX = math.Rand(-r, r)
    shardY = math.Rand(-r, r)
    shardGrabbed = false
end

local function CreateOverlay()
    if IsValid(MG.overlay) then MG.overlay:Remove() end
    local pnl = vgui.Create("DPanel")
    pnl:SetSize(ScrW(), ScrH())
    pnl:SetPos(0,0)
    pnl:SetMouseInputEnabled(true)
    pnl:SetKeyboardInputEnabled(false)
    pnl:MakePopup()
    pnl:SetPopupStayAtBack(false)
    pnl.Paint = function(self,w,h)
        local cfg = GetCfg()
        local cx, cy = w/2 + cfg.CenterOffsetX, h/2 + cfg.CenterOffsetY

        -- dark backdrop
        surface.SetDrawColor(0,0,0,160)
        surface.DrawRect(0,0,w,h)

        -- pain vignette grows with failCount
        if failCount>0 then
            local a = math.Clamp(failCount*18,0,110)
            surface.SetDrawColor(120, 20, 20, a)
            surface.DrawRect(0,0,w,h)
        end

        -- clip for minigame area
        local clipW, clipH = 900*cfg.Scale, 480*cfg.Scale
        local clipX, clipY = cx - clipW/2, cy - clipH/2
        -- bone base
        surface.SetMaterial(matBoneBase)
        surface.SetDrawColor(255,255,255,cfg.BoneBaseAlpha)
        surface.DrawTexturedRectRotated(cx+cfg.BoneBaseOffsetX*cfg.Scale, cy+cfg.BoneBaseOffsetY*cfg.Scale, cfg.BoneBaseWidth*cfg.Scale, cfg.BoneBaseHeight*cfg.Scale, cfg.BoneBaseRotation)

        -- ghost target
        surface.SetMaterial(matBoneGhost)
        surface.SetDrawColor(255,255,255,cfg.BoneGhostAlpha)
        surface.DrawTexturedRectRotated(cx+cfg.BoneGhostOffsetX*cfg.Scale, cy+cfg.BoneGhostOffsetY*cfg.Scale, cfg.BoneGhostWidth*cfg.Scale, cfg.BoneGhostHeight*cfg.Scale, cfg.BoneGhostRotation)

        -- moveable bone with shard
        local boneX, boneY = cx, cy
        if sim then
            local hx, hy = sim:GetHandPos()
            -- simple follow: bone follows hand slightly when grabbed
            if shardGrabbed and holding then
                shardX = shardX + (hx - boneX)*0.1
                shardY = shardY + (hy - boneY)*0.1
            end
        end
        surface.SetMaterial(matBoneMove)
        surface.SetDrawColor(255,255,255,cfg.BoneMoveAlpha)
        surface.DrawTexturedRectRotated(boneX, boneY, cfg.BoneMoveWidth*cfg.Scale, cfg.BoneMoveHeight*cfg.Scale, 0)

        -- shard itself (tweezers target)
        local sx, sy = boneX + shardX*cfg.Scale, boneY + shardY*cfg.Scale
        surface.SetMaterial(matShard)
        if shardGrabbed then
            surface.SetDrawColor(200,255,200,255)
        else
            surface.SetDrawColor(180,220,255,235)
        end
        local sw, sh = 68*cfg.Scale, 48*cfg.Scale
        -- pulse if near finish
        local distToFinish = math.sqrt((sx-FINISH_X)^2 + (sy-FINISH_Y)^2)
        if shardGrabbed then
            -- draw tray at finish
            surface.SetDrawColor(100,100,100,90)
            surface.DrawRect(FINISH_X-44, FINISH_Y-34, 88, 68)
            surface.SetDrawColor(200,200,200,180)
            surface.DrawOutlinedRect(FINISH_X-44, FINISH_Y-34, 88, 68)
            if CurTime() - finishPulse < 0.3 then
                surface.SetDrawColor(120,255,120,140)
                surface.DrawRect(FINISH_X-44, FINISH_Y-34, 88, 68)
            end
        end
        surface.DrawTexturedRectRotated(sx, sy, sw, sh, shardGrabbed and (CurTime()*45 %360) or 0)

        -- hand / tweezers (reuse hand mats as tweezers placeholder per keep png)
        if sim then
            local hx, hy = sim:GetHandPos()
            local mat = holding and matHandClick or matHandIdle
            surface.SetMaterial(mat)
            surface.SetDrawColor(255,255,255,cfg.HandAlpha)
            -- pain shake
            local shakeX = math.sin(CurTime()*18) * math.min(failCount*2.2, 14)
            local shakeY = math.cos(CurTime()*14) * math.min(failCount*1.2, 8)
            hx = hx + shakeX
            hy = hy + shakeY
            surface.DrawTexturedRectRotated(hx, hy, cfg.HandWidth*cfg.HandScale*0.11, cfg.HandHeight*cfg.HandScale*0.11, 0)
        end

        -- instructions
        draw.SimpleText("GLASS SHARD EXTRACTION - "..(activeLimb or "?"), "DermaLarge", cx, 64, Color(255,255,255,255), TEXT_ALIGN_CENTER)
        draw.SimpleText(shardGrabbed and "Drag shard to tray (top-right) and click!" or "Grab glass shard with tweezers (hold LMB)", "Default", cx, 96, Color(210,230,255,255), TEXT_ALIGN_CENTER)
        if failCount>0 then
            draw.SimpleText("Pain: "..failCount.." mistakes - further errors cause unconsciousness", "Default", cx, h-48, Color(255,120,120,255), TEXT_ALIGN_CENTER)
        end
        draw.SimpleText("ESC to close", "Default", w-84, 16, Color(200,200,200,200), TEXT_ALIGN_CENTER)
    end
    pnl.OnMousePressed = function(self, code)
        if code == MOUSE_LEFT then
            holding = true
            -- check if near shard
            if not shardGrabbed and sim then
                local hx, hy = sim:GetHandPos()
                local cfg2 = GetCfg()
                local cx2, cy2 = w/2+cfg2.CenterOffsetX, h/2+cfg2.CenterOffsetY
                local sx, sy = cx2 + shardX*cfg2.Scale, cy2 + shardY*cfg2.Scale
                local dist = math.sqrt((hx-sx)^2 + (hy-sy)^2)
                if dist < 52*cfg2.Scale then
                    shardGrabbed = true
                    surface.PlaySound("physics/flesh/flesh_impact_hard"..math.random(1,5)..".wav")
                else
                    -- miss near shard => pain
                    local missThresh = 110*cfg2.Scale
                    if dist < missThresh then
                        failCount = failCount+1
                        AddLocalPain(math.Rand(6,11))
                        surface.PlaySound("physics/body/body_medium_impact_soft"..math.random(3,7)..".wav")
                        if failCount >= 6 then
                            -- too many mistakes => faint
                            net.Start("WoundSystem_GlassFaint")
                                net.WriteString(activeLimb or "hand_R")
                            net.SendToServer()
                        end
                    end
                end
            elseif shardGrabbed then
                -- check drop at finish
                local hx, hy = sim and sim:GetHandPos() or Vector(0,0)
                -- hx/hy are 2d, use stored
                -- Instead get mouse pos
                local mx, my = gui.MousePos()
                local distF = math.sqrt((mx-FINISH_X)^2 + (my-FINISH_Y)^2)
                -- also check hand pos proximity
                if sim then
                    local hx2, hy2 = sim:GetHandPos()
                    distF = math.min(distF, math.sqrt((hx2-FINISH_X)^2 + (hy2-FINISH_Y)^2))
                end
                if distF < 64 then
                    -- success
                    finishPulse = CurTime()
                    surface.PlaySound("physics/flesh/flesh_impact_hard6.wav")
                    net.Start("WoundSystem_GlassSuccess")
                        net.WriteString(activeLimb or "hand_R")
                    net.SendToServer()
                    CloseGlass()
                else
                    -- dropped shard mid-way = fail
                    failCount = failCount+1
                    AddLocalPain(math.Rand(8,13))
                    shardGrabbed = false
                    ResetShardPos()
                    surface.PlaySound("physics/body/body_medium_impact_soft"..math.random(1,7)..".wav")
                end
            end
        end
    end
    pnl.OnMouseReleased = function(self, code)
        if code == MOUSE_LEFT then
            if shardGrabbed then
                -- if released not at tray, count as drop/fail if far
                local mx, my = gui.MousePos()
                local distF = math.sqrt((mx-FINISH_X)^2 + (my-FINISH_Y)^2)
                if distF > 90 then
                    -- allow holding via drag? if released away from tray, drop
                    -- we keep grabbed until they click tray, so ignore release
                end
            end
            holding = false
        end
    end
    MG.overlay = pnl
end

function CloseGlass()
    if IsValid(MG.overlay) then MG.overlay:Remove() end
    MG.overlay = nil
    activeLimb = nil
    holding = false
    shardGrabbed = false
    hook.Remove("Think", "WoundSystem_GlassInput")
    hook.Remove("OnScreenSizeChanged", "WoundSystem_GlassResize")
    gui.EnableScreenClicker(false)
end

function OpenGlass(limbId)
    activeLimb = limbId or "hand_R"
    failCount = 0
    startTime = CurTime()
    -- init hand physics sim
    if HandPhysics then
        sim = HandPhysics.New()
        if sim and sim.SetCenter then sim:SetCenter(ScrW()/2, ScrH()/2) end
    end
    ResetShardPos()
    CreateOverlay()
    gui.EnableScreenClicker(true)

    hook.Add("Think", "WoundSystem_GlassInput", function()
        if not IsValid(MG.overlay) then return end
        if sim and sim.Update then
            local mx, my = gui.MousePos()
            sim:Update(mx, my, holding)
        end
        if input.IsKeyDown(KEY_ESCAPE) then
            -- pain on abort? small
            CloseGlass()
        end
    end)
    hook.Add("OnScreenSizeChanged", "WoundSystem_GlassResize", function()
        if IsValid(MG.overlay) then
            MG.overlay:SetSize(ScrW(), ScrH())
        end
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
    -- request server to allow glass extraction minigame if limb has shard
    net.Start("WoundSystem_GlassRequest")
        net.WriteString(limb)
    net.SendToServer()
end)

-- also support hg style command
concommand.Add("hg_extract_glass", function(_,_,args)
    RunConsoleCommand("woundsys_glass_extract", args[1] or "hand_R")
end)
