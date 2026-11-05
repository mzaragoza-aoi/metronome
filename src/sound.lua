-- Play built-in sounds; retain only the numeric ID of this plugin's instance.
local Sound = {}
Sound.__index = Sound

function Sound.new(audioApi, soundIds, logMessage, clientOptions)
    return setmetatable({audioApi = audioApi, soundIds = soundIds, logMessage = logMessage,
        clientOptions = clientOptions, reportedErrors = {}}, Sound)
end

function Sound:logPlaybackErrorOnce(kind, reason)
    if self.reportedErrors[kind] then return end
    self.reportedErrors[kind] = true
    self.logMessage("Metronome: cannot play built-in " .. kind .. " sound (ID " ..
        tostring(self.soundIds[kind]) .. "): " .. reason)
end

function Sound:stopPlayback()
    if self.currentSoundInstanceId then
        local instanceId = self.currentSoundInstanceId
        self.currentSoundInstanceId = nil
        -- A one-shot may have finished already. Stop by ID tolerates defunct instances.
        self.audioApi.Stop(instanceId)
    end
end

function Sound:playBeat(beat)
    if not beat or beat.volume <= 0 then return false, "Plugin volume is zero." end
    local soundId = self.soundIds[beat.kind]
    if math.type(soundId) ~= "integer" then
        local reason = "No built-in sound ID is configured."
        self:logPlaybackErrorOnce(beat.kind, reason)
        return false, reason
    end
    self:stopPlayback()
    local ok, instanceId = pcall(function()
        local playbackParams = self.audioApi.SoundPlaybackParams.new()
        playbackParams.type = self.audioApi.SoundType.SCRIPT
        playbackParams.audioBus = self.audioApi.AudioBus.SFX
        playbackParams.emitterShape = self.audioApi.EmitterShape.NONE
        playbackParams.numLoops = 0
        playbackParams.delayTick = 0
        playbackParams.volume = beat.volume / 100
        local instance = self.audioApi.Play(soundId, playbackParams)
        return instance and instance.id
    end)
    if ok and math.type(instanceId) == "integer" then
        self.currentSoundInstanceId = instanceId
        return true
    end
    local reason = ok and "The client did not return a sound instance ID." or tostring(instanceId)
    self:logPlaybackErrorOnce(beat.kind, reason)
    return false, reason
end

local function readVolumePercent(options, name)
    local ok, current, maximum = pcall(function()
        local option = options and options[name]
        if option then return option.setting, option.max end
    end)
    if not ok or type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
        return nil
    end
    return math.max(0, math.min(100, current / maximum * 100))
end

function Sound:getGameVolumeLevels()
    return readVolumePercent(self.clientOptions, "VolumeMaster"),
        readVolumePercent(self.clientOptions, "VolumeMainEffects")
end

function Sound:getGameVolumeText()
    local master, effects = self:getGameVolumeLevels()
    local function formatPercent(value)
        return value and (math.floor(value + 0.5) .. "%") or "unavailable"
    end
    return "Game audio: master " .. formatPercent(master) .. ", sound effects " .. formatPercent(effects) .. "."
end

function Sound:shutdown()
    self:stopPlayback()
end

return Sound
