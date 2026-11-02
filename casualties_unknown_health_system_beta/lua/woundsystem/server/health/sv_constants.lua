WoundSystem = WoundSystem or {}
WoundSystem.Health = WoundSystem.Health or {}

local Constants = WoundSystem.Health.Constants or {}
WoundSystem.Health.Constants = Constants

Constants.InventorySlots = 5
Constants.LimbSyncEpsilon = 0.05
Constants.BandageDurabilityPerWrap = 2
Constants.BandageInputTimeout = 30
Constants.SyringeDurabilityPerSecond = 18
Constants.SyringeInputTimeout = 1.5
Constants.SyringeInputHz = 20
Constants.AedSessionTimeout = 45
Constants.BloodVomitThreshold = 15
Constants.BloodVomitWarningTime = 5
Constants.FurBloodGainPerSecond = 0.2 * 0.007 * 60
Constants.FurBloodDryPerSecond = 0.00066666666 * 60
Constants.FurBloodMax = 10
Constants.FurBloodRegions = {"head", "torso", "leftArm", "rightArm", "leftLeg", "rightLeg"}
Constants.FurBloodRegionByLimb = {
    head = "head",
    thorax = "torso",
    abdomen = "torso",
    arm_L = "leftArm",
    forearm_L = "leftArm",
    hand_L = "leftArm",
    arm_R = "rightArm",
    forearm_R = "rightArm",
    hand_R = "rightArm",
    thigh_L = "leftLeg",
    crus_L = "leftLeg",
    foot_L = "leftLeg",
    thigh_R = "rightLeg",
    crus_R = "rightLeg",
    foot_R = "rightLeg"
}

Constants.DislocationFinishX = 421.82
Constants.DislocationFinishY = 229.82
Constants.DislocationStartSpread = 5
Constants.DislocationBoneDrag = 6
Constants.DislocationBoneMoveMult = 1.5
Constants.DislocationHitMinHandSpeed = 4
Constants.DislocationHitMaxBoneSpeed = 60
Constants.DislocationHitHalfW = 90
Constants.DislocationHitHalfH = 55
Constants.DislocationPainBlock = 75
Constants.DislocationSuccessTimer = 3
Constants.DislocationInputTimeout = 1.5

-- RU: expanded damage perception range (Z-City bridge) - lower thresholds, higher sensitivity
Constants.DamagePerceptionRangeMult = 1.45
Constants.GlassShardFinishX = 421.82
Constants.GlassShardFinishY = 229.82
Constants.GlassPainBlock = 75
Constants.GlassFallPainFloor = 28
Constants.FallbackWorldTools = { "BRUISE KIT", "DISINFECTANT", "GAUZE", "INJECTION", "AED" }
Constants.ForceWorldAedSpawns = false
Constants.RagdollWakeBridgeDuration = 0.55
Constants.RagdollWakeCollisionGraceDuration = 1.1
Constants.RagdollWakeCollisionGracePoll = 0.1
Constants.LimbTimerName = "WoundSystem_LimbTick"
Constants.CardioTimerName = "WoundSystem_CardioTick"
Constants.MedicalSessionTimerName = "WoundSystem_MedicalSessionTick"
