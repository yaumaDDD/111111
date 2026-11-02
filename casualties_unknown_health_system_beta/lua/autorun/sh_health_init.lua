WoundSystem = WoundSystem or {}

local sharedFiles = {
    "woundsystem/shared/sh_core.lua",
    "woundsystem/shared/sh_limb_statuses.lua",
    "woundsystem/shared/sh_medical_items.lua",
    "woundsystem/shared/sh_cas3_locale.lua",
    "woundsystem/shared/sh_limb_muscle.lua",
    "woundsystem/shared/sh_ragdoll_visuals.lua"
}

local sharedDirs = {
    "woundsystem/medical_tools"
}

local serverFiles = {
    "woundsystem/server/sv_resources.lua",
    "woundsystem/server/health/sv_config.lua",
    "woundsystem/server/health/sv_constants.lua",
    "woundsystem/server/health/sv_wake_positions.lua",
    "woundsystem/server/health/sv_facial_state.lua",
    "woundsystem/server/health/sv_damage_feedback.lua",
    "woundsystem/server/health/sv_fall_impact.lua",
    "woundsystem/server/health/sv_fall_trauma.lua",
    "woundsystem/server/health/sv_cas3_bodyfeel.lua",
    "woundsystem/server/sv_glass.lua",
    "woundsystem/server/sv_glass_sync.lua",
    "woundsystem/server/sv_health.lua",
    "woundsystem/server/sv_blood_effects.lua",
    "woundsystem/server/sv_brain_effects.lua",
    "woundsystem/server/sv_deathscreen.lua",
    "woundsystem/server/sv_sounds.lua"
}

local clientFiles = {
    "woundsystem/client/cl_ui_registry.lua",
    "woundsystem/client/cl_text_corruption.lua",
    "woundsystem/client/minigames/cl_clip.lua",
    "woundsystem/client/minigames/sh_handphysics.lua",
    "woundsystem/client/minigames/minigame_dev_config.lua",
    "woundsystem/client/minigames/cl_dislocation.lua",
    "woundsystem/client/minigames/cl_glass.lua",
    "woundsystem/client/minigames/cl_bandage.lua",
    "woundsystem/client/minigames/cl_syringe.lua",
    "woundsystem/client/minigames/cl_aed.lua",
    "woundsystem/client/cl_dismemberment_visuals.lua",
    "woundsystem/client/cl_health_gui.lua",
    "woundsystem/client/cl_multiplayer_feedback.lua",
    "woundsystem/client/cl_facial_expressions.lua",
    "woundsystem/client/cl_screen_effect_smoothing.lua",
    "woundsystem/client/cl_screen_effect_shaders.lua",
    "woundsystem/client/cl_blood_effects.lua",
    "woundsystem/client/cl_brain_effects.lua",
    "woundsystem/client/cl_moodles.lua",
    "woundsystem/client/cl_options.lua",
    "woundsystem/client/cl_sound_manager.lua"
}

local function AddClientFile(path)
    if SERVER then
        AddCSLuaFile(path)
    end
end

local function IncludeShared(path)
    AddClientFile(path)
    include(path)
end

local function IncludeRealmFile(path)
    local name = string.GetFileFromFilename and string.GetFileFromFilename(path) or string.match(path, "[^/\\]+$") or path
    local prefix = string.sub(name, 1, 3)

    if prefix == "sv_" then
        if SERVER then include(path) end
        return
    end

    if prefix == "cl_" then
        AddClientFile(path)
        if CLIENT then include(path) end
        return
    end

    IncludeShared(path)
end

local function IncludeDir(dir)
    if not file or not file.Find then return end

    local files = file.Find(dir .. "/*.lua", "LUA") or {}
    table.sort(files)

    for _, name in ipairs(files) do
        IncludeRealmFile(dir .. "/" .. name)
    end
end

for _, path in ipairs(sharedFiles) do
    IncludeShared(path)
end

for _, dir in ipairs(sharedDirs) do
    IncludeDir(dir)
end

if SERVER then
    WoundSystem.PoolNetStrings()

    for _, path in ipairs(clientFiles) do
        AddClientFile(path)
    end

    for _, path in ipairs(serverFiles) do
        include(path)
    end
else
    for _, path in ipairs(clientFiles) do
        include(path)
    end
end
