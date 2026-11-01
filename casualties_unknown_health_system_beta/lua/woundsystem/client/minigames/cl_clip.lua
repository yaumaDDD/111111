WoundSystem = WoundSystem or {}
WoundSystem.MinigameClip = WoundSystem.MinigameClip or {}

local Clip = WoundSystem.MinigameClip

local function CorruptUIText(text)
    return tostring(text or "")
end

surface.CreateFont("RetroTooltipTitle", { font = "Retro Gaming", size = 20, weight = 600, antialias = false })
surface.CreateFont("RetroTooltipDesc", { font = "Retro Gaming", size = 20, weight = 400, antialias = false })
surface.CreateFont("RetroMinigameGuide", { font = "Retro Gaming", size = 18, weight = 500, antialias = false })

Clip.Enabled = Clip.Enabled or CreateClientConVar("woundsys_minigame_clip_enabled", "1", true, false, "Clip minigame moving pieces inside an invisible rounded square.")
Clip.Size = Clip.Size or CreateClientConVar("woundsys_minigame_clip_size", "760", true, false, "Base minigame clip square size at 1080p.")
Clip.Radius = Clip.Radius or CreateClientConVar("woundsys_minigame_clip_radius", "38", true, false, "Minigame clip rounded corner radius at 1080p.")
Clip.OffsetX = Clip.OffsetX or CreateClientConVar("woundsys_minigame_clip_offset_x", "0", true, false, "Minigame clip square horizontal offset at 1080p.")
Clip.OffsetY = Clip.OffsetY or CreateClientConVar("woundsys_minigame_clip_offset_y", "0", true, false, "Minigame clip square vertical offset at 1080p.")
Clip.RoundedMigration = Clip.RoundedMigration or CreateClientConVar("woundsys_minigame_clip_rounded_migration", "0", true, false, "Internal migration for minigame rounded clipping defaults.")
Clip.BackdropEnabled = Clip.BackdropEnabled or CreateClientConVar("woundsys_minigame_backdrop_enabled", "1", true, false, "Draw the shared dark rounded minigame clip backdrop.", 0, 1)
Clip.BackdropAlpha = Clip.BackdropAlpha or CreateClientConVar("woundsys_minigame_backdrop_alpha", "200", true, false, "Alpha for the shared dark minigame clip backdrop.", 0, 255)
Clip.BackdropFadeTime = Clip.BackdropFadeTime or CreateClientConVar("woundsys_minigame_backdrop_fade_time", "0.2", true, false, "Fade-in time for the shared dark minigame clip backdrop.", 0, 2)
Clip.EdgeEnabled = Clip.EdgeEnabled or CreateClientConVar("woundsys_minigame_clip_edge_enabled", "1", true, false, "Draw faded rounded edges outside the minigame clip.", 0, 1)
Clip.EdgeAlpha = Clip.EdgeAlpha or CreateClientConVar("woundsys_minigame_clip_edge_alpha", "80", true, false, "Alpha for faded rounded edges outside the minigame clip.", 0, 255)
Clip.EdgeSize = Clip.EdgeSize or CreateClientConVar("woundsys_minigame_clip_edge_size", "34", true, false, "Pixel spread of faded rounded edges outside the minigame clip at 1080p.", 0, 128)
Clip.HeaderPanelAlpha = Clip.HeaderPanelAlpha or CreateClientConVar("woundsys_minigame_header_panel_alpha", "210", true, false, "Alpha for the full-square minigame header guide panel.", 0, 255)

