WoundSystem = WoundSystem or {}

local Skills = WoundSystem.Skills or {}
WoundSystem.Skills = Skills

Skills.Defaults = Skills.Defaults or {
    STR = 9,
    RES = 8,
    INT = 7
}

Skills.IntFrozen = true
Skills.XPGainMult = 1
Skills.Session = Skills.Session or {}

local STAT_NAMES = {
    STR = true,
    RES = true,
    INT = true
}

local STAT_LABELS = {
    STR = "Strength",
    RES = "Resilience",
    INT = "Intelligence"
}

local function NormalizeStat(stat)
    stat = string.upper(string.Trim(tostring(stat or "")))

    if stat == "STRENGTH" then return "STR" end
    if stat == "RESILIENCE" or stat == "RESISTANCE" then return "RES" end
    if stat == "INTELLIGENCE" then return "INT" end

    return STAT_NAMES[stat] and stat or nil
end

function Skills.GetExperienceForLevel(targetLevel)
    targetLevel = math.floor(tonumber(targetLevel) or 0)
    if targetLevel <= 0 then return 0 end

    local total = 0
    local step = 60

    for level = 1, targetLevel do
        if level < 10 then
            total = total + 60
        elseif level == 10 then
            step = 100
            total = total + step
        else
            step = step * 1.18
            if level > 20 then
                step = step * 1.15
                if level >= 30 then
                    step = step * 2
                end
            end
            total = total + step
        end
    end

    return math.Round(total)
end

function Skills.UpdateExpBoundaries(skills)
    if not istable(skills) then return end

    for stat in pairs(STAT_NAMES) do
        local level = math.floor(tonumber(skills[stat]) or Skills.Defaults[stat] or 0)
        skills[stat] = level
        skills["min" .. stat] = Skills.GetExperienceForLevel(level)
        skills["max" .. stat] = Skills.GetExperienceForLevel(level + 1)
        skills["exp" .. stat] = tonumber(skills["exp" .. stat]) or skills["min" .. stat]
    end
end

function Skills.CreateDefault()
    local skills = {
        STR = Skills.Defaults.STR,
        RES = Skills.Defaults.RES,
        INT = Skills.Defaults.INT
    }

    Skills.UpdateExpBoundaries(skills)
    skills.expSTR = skills.minSTR
    skills.expRES = skills.minRES
    skills.expINT = skills.minINT
    return skills
end

function Skills.GetFrom10(skills, stat)
    stat = NormalizeStat(stat)
    if not stat then return 0 end

    return (tonumber(skills and skills[stat]) or Skills.Defaults[stat] or 10) - 10
end

function Skills.GetPainMultiplier(skills)
    return math.max(0, 1 - (Skills.GetFrom10(skills, "RES") * 0.025))
end

function Skills.ApplyPainResilience(rawPain, skills)
    return math.max(0, (tonumber(rawPain) or 0) * Skills.GetPainMultiplier(skills))
end

function Skills.ToNextNormalized(skills, stat)
    stat = NormalizeStat(stat)
    if not stat or not istable(skills) then return 0 end

    local minXP = tonumber(skills["min" .. stat]) or 0
    local maxXP = tonumber(skills["max" .. stat]) or minXP
    if maxXP <= minXP then return 0 end

    return math.Clamp(((tonumber(skills["exp" .. stat]) or minXP) - minXP) / (maxXP - minXP), 0, 1)
end

function Skills.Format(skills)
    if not istable(skills) then return "no skills" end

    return string.format(
        "STR %d (%.0f/%.0f), RES %d (%.0f/%.0f), INT %d (frozen)",
        tonumber(skills.STR) or 0,
        tonumber(skills.expSTR) or 0,
        tonumber(skills.maxSTR) or 0,
        tonumber(skills.RES) or 0,
        tonumber(skills.expRES) or 0,
        tonumber(skills.maxRES) or 0,
        tonumber(skills.INT) or 0
    )
end

