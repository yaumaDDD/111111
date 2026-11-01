-- Clean-room flex-based facial feedback for health state.

WoundSystem = WoundSystem or {}

if WoundSystem.FacialExpressions and WoundSystem.FacialExpressions.HookName then
    hook.Remove("Think", WoundSystem.FacialExpressions.HookName)
    hook.Remove("EntityRemoved", WoundSystem.FacialExpressions.RemoveHookName)
end

local Facial = {}
WoundSystem.FacialExpressions = Facial

Facial.HookName = "WoundSystem_FacialExpressionsThink"
Facial.RemoveHookName = "WoundSystem_FacialExpressionsEntityRemoved"

local function EnsureClientConVar(name, defaultValue, helpText, minValue, maxValue)
    local existing = GetConVar(name)
    if existing then return existing end

    return CreateClientConVar(name, defaultValue, true, false, helpText, minValue, maxValue)
end

local RAW_FACEPOSER_FILE = "woundsystem/faceposer_flexes.txt"

local enabledCVar = EnsureClientConVar("woundsys_face_expressions_enabled", "1", "Enable WoundSystem flex-based facial expressions.", 0, 1)
local voiceMouthCVar = EnsureClientConVar("woundsys_face_voice_mouth", "1", "Move supported mouth flexes while players speak.", 0, 1)
local voiceMouthScaleCVar = EnsureClientConVar("woundsys_face_voice_scale", "5", "Scale live voice volume into mouth flex weight.", 0, 10)
local selfTalkMouthCVar = EnsureClientConVar("woundsys_face_self_talk_mouth", "1", "Move supported mouth flexes during WoundSystem self-talk.", 0, 1)
local distanceCVar = EnsureClientConVar("woundsys_face_expression_distance", "1800", "Maximum distance for remote facial expression updates.", 256, 6000)
local debugExpressionCVar = EnsureClientConVar("woundsys_face_debug_expression", "auto", "Temporary facial expression test override. Use auto, normal, tired, pain, shock, panic, sad, happy, unconscious, dead, or disfigured.")
local debugIntensityCVar = EnsureClientConVar("woundsys_face_debug_intensity", "1", "Temporary facial expression test intensity.", 0, 1)
local debugEyesCVar = EnsureClientConVar("woundsys_face_debug_eyes", "2", "Temporary facial expression test eye count.", 0, 2)

local EXPRESSION_DEFINITIONS = {
    {id = "normal", label = "Normal"},
    {id = "tired", label = "Tired"},
    {id = "pain", label = "Pain"},
    {id = "shock", label = "Shock"},
    {id = "panic", label = "Panic"},
    {id = "sad", label = "Sad"},
    {id = "happy", label = "Happy"},
    {id = "unconscious", label = "Unconscious"},
    {id = "dead", label = "Dead"},
    {id = "disfigured", label = "Disfigured"}
}

local EXPRESSION_CVARS = {
    normal = EnsureClientConVar("woundsys_face_expr_normal", "1", "Scale neutral WoundSystem facial expression strength.", 0, 2),
    tired = EnsureClientConVar("woundsys_face_expr_tired", "1", "Scale tired WoundSystem facial expression strength.", 0, 2),
    pain = EnsureClientConVar("woundsys_face_expr_pain", "1", "Scale pain WoundSystem facial expression strength.", 0, 2),
    shock = EnsureClientConVar("woundsys_face_expr_shock", "1", "Scale shock WoundSystem facial expression strength.", 0, 2),
    panic = EnsureClientConVar("woundsys_face_expr_panic", "1", "Scale panic WoundSystem facial expression strength.", 0, 2),
    sad = EnsureClientConVar("woundsys_face_expr_sad", "1", "Scale sad WoundSystem facial expression strength.", 0, 2),
    happy = EnsureClientConVar("woundsys_face_expr_happy", "1", "Scale happy WoundSystem facial expression strength.", 0, 2),
    unconscious = EnsureClientConVar("woundsys_face_expr_unconscious", "1", "Scale unconscious WoundSystem facial expression strength.", 0, 2),
    dead = EnsureClientConVar("woundsys_face_expr_dead", "1", "Scale dead WoundSystem facial expression strength.", 0, 2),
    disfigured = EnsureClientConVar("woundsys_face_expr_disfigured", "1", "Scale disfigured WoundSystem facial expression strength.", 0, 2)
}

