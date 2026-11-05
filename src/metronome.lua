-- Count server ticks and choose the sound for each beat.
local Metronome = {}
Metronome.__index = Metronome

function Metronome.new(settings)
    local self = setmetatable({}, Metronome)
    self:resetCount()
    self:applySettings(settings)
    return self
end

function Metronome:resetCount()
    self.count = 0
    self.nextSound = "tick"
end

function Metronome:applySettings(settings)
    if self.tickCount ~= settings.tickCount or self.enabled ~= settings.enabled then
        self:resetCount()
    end
    -- Enabling or disabling alternation starts with the tick sound.
    if ((self.tockVolume or 0) > 0) ~= (settings.tockVolume > 0) then
        self.nextSound = "tick"
    end
    self.enabled = settings.enabled
    self.tickCount = settings.tickCount
    self.tickVolume = settings.tickVolume
    self.tockVolume = settings.tockVolume
end

function Metronome:onServerTick()
    if not self.enabled then return nil end
    self.count = self.count % self.tickCount + 1
    if self.count ~= self.tickCount then return nil end

    local kind = self.tockVolume > 0 and self.nextSound or "tick"
    self.nextSound = kind == "tick" and "tock" or "tick"
    return {kind = kind, volume = kind == "tick" and self.tickVolume or self.tockVolume}
end

return Metronome
