-- PrettyUI provides the game's standard controls and Alt-drag panel movement.
local UI = {}
UI.__index = UI

local TEXT_COLOR = 0xD8E2EBFF
local FLASH_COLOR = 0xFFD966FF
local POSITION_SAVE_DELAY_UPDATES = 10 -- client updates: save after movement settles

-- The client can clear plugin settings children before the next ready event.
local function isViewAttached(view)
    if not view or not view.root then return false end
    local ok, attached = pcall(function() return view.root.parent ~= nil end)
    return ok and attached
end

function UI.new(prettyUi, settings, metronome, callbacks)
    assert(prettyUi, "Metronome requires PrettyUI (6398181)")
    return setmetatable({prettyUi = prettyUi, settings = settings, metronome = metronome,
        callbacks = callbacks, flashUpdatesRemaining = 0}, UI)
end

function UI:destroyView(name)
    local view = self[name]
    self[name] = nil
    if view then
        -- Still invoke the library cleanup when the client has removed its root.
        local ok, err = pcall(view.Destroy, view)
        if not ok then log("Metronome: UI cleanup: " .. tostring(err)) end
    end
end

function UI:destroyOverlay()
    self:readOverlayPosition()
    self:saveOverlayPosition()
    self:destroyView("overlay")
    self.counter = nil
    self.overlayParent = nil
    self.flashUpdatesRemaining = 0
    self.positionX, self.positionY, self.updatesSinceMove = nil, nil, nil
end

function UI:readOverlayPosition()
    if not isViewAttached(self.overlay) then return end
    local x, y = self.overlay.root.x, self.overlay.root.y
    if x ~= self.positionX or y ~= self.positionY then
        self.positionX, self.positionY = x, y
        self.updatesSinceMove = 0
    end
end

function UI:saveOverlayPosition()
    if self.positionX == nil then return end
    -- Automatic persistence must never prevent view or audio cleanup.
    local ok, err = pcall(self.settings.saveOverlayPosition, self.settings, self.positionX, self.positionY)
    if not ok and not self.positionSaveWarned then
        self.positionSaveWarned = true
        log("Metronome: Could not save overlay position: " .. tostring(err))
    end
end

function UI:updateOverlay(parent)
    self:readOverlayPosition()
    if not self.settings:get("showCounter") then parent = nil end
    if self.overlay and (parent ~= self.overlayParent or not isViewAttached(self.overlay)) then
        self:destroyOverlay()
    end
    if not parent or self.overlay then return end
    self.overlayParent = parent
    self.overlay = self.prettyUi.Panel.new(parent, {
        x = self.settings:get("overlayX"), y = self.settings:get("overlayY"),
        width = 240, height = 112,
        backgroundAlpha = 0.85, popout = false, scrollable = false,
        layout = {startY = 8, paddingLeft = 12, paddingRight = 12, rowGap = 5},
    })
    local title = self.overlay:AddText({text = "Metronome", height = 24, colour = FLASH_COLOR})
    self.counter = self.overlay:AddText({text = "", height = 28, colour = TEXT_COLOR})
    local hint = self.overlay:AddText({text = "Option/Alt + drag to move", height = 20, colour = TEXT_COLOR})
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
    if not isViewAttached(self.overlay) then return end
    if not self.settings:get("enabled") then
        self.counter.content = "Paused"
    elseif self.metronome.count == 0 then
        self.counter.content = "Waiting for tick"
    else
        local suffix = self.metronome.count == self.metronome.tickCount and "  BEAT" or ""
        self.counter.content = self.metronome.count .. " / " .. self.metronome.tickCount .. suffix
    end
    self.counter.rgba = self.flashUpdatesRemaining > 0 and FLASH_COLOR or TEXT_COLOR
end

function UI:flashCounter()
    self.flashUpdatesRemaining = 8 -- 8 client updates at 50 Hz, used only for the visual flash.
    self:refreshCounter()
end

function UI:updateFrame()
    if self.updatesSinceMove ~= nil and self.updatesSinceMove < POSITION_SAVE_DELAY_UPDATES then
        self.updatesSinceMove = self.updatesSinceMove + 1
        if self.updatesSinceMove == POSITION_SAVE_DELAY_UPDATES then self:saveOverlayPosition() end
    end
    if self.flashUpdatesRemaining <= 0 then return end
    self.flashUpdatesRemaining = self.flashUpdatesRemaining - 1
    if self.flashUpdatesRemaining == 0 then self:refreshCounter() end
end

function UI:showSettings(parent)
    self:destroyView("settingsView")
    self.controls = nil
    if not parent then return end
    local view = self.prettyUi.SimpleView.new(parent, {
        width = 0, height = 0, widthAnchor = 1, heightAnchor = 1,
        layout = {startY = 12, paddingLeft = 14, paddingRight = 14, rowGap = 8},
    })
    self.settingsView = view
    self.controls = {}
    view:AddText({text = "Metronome", height = 28, colour = FLASH_COLOR})
    view:AddText({text = "by moishe6669", height = 24, colour = TEXT_COLOR})
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
    self.gameVolumeLabel = view:AddText({text = "", height = 40})
    view:AddText({text = "Hold Option/Alt and drag to move. Position is saved automatically.", height = 48})
    view:AddText({text = "Clicks pass through the counter. Use Enable metronome above to pause/resume.", height = 48})
    view:AddSimpleButton("Reset count", self.callbacks.resetCount, {height = 28})
    self:refreshControls()
end

function UI:refreshControls()
    if not self.settings:get("enabled") or self.metronome.count == 0 then self.flashUpdatesRemaining = 0 end
    self:refreshCounter()
    if not isViewAttached(self.settingsView) then return end
    self.gameVolumeLabel.content = self.callbacks.getGameVolumeText()
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
    self:destroyView("settingsView")
    self.controls = nil
    self.checkboxes = nil
    self.gameVolumeLabel = nil
end

return UI