local VALID_EXPRESSIONS = {
    normal = true,
    tired = true,
    pain = true,
    shock = true,
    panic = true,
    sad = true,
    happy = true,
    unconscious = true,
    dead = true,
    disfigured = true
}

local function WoundSystemClientEnabled()
    local client = WoundSystem and WoundSystem.Client
    if client and client.IsEnabled then
        return client.IsEnabled()
    end

    local cvar = GetConVar("woundsys_enabled")
    return not cvar or cvar:GetBool()
end

local CATEGORY_NAMES = {
    closeBoth = {
        "blink", "eyes_closed", "eye_close", "close_lid", "close_eyes", "eyelids_closed"
    },
    closeLeft = {
        "left_blink", "blink_left", "left_eye_close", "left_close_lid", "left_eyelid_close", "eye_close_l"
    },
    closeRight = {
        "right_blink", "blink_right", "right_eye_close", "right_close_lid", "right_eyelid_close", "eye_close_r"
    },
    squintBoth = {
        "squint", "eyes_squint", "squint_eyes", "narrow_eyes"
    },
    squintLeft = {
        "left_squint", "squint_left", "eye_squint_l", "L_Eye_pain", "l_eye_pain", "left_eye_pain"
    },
    squintRight = {
        "right_squint", "squint_right", "eye_squint_r", "R_Eye_pain", "r_eye_pain", "right_eye_pain"
    },
    browStrain = {
        "brow_lowerer", "brow_lower", "inner_brow_raiser", "outer_brow_raiser", "wrinkler", "anger", "scared"
    },
    jawSlack = {
        "jaw_drop", "jaw_open", "jaw_slack", "mouth_drop", "left_mouth_drop", "right_mouth_drop"
    },
    mouthOpen = {
        "mouth_open", "Mouth_open", "open_mouth", "mouth_ah", "mouth_oh", "lower_lip", "left_part", "right_part"
    },
    mouthTighten = {
        "mouth_stretch", "tightener", "lip_tightener", "upper_lip_raiser", "mouth_press"
    },
    mouthSmile = {
        "smile", "mouth_smile", "left_smile", "right_smile", "happy"
    }
}

local CATEGORY_MAX_WEIGHTS = {
    jawSlack = 2,
    mouthOpen = 2
}

local POSE_COMPONENTS = {
    {id = "close", label = "Eyelids", max = 1},
    {id = "squint", label = "Squint / pain eyes", max = 1},
    {id = "brow", label = "Brow strain", max = 1},
    {id = "jaw", label = "Jaw slack", max = 2},
    {id = "mouth_open", label = "Mouth open", max = 2},
    {id = "mouth_tight", label = "Mouth tight", max = 1},
    {id = "smile", label = "Smile", max = 1}
}