Clip.HeaderIconCache = Clip.HeaderIconCache or {}
Clip.ExtraSize = 60
Clip.ExitGuide = Clip.ExitGuide or "Press RMB/ESC to exit"
Clip.Guides = Clip.Guides or {
    bandageMinigameGuide = "Click and drag the dressing around the limb to bandage.\nYou don't have to use the entire bandage.",
    syringeMinigameGuide = "Push syringe down to inject. Make sure to check the dosage.",
    lockpickMinigameGuide = "Click anywhere on the arch to try picking the lock.\nThe closer to the spot, the more it will turn.\nBe careful not to break your claws.",
    lifepodMinigameGuide = "Match the code to open.",
    shrapnelMinigameGuide = "Pull the shrapnel out slowly. Going too fast will hurt.\nUsing tweezers will bypass the speed limit.",
    dislocationMinigameGuide = "Hit the bone into the correct spot to correct dislocation.\nUsing a wrench would hurt way less.",
    amputationMinigameGuide = "Saw through the limb to amputate. Make sure to stop the bleeding after.",
    aedMinigameGuide = "Follow the displayed instructions.",
    manualDefibMinigameGuide = "Match the charge proportional to how far along the fibrillation cycle your heart is, charge, then shock. Repeat if needed.\nThe recommended estimate (POW.EST) gets more accurate with higher INT.",
    handCrankMinigameGuide = "Grab the handle and rotate it to charge."
}

if WoundSystem.CAS3Locale and WoundSystem.CAS3Locale.ApplyMinigameText then
    WoundSystem.CAS3Locale.ApplyMinigameText(Clip)
end

if not Clip.RoundedMigration:GetBool() then
    RunConsoleCommand("woundsys_minigame_clip_enabled", "1")
    if Clip.Radius:GetFloat() <= 0 then
        RunConsoleCommand("woundsys_minigame_clip_radius", "38")
    end
    RunConsoleCommand("woundsys_minigame_clip_rounded_migration", "1")
end

function Clip.Scale()
    local scale = ScrH() / 1080
    local uiScaleCv = GetConVar("woundsys_ui_scale")
    local uiScale = uiScaleCv and math.Clamp(uiScaleCv:GetFloat(), 0.6, 1.6) or 1
    if ScrH() <= 600 then
        uiScale = uiScale * 0.72
    elseif ScrH() <= 768 then
        uiScale = uiScale * 0.86
    end
    return scale * uiScale
end

function Clip.GetRect()
    local scale = Clip.Scale()
    local size = math.max(tonumber(Clip.Size:GetFloat()) or 760, 64) * scale + (Clip.ExtraSize * scale)
    local x = (ScrW() - size) * 0.5 + (Clip.OffsetX:GetFloat() * scale)
    local y = (ScrH() - size) * 0.5 + (Clip.OffsetY:GetFloat() * scale)
    local radius = math.Clamp((Clip.Radius:GetFloat() or 0) * scale, 0, size * 0.5)

    return x, y, size, size, radius
end

local function FadeFor(openTime, fadeTime)
    fadeTime = tonumber(fadeTime) or Clip.BackdropFadeTime:GetFloat()
    if fadeTime <= 0 then return 1 end
    return math.Clamp((CurTime() - (tonumber(openTime) or CurTime())) / fadeTime, 0, 1)
end

function Clip.DrawBackdrop(data)
    if not Clip.BackdropEnabled:GetBool() then return end

    data = data or {}
    local x, y, w, h, radius = Clip.GetRect()
    local scale = Clip.Scale()
    local fade = FadeFor(data.openTime, data.fadeTime)
    local innerAlpha = (tonumber(data.alpha) or Clip.BackdropAlpha:GetFloat()) * fade
    local edgeAlpha = (tonumber(data.edgeAlpha) or Clip.EdgeAlpha:GetFloat()) * fade
    local edgeSize = math.max(tonumber(data.edgeSize) or Clip.EdgeSize:GetFloat(), 0) * scale
    local rounded = math.Round(radius)

    if Clip.EdgeEnabled:GetBool() and edgeSize > 0 and edgeAlpha > 0 then
        local steps = math.max(3, math.ceil(edgeSize / (8 * scale)))
        for i = steps, 1, -1 do
            local t = i / steps
            local pad = edgeSize * t
            local alpha = edgeAlpha * (1 - t) ^ 1.35
            draw.RoundedBox(
                math.Round(radius + pad),
                math.Round(x - pad),
                math.Round(y - pad),
                math.Round(w + pad * 2),
                math.Round(h + pad * 2),
                Color(0, 0, 0, math.Clamp(alpha, 0, 255))
            )
        end
    end

    if innerAlpha > 0 then
        draw.RoundedBox(rounded, math.Round(x), math.Round(y), math.Round(w), math.Round(h), Color(0, 0, 0, math.Clamp(innerAlpha, 0, 255)))
    end
