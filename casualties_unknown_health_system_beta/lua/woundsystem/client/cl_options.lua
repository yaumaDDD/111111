if WoundSystem and WoundSystem.Options and WoundSystem.Options._Loaded then
    hook.Remove("PopulateToolMenu", "WoundSystem_OptionsMenu")
end

WoundSystem = WoundSystem or {}
WoundSystem.Options = WoundSystem.Options or {}
WoundSystem.Options._Loaded = true

local PRESET_FILE = "woundsystem/client_presets.txt"

local function EnsureClientConVar(name, default, help, min, max)
    if GetConVar(name) then return end

    CreateClientConVar(name, tostring(default), true, false, help or "", min, max)
end

CreateClientConVar("woundsys_pain_sounds_enabled", "1", true, true, "Enable CAS-style pain vocalizations.", 0, 1)
CreateClientConVar("woundsys_death_sounds_enabled", "1", true, true, "Enable death vocalization sounds.", 0, 1)
CreateClientConVar("woundsys_growl_sounds_enabled", "1", true, true, "Enable unhappy growl sounds.", 0, 1)
CreateClientConVar("woundsys_self_talk_enabled", "1", true, true, "Let your character automatically say quoted C:U-style self-talk lines in chat.", 0, 1)
EnsureClientConVar("woundsys_music_enabled", "1", "Enable the CAS3-style WoundSystem music manager.", 0, 1)
EnsureClientConVar("woundsys_music_volume", "0.45", "CAS3 music song volume.", 0, 1)
EnsureClientConVar("woundsys_music_drone_volume", "1", "CAS3 medical drone volume.", 0, 1)
EnsureClientConVar("woundsys_music_sadness_distortion", "1", "Approximate CAS3 sadness mixer distortion.", 0, 1)
EnsureClientConVar("woundsys_tinnitus_volume", "1.0", "Volume multiplier for deafened tinnitus ringing SFX.", 0, 2)
if not GetConVar("woundsys_face_expressions_enabled") then
    CreateClientConVar("woundsys_face_expressions_enabled", "1", true, false, "Enable WoundSystem flex-based facial expressions.", 0, 1)
end
if not GetConVar("woundsys_face_voice_mouth") then
    CreateClientConVar("woundsys_face_voice_mouth", "1", true, false, "Move supported mouth flexes while players speak.", 0, 1)
end
if not GetConVar("woundsys_face_self_talk_mouth") then
    CreateClientConVar("woundsys_face_self_talk_mouth", "1", true, false, "Move supported mouth flexes during WoundSystem self-talk.", 0, 1)
end
if not GetConVar("woundsys_face_expression_distance") then
    CreateClientConVar("woundsys_face_expression_distance", "1800", true, false, "Maximum distance for remote facial expression updates.", 256, 6000)
end
if not GetConVar("woundsys_pain_shader_enabled") then
    CreateClientConVar("woundsys_pain_shader_enabled", "1", true, false, "Use the WoundSystem custom pain pixel shader when available.", 0, 1)
end
if not GetConVar("woundsys_pain_shader_strength") then
    CreateClientConVar("woundsys_pain_shader_strength", "1", true, false, "Scale the custom pain pixel shader blend.", 0, 2)
end
if not GetConVar("woundsys_pain_shader_distortion") then
    CreateClientConVar("woundsys_pain_shader_distortion", "1", true, false, "Scale pain pixel shader mask distortion.", 0, 2)
end
if not GetConVar("woundsys_woundview_key") then
    CreateClientConVar("woundsys_woundview_key", tostring(KEY_T or 20), true, true, "Key used to open and close the wound view.")
end
if not GetConVar("woundsys_bodyuse_key") then
    CreateClientConVar("woundsys_bodyuse_key", tostring(KEY_F or 17), true, true, "Key used to take body-use medical items while crouching and holding them.")
end
if not GetConVar("woundsys_worlditem_grab_key") then
    CreateClientConVar("woundsys_worlditem_grab_key", tostring(KEY_E or 11), true, true, "Key used to grab world medical items while looking at them.")
end

