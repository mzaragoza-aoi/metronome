-- PrettyUI provides the game's standard controls and Alt-drag panel movement.
local UI = {}
UI.__index = UI

local TEXT = 0xD8E2EBFF
local PULSE = 0xFFD966FF
local POSITION_SAVE_DELAY = 10 -- client updates: save after movement settles

-- The client can clear plugin settings children before the next ready event.
local function alive(view)
    if not view or not view.root then return false end
    local ok, attached = pcall(function() return view.root.parent ~= nil end)
    return ok and attached
end

function UI.new(library, settings, engine, callbacks)
    assert(library, "Metronome requires PrettyUI (6398181)")
    return setmetatable({library = library, settings = settings, engine = engine,
        callbacks = callbacks, flash = 0}, UI)
end

function UI:release(name)
    local view = self[name]
    self[name] = nil
    if view then
        -- Still invoke the library cleanup when the client has removed its root.
        local ok, err = pcall(view.Destroy, view)
        if not ok then log("Metronome: UI cleanup: " .. tostring(err)) end
    end
end

function UI:destroyOverlay()
    self:capturePosition()
    self:savePosition()
    self:release("overlay")
    self.counter = nil
    self.parent = nil
    self.flash = 0
    self.positionX, self.positionY, self.positionAge = nil, nil, nil
end

function UI:capturePosition()
    if not alive(self.overlay) then return end
    local x, y = self.overlay.root.x, self.overlay.root.y
    if x ~= self.positionX or y ~= self.positionY then
        self.positionX, self.positionY = x, y
        self.positionAge = 0
    end
end

function UI:savePosition()
    if self.positionX == nil then return end
    -- Automatic persistence must never prevent view or audio cleanup.
    local ok, err = pcall(self.settings.setPosition, self.settings, self.positionX, self.positionY)
    if not ok and not self.positionSaveWarned then
        self.positionSaveWarned = true
        log("Metronome: Could not save overlay position: " .. tostring(err))
    end
end

function UI:syncOverlay(parent)
    self:capturePosition()
    if not self.settings:get("showCounter") then parent = nil end
    if self.overlay and (parent ~= self.parent or not alive(self.overlay)) then
        self:destroyOverlay()
    end
    if not parent or self.overlay then return end
    self.parent = parent
    self.overlay = self.library.Panel.new(parent, {
        x = self.settings:get("overlayX"), y = self.settings:get("overlayY"),
        width = 240, height = 112,
        backgroundAlpha = 0.85, popout = false, scrollable = false,
        layout = {startY = 8, paddingLeft = 12, paddingRight = 12, rowGap = 5},
    })
    local title = self.overlay:AddText({text = "Metronome", height = 24, colour = PULSE})
    self.counter = self.overlay:AddText({text = "", height = 28, colour = TEXT})
    local hint = self.overlay:AddText({text = "Option/Alt + drag to move", height = 20, colour = TEXT})
    title.clickthrough = true
    self.counter.clickthrough = true
    hint.clickthrough = true

    -- Apply PrettyUI's popout click-through policy to the docked display surface.
    -- Its Alt-drag capture layer is a sibling, so it can still intercept drags.
    local surface = self.overlay.dock
    surface.root.clickthrough = true
    surface.background.clickthrough = true
    surface.container.clickthrough = true
    surface.container.enabled = false
    surface.scroll:SetClickthrough(true)
    self:refreshCounter()
end

function UI:refreshCounter()
    if not alive(self.overlay) then return end
    if not self.settings:get("enabled") then
        self.counter.content = "Paused"
    elseif self.engine.count == 0 then
        self.counter.content = "Waiting for tick"
    else
        local suffix = self.engine.count == self.engine.tickCount and "  BEAT" or ""
        self.counter.content = self.engine.count .. " / " .. self.engine.tickCount .. suffix
    end
    self.counter.rgba = self.flash > 0 and PULSE or TEXT
end

function UI:pulse()
    self.flash = 8 -- 8 client updates at 50 Hz, used only for the visual flash.
    self:refreshCounter()
end

function UI:advance()
    if self.positionAge ~= nil and self.positionAge < POSITION_SAVE_DELAY then
        self.positionAge = self.positionAge + 1
        if self.positionAge == POSITION_SAVE_DELAY then self:savePosition() end
    end
    if self.flash <= 0 then return end
    self.flash = self.flash - 1
    if self.flash == 0 then self:refreshCounter() end
end

function UI:mountSettings(parent)
    self:release("settingsView")
    self.controls = nil
    if not parent then return end
    local view = self.library.SimpleView.new(parent, {
        width = 0, height = 0, widthAnchor = 1, heightAnchor = 1,
        layout = {startY = 12, paddingLeft = 14, paddingRight = 14, rowGap = 8},
    })
    self.settingsView = view
    self.controls = {}
    view:AddText({text = "Metronome", height = 28, colour = PULSE})
    view:AddText({text = "by moishe6669", height = 24, colour = TEXT})
    self.checkboxes = view:AddCheckboxButton({
        {text = "Enable metronome", value = "enabled", selected = self.settings:get("enabled")},
        {text = "Show tick counter", value = "showCounter", selected = self.settings:get("showCounter")},
    }, {onChange = function(_, _, name, selected) self.settings:set(name, selected == true) end})

    for _, field in ipairs({
        {name = "tickCount", label = "Ticks between beats", min = 1},
        {name = "tickVolume", label = "Tick volume", min = 0},
        {name = "tockVolume", label = "Tock volume (0 = no alternation)", min = 0},
    }) do
        local label = view:AddText({text = "", height = 24})
        local slider = view:AddSlider({
            min = field.min, max = 100, step = 1, value = self.settings:get(field.name),
            onChange = function(_, value)
                self.settings:set(field.name, math.floor(value + 0.5))
            end,
        })
        self.controls[field.name] = {label = label, slider = slider, title = field.label}
    end
    view:AddText({text = "Sound source: RuneScape UI clicks", height = 24})
    self.audioLevels = view:AddText({text = "", height = 40})
    view:AddText({text = "Hold Option/Alt and drag to move. Position is saved automatically.", height = 48})
    view:AddText({text = "Clicks pass through the counter. Use Enable metronome above to pause/resume.", height = 48})
    view:AddSimpleButton("Reset count", self.callbacks.reset, {height = 28})
    self:refresh()
end

function UI:refresh()
    if not self.settings:get("enabled") or self.engine.count == 0 then self.flash = 0 end
    self:refreshCounter()
    if not alive(self.settingsView) then return end
    self.audioLevels.content = self.callbacks.audioLevels()
    for _, name in ipairs({"enabled", "showCounter"}) do
        self.checkboxes:SetSelected(name, self.settings:get(name), false)
    end
    for name, control in pairs(self.controls) do
        local value = self.settings:get(name)
        local suffix = name == "tickCount" and " ticks" or "%"
        control.label.content = control.title .. ": " .. value .. suffix
        control.slider:SetValue(value, false)
    end
end

function UI:shutdown()
    self:destroyOverlay()
    self:release("settingsView")
    self.controls = nil
    self.checkboxes = nil
    self.audioLevels = nil
end

return UI
