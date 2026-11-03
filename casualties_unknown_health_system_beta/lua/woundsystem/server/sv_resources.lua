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
    "sound/bloodvomitwarning.ogg",
    "sound/boneHit.ogg",
    "sound/body/bodyfall1.ogg",
    "sound/body/bodyfall2.ogg",
    "sound/body/bodyfall3.ogg",
    "sound/body/bodyfall4.ogg",
    "sound/body/bodyfall5.ogg",
    "sound/body/BoneBreak1.ogg",
    "sound/body/BoneBreak2.ogg",
    "sound/body/BoneBreak3.ogg",
    "sound/body/death1.ogg",
    "sound/body/death3.ogg",
    "sound/body/death4.ogg",
    "sound/body/deatth5.ogg",
    "sound/body/dislocation.ogg",
    "sound/body/exp10.ogg",
    "sound/body/exp11.ogg",
    "sound/body/exp12.ogg",
    "sound/body/exp13.ogg",
    "sound/body/exp14.ogg",
    "sound/body/exp15.ogg",
    "sound/body/exp16.ogg",
    "sound/body/exp17.ogg",
    "sound/body/exp5.ogg",
    "sound/body/exp6.ogg",
    "sound/body/exp7.ogg",
    "sound/body/exp8.ogg",
    "sound/body/exp9.ogg",
    "sound/body/gore1.ogg",
    "sound/body/gore2.ogg",
    "sound/body/gore3.ogg",
    "sound/body/gore4.ogg",
    "sound/body/gore5.ogg",
    "sound/body/headhit.ogg",
    "sound/body/landheavy1.ogg",
    "sound/body/landheavy2.ogg",
    "sound/body/landmedium1.ogg",
    "sound/body/landsmall1.ogg",
    "sound/body/pain1.ogg",
    "sound/body/warningloop.ogg",
    "sound/bullethit.ogg",
    "sound/click.ogg",
    "sound/criticalloop-unconscious.ogg",
    "sound/criticalloop.ogg",
    "sound/death.ogg",
    "sound/drip/drip11.ogg",
    "sound/drip/drip15.ogg",
    "sound/drip/drip16.ogg",
    "sound/drip/drip17.ogg",
    "sound/drip/drip18.ogg",
    "sound/drip/drip2.ogg",
    "sound/drip/drip20.ogg",
    "sound/drip/drip21.ogg",
    "sound/drip/drip24.ogg",
    "sound/drip/drip3.ogg",
    "sound/drip/drip4.ogg",
    "sound/drip/drip7.ogg",
    "sound/dying.ogg",
    "sound/exhaustedloop.ogg",
    "sound/flatline.ogg",
    "sound/glassshard.ogg",
    "sound/growl1.ogg",
    "sound/growl2.ogg",
    "sound/growl3.ogg",
    "sound/growl4.ogg",
    "sound/growl5.ogg",
    "sound/growl6.ogg",
    "sound/growl7.ogg",
    "sound/growl8.ogg",
    "sound/growl9.ogg",
    "sound/growl10.ogg",
    "sound/growl11.ogg",
    "sound/heartthump-heavy-monitor.ogg",
    "sound/heartthump-heavy.ogg",
    "sound/heartthump.ogg",
    "sound/healthpanel-alert.ogg",
    "sound/isthistheend.ogg",
    "sound/lobotomy.ogg",
    "sound/lobotomy_assets/Lobotomy.ogg",
    "sound/menuopen.ogg",
    "sound/miniclick.ogg",
    "sound/mooddown.ogg",
    "sound/moodup.ogg",
    "sound/music/levelup.ogg",
    "sound/paindrone.ogg",
    "sound/paindroneother.ogg",
    "sound/pant.ogg",
    "sound/pills.ogg",
    "sound/rightclick.ogg",
    "sound/speech.ogg",
    "sound/speechbad.ogg",
    "sound/splint.ogg",
    "sound/squelchloop.ogg",
    "sound/syringe.ogg",
    "sound/syringeloop.ogg",
    "sound/tinnitus.ogg",
    "sound/tweezeruse.ogg",
    "sound/vomit1.ogg",
    "sound/vomit2a.ogg",
    "sound/vomitwarning.ogg",
    "sound/woundon.ogg",
    "sound/wrenchhit.ogg",
    "sound/yawn1.ogg",
    "sound/yawn2.ogg"
}

if cvResourceDownloads:GetBool() then
    Resources.AddTree("materials/casunknown-images", { ".png", ".vmt", ".vtf" })
    Resources.AddTree("materials/woundsystem", { ".vmt" })
    Resources.AddTree("shaders/fxc", { ".vcs" })
    Resources.AddTree("resource/fonts", { ".ttf" })
    Resources.AddFiles(ADDON_SOUND_FILES)
end
