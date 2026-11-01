if WoundSystem and WoundSystem.ChatDistance and WoundSystem.ChatDistance._Loaded then
    hook.Remove("OnPlayerChat", "WoundSystem_DistanceChatDistortion")
    hook.Remove("Think", "WoundSystem_SelfTalkPendingInterruptThink")
end

WoundSystem = WoundSystem or {}
WoundSystem.ChatDistance = WoundSystem.ChatDistance or {}
WoundSystem.ChatDistance._Loaded = true

local ChatDistance = WoundSystem.ChatDistance
local SELF_TALK_LOUDNESS_MULT = 1 / 3
local PendingSelfTalk = ChatDistance.PendingSelfTalk or {}
ChatDistance.PendingSelfTalk = PendingSelfTalk
local COMMAND_PREFIXES = {
    ["/"] = true,
    ["!"] = true,
    ["."] = true,
    ["@"] = true
}

local function CVarBool(name, fallback)
    local cvar = GetConVar(name)
    if not cvar then return fallback end
    return cvar:GetBool()
end

local function CVarFloat(name, fallback)
    local cvar = GetConVar(name)
    if not cvar then return fallback end
    return cvar:GetFloat()
end

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    return CVarBool("woundsys_enabled", true)
end

local function SpeakerPos(ply)
    if not IsValid(ply) then return nil end
    return ply:EyePos()
end

local function ListenerPos(ply)
    if not IsValid(ply) then return nil end
    return ply:EyePos()
end

local function IsCommandText(text)
    text = string.Trim(tostring(text or ""))
    if text == "" then return true end

    return COMMAND_PREFIXES[string.sub(text, 1, 1)] == true
end

local function SpeakerKey(ply)
    if not IsValid(ply) then return nil end
    return ply:EntIndex()
end

local function StripWrappingQuotes(text)
    text = string.Trim(tostring(text or ""))
    if #text >= 2 and string.sub(text, 1, 1) == "\"" and string.sub(text, -1) == "\"" then
        return string.sub(text, 2, -2)
    end

    return text
end

local function HasWrappingQuotes(text)
    text = string.Trim(tostring(text or ""))
    return #text >= 2 and string.sub(text, 1, 1) == "\"" and string.sub(text, -1) == "\""
end

local function FormatInterruptedLine(partial, fullText)
    local quoted = HasWrappingQuotes(fullText)
    partial = StripWrappingQuotes(partial)
    fullText = StripWrappingQuotes(fullText)
    if partial == "" then return "" end
    if #partial < #fullText and string.sub(partial, -1) ~= "-" then partial = partial .. "-" end
    if quoted then return "\"" .. partial .. "\"" end
    return partial
end

local function TypingDuration(speaker, text)
    local visible = StripWrappingQuotes(text)
    local scale = 1
    if IsValid(speaker) then
        scale = math.Clamp((tonumber(speaker:GetNWFloat("Consciousness", 100)) or 100) * 0.01, 0.1, 1)
    end

    return #visible / math.max(18 * scale, 1)
end

local function ShouldUseLocalTypingHUD(speaker)
    return speaker == LocalPlayer() and WoundSystem.SelfTalkHUD and WoundSystem.SelfTalkHUD.Say
end

local function IsBlockedByWorld(listener, speaker)
    local startPos = ListenerPos(listener)
    local endPos = SpeakerPos(speaker)
    if not startPos or not endPos then return false end

    local tr = util.TraceLine({
        start = startPos,
        endpos = endPos,
        filter = {listener, speaker},
        mask = MASK_SOLID_BRUSHONLY or MASK_SOLID
    })

    return tr.HitWorld == true
end

local function MessageSeed(ply, text)
    local seed = #tostring(text or "") * 131
    if IsValid(ply) then
        seed = seed + ply:EntIndex() * 8191
    end
    seed = seed + math.floor(CurTime() * 10)
    return seed
end

local function Noise01(seed, index)
    local n = math.sin((seed + index * 37.719) * 12.9898) * 43758.5453
    return n - math.floor(n)
end