local DEFAULT_POSES = {
    normal = {},
    tired = {
        close = {base = 0.38, full = 0.73},
        squint = {base = 0.16, full = 0.36},
        jaw = {base = 0.05, full = 0.15}
    },
    pain = {
        squint = {base = 0.25, full = 0.7},
        brow = {base = 0.2, full = 0.7},
        mouth_tight = {base = 0.18, full = 0.53}
    },
    shock = {
        squint = {base = 0.12, full = 0.32},
        brow = {base = 0.35, full = 0.7},
        jaw = {base = 0.14, full = 0.46},
        mouth_open = {base = 0.12, full = 0.32}
    },
    panic = {
        brow = {base = 0.65, full = 0.95},
        jaw = {base = 0.28, full = 0.63},
        mouth_open = {base = 0.22, full = 0.54}
    },
    sad = {
        close = {base = 0.18, full = 0.36},
        squint = {base = 0.22, full = 0.47},
        brow = {base = 0.35, full = 0.8},
        jaw = {base = 0.04, full = 0.12},
        mouth_tight = {base = 0.12, full = 0.4}
    },
    happy = {
        squint = {base = 0.08, full = 0.28},
        smile = {base = 0.25, full = 0.75}
    },
    unconscious = {
        close = {base = 1, full = 1},
        jaw = {base = 0.22, full = 0.42},
        mouth_open = {base = 0.08, full = 0.22}
    },
    dead = {
        close = {base = 1, full = 1},
        jaw = {base = 0.3, full = 0.3},
        mouth_open = {base = 0.12, full = 0.12}
    },
    disfigured = {
        squint = {base = 0.4, full = 0.8},
        brow = {base = 0.35, full = 0.7},
        mouth_tight = {base = 0.28, full = 0.68}
    }
}

local function GetPoseCVarName(expression, component, point)
    return "woundsys_face_pose_" .. tostring(expression) .. "_" .. tostring(component) .. "_" .. tostring(point)
end

local function GetPoseDefault(expression, component, point)
    local expressionDefaults = DEFAULT_POSES[expression]
    local componentDefaults = expressionDefaults and expressionDefaults[component]
    return componentDefaults and componentDefaults[point] or 0
end

local PoseCVars = {}

for _, expressionInfo in ipairs(EXPRESSION_DEFINITIONS) do
    local expression = expressionInfo.id
    PoseCVars[expression] = {}

    for _, component in ipairs(POSE_COMPONENTS) do
        local componentID = component.id
        PoseCVars[expression][componentID] = {
            base = EnsureClientConVar(GetPoseCVarName(expression, componentID, "base"), tostring(GetPoseDefault(expression, componentID, "base")), "Face poser rest value for " .. expression .. " " .. component.label .. ".", 0, component.max),
            full = EnsureClientConVar(GetPoseCVarName(expression, componentID, "full"), tostring(GetPoseDefault(expression, componentID, "full")), "Face poser full-intensity value for " .. expression .. " " .. component.label .. ".", 0, component.max)
        }
    end
end

Facial.ExpressionDefinitions = EXPRESSION_DEFINITIONS
Facial.PoseComponents = POSE_COMPONENTS
Facial.DefaultPoses = DEFAULT_POSES
Facial.GetPoseCVarName = GetPoseCVarName

function Facial.ResetExpressionPose(expression)
    if not VALID_EXPRESSIONS[expression] then return end

    for _, component in ipairs(POSE_COMPONENTS) do
        local componentID = component.id
        RunConsoleCommand(GetPoseCVarName(expression, componentID, "base"), tostring(GetPoseDefault(expression, componentID, "base")))
        RunConsoleCommand(GetPoseCVarName(expression, componentID, "full"), tostring(GetPoseDefault(expression, componentID, "full")))
    end
end

local RawFlexPoses

local function NormalizeModelName(model)
    return string.lower(tostring(model or ""))
end

local function LoadRawFlexPoses()
    if RawFlexPoses then return RawFlexPoses end

    RawFlexPoses = {}
    if not file.Exists(RAW_FACEPOSER_FILE, "DATA") then return RawFlexPoses end

    local decoded = util.JSONToTable(file.Read(RAW_FACEPOSER_FILE, "DATA") or "")
    if istable(decoded) then
        RawFlexPoses = decoded
    end

    return RawFlexPoses
end

local function SaveRawFlexPoses()
    file.CreateDir("woundsystem")
    file.Write(RAW_FACEPOSER_FILE, util.TableToJSON(LoadRawFlexPoses(), true))
end

