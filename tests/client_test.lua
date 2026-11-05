local TestClient = require("tests/support/client")

local function startPlugin(saved)
    local client = TestClient.new(saved)
    dofile("main.lua")
    return client
end

local function getSettingsText(view)
    local lines = {}
    for _, label in ipairs(view.labels) do table.insert(lines, label.content) end
    return table.concat(lines, "\n")
end

test("settings show game audio levels without changing client volumes", function()
    local client = startPlugin({enabled = false})
    game.options.VolumeMaster.setting = 0
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    assert(getSettingsText(client.views[1]):find("master 0%", 1, true))
    assertEqual(game.options.VolumeMaster.setting, 0)
    game.options.VolumeMaster.setting = 128
    game.options.VolumeMainEffects.setting = 0
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    local text = getSettingsText(client.views[2])
    assert(text:find("master 50%", 1, true))
    assert(text:find("sound effects 0%", 1, true))
    assertEqual(game.options.VolumeMaster.setting, 128)
    assertEqual(game.options.VolumeMainEffects.setting, 0)
    assertEqual(#client.played, 0)
    PluginShutdown()
end)

test("settings remain usable when game audio options are unavailable", function()
    local client = TestClient.new()
    game.options = nil
    dofile("main.lua")
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    assert(getSettingsText(client.views[1]):find("master unavailable, sound effects unavailable", 1, true))
    client.views[1].sliders[1]:SetValue(2)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 0)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 1)
    PluginShutdown()
end)

