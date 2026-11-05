package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
function test(name, callback)
    local ok, err = pcall(callback)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

function assertEqual(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local Settings = require("src/settings")
local Metronome = require("src/metronome")

local function createTestDatabase(initial)
    local data = initial or {}
    return {
        GetBool = function(_, key) return data[key] end,
        GetInt = function(_, key) return data[key] end,
        SetBool = function(_, key, value) data[key] = value; return true end,
        SetInt = function(_, key, value) data[key] = value; return true end,
    }
end

local function createMetronome(overrides)
    local settings = Settings.new(createTestDatabase())
    for name, value in pairs(overrides or {}) do settings:set(name, value) end
    return Metronome.new(settings.values), settings
end

test("default emits a tick on every server event", function()
    local metronome = createMetronome()
    for _ = 1, 6 do
        local beat = metronome:onServerTick()
        assertEqual(beat.kind, "tick")
        assertEqual(beat.volume, 38)
        assertEqual(metronome.count, 1)
    end
end)

test("three-tick interval waits for the third event in each cycle", function()
    local metronome = createMetronome({tickCount = 3})
    for _ = 1, 3 do
        assertEqual(metronome:onServerTick(), nil); assertEqual(metronome.count, 1)
        assertEqual(metronome:onServerTick(), nil); assertEqual(metronome.count, 2)
        assertEqual(metronome:onServerTick().kind, "tick"); assertEqual(metronome.count, 3)
    end
end)

test("tock alternates per beat, not per server tick", function()
    local metronome = createMetronome({tickCount = 2, tockVolume = 70})
    for _, kind in ipairs({"tick", "tock", "tick", "tock"}) do
        assertEqual(metronome:onServerTick(), nil)
        local beat = metronome:onServerTick()
        assertEqual(beat.kind, kind)
        assertEqual(beat.volume, kind == "tick" and 38 or 70)
    end
end)

test("silent tick still permits audible tock", function()
    local metronome = createMetronome({tickVolume = 0, tockVolume = 70})
    assertEqual(metronome:onServerTick().volume, 0)
    local beat = metronome:onServerTick()
    assertEqual(beat.kind, "tock"); assertEqual(beat.volume, 70)
end)

test("reset restarts cadence and alternating sound", function()
    local metronome = createMetronome({tickCount = 2, tockVolume = 70})
    metronome:onServerTick(); metronome:onServerTick(); metronome:onServerTick(); metronome:resetCount()
    assertEqual(metronome.count, 0)
    assertEqual(metronome:onServerTick(), nil)
    assertEqual(metronome:onServerTick().kind, "tick")
end)

test("changing interval restarts counting but volume changes preserve it", function()
    local metronome, settings = createMetronome({tickCount = 3})
    metronome:onServerTick(); settings:set("tickVolume", 50); metronome:applySettings(settings.values)
    assertEqual(metronome.count, 1)
    settings:set("tickCount", 2); metronome:applySettings(settings.values)
    assertEqual(metronome.count, 0)
    assertEqual(metronome:onServerTick(), nil); assertEqual(metronome:onServerTick().volume, 50)
end)

test("pause is silent and resume starts a fresh cycle", function()
    local metronome, settings = createMetronome({tickCount = 2})
    metronome:onServerTick(); settings:set("enabled", false); metronome:applySettings(settings.values)
    assertEqual(metronome:onServerTick(), nil); assertEqual(metronome.count, 0)
    settings:set("enabled", true); metronome:applySettings(settings.values)
    assertEqual(metronome:onServerTick(), nil); assertEqual(metronome:onServerTick().kind, "tick")
end)

test("disabling tock restores tick-only immediately", function()
    local metronome, settings = createMetronome({tockVolume = 70})
    metronome:onServerTick(); settings:set("tockVolume", 0); metronome:applySettings(settings.values)
    assertEqual(metronome:onServerTick().kind, "tick")
    assertEqual(metronome:onServerTick().kind, "tick")
end)

test("preferences preserve false and zero across reload", function()
    local database = createTestDatabase()
    local settings = Settings.new(database)
    settings:set("enabled", false); settings:set("tickVolume", 0); settings:set("tickCount", 100)
    local restoredSettings = Settings.new(database)
    assertEqual(restoredSettings:get("enabled"), false)
    assertEqual(restoredSettings:get("tickVolume"), 0)
    assertEqual(restoredSettings:get("tickCount"), 100)
end)

test("corrupt saved preferences fall back individually", function()
    local settings = Settings.new(createTestDatabase({tickCount = 0, tickVolume = 101, tockVolume = "loud", enabled = 1}))
    assertEqual(settings:get("tickCount"), 1); assertEqual(settings:get("tickVolume"), 38)
    assertEqual(settings:get("tockVolume"), 0); assertEqual(settings:get("enabled"), true)
end)

test("invalid writes cannot change preferences", function()
    local settings = Settings.new(createTestDatabase())
    for _, value in ipairs({0, -1, 101, 2.5, "3", math.huge, 0/0}) do
        assertEqual(pcall(function() settings:set("tickCount", value) end), false)
    end
    assertEqual(pcall(function() settings:set("unknown", 1) end), false)
    assertEqual(settings:get("tickCount"), 1)
end)

test("settings notify once only when value changes", function()
    local settings = Settings.new(createTestDatabase())
    local changes = 0
    settings.onChange = function(name, value)
        assertEqual(name, "tickCount"); assertEqual(value, 3); changes = changes + 1
    end
    settings:set("tickCount", 3); settings:set("tickCount", 3)
    assertEqual(changes, 1)
end)

test("overlay placement persists independently of playback settings", function()
    local database = createTestDatabase()
    local settings = Settings.new(database)
    local changes = 0
    settings.onChange = function() changes = changes + 1 end
    settings:saveOverlayPosition(1920, 1080)
    local restoredSettings = Settings.new(database)
    assertEqual(restoredSettings:get("overlayX"), 1920); assertEqual(restoredSettings:get("overlayY"), 1080)
    assertEqual(changes, 0)
    assertEqual(settings:get("tickCount"), 1)
end)

test("invalid saved positions fall back and invalid moves cannot partially save", function()
    local settings = Settings.new(createTestDatabase({overlayX = -10, overlayY = "bottom"}))
    assertEqual(settings:get("overlayX"), 420); assertEqual(settings:get("overlayY"), 80)
    for _, value in ipairs({-1, 32768, 1.5, math.huge, 0/0}) do
        assertEqual(pcall(function() settings:saveOverlayPosition(900, value) end), false)
        assertEqual(settings:get("overlayX"), 420)
    end
end)

dofile("tests/client_test.lua")
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
