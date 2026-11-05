local Client = require("tests/support/client")

local function start(saved)
    local c = Client.new(saved)
    dofile("main.lua")
    return c
end

local function settingsText(view)
    local lines = {}
    for _, label in ipairs(view.labels) do table.insert(lines, label.content) end
    return table.concat(lines, "\n")
end

test("settings show game audio levels without changing client volumes", function()
    local c = start({enabled = false})
    game.options.VolumeMaster.setting = 0
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    assert(settingsText(c.views[1]):find("master 0%", 1, true))
    equal(game.options.VolumeMaster.setting, 0)
    game.options.VolumeMaster.setting = 128
    game.options.VolumeMainEffects.setting = 0
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    local text = settingsText(c.views[2])
    assert(text:find("master 50%", 1, true))
    assert(text:find("sound effects 0%", 1, true))
    equal(game.options.VolumeMaster.setting, 128)
    equal(game.options.VolumeMainEffects.setting, 0)
    equal(#c.played, 0)
    PluginShutdown()
end)

test("settings remain usable when game audio options are unavailable", function()
    local c = Client.new()
    game.options = nil
    dofile("main.lua")
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    assert(settingsText(c.views[1]):find("master unavailable, sound effects unavailable", 1, true))
    c.views[1].sliders[1]:SetValue(2)
    c:emit("ServerLogic"); equal(#c.played, 0)
    c:emit("ServerLogic"); equal(#c.played, 1)
    PluginShutdown()
end)

test("client updates never drive audio", function()
    local c = start()
    for _ = 1, 100 do c:emit("Logic") end
    equal(#c.played, 0)
    c:emit("ServerLogic")
    equal(#c.played, 1); equal(c.played[1].kind, "tick")
    equal(c.played[1].volume, 0.38)
    equal(c.played[1].params.numLoops, 0)
    equal(c.played[1].params.emitterShape, audio.EmitterShape.NONE)
    PluginShutdown()
end)

test("server events obey saved cadence and alternating volumes", function()
    local c = start({tickCount = 3, tockVolume = 65})
    for _ = 1, 5 do c:emit("ServerLogic") end
    equal(#c.played, 1)
    c:emit("ServerLogic")
    equal(#c.played, 2); equal(c.played[2].kind, "tock")
    equal(c.played[2].volume, 0.65)
    PluginShutdown()
end)

test("zero volume allocates no sound instances", function()
    local c = start({tickVolume = 0, tockVolume = 50})
    c:emit("ServerLogic"); equal(#c.played, 0)
    c:emit("ServerLogic"); equal(#c.played, 1)
    equal(c.played[1].kind, "tock")
    PluginShutdown()
end)

test("game-state transition blocks late ticks and resets alternation", function()
    local c = start({tockVolume = 50})
    c:emit("Logic"); c:emit("ServerLogic")
    c:emit("GameStateChanged", {newState = GameState.RECONNECTING})
    c:emit("ServerLogic"); c:emit("Logic")
    equal(#c.played, 1); equal(c.played[1].stopped, true)
    equal(c.views[1].destroyed, true)
    c:emit("GameStateChanged", {newState = GameState.GAME})
    c:emit("ServerLogic")
    equal(c.played[2].kind, "tick")
    PluginShutdown()
end)

test("player becomes available after plugin starts in lobby", function()
    local c = Client.new()
    c.available = false
    dofile("main.lua")
    c:emit("Logic"); c:emit("ServerLogic")
    equal(#c.played, 0); equal(#c.views, 0)
    c.available = true
    c:emit("GameStateChanged", {newState = GameState.GAME})
    c:emit("Logic"); c:emit("ServerLogic")
    equal(#c.views, 1); equal(#c.played, 1)
    PluginShutdown()
end)

test("overlay parent replacement destroys the old panel", function()
    local c = start()
    c:emit("Logic")
    c.parent = {name = "replacement"}
    c:emit("Logic")
    equal(c.views[1].destroyed, true); equal(#c.views, 2)
    PluginShutdown()
end)

test("settings controls persist and hidden overlay keeps audio running", function()
    local c = start()
    c:emit("Logic")
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    local settings = c.views[2]
    settings.sliders[1]:SetValue(3)
    settings.sliders[2]:SetValue(55)
    settings.checkbox:SetSelected("showCounter", false)
    c:emit("Logic")
    equal(c.saved.tickCount, 3); equal(c.saved.tickVolume, 55)
    equal(c.views[1].destroyed, true)
    c:emit("ServerLogic"); c:emit("ServerLogic"); c:emit("ServerLogic")
    equal(#c.played, 1); equal(c.played[1].volume, 0.55)
    settings.checkbox:SetSelected("enabled", false)
    for _ = 1, 6 do c:emit("ServerLogic") end
    equal(#c.played, 1)
    PluginShutdown()
end)

test("settings pause and reset restart the interval", function()
    local c = start({tickCount = 2})
    c:emit("Logic"); c:emit("ServerLogic")
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    local settings = c.views[2]
    settings.buttons["Reset count"]()
    c:emit("ServerLogic"); equal(#c.played, 0)
    c:emit("ServerLogic"); equal(#c.played, 1)
    settings.checkbox:SetSelected("enabled", false)
    c:emit("ServerLogic"); c:emit("ServerLogic")
    equal(#c.played, 1)
    settings.checkbox:SetSelected("enabled", true)
    c:emit("ServerLogic"); equal(#c.played, 1)
    c:emit("ServerLogic"); equal(#c.played, 2)
    PluginShutdown()
end)

test("the display passes clicks through while leaving Alt-drag capture independent", function()
    local c = start()
    c:emit("Logic")
    local panel = c.views[1]
    equal(panel.root.clickthrough, true)
    equal(panel.dock.background.clickthrough, true)
    equal(panel.dock.container.clickthrough, true)
    equal(panel.dock.container.enabled, false)
    equal(panel.dock.scroll.clickthrough, true)
    for _, label in ipairs(panel.labels) do equal(label.clickthrough, true) end
    equal(next(panel.buttons), nil)
    equal(panel.dockDragLayer.enabled, true)
    equal(panel.dockDragLayer.parent, c.parent)
    -- Settings must remain usable even though the HUD is passive.
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    equal(c.views[2].dock.scroll.clickthrough, nil)
    c.views[2].checkbox:SetSelected("enabled", false)
    c:emit("ServerLogic")
    equal(#c.played, 0)
    c.views[2].checkbox:SetSelected("enabled", true)
    c:emit("ServerLogic")
    equal(#c.played, 1)
    PluginShutdown()
end)

test("settings reopening replaces client-cleared controls", function()
    local c = start()
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    c.views[1].root.parent = nil -- the client clears the old layer
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    equal(c.views[1].destroyed, true)
    c.views[2].sliders[1]:SetValue(2)
    c:emit("ServerLogic"); equal(#c.played, 0)
    c:emit("ServerLogic"); equal(#c.played, 1)
    PluginShutdown()
end)

test("unload removes every event and view and stops audio by numeric ID", function()
    local c = start()
    c:emit("Logic"); c:emit("ServerLogic")
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    PluginShutdown()
    PluginShutdown() -- cleanup is safe if repeated
    for _, event in pairs(Event) do equal(next(event.handlers), nil) end
    for _, view in ipairs(c.views) do equal(view.destroyed, true) end
    equal(c.played[1].stopped, true)
    equal(c.resources.tick.loaded, nil); equal(c.resources.tock.loaded, nil)
end)

test("reload never touches custom audio resources or expired sound userdata", function()
    local c = Client.new()
    Plugin.resources = setmetatable({}, {__index = function()
        error("custom audio resources must not be accessed")
    end})
    dofile("main.lua")
    c:emit("Logic")
    c:emit("ServerLogic")
    equal(c.played[1].soundID, 36970)
    PluginShutdown()
    equal(c.played[1].stopped, true)
    dofile("main.lua")
    c:emit("Logic"); c:emit("ServerLogic")
    equal(c.played[2].soundID, 36970)
    PluginShutdown()
    for _, event in pairs(Event) do equal(next(event.handlers), nil) end
end)

for _, failure in ipairs({"nil", "error"}) do
    test("audio playback failure keeps counter usable and logs once: " .. failure, function()
        local c = Client.new()
        audio.Play = function()
            if failure == "error" then error("audio device unavailable") end
            return nil
        end
        dofile("main.lua")
        c:emit("Logic")
        for _ = 1, 4 do c:emit("ServerLogic") end
        assert(c.views[1].labels[2].content:find("1 / 1", 1, true))
        local errors = 0
        for _, line in ipairs(c.logs) do if line:find("tick", 1, true) then errors = errors + 1 end end
        equal(errors, 1)
        if failure == "error" then
            assert(table.concat(c.logs, "\n"):find("audio device unavailable", 1, true))
        end
        PluginShutdown()
    end)
end

test("moving the overlay remembers its position without interrupting audio", function()
    local c = start()
    c:emit("Logic"); c:emit("ServerLogic")
    -- PrettyUI changes the root coordinates while the user Option/Alt-drags.
    for i = 1, 20 do
        c.views[1].root.x = 700 + i
        c.views[1].root.y = 300 + i
        c:emit("Logic")
    end
    equal(c.writes.overlayX, nil) -- no database writes on each drag frame
    equal(c.writes.overlayY, nil)
    for _ = 1, 20 do c:emit("Logic") end
    equal(c.saved.overlayX, 720); equal(c.saved.overlayY, 320)
    equal(c.writes.overlayX, 1); equal(c.writes.overlayY, 1)
    equal(c.played[1].stopped, nil)
    equal(#c.played, 1)
    PluginShutdown()
    dofile("main.lua")
    c:emit("Logic")
    equal(c.views[2].root.x, 720); equal(c.views[2].root.y, 320)
    PluginShutdown()
end)

test("hiding the overlay immediately after moving preserves its position", function()
    local c = start()
    c:emit("Logic")
    c.views[1].root.x = 950; c.views[1].root.y = 470
    c:emit("SettingsLayerReady", {component = {name = "settings"}})
    c.views[2].checkbox:SetSelected("showCounter", false)
    c:emit("Logic")
    c.views[2].checkbox:SetSelected("showCounter", true)
    c:emit("Logic")
    equal(c.views[3].root.x, 950); equal(c.views[3].root.y, 470)
    PluginShutdown()
end)

test("client-cleared overlay restores the last observed position", function()
    local c = start()
    c:emit("Logic")
    c.views[1].root.x = 610; c.views[1].root.y = 280
    c:emit("Logic")
    c.views[1].root = setmetatable({}, {__index = function() error("expired UI component") end})
    c.parent = {name = "new game layer"}
    c:emit("Logic")
    equal(c.views[2].root.x, 610); equal(c.views[2].root.y, 280)
    PluginShutdown()
end)

test("shutdown saves the final movement before another client update", function()
    local c = start()
    c:emit("Logic")
    c.views[1].root.x = 815; c.views[1].root.y = 405
    PluginShutdown()
    equal(c.saved.overlayX, 815); equal(c.saved.overlayY, 405)
end)

for _, failure in ipairs({"false", "error"}) do
    test("failed position save cannot block shutdown: " .. failure, function()
        local c = start()
        c:emit("Logic"); c:emit("ServerLogic")
        c:emit("SettingsLayerReady", {component = {name = "settings"}})
        c.views[1].root.x = 700; c.views[1].root.y = 400
        PersistentDB.SetInt = function()
            if failure == "error" then error("storage unavailable") end
            return false
        end
        PluginShutdown()
        PluginShutdown()
        for _, event in pairs(Event) do equal(next(event.handlers), nil) end
        for _, view in ipairs(c.views) do equal(view.destroyed, true) end
        equal(c.played[1].stopped, true)
        local warnings = 0
        for _, line in ipairs(c.logs) do
            if line:find("Could not save overlay position", 1, true) then warnings = warnings + 1 end
        end
        equal(warnings, 1)
    end)
end