local function QueueRawFlexSave()
    timer.Create("WoundSystem_SaveFaceposerFlexes", 0.25, 1, SaveRawFlexPoses)
end

function Facial.SaveRawFlexPoses()
    SaveRawFlexPoses()
end

function Facial.GetRawFlexPoseValue(model, expression, flexName, point)
    local modelData = LoadRawFlexPoses()[NormalizeModelName(model)]
    local expressionData = modelData and modelData[expression]
    local flexData = expressionData and expressionData[flexName]
    return flexData and tonumber(flexData[point]) or 0
end

function Facial.SetRawFlexPoseValue(model, expression, flexName, point, value)
    if not VALID_EXPRESSIONS[expression] then return end
    if not isstring(flexName) or flexName == "" then return end

    point = point == "base" and "base" or "full"

    local modelKey = NormalizeModelName(model)
    if modelKey == "" then return end

    local poses = LoadRawFlexPoses()
    poses[modelKey] = poses[modelKey] or {}
    poses[modelKey][expression] = poses[modelKey][expression] or {}
    poses[modelKey][expression][flexName] = poses[modelKey][expression][flexName] or {}
    poses[modelKey][expression][flexName][point] = math.Clamp(tonumber(value) or 0, 0, 2)

    QueueRawFlexSave()
end

function Facial.ClearRawFlexPose(model, expression)
    local modelKey = NormalizeModelName(model)
    local poses = LoadRawFlexPoses()
    if poses[modelKey] then
        poses[modelKey][expression] = nil
    end

    QueueRawFlexSave()
end

function Facial.GetRawFlexesForExpression(model, expression)
    local modelData = LoadRawFlexPoses()[NormalizeModelName(model)]
    return modelData and modelData[expression] or nil
end

function Facial.GetEntityFlexList(ent)
    local result = {}
    if not IsValid(ent) or not ent.GetFlexNum or not ent.GetFlexName then return result end

    local count = math.min(math.max(tonumber(ent:GetFlexNum()) or 0, 0), 96)
    for index = 0, count - 1 do
        local name = ent:GetFlexName(index)
        if isstring(name) and name ~= "" then
            result[#result + 1] = {
                id = index,
                name = name
            }
        end
    end

    return result
end

local FlexCache = {}
local Runtime = setmetatable({}, { __mode = "k" })

