-- Play built-in sounds; retain only the numeric ID of this plugin's instance.
local Sound = {}
Sound.__index = Sound

function Sound.new(api, soundIDs, logger, clientOptions)
    return setmetatable({api = api, soundIDs = soundIDs, logger = logger,
        clientOptions = clientOptions, warned = {}}, Sound)
end

function Sound:warn(kind, reason)
    if self.warned[kind] then return end
    self.warned[kind] = true
    self.logger("Metronome: cannot play built-in " .. kind .. " sound (ID " ..
        tostring(self.soundIDs[kind]) .. "): " .. reason)
end

function Sound:stop()
    if self.currentID then
        local instanceID = self.currentID
        self.currentID = nil
        -- A one-shot may have finished already. Stop by ID tolerates defunct instances.
        self.api.Stop(instanceID)
    end
end

function Sound:play(beat)
    if not beat or beat.volume <= 0 then return false, "Plugin volume is zero." end
    local soundID = self.soundIDs[beat.kind]
    if math.type(soundID) ~= "integer" then
        local reason = "No built-in sound ID is configured."
        self:warn(beat.kind, reason)
        return false, reason
    end
    self:stop()
    local ok, instanceID = pcall(function()
        local params = self.api.SoundPlaybackParams.new()
        params.type = self.api.SoundType.SCRIPT
        params.audioBus = self.api.AudioBus.SFX
        params.emitterShape = self.api.EmitterShape.NONE
        params.numLoops = 0
        params.delayTick = 0
        params.volume = beat.volume / 100
        local instance = self.api.Play(soundID, params)
        return instance and instance.id
    end)
    if ok and math.type(instanceID) == "integer" then
        self.currentID = instanceID
        return true
    end
    local reason = ok and "The client did not return a sound instance ID." or tostring(instanceID)
    self:warn(beat.kind, reason)
    return false, reason
end

local function volumePercent(options, name)
    local ok, current, maximum = pcall(function()
        local option = options and options[name]
        if option then return option.setting, option.max end
    end)
    if not ok or type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
        return nil
    end
    return math.max(0, math.min(100, current / maximum * 100))
end

function Sound:volumeLevels()
    return volumePercent(self.clientOptions, "VolumeMaster"),
        volumePercent(self.clientOptions, "VolumeMainEffects")
end

function Sound:describeLevels()
    local master, effects = self:volumeLevels()
    local function percent(value)
        return value and (math.floor(value + 0.5) .. "%") or "unavailable"
    end
    return "Game audio: master " .. percent(master) .. ", sound effects " .. percent(effects) .. "."
end

function Sound:shutdown()
    self:stop()
end

return Sound
