if WoundSystem and WoundSystem.Resources and WoundSystem.Resources._Loaded then return end

WoundSystem = WoundSystem or {}

local Resources = WoundSystem.Resources or {}
Resources._Loaded = true
Resources.Added = Resources.Added or {}
WoundSystem.Resources = Resources

local cvResourceDownloads = CreateConVar(
    "woundsys_resource_downloads",
    "0",
    {FCVAR_ARCHIVE, FCVAR_NOTIFY},
    "Force clients to download this addon's custom materials, sounds and fonts with resource.AddFile. Requires a map change/restart after changing.",
    0,
    1
)

local function HasExtension(fileName, extensions)
    local lower = string.lower(fileName or "")

    for _, extension in ipairs(extensions) do
        if string.EndsWith(lower, extension) then
            return true
        end
    end

    return false
end

function Resources.AddFile(path)
    if not path or path == "" or Resources.Added[path] then return end
    if not cvResourceDownloads:GetBool() then return end
    if not resource or not resource.AddFile then return end

    resource.AddFile(path)
    Resources.Added[path] = true
end

function Resources.AddExistingFile(path)
    if not path or path == "" then return end
    if file and file.Exists and not file.Exists(path, "GAME") then return end

    Resources.AddFile(path)
end

function Resources.AddFiles(paths)
    for _, path in ipairs(paths or {}) do
        Resources.AddExistingFile(path)
    end
end

function Resources.AddTree(baseDir, extensions)
    if not file or not file.Find then return end

    local files, dirs = file.Find(baseDir .. "/*", "GAME")

    for _, fileName in ipairs(files or {}) do
        if HasExtension(fileName, extensions) then
            Resources.AddExistingFile(baseDir .. "/" .. fileName)
        end
    end

    for _, dirName in ipairs(dirs or {}) do
        Resources.AddTree(baseDir .. "/" .. dirName, extensions)
    end
end

local ADDON_SOUND_FILES = {
    "sound/aed.ogg",
    "sound/aedanalyze.ogg",
    "sound/aedcharge.ogg",
    "sound/aedfail.ogg",
    "sound/aedstart.ogg",
    "sound/bandage.ogg",
    "sound/boneHit.ogg",
    "sound/bullethit.ogg",
    "sound/click.ogg",
    "sound/glassshard.ogg",
    "sound/heartthump-heavy-monitor.ogg",
    "sound/heartthump-heavy.ogg",
    "sound/heartthump.ogg",
    "sound/menuopen.ogg",
    "sound/miniclick.ogg",
    "sound/pills.ogg",
    "sound/splint.ogg",
    "sound/squelchloop.ogg",
    "sound/syringe.ogg",
    "sound/syringeloop.ogg",
    "sound/tweezeruse.ogg",
    "sound/wrenchhit.ogg"

}

if cvResourceDownloads:GetBool() then
    Resources.AddTree("materials/casunknown-images", { ".png", ".vmt", ".vtf" })
    Resources.AddTree("materials/woundsystem", { ".vmt" })
    Resources.AddTree("shaders/fxc", { ".vcs" })
    Resources.AddTree("resource/fonts", { ".ttf" })
    Resources.AddFiles(ADDON_SOUND_FILES)
end
