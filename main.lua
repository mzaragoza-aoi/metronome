local Settings = require("src/settings")
local Metronome = require("src/metronome")
local Sound = require("src/sound")
local UI = require("src/ui")

local EVENT_ID = "metronome"
local settings = Settings.new(PersistentDB)
local metronome = Metronome.new(settings.values)
-- Custom resource playback is disabled for beta-client compatibility.
local sound = Sound.new(audio, {tick = 36970, tock = 36966}, log, game and game.options)
local pluginUi
local isShutdown = false
-- Startup can occur while already logged in, before a GameStateChanged event.
local isInGame = Player.IsAvailable()

local function resetCount()
    metronome:resetCount()
    sound:stopPlayback()
    pluginUi:refreshControls()
end

pluginUi = UI.new(prettyui, settings, metronome, {
    resetCount = resetCount,
    getGameVolumeText = function() return sound:getGameVolumeText() end,
})

settings.onChange = function()
    metronome:applySettings(settings.values)
    sound:stopPlayback()
    pluginUi:refreshControls()
end

-- All timing comes from received server ticks. Never synthesize missed beats.
Event.ServerLogic.Subscribe(EVENT_ID, function()
    if not isInGame or not Player.IsAvailable() then
        resetCount()
        return
    end
    local beat = metronome:onServerTick()
    sound:playBeat(beat)
    if settings:get("enabled") then pluginUi:flashCounter() end
end)

-- Client updates only mount the overlay and fade its brief visual pulse.
Event.Logic.Subscribe(EVENT_ID, function()
    local parent
    if isInGame and Player.IsAvailable() and settings:get("showCounter") then
        parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end
    pluginUi:updateOverlay(parent)
    pluginUi:updateFrame()
end)

Event.GameStateChanged.Subscribe(EVENT_ID, function(event)
    isInGame = event.newState == GameState.GAME
    metronome:resetCount()
    sound:stopPlayback()
    if not isInGame then pluginUi:shutdown() else pluginUi:refreshControls() end
end)

Event.SettingsLayerReady.Subscribe(EVENT_ID, function(event)
    pluginUi:showSettings(event.component)
end)

function PluginShutdown()
    if isShutdown then return end
    isShutdown = true
    Event.ServerLogic.Unsubscribe(EVENT_ID)
    Event.Logic.Unsubscribe(EVENT_ID)
    Event.GameStateChanged.Unsubscribe(EVENT_ID)
    Event.SettingsLayerReady.Unsubscribe(EVENT_ID)
    settings.onChange = nil
    pluginUi:shutdown()
    sound:shutdown()
    metronome:resetCount()
    log("Metronome stopped.")
end

log("Metronome v0.0.1 loaded. Open its Plugin Hub settings to configure.")