end

local function BeginScissor(x, y, w, h)
    if not render or not render.SetScissorRect then return false end
    render.SetScissorRect(math.Round(x), math.Round(y), math.Round(x + w), math.Round(y + h), true)
    return "scissor"
end

function Clip.Begin()
    if not Clip.Enabled:GetBool() then return false end
    if not render then return false end

    local x, y, w, h, radius = Clip.GetRect()
    if radius <= 0 or not render.SetStencilEnable or not render.OverrideColorWriteEnable then
        return BeginScissor(x, y, w, h)
    end

    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)

    render.OverrideColorWriteEnable(true, false)
    draw.NoTexture()
    surface.SetDrawColor(255, 255, 255, 255)
    draw.RoundedBox(math.Round(radius), math.Round(x), math.Round(y), math.Round(w), math.Round(h), color_white)
    render.OverrideColorWriteEnable(false, false)

    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)

    return "stencil"
end

function Clip.End(active)
    if not active then return end
    if active == "scissor" and render and render.SetScissorRect then
        render.SetScissorRect(0, 0, 0, 0, false)
        return
    end

    if active == "stencil" and render and render.SetStencilEnable then
        render.SetStencilEnable(false)
    end
end

function Clip.MarkOpened(mg)
    if not mg then return end
    mg.closing = false
    if IsValid(mg.overlay) then
        mg.overlay:SetPos(0, 0)
    end
end

function Clip.MarkClosing(mg)
    if not mg then return end
    mg.closing = false
end

function Clip.IsClosingDone(mg)
    return true
end

function Clip.ApplyPopup(mg)
    if not mg or not IsValid(mg.overlay) then return end
    mg.overlay:SetPos(0, 0)
end

local function GetIconMaterial(path)
    if not path or path == "" then return nil end
    if not Clip.HeaderIconCache[path] then
        Clip.HeaderIconCache[path] = Material(path, "smooth noclamp")
    end
    return Clip.HeaderIconCache[path]
end

function Clip.GetGuide(minigameName)
    if not minigameName or minigameName == "" then return "" end
    local guides = Clip.Guides or {}
    return tostring(guides[minigameName] or guides[minigameName .. "MinigameGuide"] or "")
end

