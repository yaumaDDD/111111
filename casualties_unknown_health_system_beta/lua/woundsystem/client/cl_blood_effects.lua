-- C:U BLOOD EFFECTS DISABLED — decorative stains/pools/trails/bodyflow removed per request
-- Original file ~980 lines kept as no-op stub for compatibility (prevents missing net receiver / undefined table errors)
-- All hooks, timers and Decal/Material work stripped because they bugged.
WoundSystem = WoundSystem or {}
WoundSystem.BloodEffects = WoundSystem.BloodEffects or {}
WoundSystem.BloodEffects._Loaded = true

-- Clean up any previous hooks/timers if this file is hot-reloaded over an enabled version
pcall(function() hook.Remove("PostDrawTranslucentRenderables", "WoundSystem_BloodEffects_Draw") end)
pcall(function() hook.Remove("Think", "WoundSystem_BloodEffects_Think") end)
pcall(function() timer.Remove("WoundSystem_BloodEffectTrails_ClientStains") end)

-- No-op public API — other addons may call WoundSystem.BloodEffects.Add
function WoundSystem.BloodEffects.Add() end

-- Install a dead net receiver so server WoundSystem_BloodEffect emits are silently dropped
-- and don't spam “no receiver” warnings. Keep net string pooled via sh_core.
net.Receive("WoundSystem_BloodEffect", function() end)
