if WoundSystem and WoundSystem.SkillsClientLoaded then return end

WoundSystem = WoundSystem or {}
WoundSystem.SkillsClientLoaded = true

local SKILL_LABELS = {
    STR = "Strength",
    RES = "Resilience",
    INT = "Intelligence"
}

net.Receive("WoundSystem_SkillLevelUp", function()
    local stat = net.ReadString()
    local oldLevel = net.ReadUInt(8)
    local newLevel = net.ReadUInt(8)
    local label = SKILL_LABELS[stat] or stat
    local message = string.format("%s increased from %d to %d.", label, oldLevel, newLevel)

    surface.PlaySound("music/levelup.ogg")

    if notification and notification.AddLegacy then
        notification.AddLegacy(message, NOTIFY_GENERIC, 5)
    end

    if chat and chat.AddText then
        chat.AddText(Color(120, 255, 160), "[WoundSystem] ", color_white, message)
    end
end)
