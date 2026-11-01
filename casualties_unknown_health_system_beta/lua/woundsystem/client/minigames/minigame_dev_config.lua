-- Developer-only minigame settings (not exposed as convars)
-- Edit values here during development. This file is included client-side by minigames.
local cfg = {
    bandageHandOffsetX = 100,
    bandageHandOffsetY = 400,
    aedHandOffsetX = 100,
    aedHandOffsetY = 400,
    shrapnelHandOffsetX = 100,
    shrapnelHandOffsetY = 600,

    -- Optional dislocation overrides. Leave keys commented/absent to use
    -- DEFAULT_CONFIG in cl_dislocation.lua.
    dislocation = {
        -- Scale = 0.95,
        -- CenterOffsetX = 0,
        -- CenterOffsetY = 0,
        -- BoneBaseWidth = 138,
        -- BoneBaseHeight = 81,
        -- BoneBaseOffsetX = 0,
        -- BoneBaseOffsetY = 0,
        -- BoneBaseRotation = 0,
        -- BoneGhostWidth = 305,
        -- BoneGhostHeight = 89,
        -- BoneMoveWidth = 323,
        -- BoneMoveHeight = 120,
        -- BoneMoveOffsetX = 0,
        -- BoneMoveOffsetY = 0,
        -- BoneHitboxWidthFactor = 1, -- 1 = full BoneMoveWidth, 0.5 = half width
        -- BoneHitboxHeightFactor = 1, -- 1 = full BoneMoveHeight, 0.5 = half height
        -- HandWidth = 512,
        -- HandHeight = 1260,
        -- HandScale = 1,
        -- HandOffsetX = 160,
        -- HandOffsetY = 200,
        -- HandHitOffsetX = 0,
        -- HandHitOffsetY = 0
    }
}

return cfg