local CLIENT_PRESET_CVARS = {
    "woundsys_lowend_mode",
    "woundsys_visual_quality",
    "woundsys_ui_scale",
    "woundsys_pain_visual_strength",
    "woundsys_pain_shader_enabled",
    "woundsys_pain_shader_strength",
    "woundsys_pain_shader_distortion",
    "woundsys_moodles_enabled",
    "woundsys_moodles_scale",
    "woundsys_moodles_icon_size",
    "woundsys_moodles_gap",
    "woundsys_moodles_columns",
    "woundsys_moodles_offset_x",
    "woundsys_moodles_offset_y",
    "woundsys_moodles_anchor",
    "woundsys_moodles_always_show_side",
    "woundsys_moodles_side_on_cursor",
    "woundsys_moodles_max_main",
    "woundsys_moodles_update_rate",
    "woundsys_moodles_tooltips",
    "woundsys_moodles_medical_chip",
    "woundsys_moodles_disabled",
    "woundsys_audio_master",
    "woundsys_music_enabled",
    "woundsys_music_volume",
    "woundsys_music_drone_volume",
    "woundsys_music_sadness_distortion",
    "woundsys_tinnitus_volume",
    "woundsys_fur_blood_models",
    "woundsys_fur_blood_alpha",
    "woundsys_blood_effects",
    "woundsys_blood_color",
    "woundsys_blood_r",
    "woundsys_blood_g",
    "woundsys_blood_b",
    "woundsys_blood_stains",
    "woundsys_blood_trails",
    "woundsys_blood_quality",
    "woundsys_blood_max_stains",
    "woundsys_blood_bodyflow",
    "woundsys_blood_bodyflow_max",
    "woundsys_blood_bodyflow_alpha",
    "woundsys_minigame_clip_enabled",
    "woundsys_minigame_clip_size",
    "woundsys_minigame_clip_radius",
    "woundsys_minigame_clip_offset_x",
    "woundsys_minigame_clip_offset_y",
    "woundsys_brain_ca_enabled",
    "woundsys_brain_ca_threshold",
    "woundsys_brain_ca_intensity",
    "woundsys_brain_invert_frame",
    "woundsys_brain_sharpen",
    "woundsys_brain_flash_duration",
    "woundsys_brain_flash_opacity",
    "woundsys_brain_flash_stack",
    "woundsys_brain_ghost_exposure_enabled",
    "woundsys_brain_ghost_exposure",
    "woundsys_brain_aim_slow",
    "woundsys_brain_input_delay",
    "woundsys_brain_delay_ms",
    "woundsys_brain_invert_controls",
    "woundsys_brain_reverse_flip",
    "woundsys_pain_sounds_enabled",
    "woundsys_death_sounds_enabled",
    "woundsys_growl_sounds_enabled",
    "woundsys_face_expressions_enabled",
    "woundsys_face_voice_mouth",
    "woundsys_face_expression_distance",
    "woundsys_woundview_key",
    "woundsys_bodyuse_key"
}

local SERVER_OPTIONS = {
    {label = "Health system enabled", cvar = "woundsys_enabled", kind = "bool"},
    {label = "Limb tick interval", cvar = "woundsys_limb_tick_interval", min = 0.1, max = 2, decimals = 2},
    {label = "Cardio tick interval", cvar = "woundsys_cardio_tick_interval", min = 0.1, max = 2, decimals = 2},
    {label = "Healing rate", cvar = "woundsys_healing_rate", min = 0, max = 10, decimals = 2},
    {label = "Bleed rate", cvar = "woundsys_bleed_rate", min = 0, max = 10, decimals = 2},
    {label = "Natural bleed slowdown", cvar = "woundsys_natural_bleed_slow_lpm", min = 0, max = 5, decimals = 3},
    {label = "Bone heal speed", cvar = "woundsys_bone_heal_speed", min = 0.001, max = 5, decimals = 3},
    {label = "Dislocation heal speed", cvar = "woundsys_dislocation_heal_speed", min = 0.001, max = 5, decimals = 3},
    {label = "Fibrillation rise rate", cvar = "woundsys_fibrillation_rise_rate", min = 0, max = 10, decimals = 2},
    {label = "Fibrillation decay rate", cvar = "woundsys_fibrillation_decay_rate", min = 0, max = 10, decimals = 2},
    {label = "Shrapnel input Hz", cvar = "woundsys_shrapnel_input_hz", min = 5, max = 60, decimals = 0},
    {label = "Strokes enabled", cvar = "woundsys_strokes_enabled", kind = "bool"},
    {label = "Temperature simulation", cvar = "woundsys_temperature_enabled", kind = "bool"},
    {label = "Map suffocation damage", cvar = "woundsys_map_suffocation_enabled", kind = "bool"},
    {label = "Map suffocation scale", cvar = "woundsys_map_suffocation_scale", min = 0, max = 10, decimals = 2},
    {label = "Gunshot hearing enabled", cvar = "woundsys_gunshot_hearing_enabled", kind = "bool"},
    {label = "Gunshot hearing radius", cvar = "woundsys_gunshot_hearing_radius", min = 0, max = 5000, decimals = 0},
    {label = "Gunshot hearing scale", cvar = "woundsys_gunshot_hearing_scale", min = 0, max = 10, decimals = 2},
    {label = "Replace vanilla blood", cvar = "woundsys_replace_vanilla_blood", kind = "bool"},
    {label = "Server pain vocalizations", cvar = "woundsys_server_pain_sounds_enabled", kind = "bool"},
    {label = "Server growls/whines/barking", cvar = "woundsys_server_growl_sounds_enabled", kind = "bool"},
    {label = "Limb force enabled", cvar = "woundsys_limb_force_enabled", kind = "bool"},
    {label = "Limb force movement scale", cvar = "woundsys_limb_force_movement_scale", min = 0, max = 2, decimals = 2},
    {label = "Limb force weapon threshold", cvar = "woundsys_limb_force_weapon_threshold", min = 0, max = 1, decimals = 2},
    {label = "Limb force collapse threshold", cvar = "woundsys_limb_force_ragdoll_threshold", min = 0, max = 1, decimals = 2},
    {label = "Brain damage symptoms", cvar = "woundsys_brain_symptoms_enabled", kind = "bool"},
    {label = "Brain symptom interval", cvar = "woundsys_brain_symptom_interval", min = 5, max = 120, decimals = 0},
    {label = "Brain symptom threshold", cvar = "woundsys_brain_symptom_threshold", min = 0, max = 100, decimals = 0},
    {label = "Brain ragdoll symptoms", cvar = "woundsys_brain_ragdoll_symptoms", kind = "bool"},
    {label = "Auto-speedup when unconscious", cvar = "woundsys_unconscious_timescale_enabled", kind = "bool"},
    {label = "Unconscious speedup multiplier", cvar = "woundsys_unconscious_timescale", min = 1, max = 10, decimals = 1},
    {label = "Force everyone unchipped", cvar = "woundsys_force_unchipped", kind = "bool"},
    {label = "Persist status across campaign transitions", cvar = "woundsys_persist_across_maps", kind = "bool"},
    {label = "Stamina drain multiplier", cvar = "woundsys_stamina_drain_scale", min = 0, max = 10, decimals = 2}
}