local function AddUnique(list, value)
    for _, existing in ipairs(list) do
        if existing == value then return end
    end

    list[#list + 1] = value
end

local function ResolveFlexes(ent)
    local model = ent:GetModel()
    if not model or model == "" then return nil end

    local cached = FlexCache[model]
    if cached then return cached end

    local resolved = {}
    for category, names in pairs(CATEGORY_NAMES) do
        resolved[category] = {}
        for _, flexName in ipairs(names) do
            local flexID = ent:GetFlexIDByName(flexName)
            if isnumber(flexID) and flexID >= 0 then
                AddUnique(resolved[category], flexID)
            end
        end
    end

    FlexCache[model] = resolved
    return resolved
end

local function GetRuntime(ent)
    local state = Runtime[ent]
    if state then return state end

    state = {
        weights = {},
        nextBlink = CurTime() + math.Rand(2.2, 5.6),
        blinkStart = 0,
        blinkEnd = 0,
        oneEyeSide = nil
    }
    Runtime[ent] = state

    return state
end

local function GetExpressionState(ply)
    local expression = ply:GetNWString("WoundSystemFaceExpression", "normal")
    local intensity = ply:GetNWFloat("WoundSystemFaceIntensity", 0)
    local eyes = ply:GetNWInt("WoundSystemFaceEyes", 2)

    if ply:GetNWBool("WoundSystemFaceForce", false) then
        expression = ply:GetNWString("WoundSystemFaceForceExpression", expression)
        intensity = ply:GetNWFloat("WoundSystemFaceForceIntensity", intensity)
        eyes = ply:GetNWInt("WoundSystemFaceForceEyes", eyes)
    end

    local debugExpression = string.lower(string.Trim(debugExpressionCVar:GetString() or "auto"))
    if ply == LocalPlayer() and debugExpression ~= "" and debugExpression ~= "auto" and VALID_EXPRESSIONS[debugExpression] then
        expression = debugExpression
        intensity = debugIntensityCVar:GetFloat()
        eyes = debugEyesCVar:GetInt()
    end

    return expression, math.Clamp(intensity, 0, 1), math.Clamp(eyes, 0, 2)
end

local function BlinkAmount(rt, expression, eyes)
    if expression == "dead" or expression == "unconscious" or eyes <= 0 then
        return 1
    end

    if expression == "panic" or expression == "sad" or expression == "tired" or expression == "happy" then
        return 0
    end

    local now = CurTime()
    if now >= rt.nextBlink then
        rt.blinkStart = now
        rt.blinkEnd = now + math.Rand(0.13, 0.22)
        rt.nextBlink = now + math.Rand(2.4, 6.1)
    end

    if now >= rt.blinkEnd then
        return 0
    end

    local duration = math.max(rt.blinkEnd - rt.blinkStart, 0.01)
    local progress = math.Clamp((now - rt.blinkStart) / duration, 0, 1)
    return math.sin(progress * math.pi)
end

local function ScaleExpressionState(expression, intensity)
    if not VALID_EXPRESSIONS[expression] then
        expression = "normal"
    end

    local expressionCVar = EXPRESSION_CVARS[expression]
    local expressionScale = expressionCVar and expressionCVar:GetFloat() or 1
    if expressionScale <= 0 then
        return "normal", 0
    end

    return expression, math.Clamp((tonumber(intensity) or 0) * expressionScale, 0, 1)
end

local function ExpressionTargets(expression, intensity, voice)
    expression, intensity = ScaleExpressionState(expression, intensity)

    local function PoseValue(componentID)
        local componentCVars = PoseCVars[expression] and PoseCVars[expression][componentID]
        if not componentCVars then return 0 end

        local base = componentCVars.base and componentCVars.base:GetFloat() or GetPoseDefault(expression, componentID, "base")
        local full = componentCVars.full and componentCVars.full:GetFloat() or GetPoseDefault(expression, componentID, "full")
        return Lerp(intensity, base, full)
    end

    return {
        close = math.Clamp(PoseValue("close"), 0, 1),
        squint = math.Clamp(PoseValue("squint"), 0, 1),
        brow = math.Clamp(PoseValue("brow"), 0, 1),
        jaw = math.Clamp(PoseValue("jaw"), 0, 2),
        mouthOpen = math.Clamp(math.max(voice, PoseValue("mouth_open")), 0, 2),
        mouthTight = math.Clamp(PoseValue("mouth_tight"), 0, 1),
        smile = math.Clamp(PoseValue("smile"), 0, 1)
    }
end

local function ApplyRawFlexPose(ent, expression, intensity, rt)
    if not IsValid(ent) or not ent.GetModel or not ent.GetFlexIDByName or not ent.SetFlexWeight then return end

    expression, intensity = ScaleExpressionState(expression, intensity)

    local rawPose = Facial.GetRawFlexesForExpression(ent:GetModel(), expression)
    local active = {}

    if istable(rawPose) then
        for flexName, values in pairs(rawPose) do
            if isstring(flexName) and istable(values) then
                local flexID = ent:GetFlexIDByName(flexName)
                if isnumber(flexID) and flexID >= 0 then
                    local base = tonumber(values.base) or 0
                    local full = tonumber(values.full) or 0
                    ent:SetFlexWeight(flexID, math.Clamp(Lerp(intensity, base, full), 0, 2))
                    active[flexID] = true
                end
            end
        end
    end

    if rt.rawFlexes then
        for flexID in pairs(rt.rawFlexes) do
            if not active[flexID] then
                ent:SetFlexWeight(flexID, 0)
            end
        end
    end

    rt.rawFlexes = active
end

local function HasFlexes(flexes, category)
    return flexes[category] and #flexes[category] > 0
end

local function Smooth(rt, key, target, speed)
    local old = rt.weights[key] or 0
    local value = Lerp(math.Clamp(FrameTime() * speed, 0, 1), old, target)
    rt.weights[key] = value
    return value
end

local function ApplyCategory(ent, flexes, category, weight)
    local ids = flexes[category]
    if not ids then return end

    weight = math.Clamp(weight, 0, CATEGORY_MAX_WEIGHTS[category] or 1)
    for _, flexID in ipairs(ids) do
        ent:SetFlexWeight(flexID, weight)
    end
end

local function ResetEntityExpression(ent)
    if not IsValid(ent) or not ent.SetFlexWeight then return end

    local rt = Runtime[ent]
    local flexes = ResolveFlexes(ent)
    if flexes then
        for category in pairs(CATEGORY_NAMES) do
            ApplyCategory(ent, flexes, category, 0)
        end
    end

    if rt and rt.rawFlexes then
        for flexID in pairs(rt.rawFlexes) do
            ent:SetFlexWeight(flexID, 0)
        end
    end

    Runtime[ent] = nil
end

local function GetSelfTalkAmount(ply)
    if not selfTalkMouthCVar:GetBool() then return 0 end
    if ply ~= LocalPlayer() then return 0 end

    local hud = WoundSystem and WoundSystem.SelfTalkHUD
    if not hud or (hud.activePhrase or "") == "" or hud.finishedCurrent then return 0 end

    local phrase = hud.activePhrase or ""
    local typeSpeed = math.max(tonumber(hud.typeSpeed) or 18, 1)
    local talkTime = tonumber(hud.talkTime) or 0
    if talkTime > (#phrase / typeSpeed) then return 0 end

    local progress = math.Clamp(math.floor(talkTime * typeSpeed), 1, #phrase)
    local char = string.sub(phrase, progress, progress)
    local voicedChar = string.match(char, "%w") ~= nil
    local chatter = (math.sin(CurTime() * 28) + 1) * 0.5

    return math.Clamp((voicedChar and 0.28 or 0.08) + chatter * 0.42, 0, 0.75)
end

local function GetSpeechAmount(ply, expression)
    if expression == "dead" or expression == "unconscious" then return 0 end

    local voice = 0
    if voiceMouthCVar:GetBool() and ply.IsSpeaking and ply.VoiceVolume and ply:IsSpeaking() then
        voice = math.Clamp((ply:VoiceVolume() or 0) * math.Clamp(voiceMouthScaleCVar:GetFloat(), 0, 10), 0, 2)
    end

    return math.max(voice, GetSelfTalkAmount(ply))
end

local function PickOneEyeSide(rt, eyes)
    if eyes ~= 1 then
        rt.oneEyeSide = nil
        return nil
    end

    if not rt.oneEyeSide then
        rt.oneEyeSide = math.random(1, 2) == 1 and "left" or "right"
    end

    return rt.oneEyeSide
end

local function ApplyExpressionToEntity(ent, ply)
    if not IsValid(ent) or not IsValid(ply) then return end
    if not ent.SetFlexWeight or not ent.GetFlexIDByName then return end

    local flexes = ResolveFlexes(ent)
    if not flexes then return end

    local rt = GetRuntime(ent)
    local expression, intensity, eyes = GetExpressionState(ply)
    local speech = GetSpeechAmount(ply, expression)
    local targets = ExpressionTargets(expression, intensity, speech)
    local blink = math.max(BlinkAmount(rt, expression, eyes), targets.close)
    local lostSide = PickOneEyeSide(rt, eyes)

    local closeBoth = blink
    local closeLeft = blink
    local closeRight = blink

    if eyes == 1 and (HasFlexes(flexes, "closeLeft") or HasFlexes(flexes, "closeRight")) then
        closeBoth = 0
        if lostSide == "left" then
            closeLeft = 1
            closeRight = math.min(blink, 0.25)
        else
            closeLeft = math.min(blink, 0.25)
            closeRight = 1
        end
    elseif eyes == 1 then
        closeBoth = math.max(closeBoth, 0.35)
    end

    ApplyCategory(ent, flexes, "closeBoth", Smooth(rt, "closeBoth", closeBoth, 16))
    ApplyCategory(ent, flexes, "closeLeft", Smooth(rt, "closeLeft", closeLeft, 16))
    ApplyCategory(ent, flexes, "closeRight", Smooth(rt, "closeRight", closeRight, 16))
    ApplyCategory(ent, flexes, "squintBoth", Smooth(rt, "squintBoth", targets.squint, 8))
    ApplyCategory(ent, flexes, "squintLeft", Smooth(rt, "squintLeft", targets.squint, 8))
    ApplyCategory(ent, flexes, "squintRight", Smooth(rt, "squintRight", targets.squint, 8))
    ApplyCategory(ent, flexes, "browStrain", Smooth(rt, "browStrain", targets.brow, 7))
    local mouthOpenTarget = math.max(targets.mouthOpen, targets.jaw * 0.65)
    local jawTarget = math.max(targets.jaw, targets.mouthOpen * 0.85)

    ApplyCategory(ent, flexes, "jawSlack", Smooth(rt, "jawSlack", jawTarget, 14))
    ApplyCategory(ent, flexes, "mouthOpen", Smooth(rt, "mouthOpen", mouthOpenTarget, 16))
    ApplyCategory(ent, flexes, "mouthTighten", Smooth(rt, "mouthTighten", targets.mouthTight, 7))
    ApplyCategory(ent, flexes, "mouthSmile", Smooth(rt, "mouthSmile", targets.smile, 7))
    ApplyRawFlexPose(ent, expression, intensity, rt)
end

local function ShouldUpdateRemote(ent, localPly, maxDistSqr)
    if ent == localPly then return true end
    if not IsValid(localPly) then return false end

    return ent:GetPos():DistToSqr(localPly:GetPos()) <= maxDistSqr
end

local function ProcessPlayerFace(ply, localPly, maxDistSqr)
    if not IsValid(ply) then return end

    if ply:Alive() and ShouldUpdateRemote(ply, localPly, maxDistSqr) then
        ApplyExpressionToEntity(ply, ply)
    end

    local unconsciousRagdoll = ply:GetNWEntity("WoundSystemUnconsciousRagdoll")
    if IsValid(unconsciousRagdoll) and ShouldUpdateRemote(unconsciousRagdoll, localPly, maxDistSqr) then
        ApplyExpressionToEntity(unconsciousRagdoll, ply)
    end

    local deathRagdoll = ply:GetNWEntity("WoundSystemDeathRagdoll")
    if IsValid(deathRagdoll) and ShouldUpdateRemote(deathRagdoll, localPly, maxDistSqr) then
        ApplyExpressionToEntity(deathRagdoll, ply)
    end
end

hook.Add("Think", Facial.HookName, function()
    if not WoundSystemClientEnabled() then
        for ent in pairs(Runtime) do
            ResetEntityExpression(ent)
        end
        return
    end

    if not enabledCVar:GetBool() then
        for ent in pairs(Runtime) do
            ResetEntityExpression(ent)
        end
        return
    end

    local localPly = LocalPlayer()
    local maxDist = math.max(distanceCVar:GetFloat(), 256)
    local maxDistSqr = maxDist * maxDist

    for _, ply in ipairs(player.GetAll()) do
        ProcessPlayerFace(ply, localPly, maxDistSqr)
    end
end)

hook.Add("EntityRemoved", Facial.RemoveHookName, function(ent)
    Runtime[ent] = nil
end)