if SERVER then
    local function SendLevelUp(ply, stat, oldLevel, newLevel)
        if not IsValid(ply) then return end

        net.Start("WoundSystem_SkillLevelUp")
            net.WriteString(stat)
            net.WriteUInt(math.Clamp(math.floor(tonumber(oldLevel) or 0), 0, 255), 8)
            net.WriteUInt(math.Clamp(math.floor(tonumber(newLevel) or 0), 0, 255), 8)
        net.Send(ply)
    end

    function Skills.EnsurePlayerSkills(ply)
        if not IsValid(ply) then return Skills.CreateDefault() end

        local skills = Skills.Session[ply]
        if not istable(skills) then
            skills = Skills.CreateDefault()
            Skills.Session[ply] = skills
        else
            Skills.UpdateExpBoundaries(skills)
        end

        return skills
    end

    function Skills.AttachToBody(ply, body)
        if not istable(body) then return nil end

        body.skills = Skills.EnsurePlayerSkills(ply)
        return body.skills
    end

    function Skills.AddSkillExp(ply, stat, xp)
        stat = NormalizeStat(stat)
        xp = tonumber(xp) or 0

        if not stat or xp <= 0 then return false end
        if stat == "INT" and Skills.IntFrozen then return false, "int_frozen" end

        local skills = Skills.EnsurePlayerSkills(ply)
        local body = WoundSystem.Health and WoundSystem.Health.GetBody and WoundSystem.Health.GetBody(ply) or nil
        if body then
            body.skills = skills
        end

        local oldLevel = math.floor(tonumber(skills[stat]) or 0)
        local expKey = "exp" .. stat
        local maxKey = "max" .. stat

        skills[expKey] = (tonumber(skills[expKey]) or 0) + (xp * (tonumber(Skills.XPGainMult) or 1))

        local leveled = false
        while skills[expKey] >= (tonumber(skills[maxKey]) or math.huge) do
            skills[stat] = (tonumber(skills[stat]) or 0) + 1
            Skills.UpdateExpBoundaries(skills)
            leveled = true
        end

        if leveled then
            SendLevelUp(ply, stat, oldLevel, skills[stat])
        end

        return true, leveled
    end

    function Skills.ClearPlayerSession(ply)
        Skills.Session[ply] = nil
    end

    local function CanUseSkillDebug(ply)
        return not IsValid(ply) or ply:IsAdmin()
    end

    local function FindPlayerByText(text)
        text = string.lower(tostring(text or ""))
        if text == "" then return nil end

        for _, candidate in ipairs(player.GetAll()) do
            if string.lower(candidate:SteamID64() or "") == text
                or string.lower(candidate:SteamID() or "") == text
                or string.find(string.lower(candidate:Nick() or ""), text, 1, true) then
                return candidate
            end
        end
    end

    concommand.Add("woundsys_skills_print", function(ply, _, args)
        if not CanUseSkillDebug(ply) then return end

        local target = IsValid(ply) and ply or nil
        if args and args[1] then
            target = FindPlayerByText(args[1]) or target
        end

        if not IsValid(target) then
            print("[WoundSystem] No target player for skills print.")
            return
        end

        local text = "[WoundSystem] " .. target:Nick() .. " skills: " .. Skills.Format(Skills.EnsurePlayerSkills(target))
        if IsValid(ply) then
            ply:ChatPrint(text)
        else
            print(text)
        end
    end)

    concommand.Add("woundsys_skills_givexp", function(ply, _, args)
        if not CanUseSkillDebug(ply) then return end

        local target = IsValid(ply) and ply or nil
        local stat
        local amount

        if args and args[3] then
            target = FindPlayerByText(args[1]) or target
            stat = args[2]
            amount = args[3]
        elseif args then
            stat = args[1]
            amount = args[2]
        end

        if not IsValid(target) then
            print("[WoundSystem] No target player for skills XP.")
            return
        end

        local ok, detail = Skills.AddSkillExp(target, stat, amount)
        local text = ok
            and ("[WoundSystem] " .. target:Nick() .. " skills: " .. Skills.Format(Skills.EnsurePlayerSkills(target)))
            or ("[WoundSystem] Could not add skill XP: " .. tostring(detail or "bad arguments"))

        if IsValid(ply) then
            ply:ChatPrint(text)
        else
            print(text)
        end
    end)

    hook.Add("PlayerDisconnected", "WoundSystem_Skills_ClearSession", function(ply)
        Skills.ClearPlayerSession(ply)
    end)
end

Skills.NormalizeStat = NormalizeStat
Skills.Labels = STAT_LABELS
