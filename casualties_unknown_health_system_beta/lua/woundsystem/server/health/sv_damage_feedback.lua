WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

local DAMAGE_FEEDBACK_KIND = {
    generic = 0,
    bullet = 1,
    slash = 2,
    club = 4,
    blast = 8,
    burn = 16,
    fall = 32,
    radiation = 64
}

local function DamageFeedbackKind(dmginfo)
    local kind = DAMAGE_FEEDBACK_KIND.generic

    if dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT) then
        kind = bit.bor(kind, DAMAGE_FEEDBACK_KIND.bullet)
    end
    if dmginfo:IsDamageType(DMG_SLASH) then
        kind = bit.bor(kind, DAMAGE_FEEDBACK_KIND.slash)
    end
    if dmginfo:IsDamageType(DMG_CLUB) then
        kind = bit.bor(kind, DAMAGE_FEEDBACK_KIND.club)
    end
    if dmginfo:IsDamageType(DMG_BLAST) then
        kind = bit.bor(kind, DAMAGE_FEEDBACK_KIND.blast)
    end
    if dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_DIRECT) then
        kind = bit.bor(kind, DAMAGE_FEEDBACK_KIND.burn)
    end
    if dmginfo:IsDamageType(DMG_FALL) then
        kind = bit.bor(kind, DAMAGE_FEEDBACK_KIND.fall)
    end
    if DMG_RADIATION and dmginfo:IsDamageType(DMG_RADIATION) then
        kind = bit.bor(kind, DAMAGE_FEEDBACK_KIND.radiation)
    end

    return kind
end

function WoundSystem.Health.QueueDamageFeedback(ply, limbId, dmginfo, damage, body, limbState, willRagdoll)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not dmginfo then return end

    local rawDamage = math.max(tonumber(damage) or 0, tonumber(dmginfo:GetDamage()) or 0, 0)
    local painSeverity = math.max(
        math.Clamp(rawDamage / 55, 0, 1),
        math.Clamp((tonumber(limbState and limbState.pain) or tonumber(body and body.avgPain) or 0) / 100, 0, 1)
    )
    local bleedSeverity = math.Clamp((tonumber(limbState and limbState.bleed) or 0) / 100, 0, 1)
    local shockSeverity = math.max(
        math.Clamp((tonumber(body and body.painShock) or 0) / 100, 0, 1),
        math.Clamp((tonumber(body and body.cardioShock) or 0) / 100, 0, 1),
        math.Clamp((tonumber(body and body.shock) or 0) / 100, 0, 1),
        willRagdoll and 0.8 or 0
    )

    local pending = ply.WoundSystemDamageFeedbackPending
    if not pending then
        pending = {
            limbId = tostring(limbId or ""),
            damageKind = DAMAGE_FEEDBACK_KIND.generic,
            painSeverity = 0,
            bleedSeverity = 0,
            shockSeverity = 0,
            willRagdoll = false
        }
        ply.WoundSystemDamageFeedbackPending = pending

        timer.Simple(0, function()
            if not IsValid(ply) then return end

            local feedback = ply.WoundSystemDamageFeedbackPending
            ply.WoundSystemDamageFeedbackPending = nil
            if not feedback then return end

            ply.WoundSystemDamageFeedbackSeq = ((ply.WoundSystemDamageFeedbackSeq or 0) + 1) % 16777216
            if ply.WoundSystemDamageFeedbackSeq <= 0 then
                ply.WoundSystemDamageFeedbackSeq = 1
            end

            net.Start("WoundSystem_DamageFeedback")
                net.WriteUInt(ply.WoundSystemDamageFeedbackSeq, 24)
                net.WriteString(feedback.limbId or "")
                net.WriteUInt(math.Clamp(feedback.damageKind or 0, 0, 255), 8)
                net.WriteFloat(math.Clamp(feedback.painSeverity or 0, 0, 1))
                net.WriteFloat(math.Clamp(feedback.bleedSeverity or 0, 0, 1))
                net.WriteFloat(math.Clamp(feedback.shockSeverity or 0, 0, 1))
                net.WriteBool(feedback.willRagdoll == true)
            net.Send(ply)
        end)
    end

    pending.limbId = tostring(limbId or pending.limbId or "")
    pending.damageKind = bit.bor(pending.damageKind or 0, DamageFeedbackKind(dmginfo))
    pending.painSeverity = math.max(pending.painSeverity or 0, painSeverity)
    pending.bleedSeverity = math.max(pending.bleedSeverity or 0, bleedSeverity)
    pending.shockSeverity = math.max(pending.shockSeverity or 0, shockSeverity)
    pending.willRagdoll = pending.willRagdoll or willRagdoll == true
end