local function WrapLine(text, font, maxW)
    surface.SetFont(font)

    local lines = {}
    local current = ""
    for _, word in ipairs(string.Explode(" ", tostring(text or ""))) do
        local nextLine = current == "" and word or (current .. " " .. word)
        if surface.GetTextSize(nextLine) <= maxW or current == "" then
            current = nextLine
        else
            lines[#lines + 1] = current
            current = word
        end
    end

    if current ~= "" then
        lines[#lines + 1] = current
    end

    return lines
end

local function DrawCenteredMultiline(text, font, x, y, maxW, color, lineGap)
    text = CorruptUIText(text)
    if text == "" then return end

    local lines = {}
    for _, rawLine in ipairs(string.Explode("\n", text)) do
        local wrapped = WrapLine(rawLine, font, maxW)
        if #wrapped == 0 then
            lines[#lines + 1] = ""
        else
            for _, line in ipairs(wrapped) do
                lines[#lines + 1] = line
            end
        end
    end

    surface.SetFont(font)
    local _, textH = surface.GetTextSize("Ag")
    local step = textH + (lineGap or 0)
    local startY = y - ((#lines - 1) * step) * 0.5

    for i, line in ipairs(lines) do
        draw.SimpleText(line, font, x, startY + ((i - 1) * step), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

function Clip.DrawHeader(data)
    data = data or {}

    local scale = Clip.Scale()
    local clipX, clipY, clipW, clipH, clipRadius = Clip.GetRect()
    local x = math.Round(clipX + (8 * scale))
    local y = math.Round(clipY + (8 * scale))
    local iconW = math.Round((tonumber(data.pw) or 30) * scale)
    local iconH = math.Round((tonumber(data.ph) or 30) * scale)
    local pad = math.Round(7 * scale)
    local gap = math.Round(9 * scale)
    local title = CorruptUIText(data.title or "Minigame")
    local value = CorruptUIText(data.value or "")
    local maxValue = tonumber(data.maxValue) or 100
    local curValue = tonumber(data.curValue) or maxValue
    local pct = maxValue > 0 and math.Clamp(curValue / maxValue, 0, 1) or 0

    local fontTitle = (WoundSystemGetFont and WoundSystemGetFont("RetroTooltipTitle", scale)) or "RetroTooltipTitle"
    local fontGuide = (WoundSystemGetFont and WoundSystemGetFont("RetroMinigameGuide", scale)) or "RetroMinigameGuide"

    surface.SetFont(fontTitle)
    local titleW, titleH = surface.GetTextSize(title)
    local openText = value ~= "" and " (" or ""
    local closeText = value ~= "" and ")" or ""
    local openW = select(1, surface.GetTextSize(openText))
    local valueW = select(1, surface.GetTextSize(value))
    local closeW = select(1, surface.GetTextSize(closeText))

    local boxW = pad * 2 + iconW + gap + titleW + openW + valueW + closeW
    local boxH = math.max(iconH + pad * 2, titleH + pad * 2)

    local panelAlpha = math.Clamp(tonumber(data.panelAlpha) or Clip.HeaderPanelAlpha:GetFloat(), 0, 255)
    local panelColor = Color(10, 10, 11, panelAlpha)
    local guideY = y + boxH + math.Round(17 * scale)
    local headerH = math.min(boxH + math.Round(46 * scale), clipH)
    if draw.RoundedBoxEx then
        draw.RoundedBoxEx(math.Round(clipRadius), math.Round(clipX), math.Round(clipY), math.Round(clipW), math.Round(headerH), panelColor, true, true, false, false)
    else
        surface.SetDrawColor(10, 10, 11, panelAlpha)
        surface.DrawRect(math.Round(clipX), math.Round(clipY), math.Round(clipW), math.Round(headerH))
    end

    local mat = data.mat or GetIconMaterial(data.icon)
    if mat and not mat:IsError() then
        surface.SetMaterial(mat)
        surface.SetDrawColor(255, 255, 255, 235)
        surface.DrawTexturedRect(x + pad, y + (boxH - iconH) * 0.5, iconW, iconH)
    end

    local textX = x + pad + iconW + gap
    local textY = y + (boxH - titleH) * 0.5
    local titleColor = Color(255, 255, 255, 255)
    local valueColor = data.valueColor or HSVToColor(pct * 120, 0.8, 0.9)

    draw.SimpleText(title, fontTitle, textX, textY, titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    textX = textX + titleW

    if value ~= "" then
        draw.SimpleText(openText, fontTitle, textX, textY, titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        textX = textX + openW
        draw.SimpleText(value, fontTitle, textX, textY, valueColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        textX = textX + valueW
        draw.SimpleText(closeText, fontTitle, textX, textY, titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local guideText = data.guide or Clip.GetGuide(data.minigame)
    DrawCenteredMultiline(guideText, fontGuide, clipX + clipW * 0.5, guideY, clipW * 0.66, Color(255, 255, 255, 245), math.Round(4 * scale))
end

function Clip.DrawExitGuide()
    local scale = Clip.Scale()
    local fontExit = (WoundSystemGetFont and WoundSystemGetFont("RetroTooltipTitle", scale)) or "RetroTooltipTitle"
    draw.SimpleText(CorruptUIText(Clip.ExitGuide or "Press RMB/ESC to exit"), fontExit, ScrW() / 2, ScrH() * 0.92, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
