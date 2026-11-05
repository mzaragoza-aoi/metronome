local Settings = require("src/settings")
local Metronome = require("src/metronome")
local Sound = require("src/sound")
local UI = require("src/ui")

local EVENT_ID = "metronome"
local settings = Settings.new(PersistentDB)
local engine = Metronome.new(settings.values)
-- Custom resource playback is disabled for beta-client compatibility.
local sound = Sound.new(audio, {tick = 36970, tock = 36966}, log, game and game.options)
local view
local stopped = false
-- Startup can occur while already logged in, before a GameStateChanged event.
local inGame = Player.IsAvailable()

local function reset()
    engine:reset()
    sound:stop()
    view:refresh()
end

view = UI.new(prettyui, settings, engine, {
    reset = reset,
    audioLevels = function() return sound:describeLevels() end,
})

settings.onChange = function()
    engine:configure(settings.values)
    sound:stop()
    view:refresh()
end

-- All timing comes from received server ticks. Never synthesize missed beats.
Event.ServerLogic.Subscribe(EVENT_ID, function()
    if not inGame or not Player.IsAvailable() then
        reset()
        return
    end
    local beat = engine:step()
    sound:play(beat)
    if settings:get("enabled") then view:pulse() end
end)

-- Client updates only mount the overlay and fade its brief visual pulse.
Event.Logic.Subscribe(EVENT_ID, function()
    local parent
    if inGame and Player.IsAvailable() and settings:get("showCounter") then
        parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end
    view:syncOverlay(parent)
    view:advance()
end)

Event.GameStateChanged.Subscribe(EVENT_ID, function(event)
    inGame = event.newState == GameState.GAME
    engine:reset()
    sound:stop()
    if not inGame then view:shutdown() else view:refresh() end
end)

Event.SettingsLayerReady.Subscribe(EVENT_ID, function(event)
    view:mountSettings(event.component)
end)

function PluginShutdown()
    if stopped then return end
    stopped = true
    Event.ServerLogic.Unsubscribe(EVENT_ID)
    Event.Logic.Unsubscribe(EVENT_ID)
    Event.GameStateChanged.Unsubscribe(EVENT_ID)
    Event.SettingsLayerReady.Unsubscribe(EVENT_ID)
    settings.onChange = nil
    view:shutdown()
    sound:shutdown()
    engine:reset()
    log("Metronome stopped.")
end

log("Metronome v0.0.1 loaded. Open its Plugin Hub settings to configure.")
