-- WoundSystem Weather Compatibility
-- Supports: StormFox 2, GWeather, GStorms
--
-- Reads ambient temperature and rain/snow from whichever weather addon
-- is active and feeds it into the WoundSystem body temperature tick.
--
-- sv_health.lua calls WoundSystem.GetAmbientTemperature() for the ambient
-- Celsius value that body temperature lerps toward.
--
-- Priority: StormFox2 > GWeather > GStorms > default (23.5 C)

if not SERVER then return end

WoundSystem = WoundSystem or {}

local _ambientTemp   = 23.5
local _precipitation = 0
local _lastUpdate    = -999
local UPDATE_INTERVAL = 3

-- -----------------------------------------------------------------------
-- Per-addon readers: return (tempC, precip 0..1) or nil
-- -----------------------------------------------------------------------
local function ReadStormFox2()
    if not StormFox2 then return nil end
    if not (StormFox2.Temperature and StormFox2.Temperature.Get) then return nil end
    local ok, temp = pcall(StormFox2.Temperature.Get, "celsius")
    if not ok or type(temp) ~= "number" or temp ~= temp then return nil end
    local precip = 0
    if StormFox2.Weather then
        if StormFox2.Weather.GetRainAmount then
            local ok2, amt = pcall(StormFox2.Weather.GetRainAmount)
            if ok2 and type(amt) == "number" then precip = math.Clamp(amt, 0, 1) end
        elseif StormFox2.Weather.IsRaining then
            local ok2, raining = pcall(StormFox2.Weather.IsRaining)
            if ok2 and raining then precip = 0.6 end
        end
    end
    return math.Clamp(temp, -60, 60), precip
end

local function ReadGWeather()
    if not gWeather then return nil end
    if not (gWeather.GetTemperature and gWeather.Atmosphere) then return nil end
    local ok, temp = pcall(gWeather.GetTemperature, gWeather)
    if not ok or type(temp) ~= "number" or temp ~= temp then return nil end
    local precip = 0
    if gWeather.GetPrecipitation then
        local ok2, p = pcall(gWeather.GetPrecipitation, gWeather)
        if ok2 and type(p) == "number" then precip = math.Clamp(p, 0, 1) end
    end
    return math.Clamp(temp, -60, 60), precip
end

local function ReadGStorms()
    if not gs_env then return nil end
    local env = gs_env.server
    if not env or not env.Networked then return nil end
    local temp = env.Temperature
    if type(temp) ~= "number" or temp ~= temp then return nil end
    local precip = 0
    if GetGlobalBool and GetGlobalBool("gs_is_snowing", false) then
        precip = 0.6
    elseif gs_weatherEntityList and gs_weatherEntityList.server then
        for _, ent in ipairs(gs_weatherEntityList.server) do
            if IsValid(ent) and ent.Networked and ent.EnableRain then
                precip = math.max(precip, math.Clamp(ent.StormPrecipitationMultiplier or 0.5, 0, 1))
                break
            end
        end
    end
    return math.Clamp(temp, -60, 60), precip
end

-- -----------------------------------------------------------------------
-- Poll (every UPDATE_INTERVAL seconds)
-- -----------------------------------------------------------------------
hook.Add("Think", "WoundSystem_WeatherCompat_Poll", function()
    local now = CurTime()
    if now - _lastUpdate < UPDATE_INTERVAL then return end
    _lastUpdate = now

    local temp, precip
    temp, precip = ReadStormFox2()
    if not temp then temp, precip = ReadGWeather() end
    if not temp then temp, precip = ReadGStorms() end
    _ambientTemp   = temp   or 23.5
    _precipitation = precip or 0
end)

-- -----------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------
function WoundSystem.GetAmbientTemperature()
    return _ambientTemp
end

function WoundSystem.GetWeatherPrecipitation()
    return _precipitation
end

-- -----------------------------------------------------------------------
-- Rain wetness: add wetness to outdoor players when it is raining/snowing
-- -----------------------------------------------------------------------
local RAIN_WETNESS_RATE = 8   -- points/sec at full precipitation
local RAIN_WETNESS_MAX  = 80  -- cap so sweating still contributes

hook.Add("Think", "WoundSystem_WeatherCompat_Wetness", function()
    if _precipitation <= 0.01 then return end
    if not BodyState then return end
    local dt = FrameTime()
    if dt <= 0 then return end
    local add = _precipitation * RAIN_WETNESS_RATE * dt
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local body = BodyState[ply]
        if not body then continue end
        if ply:WaterLevel() >= 2 then continue end  -- already handled by sv_health
        -- Outdoor check: trace 512u straight up; if blocked they are under a roof
        local tr = util.TraceLine({
            start  = ply:GetPos() + Vector(0, 0, 32),
            endpos = ply:GetPos() + Vector(0, 0, 512),
            filter = ply, mask = MASK_SOLID_BRUSHONLY
        })
        if tr.Hit then continue end
        body.wetness = math.Clamp((body.wetness or 0) + add, 0, RAIN_WETNESS_MAX)
    end
end)

-- -----------------------------------------------------------------------
-- Admin concommand: woundsys_set_ambient_temp <celsius|auto>
-- -----------------------------------------------------------------------
local _override = nil
local _baseGetTemp = WoundSystem.GetAmbientTemperature
function WoundSystem.GetAmbientTemperature()
    if _override ~= nil then return _override end
    return _baseGetTemp()
end

concommand.Add("woundsys_set_ambient_temp", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local arg = args[1]
    if not arg or string.lower(arg) == "auto" then
        _override = nil
        local m = "[WoundSystem] Ambient temp override cleared."
        if IsValid(ply) then ply:ChatPrint(m) else print(m) end
        return
    end
    local val = tonumber(arg)
    if val then
        _override = math.Clamp(val, -60, 60)
        local m = string.format("[WoundSystem] Ambient temp locked to %.1f C.", _override)
        if IsValid(ply) then ply:ChatPrint(m) else print(m) end
    end
end, nil, "Lock WoundSystem ambient temp. Usage: woundsys_set_ambient_temp <celsius|auto>")