local function ReadPresets()
    if not file.Exists(PRESET_FILE, "DATA") then return {} end

    local raw = file.Read(PRESET_FILE, "DATA")
    local data = util.JSONToTable(raw or "")
    return istable(data) and data or {}
end

local function WritePresets(presets)
    file.CreateDir("woundsystem")
    file.Write(PRESET_FILE, util.TableToJSON(presets or {}, true))
end

local function CleanPresetName(name)
    name = string.Trim(tostring(name or ""))
    name = string.gsub(name, "[\r\n\t]", " ")
    name = string.sub(name, 1, 48)
    return name
end

local function CaptureClientPreset()
    local values = {}
    for _, cvarName in ipairs(CLIENT_PRESET_CVARS) do
        local cvar = GetConVar(cvarName)
        if cvar then
            values[cvarName] = cvar:GetString()
        end
    end
    return values
end

local function ApplyClientPreset(values)
    if not istable(values) then return end

    for _, cvarName in ipairs(CLIENT_PRESET_CVARS) do
        local value = values[cvarName]
        if value ~= nil then
            RunConsoleCommand(cvarName, tostring(value))
        end
    end

end

local function AddHelp(panel, text)
    if panel.Help then
        panel:Help(text)
    end
end

local function AddClientPresetControls(panel)
    AddHelp(panel, "Presets save your client UI, audio, and alien blood settings locally.")

    local nameEntry = vgui.Create("DTextEntry")
    nameEntry:SetPlaceholderText("Preset name")
    panel:AddItem(nameEntry)

    local combo = vgui.Create("DComboBox")
    panel:AddItem(combo)

    local function RefreshCombo()
        combo:Clear()
        local presets = ReadPresets()
        for name in pairs(presets) do
            combo:AddChoice(name)
        end
    end

    local saveButton = vgui.Create("DButton")
    saveButton:SetText("Save Current Client Preset")
    saveButton.DoClick = function()
        local name = CleanPresetName(nameEntry:GetValue())
        if name == "" then
            chat.AddText(Color(255, 120, 80), "[WoundSystem] Name the preset first.")
            return
        end

        local presets = ReadPresets()
        presets[name] = CaptureClientPreset()
        WritePresets(presets)
        RefreshCombo()
        chat.AddText(Color(120, 255, 160), "[WoundSystem] Saved preset: " .. name)
    end
    panel:AddItem(saveButton)

    local loadButton = vgui.Create("DButton")
    loadButton:SetText("Load Selected Preset")
    loadButton.DoClick = function()
        local name = combo:GetValue()
        if not name then return end

        local presets = ReadPresets()
        ApplyClientPreset(presets[name])
        chat.AddText(Color(120, 255, 160), "[WoundSystem] Loaded preset: " .. name)
    end
    panel:AddItem(loadButton)

    local deleteButton = vgui.Create("DButton")
    deleteButton:SetText("Delete Selected Preset")
    deleteButton.DoClick = function()
        local name = combo:GetValue()
        if not name then return end

        local presets = ReadPresets()
        presets[name] = nil
        WritePresets(presets)
        RefreshCombo()
        chat.AddText(Color(255, 180, 100), "[WoundSystem] Deleted preset: " .. name)
    end
    panel:AddItem(deleteButton)

    RefreshCombo()
