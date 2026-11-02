-- C:U BLOOD EFFECTS DISABLED — server decorative trails/pools removed per request
-- Stub keeps WoundSystem.BloodEffects table so sv_health call sites remain valid (they guard with if, but we provide no-op)
WoundSystem = WoundSystem or {}
WoundSystem.BloodEffects = WoundSystem.BloodEffects or {}
WoundSystem.ServerBloodEffects = WoundSystem.ServerBloodEffects or {}
WoundSystem.ServerBloodEffects._Loaded = true

pcall(function() timer.Remove("WoundSystem_BloodEffectTrails") end)

function WoundSystem.BloodEffects.Emit(pos, normal, severity, kind, recipients, attachedEnt, limbId) end
function WoundSystem.BloodEffects.EmitGround(pos, severity, kind, ignore, recipients) end