local function DegradeText(text, severity, seed)
    severity = math.Clamp(tonumber(severity) or 0, 0, 1)
    if severity <= 0.01 then return text end
    if severity >= 0.985 then
        return string.gsub(text, "[^%s]", "_")
    end

    local out = {}
    for i = 1, #text do
        local ch = string.sub(text, i, i)
        if string.match(ch, "%s") then
            out[#out + 1] = ch
        elseif Noise01(seed, i) < severity then
            out[#out + 1] = "_"
        else
            out[#out + 1] = ch
        end
    end

    return table.concat(out)
end

local function CountPattern(text, pattern)
    local count = 0
    for _ in string.gmatch(text, pattern) do
        count = count + 1
    end
    return count
end

local function LongestRun(text, target)
    local longest = 0
    local current = 0

    for i = 1, #text do
        if string.sub(text, i, i) == target then
            current = current + 1
            if current > longest then longest = current end
        else
            current = 0
        end
    end

    return longest
end

local function WordStats(text)
    local words = 0
    local capWords = 0
    local longCapWords = 0

    for word in string.gmatch(text, "%a+") do
        words = words + 1

        if #word >= 2 and not string.find(word, "%l") and string.find(word, "%u") then
            capWords = capWords + 1
            if #word >= 4 then
                longCapWords = longCapWords + 1
            end
        end
    end

    return words, capWords, longCapWords
end

local function EndsWithSentencePunctuation(text)
    return string.find(text, "[%.%!%?]%s*$") ~= nil
end

function ChatDistance.GetMessageVocalEffortDb(text)
    text = string.Trim(tostring(text or ""))

    local letters = CountPattern(text, "%a")
    if letters <= 0 then return 0 end

    local upper = CountPattern(text, "%u")
    local lower = CountPattern(text, "%l")
    local exclam = CountPattern(text, "!")
    local question = CountPattern(text, "%?")
    local capsRatio = upper / math.max(letters, 1)
    local words, capWords, longCapWords = WordStats(text)
    local capWordRatio = capWords / math.max(words, 1)
    local effortDb = 0

    if lower > 0 and upper == 0 and letters >= 3 then
        effortDb = effortDb - (EndsWithSentencePunctuation(text) and 2.2 or 3.2)
    elseif capsRatio >= 0.86 and letters >= 3 then
        effortDb = effortDb + 6.5
    elseif capWordRatio >= 0.5 and longCapWords > 0 then
        effortDb = effortDb + 4.2 + math.min(longCapWords - 1, 3) * 0.8
    elseif capsRatio >= 0.35 and letters >= 5 then
        effortDb = effortDb + Lerp(math.Clamp((capsRatio - 0.35) / 0.45, 0, 1), 1.2, 3.8)
    end

    if words == 1 and letters <= 3 and capsRatio >= 0.66 then
        effortDb = effortDb + 1.2
    end

    if exclam > 0 then
        effortDb = effortDb
            + math.min(exclam, 1) * 2.0
            + math.min(math.max(exclam - 1, 0), 2) * 1.25
            + math.min(math.max(exclam - 3, 0), 4) * 0.55
            + math.min(math.max(LongestRun(text, "!") - 1, 0), 4) * 0.35
    end

    if question > 0 then
        effortDb = effortDb + math.min(question, 3) * 0.45
    end

    if exclam <= 0 and capsRatio < 0.35 and lower > 0 and not EndsWithSentencePunctuation(text) and letters >= 12 then
        effortDb = effortDb - 0.8
    end

    return math.Clamp(effortDb, -7.0, 13.0)
end

function ChatDistance.GetMessageLoudness(text)
    local effortDb = ChatDistance.GetMessageVocalEffortDb(text)
    return math.Clamp(2 ^ (effortDb / 6), 0.45, 3.8)
end

function ChatDistance.GetSeverity(speaker, text, loudnessMult)
    local listener = LocalPlayer()
    if not IsValid(listener) or not IsValid(speaker) or listener == speaker then return 0, false, true end

    local closeDist = math.max(CVarFloat("woundsys_chat_distortion_close", 350), 0)
    local farDist = math.max(CVarFloat("woundsys_chat_distortion_far", 1800), closeDist + 1)
    local power = math.max(CVarFloat("woundsys_chat_distortion_power", 1.15), 0.01)
    local loudness = ChatDistance.GetMessageLoudness(text) * (tonumber(loudnessMult) or 1)

    closeDist = closeDist * math.Clamp(math.sqrt(loudness), 0.72, 1.95)
    farDist = math.max(farDist * loudness, closeDist + 1)

    local dist = listener:GetPos():Distance(speaker:GetPos())
    if dist > farDist then
        return 1, false, false
    end

    local severity = math.Clamp((dist - closeDist) / math.max(farDist - closeDist, 1), 0, 1)
    severity = math.Clamp(severity ^ power, 0, 1)

    local blocked = IsBlockedByWorld(listener, speaker)
    if blocked then
        local wallAdd = math.Clamp(CVarFloat("woundsys_chat_distortion_wall", 0.12), 0, 1)
        local wallMin = math.Clamp(CVarFloat("woundsys_chat_distortion_wall_min", 0.18), 0, 1)
        severity = math.Clamp(math.max(severity, wallMin) + wallAdd, 0, 1)
    end

    return severity, blocked, true
end

local function ApplyDistanceDistortion(speaker, text, loudnessMult)
    local severity, _, audible = ChatDistance.GetSeverity(speaker, text, loudnessMult)
    if audible == false then return nil, severity, false end

    text = tostring(text or "")
    if CVarBool("woundsys_chat_distortion_enabled", true) and severity > 0.01 then
        text = DegradeText(text, severity, MessageSeed(speaker, text))
    end

    return text, severity, true
end

local function AddDistortedChat(ply, text, teamChat, isDead)
    local nameColor = IsValid(ply) and team.GetColor(ply:Team()) or Color(180, 180, 180)
    local prefixColor = Color(170, 170, 170)
    local textColor = Color(230, 230, 230)
    local name = IsValid(ply) and ply:Nick() or "Console"

    if WoundSystem.TextCorruption and WoundSystem.TextCorruption.ForChat then
        text = WoundSystem.TextCorruption.ForChat(text)
    end

    local parts = {}
    if isDead then
        parts[#parts + 1] = prefixColor
        parts[#parts + 1] = "*DEAD* "
    end
    if teamChat then
        parts[#parts + 1] = prefixColor
        parts[#parts + 1] = "(TEAM) "
    end

    parts[#parts + 1] = nameColor
    parts[#parts + 1] = name
    parts[#parts + 1] = color_white
    parts[#parts + 1] = ": "
    parts[#parts + 1] = textColor
    parts[#parts + 1] = text
    chat.AddText(unpack(parts))
end

local function FinishPendingSelfTalk(key, interrupted, partial)
    local pending = key and PendingSelfTalk[key]
    if not pending then return end

    PendingSelfTalk[key] = nil
    if pending.timerName then timer.Remove(pending.timerName) end

    local line = pending.text
    if interrupted then
        line = FormatInterruptedLine(partial or "", pending.text)
    end

    if line == "" then return end
    AddDistortedChat(pending.speaker, line, pending.teamChat, pending.isDead)
end

local function InterruptPendingSelfTalk(ply)
    local key = SpeakerKey(ply)
    local pending = key and PendingSelfTalk[key]
    if not pending then return end

    if pending.localHud and WoundSystem.SelfTalkHUD and WoundSystem.SelfTalkHUD.Interrupt then
        WoundSystem.SelfTalkHUD.Interrupt()
        return
    end

    local visible = StripWrappingQuotes(pending.text)
    local elapsed = math.max(CurTime() - (pending.startTime or CurTime()), 0)
    local duration = math.max(pending.duration or 0.01, 0.01)
    local progress = math.Clamp(math.floor((elapsed / duration) * #visible), 0, #visible)
    FinishPendingSelfTalk(key, true, string.sub(visible, 1, progress))
end

local function QueueTypedChat(speaker, text, teamChat, isDead, useLocalHud)
    local key = SpeakerKey(speaker)
    if not key then return end

    InterruptPendingSelfTalk(speaker)

    local visible = StripWrappingQuotes(text)
    local pendingId = tostring(key) .. ":" .. tostring(CurTime()) .. ":" .. tostring(math.random(1, 2147483647))
    local pending = {
        id = pendingId,
        speaker = speaker,
        text = tostring(text or ""),
        startTime = CurTime(),
        duration = TypingDuration(speaker, visible),
        teamChat = teamChat == true,
        isDead = isDead == true
    }

    PendingSelfTalk[key] = pending

    if useLocalHud and ShouldUseLocalTypingHUD(speaker) then
        pending.localHud = true
        WoundSystem.SelfTalkHUD.Say(text, {
            onFinish = function()
                local current = PendingSelfTalk[key]
                if current and current.id == pendingId then
                    FinishPendingSelfTalk(key, false)
                end
            end,
            onInterrupt = function(partial)
                local current = PendingSelfTalk[key]
                if current and current.id == pendingId then
                    FinishPendingSelfTalk(key, true, partial)
                end
            end
        })
        return
    end

    pending.timerName = "WoundSystem_SelfTalkChatFinish_" .. pendingId
    timer.Create(pending.timerName, math.max(pending.duration, 0.05), 1, function()
        local current = PendingSelfTalk[key]
        if current and current.id == pendingId then
            FinishPendingSelfTalk(key, false)
        end
    end)
end

local function IsHEVStatusLine(text)
    local upper = string.upper(tostring(text or ""))
    return string.find(upper, "%[HAZARDOUS ENVIRONMENT SUIT%]", 1, true) ~= nil
end

local function FormatHEVStatusLine(text)
    local clean = string.Trim(tostring(text or ""))
    if clean == "" then return "[HAZARDOUS ENVIRONMENT SUIT]\nWOUND STABILIZED." end

    clean = string.upper(clean)
    if string.find(clean, "%[HAZARDOUS ENVIRONMENT SUIT%]", 1, true) then
        local main, sub = clean:match("^([^\n]+)\n?(.*)$")
        if sub and sub ~= "" then
            return main .. "\n" .. string.upper(string.Trim(sub))
        end
        return clean
    end

    clean = clean:gsub("^%s+", "")
    clean = clean:gsub("%s+", " ")
    return "[HAZARDOUS ENVIRONMENT SUIT]\n" .. (clean ~= "" and clean or "WOUND STABILIZED.")
end

local function QueueHEVSelfTalk(speaker, text, duration)
    if not IsValid(speaker) or not WoundSystem or not WoundSystem.SelfTalkHUD or not WoundSystem.SelfTalkHUD.SetHEVStatus then return end
    WoundSystem.SelfTalkHUD.SetHEVStatus("[HAZARDOUS ENVIRONMENT SUIT]", text, duration)
end

local function QueueSelfTalkChat(speaker, text)
    QueueTypedChat(speaker, text, false, false, speaker == LocalPlayer())
end

net.Receive("WoundSystem_HEV_SelfTalk", function()
    if not WoundSystemClientEnabled() then return end

    local text = net.ReadString()
    local duration = net.ReadFloat()
    if not text or text == "" then return end

    local speaker = LocalPlayer()
    QueueHEVSelfTalk(speaker, text, duration)
end)

net.Receive("WoundSystem_SelfTalkChat", function()
    if not WoundSystemClientEnabled() then return end

    local speaker = net.ReadEntity()
    local text = net.ReadString()
    if not IsValid(speaker) then return end

    if IsHEVStatusLine(text) then
        return
    end

    local displayed, _, audible = ApplyDistanceDistortion(speaker, text, SELF_TALK_LOUDNESS_MULT)
    if audible == false then return end

    QueueSelfTalkChat(speaker, displayed)
end)

hook.Add("OnPlayerChat", "WoundSystem_DistanceChatDistortion", function(ply, text, teamChat, isDead)
    if not WoundSystemClientEnabled() then return end
    if not IsValid(ply) then return end
    if IsCommandText(text) then return end

    local displayed, _, audible = ApplyDistanceDistortion(ply, text)
    if audible == false then return true end

    QueueTypedChat(ply, displayed, teamChat, isDead, ply == LocalPlayer())
    return true
end)

hook.Add("Think", "WoundSystem_SelfTalkPendingInterruptThink", function()
    if not WoundSystemClientEnabled() then
        for _, pending in pairs(PendingSelfTalk) do
            if pending and pending.timerName then
                timer.Remove(pending.timerName)
            end
        end
        table.Empty(PendingSelfTalk)
        return
    end

    for key, pending in pairs(PendingSelfTalk) do
        local speaker = pending and pending.speaker
        if not IsValid(speaker) then
            if pending.timerName then timer.Remove(pending.timerName) end
            PendingSelfTalk[key] = nil
        elseif not speaker:Alive() or speaker:GetNWBool("WoundSystemUnconscious", false) then
            InterruptPendingSelfTalk(speaker)
        end
    end
end)