end

local function AddKeyBinder(panel, label, cvarName, fallbackKey)
    local row = vgui.Create("DPanel")
    row:SetTall(28)
    row.Paint = nil

    local text = vgui.Create("DLabel", row)
    text:Dock(LEFT)
    text:SetWide(150)
    text:SetText(label)
    text:SetDark(true)

    local binder = vgui.Create("DBinder", row)
    binder:Dock(FILL)

    local cvar = GetConVar(cvarName)
    binder:SetSelectedNumber(cvar and cvar:GetInt() or fallbackKey)
    binder.OnChange = function(_, keyCode)
        RunConsoleCommand(cvarName, tostring(keyCode or fallbackKey))
    end

    panel:AddItem(row)
end

local function BuildClientPanel(panel)
    panel:ClearControls()
    AddHelp(panel, "C:U Health System client customization. These settings are per-player.")

    panel:CheckBox("Low-end mode", "woundsys_lowend_mode")
    panel:NumSlider("Visual quality", "woundsys_visual_quality", 0, 2, 0)
    panel:NumSlider("All UI scale", "woundsys_ui_scale", 0.6, 1.6, 2)
    panel:NumSlider("Pain UI strength", "woundsys_pain_visual_strength", 0, 2, 2)
    panel:CheckBox("Pain pixel shader", "woundsys_pain_shader_enabled")
    panel:NumSlider("Pain shader strength", "woundsys_pain_shader_strength", 0, 2, 2)
    panel:NumSlider("Pain shader distortion", "woundsys_pain_shader_distortion", 0, 2, 2)
    panel:NumSlider("Medical audio loudness", "woundsys_audio_master", 0, 2, 2)
    panel:CheckBox("CAS3 health audio", "woundsys_music_enabled")
    panel:NumSlider("Dying/death cue volume", "woundsys_music_volume", 0, 1, 2)
    panel:NumSlider("Drone volume", "woundsys_music_drone_volume", 0, 1, 2)
    panel:CheckBox("Sadness audio distortion", "woundsys_music_sadness_distortion")
    panel:NumSlider("Tinnitus SFX volume", "woundsys_tinnitus_volume", 0, 2, 2)
    AddKeyBinder(panel, "Wound view key", "woundsys_woundview_key", KEY_T or 20)
    AddKeyBinder(panel, "Self-use item key", "woundsys_bodyuse_key", KEY_F or 17)
    AddKeyBinder(panel, "World item grab key", "woundsys_worlditem_grab_key", KEY_E or 11)
    panel:CheckBox("Enable pain vocalizations", "woundsys_pain_sounds_enabled")
    panel:CheckBox("Enable death vocalizations", "woundsys_death_sounds_enabled")
    panel:CheckBox("Enable unhappy growls", "woundsys_growl_sounds_enabled")

    AddHelp(panel, "Flex-based facial feedback for supported playermodels.")
    panel:CheckBox("Facial expressions", "woundsys_face_expressions_enabled")
    panel:CheckBox("Voice mouth movement", "woundsys_face_voice_mouth")
    panel:NumSlider("Face update distance", "woundsys_face_expression_distance", 256, 6000, 0)

    AddHelp(panel, "Symptom moodles. Anchor accepts topleft, topright, bottomleft, bottomright, centerleft, or centerright. Disable entries with comma-separated moodle ids.")
    panel:CheckBox("Moodles enabled", "woundsys_moodles_enabled")
    panel:CheckBox("Show chip-gated diagnostics", "woundsys_moodles_medical_chip")
    panel:NumSlider("Moodle scale", "woundsys_moodles_scale", 0.4, 3, 2)
    panel:NumSlider("Moodle icon size", "woundsys_moodles_icon_size", 24, 128, 0)
    panel:NumSlider("Moodle gap", "woundsys_moodles_gap", 0, 64, 0)
    panel:NumSlider("Moodle columns", "woundsys_moodles_columns", 1, 32, 0)
    panel:NumSlider("Moodle offset X", "woundsys_moodles_offset_x", -600, 600, 0)
    panel:NumSlider("Moodle offset Y", "woundsys_moodles_offset_y", -600, 600, 0)
    panel:TextEntry("Moodle anchor", "woundsys_moodles_anchor")
    panel:CheckBox("Always show side moodles", "woundsys_moodles_always_show_side")
    panel:CheckBox("Show side moodles while cursor visible", "woundsys_moodles_side_on_cursor")
    panel:NumSlider("Max main moodles", "woundsys_moodles_max_main", 1, 40, 0)
    panel:NumSlider("Moodle update seconds", "woundsys_moodles_update_rate", 0.1, 5, 1)
    panel:CheckBox("Moodle tooltips", "woundsys_moodles_tooltips")
    panel:TextEntry("Disabled moodle ids", "woundsys_moodles_disabled")

    AddHelp(panel, "Alien blood / fur blood model overlay.")
    panel:CheckBox("Draw alien blood on playermodels", "woundsys_fur_blood_models")
    panel:NumSlider("Alien blood opacity", "woundsys_fur_blood_alpha", 0, 0.5, 2)

    AddHelp(panel, "Decorative blood stains, pools, trails, and droplets.")
    panel:CheckBox("Blood effects", "woundsys_blood_effects")
    panel:CheckBox("Blood stains / pools", "woundsys_blood_stains")
    panel:CheckBox("Blood trails", "woundsys_blood_trails")
    panel:NumSlider("Blood effect quality", "woundsys_blood_quality", 0, 2, 0)
    panel:NumSlider("Max blood stains", "woundsys_blood_max_stains", 0, 250, 0)
    panel:CheckBox("Body-following blood flow", "woundsys_blood_bodyflow")
    panel:NumSlider("Max body blood flows (0 auto)", "woundsys_blood_bodyflow_max", 0, 96, 0)
    panel:NumSlider("Body blood flow opacity", "woundsys_blood_bodyflow_alpha", 0, 2, 2)

    AddHelp(panel, "Minigame invisible clip border.")
    panel:CheckBox("Clip minigame visuals", "woundsys_minigame_clip_enabled")
    panel:NumSlider("Clip square size", "woundsys_minigame_clip_size", 300, 1400, 0)
    panel:NumSlider("Clip corner roundness", "woundsys_minigame_clip_radius", 0, 160, 0)
    panel:NumSlider("Clip horizontal offset", "woundsys_minigame_clip_offset_x", -600, 600, 0)
    panel:NumSlider("Clip vertical offset", "woundsys_minigame_clip_offset_y", -600, 600, 0)

    AddHelp(panel, "POV Motion Nausea & Disorientation.")
    panel:CheckBox("POV spin/shake motion nausea", "woundsys_nausea_enabled")
    panel:NumSlider("Motion nausea sensitivity", "woundsys_nausea_sensitivity", 0.2, 3.0, 2)

    AddHelp(panel, "Blood Color (RGB / Species Presets). Default is Alien Yellow.")
    local colorCombo = vgui.Create("DComboBox")
    colorCombo:AddChoice("Alien Yellow", "alien_yellow")
    colorCombo:AddChoice("Human Red", "red")
    colorCombo:AddChoice("Custom RGB", "custom")

    local curMode = GetConVar("woundsys_blood_color") and GetConVar("woundsys_blood_color"):GetString() or "alien_yellow"
    if curMode == "red" then
        colorCombo:SetValue("Human Red")
    elseif curMode == "custom" then
        colorCombo:SetValue("Custom RGB")
    else
        colorCombo:SetValue("Alien Yellow")
    end

    panel:AddItem(colorCombo)

    local sliderR = panel:NumSlider("Blood Red (R)", "woundsys_blood_r", 0, 255, 0)
    local sliderG = panel:NumSlider("Blood Green (G)", "woundsys_blood_g", 0, 255, 0)
    local sliderB = panel:NumSlider("Blood Blue (B)", "woundsys_blood_b", 0, 255, 0)

    colorCombo.OnSelect = function(_, _, _, value)
        RunConsoleCommand("woundsys_blood_color", value)
        if value == "alien_yellow" then
            RunConsoleCommand("woundsys_blood_r", "255")
            RunConsoleCommand("woundsys_blood_g", "201")
            RunConsoleCommand("woundsys_blood_b", "0")
            if sliderR and sliderR.SetValue then sliderR:SetValue(255) end
            if sliderG and sliderG.SetValue then sliderG:SetValue(201) end
            if sliderB and sliderB.SetValue then sliderB:SetValue(0) end
        elseif value == "red" then
            RunConsoleCommand("woundsys_blood_r", "199")
            RunConsoleCommand("woundsys_blood_g", "10")
            RunConsoleCommand("woundsys_blood_b", "10")
            if sliderR and sliderR.SetValue then sliderR:SetValue(199) end
            if sliderG and sliderG.SetValue then sliderG:SetValue(10) end
            if sliderB and sliderB.SetValue then sliderB:SetValue(10) end
        end
    end

    local previewPanel = vgui.Create("DPanel")
    previewPanel:SetTall(24)
    previewPanel.Paint = function(s, w, h)
        local r = GetConVar("woundsys_blood_r") and GetConVar("woundsys_blood_r"):GetInt() or 255
        local g = GetConVar("woundsys_blood_g") and GetConVar("woundsys_blood_g"):GetInt() or 236
        local b = GetConVar("woundsys_blood_b") and GetConVar("woundsys_blood_b"):GetInt() or 58
        draw.RoundedBox(4, 0, 0, w, h, Color(r, g, b, 255))
        draw.SimpleText("Blood Color Preview", "DermaDefaultBold", w / 2, h / 2, (r + g + b > 380) and Color(0, 0, 0) or Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    panel:AddItem(previewPanel)

    AddClientPresetControls(panel)
end

local function SendServerCVar(name, value)
    net.Start("WoundSystem_SetServerConVar")
        net.WriteString(name)
        net.WriteString(tostring(value))
    net.SendToServer()
end

local function BuildServerPanel(panel)
    panel:ClearControls()
    AddHelp(panel, "C:U Health System server settings. Only server owners/admins can apply these.")

    local ply = LocalPlayer()
    local canApply = IsValid(ply) and ply:IsAdmin()
    if not canApply then
        AddHelp(panel, "You are not an admin on this server, so Apply will not change server values.")
    end

    local controls = {}

    for _, opt in ipairs(SERVER_OPTIONS) do
        if opt.kind == "bool" then
            local check = vgui.Create("DCheckBoxLabel")
            check:SetText(opt.label)
            check:SetDark(true)
            check:SetValue(GetConVar(opt.cvar) and GetConVar(opt.cvar):GetBool() or false)
            panel:AddItem(check)
            controls[#controls + 1] = {option = opt, control = check}
        else
            local slider = vgui.Create("DNumSlider")
            slider:SetText(opt.label)
            slider:SetMin(opt.min)
            slider:SetMax(opt.max)
            slider:SetDecimals(opt.decimals or 2)
            slider:SetValue(GetConVar(opt.cvar) and GetConVar(opt.cvar):GetFloat() or opt.min)
            panel:AddItem(slider)
            controls[#controls + 1] = {option = opt, control = slider}
        end
    end

    AddHelp(panel, "Default Starting Spawn Inventory (Slots 1 - 5):")

    AddHelp(panel, "--- Health Station - WIP, still doesn't work for now! ---")
    local chargerMedicines = {
        "MORPHINE", "FENTANYL", "ANTIBIOTICS", "CEFTRIAXONE",
        "BLOOD BAG", "SALINE", "NALOXONE", "PAINCREAM",
        "ANTIDEPRESSANTS", "INJECTION",
    }
    local chargerLbl = vgui.Create("DLabel")
    chargerLbl:SetText("Station injection medicine:")
    chargerLbl:SetDark(true)
    panel:AddItem(chargerLbl)

    local chargerCombo = vgui.Create("DComboBox")
    local curMed = (GetConVar("woundsystem_charger_medicine") and GetConVar("woundsystem_charger_medicine"):GetString() or "MORPHINE"):upper()
    for _, med in ipairs(chargerMedicines) do
        chargerCombo:AddChoice(med, med, med == curMed)
    end
    chargerCombo.SelectedMed = curMed
    chargerCombo.OnSelect = function(_, _, _, val)
        chargerCombo.SelectedMed = val
    end
    panel:AddItem(chargerCombo)

    local spawnControls = {}
    local availableItems = {
        {id = "empty", title = "-- Empty Slot --"},
        {id = "weapon", title = "-- Equipped Weapon --"}
    }

    if WoundSystem.Items and WoundSystem.Items.Order then
        for _, itemId in ipairs(WoundSystem.Items.Order) do
            local item = WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
            if item then
                availableItems[#availableItems + 1] = {id = item.id or itemId, title = (item.title or itemId) .. " (" .. (item.id or itemId) .. ")"}
            end
        end
    end

    for slotIdx = 1, 5 do
        local cvarName = "woundsystem_spawn_slot" .. slotIdx
        local currentVal = GetConVar(cvarName) and GetConVar(cvarName):GetString() or ""

        local lbl = vgui.Create("DLabel")
        lbl:SetText("Spawn Slot " .. slotIdx .. ":")
        lbl:SetDark(true)
        lbl:SetFont("DermaDefaultBold")
        panel:AddItem(lbl)

        local combo = vgui.Create("DComboBox")
        local selectIndex = 1

        for idx, itm in ipairs(availableItems) do
            combo:AddChoice(itm.title, itm.id)
            if string.lower(itm.id) == string.lower(string.Trim(currentVal)) then
                selectIndex = idx
            end
        end

        combo.OnSelect = function(self, index, value, data)
            self.SelectedData = data
        end

        combo:ChooseOptionID(selectIndex)
        local selectedID = combo:GetSelectedID()
        combo.SelectedData = selectedID and combo:GetOptionData(selectedID) or availableItems[selectIndex].id

        panel:AddItem(combo)

        spawnControls[#spawnControls + 1] = {cvar = cvarName, combo = combo}
    end

    local applyButton = vgui.Create("DButton")
    applyButton:SetText("Apply Server Settings")
    applyButton.DoClick = function()
        if not (IsValid(LocalPlayer()) and LocalPlayer():IsAdmin()) then
            chat.AddText(Color(255, 120, 80), "[WoundSystem] Server settings require admin.")
            return
        end

        for _, row in ipairs(controls) do
            local value
            if row.option.kind == "bool" then
                local b = false
                if row.control.GetChecked then
                    b = row.control:GetChecked()
                elseif row.control.GetValue then
                    b = tobool(row.control:GetValue())
                end
                value = b and "1" or "0"
            else
                value = row.control:GetValue()
            end
            SendServerCVar(row.option.cvar, value)
        end

        for _, spawnRow in ipairs(spawnControls) do
            local selectedID = spawnRow.combo:GetSelectedID()
            local data = spawnRow.combo.SelectedData or (selectedID and spawnRow.combo:GetOptionData(selectedID))
            SendServerCVar(spawnRow.cvar, tostring(data or "empty"))
        end

        SendServerCVar("woundsystem_charger_medicine", chargerCombo.SelectedMed or "MORPHINE")

        chat.AddText(Color(120, 255, 160), "[WoundSystem] Sent server settings.")
    end
    panel:AddItem(applyButton)
end



-- ============================================================
-- ADMIN DEBUG PANEL
-- ============================================================
local LIMB_LIST = {
    "head", "thorax", "abdomen",
    "arm_R", "forearm_R", "hand_R",
    "arm_L", "forearm_L", "hand_L",
    "thigh_R", "crus_R", "foot_R",
    "thigh_L", "crus_L", "foot_L",
}

local function SendAdminDebug(action, param1, param2)
    net.Start("WoundSystem_AdminDebugAction")
    net.WriteString(action)
    net.WriteString(tostring(param1 or ""))
    net.WriteFloat(tonumber(param2) or 0)
    net.SendToServer()
end

local function BuildAdminDebugPanel(panel)
    panel:ClearControls()

    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then
        local lbl = panel:Help("Admin only")
        lbl:SetDark(true)
        return
    end

    panel:Help("C:U Health System - Admin Debug")
    panel:Help("All actions affect your own character only.")

    -- SECTION: Body Stats
    panel:Help("--- Body State ---")

    local bloodEntry = panel:TextEntry("Set Blood Volume (-100 to 200)", "200")
    local btnSetBlood = panel:Button("Set Blood Volume")
    btnSetBlood.DoClick = function()
        SendAdminDebug("set_blood", "", tonumber(bloodEntry:GetValue()) or 100)
    end

    local addBloodEntry = panel:TextEntry("Add Blood Amount", "20")
    local btnAddBlood = panel:Button("Add Blood")
    btnAddBlood.DoClick = function()
        SendAdminDebug("add_blood", "", tonumber(addBloodEntry:GetValue()) or 20)
    end

    local btnRemBlood = panel:Button("Remove Blood (same amount)")
    btnRemBlood.DoClick = function()
        SendAdminDebug("remove_blood", "", tonumber(addBloodEntry:GetValue()) or 20)
    end

    local tempEntry = panel:TextEntry("Set Body Temperature (C, 20-45)", "37.0")
    local btnSetTemp = panel:Button("Set Temperature")
    btnSetTemp.DoClick = function()
        SendAdminDebug("set_temperature", "", tonumber(tempEntry:GetValue()) or 37.0)
    end

    local staminaEntry = panel:TextEntry("Set Stamina (0-100)", "100")
    local btnSetStamina = panel:Button("Set Stamina")
    btnSetStamina.DoClick = function()
        SendAdminDebug("set_stamina", "", tonumber(staminaEntry:GetValue()) or 100)
    end

    local painEntry = panel:TextEntry("Set Pain (0-100)", "0")
    local btnSetPain = panel:Button("Set Pain")
    btnSetPain.DoClick = function()
        SendAdminDebug("set_pain", "", tonumber(painEntry:GetValue()) or 0)
    end

    local consEntry = panel:TextEntry("Set Consciousness (0-100)", "100")
    local btnSetCons = panel:Button("Set Consciousness")
    btnSetCons.DoClick = function()
        SendAdminDebug("set_consciousness", "", tonumber(consEntry:GetValue()) or 100)
    end

    local oxyEntry = panel:TextEntry("Set Blood Oxygen (0-100)", "98")
    local btnSetOxy = panel:Button("Set Blood Oxygen")
    btnSetOxy.DoClick = function()
        SendAdminDebug("set_oxygen", "", tonumber(oxyEntry:GetValue()) or 98)
    end

    local hrEntry = panel:TextEntry("Set Heart Rate (BPM)", "70")
    local btnSetHR = panel:Button("Set Heart Rate")
    btnSetHR.DoClick = function()
        SendAdminDebug("set_heartrate", "", tonumber(hrEntry:GetValue()) or 70)
    end

    -- SECTION: Stop All Bleeding
    panel:Help("--- Bleeding ---")

    local btnStopAll = panel:Button("Stop All Bleeding (all limbs)")
    btnStopAll.DoClick = function()
        SendAdminDebug("stop_limb_bleed", "all", 0)
    end

    -- SECTION: Full Heal
    panel:Help("--- Full Heal ---")

    local btnFullHeal = panel:Button("FULL HEAL (reset everything)")
    btnFullHeal.DoClick = function()
        SendAdminDebug("full_heal", "", 0)
    end

    -- SECTION: Limb-specific controls
    panel:Help("--- Limb Actions ---")

    -- Limb selector
    local limbCombo = panel:ComboBox("Target Limb", "")
    for _, limbName in ipairs(LIMB_LIST) do
        limbCombo:AddChoice(limbName)
    end
    local selectedLimb = "head"
    function limbCombo:OnSelect(index, value)
        selectedLimb = value
    end

    local dmgEntry = panel:TextEntry("Damage Amount", "30")

    local btnDmg = panel:Button("Damage Selected Limb")
    btnDmg.DoClick = function()
        SendAdminDebug("damage_limb", selectedLimb, tonumber(dmgEntry:GetValue()) or 30)
    end

    local btnHealLimb = panel:Button("Heal Selected Limb")
    btnHealLimb.DoClick = function()
        SendAdminDebug("heal_limb", selectedLimb, 0)
    end

    local btnFracture = panel:Button("Add Fracture")
    btnFracture.DoClick = function()
        SendAdminDebug("set_fracture", selectedLimb, 1)
    end

    local btnUnfracture = panel:Button("Remove Fracture")
    btnUnfracture.DoClick = function()
        SendAdminDebug("set_fracture", selectedLimb, 0)
    end

    local btnDislocate = panel:Button("Add Dislocation")
    btnDislocate.DoClick = function()
        SendAdminDebug("set_dislocation", selectedLimb, 1)
    end

    local btnRelocate = panel:Button("Remove Dislocation")
    btnRelocate.DoClick = function()
        SendAdminDebug("set_dislocation", selectedLimb, 0)
    end

    local btnDismember = panel:Button("Dismember Limb")
    btnDismember.DoClick = function()
        SendAdminDebug("set_dismember", selectedLimb, 1)
    end

    local btnRestoreLimb = panel:Button("Restore Limb (un-dismember)")
    btnRestoreLimb.DoClick = function()
        SendAdminDebug("set_dismember", selectedLimb, 0)
    end

    -- SECTION: Shrapnel
    panel:Help("--- Shrapnel ---")

    local shrapEntry = panel:TextEntry("Shrapnel Amount", "1")

    local btnAddShrap = panel:Button("Add Shrapnel to Selected Limb")
    btnAddShrap.DoClick = function()
        SendAdminDebug("add_shrapnel", selectedLimb, tonumber(shrapEntry:GetValue()) or 1)
    end

    local btnRemShrap = panel:Button("Remove All Shrapnel from Selected Limb")
    btnRemShrap.DoClick = function()
        SendAdminDebug("remove_shrapnel", selectedLimb, 0)
    end

    -- SECTION: Bleeding per-limb
    panel:Help("--- Per-Limb Bleeding ---")

    local bleedEntry = panel:TextEntry("Bleed Rate to Add", "50")

    local btnAddBleed = panel:Button("Add Bleeding to Selected Limb")
    btnAddBleed.DoClick = function()
        SendAdminDebug("add_limb_bleed", selectedLimb, tonumber(bleedEntry:GetValue()) or 50)
    end

    local btnStopBleed = panel:Button("Stop Bleeding in Selected Limb")
    btnStopBleed.DoClick = function()
        SendAdminDebug("stop_limb_bleed", selectedLimb, 0)
    end
end

hook.Add("PopulateToolMenu", "WoundSystem_OptionsMenu", function()
    spawnmenu.AddToolMenuOption("Options", "doggo's addons", "WoundSystem_Client", "C:U Health System - Client", "", "", BuildClientPanel)
    spawnmenu.AddToolMenuOption("Options", "doggo's addons", "WoundSystem_Server", "C:U Health System - Server", "", "", BuildServerPanel)
    spawnmenu.AddToolMenuOption("Options", "doggo's addons", "WoundSystem_AdminDebug", "C:U Health System - Admin Debug", "", "", BuildAdminDebugPanel)
end)
