WoundSystem = WoundSystem or {}
WoundSystem.RagdollVisuals = WoundSystem.RagdollVisuals or {}

function WoundSystem.RagdollVisuals.IsRagdollEntity(ent)
    if not IsValid(ent) then return false end
    local className = ent:GetClass()
    return className == "prop_ragdoll" or className == "hl2mp_ragdoll"
end

function WoundSystem.RagdollVisuals.VectorSame(a, b)
    if not a or not b then return false end
    return math.abs((a.x or 0) - (b.x or 0)) <= 0.0001
        and math.abs((a.y or 0) - (b.y or 0)) <= 0.0001
        and math.abs((a.z or 0) - (b.z or 0)) <= 0.0001
end

function WoundSystem.RagdollVisuals.ColorSame(a, b)
    if not a or not b then return false end
    return (a.r or 0) == (b.r or 0)
        and (a.g or 0) == (b.g or 0)
        and (a.b or 0) == (b.b or 0)
        and (a.a or 255) == (b.a or 255)
end

function WoundSystem.RagdollVisuals.ApplyColorMethods(ent, playerColor, weaponColor)
    if not IsValid(ent) then return end

    if playerColor then
        ent.WoundSystemPlayerColor = playerColor
        if ent.SetPlayerColor then
            ent:SetPlayerColor(playerColor)
        end
        ent.GetPlayerColor = function()
            return playerColor
        end
    end

    if weaponColor then
        ent.WoundSystemWeaponColor = weaponColor
        if ent.SetWeaponColor then
            ent:SetWeaponColor(weaponColor)
        end
        ent.GetWeaponColor = function()
            return weaponColor
        end
    end
end

function WoundSystem.RagdollVisuals.ApplyNetworked(ent)
    if not IsValid(ent) or not ent:GetNWBool("WoundSystemHasRagdollVisuals", false) then return end

    WoundSystem.RagdollVisuals.ApplyColorMethods(
        ent,
        ent:GetNWVector("WoundSystemPlayerColor", Vector(1, 1, 1)),
        ent:GetNWVector("WoundSystemWeaponColor", Vector(1, 1, 1))
    )
end

if SERVER then
    function WoundSystem.RagdollVisuals.CopyBodygroupsAndMaterials(ply, ragdoll)
        if not IsValid(ply) or not IsValid(ragdoll) then return end

        if ply.GetSkin and ragdoll.SetSkin then
            local skin = ply:GetSkin()
            if not ragdoll.GetSkin or ragdoll:GetSkin() ~= skin then
                ragdoll:SetSkin(skin)
            end
        end

        if ply.GetNumBodyGroups and ply.GetBodygroup and ragdoll.SetBodygroup then
            for i = 0, ply:GetNumBodyGroups() - 1 do
                local bodygroup = ply:GetBodygroup(i)
                if not ragdoll.GetBodygroup or ragdoll:GetBodygroup(i) ~= bodygroup then
                    ragdoll:SetBodygroup(i, bodygroup)
                end
            end
        end

        if ply.GetMaterial and ragdoll.SetMaterial then
            local materialName = ply:GetMaterial() or ""
            if not ragdoll.GetMaterial or (ragdoll:GetMaterial() or "") ~= materialName then
                ragdoll:SetMaterial(materialName)
            end
        end

        if ply.GetColor and ragdoll.SetColor then
            local color = ply:GetColor()
            if not ragdoll.GetColor or not WoundSystem.RagdollVisuals.ColorSame(ragdoll:GetColor(), color) then
                ragdoll:SetColor(color)
            end
        end

        if ply.GetRenderMode and ragdoll.SetRenderMode then
            local renderMode = ply:GetRenderMode()
            if not ragdoll.GetRenderMode or ragdoll:GetRenderMode() ~= renderMode then
                ragdoll:SetRenderMode(renderMode)
            end
        end

        if ply.GetRenderFX and ragdoll.SetRenderFX then
            local renderFX = ply:GetRenderFX()
            if not ragdoll.GetRenderFX or ragdoll:GetRenderFX() ~= renderFX then
                ragdoll:SetRenderFX(renderFX)
            end
        end

        if ply.GetMaterials and ply.GetSubMaterial and ragdoll.SetSubMaterial then
            for i = 0, #ply:GetMaterials() - 1 do
                local subMaterial = ply:GetSubMaterial(i) or ""
                if not ragdoll.GetSubMaterial or (ragdoll:GetSubMaterial(i) or "") ~= subMaterial then
                    ragdoll:SetSubMaterial(i, subMaterial)
                end
            end
        end
    end

    function WoundSystem.RagdollVisuals.CopyFromPlayer(ply, ragdoll)
        if not IsValid(ply) or not IsValid(ragdoll) then return end

        local playerColor = ply.GetPlayerColor and ply:GetPlayerColor() or Vector(1, 1, 1)
        local weaponColor = ply.GetWeaponColor and ply:GetWeaponColor() or Vector(1, 1, 1)

        WoundSystem.RagdollVisuals.CopyBodygroupsAndMaterials(ply, ragdoll)
        WoundSystem.RagdollVisuals.ApplyColorMethods(ragdoll, playerColor, weaponColor)

        if not ragdoll:GetNWBool("WoundSystemHasRagdollVisuals", false) then
            ragdoll:SetNWBool("WoundSystemHasRagdollVisuals", true)
        end

        if not WoundSystem.RagdollVisuals.VectorSame(ragdoll:GetNWVector("WoundSystemPlayerColor", Vector(1, 1, 1)), playerColor) then
            ragdoll:SetNWVector("WoundSystemPlayerColor", playerColor)
        end

        if not WoundSystem.RagdollVisuals.VectorSame(ragdoll:GetNWVector("WoundSystemWeaponColor", Vector(1, 1, 1)), weaponColor) then
            ragdoll:SetNWVector("WoundSystemWeaponColor", weaponColor)
        end
    end
else
    function WoundSystem.RagdollVisuals.RefreshExisting()
        for _, className in ipairs({"prop_ragdoll", "hl2mp_ragdoll"}) do
            for _, ent in ipairs(ents.FindByClass(className)) do
                WoundSystem.RagdollVisuals.ApplyNetworked(ent)
            end
        end
    end

    hook.Add("OnEntityCreated", "WoundSystem_RagdollVisualParity", function(ent)
        if not WoundSystem.RagdollVisuals.IsRagdollEntity(ent) then return end

        timer.Simple(0, function()
            WoundSystem.RagdollVisuals.ApplyNetworked(ent)
        end)
        timer.Simple(0.25, function()
            WoundSystem.RagdollVisuals.ApplyNetworked(ent)
        end)
        timer.Simple(1, function()
            WoundSystem.RagdollVisuals.ApplyNetworked(ent)
        end)
        timer.Simple(2.5, function()
            WoundSystem.RagdollVisuals.ApplyNetworked(ent)
        end)
    end)

    hook.Add("InitPostEntity", "WoundSystem_RagdollVisualParityInitial", function()
        timer.Simple(1, function()
            WoundSystem.RagdollVisuals.RefreshExisting()
        end)
    end)
end