test("client updates never drive audio", function()
    local client = startPlugin()
    for _ = 1, 100 do client:emitEvent("Logic") end
    assertEqual(#client.played, 0)
    client:emitEvent("ServerLogic")
    assertEqual(#client.played, 1); assertEqual(client.played[1].kind, "tick")
    assertEqual(client.played[1].volume, 0.38)
    assertEqual(client.played[1].params.numLoops, 0)
    assertEqual(client.played[1].params.emitterShape, audio.EmitterShape.NONE)
    PluginShutdown()
end)

test("server events obey saved cadence and alternating volumes", function()
    local client = startPlugin({tickCount = 3, tockVolume = 65})
    for _ = 1, 5 do client:emitEvent("ServerLogic") end
    assertEqual(#client.played, 1)
    client:emitEvent("ServerLogic")
    assertEqual(#client.played, 2); assertEqual(client.played[2].kind, "tock")
    assertEqual(client.played[2].volume, 0.65)
    PluginShutdown()
end)

test("zero volume allocates no sound instances", function()
    local client = startPlugin({tickVolume = 0, tockVolume = 50})
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 0)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 1)
    assertEqual(client.played[1].kind, "tock")
    PluginShutdown()
end)

test("game-state transition blocks late ticks and resets alternation", function()
    local client = startPlugin({tockVolume = 50})
    client:emitEvent("Logic"); client:emitEvent("ServerLogic")
    client:emitEvent("GameStateChanged", {newState = GameState.RECONNECTING})
    client:emitEvent("ServerLogic"); client:emitEvent("Logic")
    assertEqual(#client.played, 1); assertEqual(client.played[1].stopped, true)
    assertEqual(client.views[1].destroyed, true)
    client:emitEvent("GameStateChanged", {newState = GameState.GAME})
    client:emitEvent("ServerLogic")
    assertEqual(client.played[2].kind, "tick")
    PluginShutdown()
end)

test("player becomes available after plugin starts in lobby", function()
    local client = TestClient.new()
    client.available = false
    dofile("main.lua")
    client:emitEvent("Logic"); client:emitEvent("ServerLogic")
    assertEqual(#client.played, 0); assertEqual(#client.views, 0)
    client.available = true
    client:emitEvent("GameStateChanged", {newState = GameState.GAME})
    client:emitEvent("Logic"); client:emitEvent("ServerLogic")
    assertEqual(#client.views, 1); assertEqual(#client.played, 1)
    PluginShutdown()
end)

test("overlay parent replacement destroys the old panel", function()
    local client = startPlugin()
    client:emitEvent("Logic")
    client.parent = {name = "replacement"}
    client:emitEvent("Logic")
    assertEqual(client.views[1].destroyed, true); assertEqual(#client.views, 2)
    PluginShutdown()
end)

test("settings controls persist and hidden overlay keeps audio running", function()
    local client = startPlugin()
    client:emitEvent("Logic")
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    local settings = client.views[2]
    settings.sliders[1]:SetValue(3)
    settings.sliders[2]:SetValue(55)
    settings.checkbox:SetSelected("showCounter", false)
    client:emitEvent("Logic")
    assertEqual(client.saved.tickCount, 3); assertEqual(client.saved.tickVolume, 55)
    assertEqual(client.views[1].destroyed, true)
    client:emitEvent("ServerLogic"); client:emitEvent("ServerLogic"); client:emitEvent("ServerLogic")
    assertEqual(#client.played, 1); assertEqual(client.played[1].volume, 0.55)
    settings.checkbox:SetSelected("enabled", false)
    for _ = 1, 6 do client:emitEvent("ServerLogic") end
    assertEqual(#client.played, 1)
    PluginShutdown()
end)

test("settings pause and reset restart the interval", function()
    local client = startPlugin({tickCount = 2})
    client:emitEvent("Logic"); client:emitEvent("ServerLogic")
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    local settings = client.views[2]
    settings.buttons["Reset count"]()
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 0)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 1)
    settings.checkbox:SetSelected("enabled", false)
    client:emitEvent("ServerLogic"); client:emitEvent("ServerLogic")
    assertEqual(#client.played, 1)
    settings.checkbox:SetSelected("enabled", true)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 1)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 2)
    PluginShutdown()
end)

test("the display passes clicks through while leaving Alt-drag capture independent", function()
    local client = startPlugin()
    client:emitEvent("Logic")
    local panel = client.views[1]
    assertEqual(panel.root.clickthrough, true)
    assertEqual(panel.dock.background.clickthrough, true)
    assertEqual(panel.dock.container.clickthrough, true)
    assertEqual(panel.dock.container.enabled, false)
    assertEqual(panel.dock.scroll.clickthrough, true)
    for _, label in ipairs(panel.labels) do assertEqual(label.clickthrough, true) end
    assertEqual(next(panel.buttons), nil)
    assertEqual(panel.dockDragLayer.enabled, true)
    assertEqual(panel.dockDragLayer.parent, client.parent)
    -- Settings must remain usable even though the HUD is passive.
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    assertEqual(client.views[2].dock.scroll.clickthrough, nil)
    client.views[2].checkbox:SetSelected("enabled", false)
    client:emitEvent("ServerLogic")
    assertEqual(#client.played, 0)
    client.views[2].checkbox:SetSelected("enabled", true)
    client:emitEvent("ServerLogic")
    assertEqual(#client.played, 1)
    PluginShutdown()
end)

test("settings reopening replaces client-cleared controls", function()
    local client = startPlugin()
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    client.views[1].root.parent = nil -- the client clears the old layer
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    assertEqual(client.views[1].destroyed, true)
    client.views[2].sliders[1]:SetValue(2)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 0)
    client:emitEvent("ServerLogic"); assertEqual(#client.played, 1)
    PluginShutdown()
end)

test("unload removes every event and view and stops audio by numeric ID", function()
    local client = startPlugin()
    client:emitEvent("Logic"); client:emitEvent("ServerLogic")
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    PluginShutdown()
    PluginShutdown() -- cleanup is safe if repeated
    for _, event in pairs(Event) do assertEqual(next(event.handlers), nil) end
    for _, view in ipairs(client.views) do assertEqual(view.destroyed, true) end
    assertEqual(client.played[1].stopped, true)
    assertEqual(client.resources.tick.loaded, nil); assertEqual(client.resources.tock.loaded, nil)
end)

test("reload never touches custom audio resources or expired sound userdata", function()
    local client = TestClient.new()
    Plugin.resources = setmetatable({}, {__index = function()
        error("custom audio resources must not be accessed")
    end})
    dofile("main.lua")
    client:emitEvent("Logic")
    client:emitEvent("ServerLogic")
    assertEqual(client.played[1].soundID, 36970)
    PluginShutdown()
    assertEqual(client.played[1].stopped, true)
    dofile("main.lua")
    client:emitEvent("Logic"); client:emitEvent("ServerLogic")
    assertEqual(client.played[2].soundID, 36970)
    PluginShutdown()
    for _, event in pairs(Event) do assertEqual(next(event.handlers), nil) end
end)

for _, failure in ipairs({"nil", "error"}) do
    test("audio playback failure keeps counter usable and logs once: " .. failure, function()
        local client = TestClient.new()
        audio.Play = function()
            if failure == "error" then error("audio device unavailable") end
            return nil
        end
        dofile("main.lua")
        client:emitEvent("Logic")
        for _ = 1, 4 do client:emitEvent("ServerLogic") end
        assert(client.views[1].labels[2].content:find("1 / 1", 1, true))
        local errors = 0
        for _, line in ipairs(client.logs) do if line:find("tick", 1, true) then errors = errors + 1 end end
        assertEqual(errors, 1)
        if failure == "error" then
            assert(table.concat(client.logs, "\n"):find("audio device unavailable", 1, true))
        end
        PluginShutdown()
    end)
end

test("moving the overlay remembers its position without interrupting audio", function()
    local client = startPlugin()
    client:emitEvent("Logic"); client:emitEvent("ServerLogic")
    -- PrettyUI changes the root coordinates while the user Option/Alt-drags.
    for i = 1, 20 do
        client.views[1].root.x = 700 + i
        client.views[1].root.y = 300 + i
        client:emitEvent("Logic")
    end
    assertEqual(client.writes.overlayX, nil) -- no database writes on each drag frame
    assertEqual(client.writes.overlayY, nil)
    for _ = 1, 20 do client:emitEvent("Logic") end
    assertEqual(client.saved.overlayX, 720); assertEqual(client.saved.overlayY, 320)
    assertEqual(client.writes.overlayX, 1); assertEqual(client.writes.overlayY, 1)
    assertEqual(client.played[1].stopped, nil)
    assertEqual(#client.played, 1)
    PluginShutdown()
    dofile("main.lua")
    client:emitEvent("Logic")
    assertEqual(client.views[2].root.x, 720); assertEqual(client.views[2].root.y, 320)
    PluginShutdown()
end)

test("hiding the overlay immediately after moving preserves its position", function()
    local client = startPlugin()
    client:emitEvent("Logic")
    client.views[1].root.x = 950; client.views[1].root.y = 470
    client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
    client.views[2].checkbox:SetSelected("showCounter", false)
    client:emitEvent("Logic")
    client.views[2].checkbox:SetSelected("showCounter", true)
    client:emitEvent("Logic")
    assertEqual(client.views[3].root.x, 950); assertEqual(client.views[3].root.y, 470)
    PluginShutdown()
end)

test("client-cleared overlay restores the last observed position", function()
    local client = startPlugin()
    client:emitEvent("Logic")
    client.views[1].root.x = 610; client.views[1].root.y = 280
    client:emitEvent("Logic")
    client.views[1].root = setmetatable({}, {__index = function() error("expired UI component") end})
    client.parent = {name = "new game layer"}
    client:emitEvent("Logic")
    assertEqual(client.views[2].root.x, 610); assertEqual(client.views[2].root.y, 280)
    PluginShutdown()
end)

test("shutdown saves the final movement before another client update", function()
    local client = startPlugin()
    client:emitEvent("Logic")
    client.views[1].root.x = 815; client.views[1].root.y = 405
    PluginShutdown()
    assertEqual(client.saved.overlayX, 815); assertEqual(client.saved.overlayY, 405)
end)

for _, failure in ipairs({"false", "error"}) do
    test("failed position save cannot block shutdown: " .. failure, function()
        local client = startPlugin()
        client:emitEvent("Logic"); client:emitEvent("ServerLogic")
        client:emitEvent("SettingsLayerReady", {component = {name = "settings"}})
        client.views[1].root.x = 700; client.views[1].root.y = 400
        PersistentDB.SetInt = function()
            if failure == "error" then error("storage unavailable") end
            return false
        end
        PluginShutdown()
        PluginShutdown()
        for _, event in pairs(Event) do assertEqual(next(event.handlers), nil) end
        for _, view in ipairs(client.views) do assertEqual(view.destroyed, true) end
        assertEqual(client.played[1].stopped, true)
        local warnings = 0
        for _, line in ipairs(client.logs) do
            if line:find("Could not save overlay position", 1, true) then warnings = warnings + 1 end
        end
        assertEqual(warnings, 1)
    end)
end
