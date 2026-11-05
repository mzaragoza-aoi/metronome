-- Saved preferences are isolated to this plugin by the client.
local Settings = {}
Settings.__index = Settings

local defaults = {
    enabled = true,
    tickCount = 1,
    tickVolume = 38,
    tockVolume = 0,
    showCounter = true,
    overlayX = 420,
    overlayY = 80,
}

local function isValidSetting(name, value)
    local default = defaults[name]
    if default == nil or type(value) ~= type(default) then return false end
    if type(default) == "boolean" then return true end
    local minimum = name == "tickCount" and 1 or 0
    local maximum = (name == "overlayX" or name == "overlayY") and 32767 or 100
    return value >= minimum and value <= maximum and value % 1 == 0
end

function Settings.new(database)
    local self = setmetatable({database = database, values = {}}, Settings)
    for name, default in pairs(defaults) do
        local value
        if type(default) == "boolean" then
            value = database:GetBool(name)
        else
            value = database:GetInt(name)
        end
        if not isValidSetting(name, value) then value = default end
        self.values[name] = value
    end
    return self
end

function Settings:get(name)
    return self.values[name]
end

local function saveSetting(self, name, value)
    assert(isValidSetting(name, value), "Invalid metronome setting: " .. tostring(name))
    if self.values[name] == value then return false end
    local saved
    if type(value) == "boolean" then
        saved = self.database:SetBool(name, value)
    else
        saved = self.database:SetInt(name, value)
    end
    assert(saved ~= false, "Could not save metronome setting: " .. name)
    self.values[name] = value
    return true
end

function Settings:set(name, value)
    if not saveSetting(self, name, value) then return end
    if self.onChange then self.onChange(name, value) end
end

function Settings:saveOverlayPosition(x, y)
    assert(isValidSetting("overlayX", x) and isValidSetting("overlayY", y), "Invalid overlay position")
    -- Moving the panel must not trigger playback reconfiguration or stop a beat.
    saveSetting(self, "overlayX", x)
    saveSetting(self, "overlayY", y)
end

return Settings
