-- Pure state machine: one step equals one received server tick.
local Metronome = {}
Metronome.__index = Metronome

function Metronome.new(values)
    local self = setmetatable({}, Metronome)
    self:reset()
    self:configure(values)
    return self
end

function Metronome:reset()
    self.count = 0
    self.nextKind = "tick"
end

function Metronome:configure(values)
    if self.tickCount ~= values.tickCount or self.enabled ~= values.enabled then
        self:reset()
    end
    -- Enabling or disabling alternation starts with the tick sound.
    if ((self.tockVolume or 0) > 0) ~= (values.tockVolume > 0) then
        self.nextKind = "tick"
    end
    self.enabled = values.enabled
    self.tickCount = values.tickCount
    self.tickVolume = values.tickVolume
    self.tockVolume = values.tockVolume
end

function Metronome:step()
    if not self.enabled then return nil end
    self.count = self.count % self.tickCount + 1
    if self.count ~= self.tickCount then return nil end

    local kind = self.tockVolume > 0 and self.nextKind or "tick"
    self.nextKind = kind == "tick" and "tock" or "tick"
    return {kind = kind, volume = kind == "tick" and self.tickVolume or self.tockVolume}
end

return Metronome
