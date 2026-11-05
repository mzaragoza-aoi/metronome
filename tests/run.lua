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

function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local Settings = require("src/settings")
local Metronome = require("src/metronome")

local function database(initial)
    local data = initial or {}
    return {
        GetBool = function(_, key) return data[key] end,
        GetInt = function(_, key) return data[key] end,
        SetBool = function(_, key, value) data[key] = value; return true end,
        SetInt = function(_, key, value) data[key] = value; return true end,
    }
end

local function engine(overrides)
    local settings = Settings.new(database())
    for name, value in pairs(overrides or {}) do settings:set(name, value) end
    return Metronome.new(settings.values), settings
end

test("default emits a tick on every server event", function()
    local m = engine()
    for _ = 1, 6 do
        local beat = m:step()
        equal(beat.kind, "tick")
        equal(beat.volume, 38)
        equal(m.count, 1)
    end
end)

test("three-tick interval waits for the third event in each cycle", function()
    local m = engine({tickCount = 3})
    for _ = 1, 3 do
        equal(m:step(), nil); equal(m.count, 1)
        equal(m:step(), nil); equal(m.count, 2)
        equal(m:step().kind, "tick"); equal(m.count, 3)
    end
end)

test("tock alternates per beat, not per server tick", function()
    local m = engine({tickCount = 2, tockVolume = 70})
    for _, kind in ipairs({"tick", "tock", "tick", "tock"}) do
        equal(m:step(), nil)
        local beat = m:step()
        equal(beat.kind, kind)
        equal(beat.volume, kind == "tick" and 38 or 70)
    end
end)

test("silent tick still permits audible tock", function()
    local m = engine({tickVolume = 0, tockVolume = 70})
    equal(m:step().volume, 0)
    local beat = m:step()
    equal(beat.kind, "tock"); equal(beat.volume, 70)
end)

test("reset restarts cadence and alternating sound", function()
    local m = engine({tickCount = 2, tockVolume = 70})
    m:step(); m:step(); m:step(); m:reset()
    equal(m.count, 0)
    equal(m:step(), nil)
    equal(m:step().kind, "tick")
end)

test("changing interval restarts counting but volume changes preserve it", function()
    local m, s = engine({tickCount = 3})
    m:step(); s:set("tickVolume", 50); m:configure(s.values)
    equal(m.count, 1)
    s:set("tickCount", 2); m:configure(s.values)
    equal(m.count, 0)
    equal(m:step(), nil); equal(m:step().volume, 50)
end)

test("pause is silent and resume starts a fresh cycle", function()
    local m, s = engine({tickCount = 2})
    m:step(); s:set("enabled", false); m:configure(s.values)
    equal(m:step(), nil); equal(m.count, 0)
    s:set("enabled", true); m:configure(s.values)
    equal(m:step(), nil); equal(m:step().kind, "tick")
end)

test("disabling tock restores tick-only immediately", function()
    local m, s = engine({tockVolume = 70})
    m:step(); s:set("tockVolume", 0); m:configure(s.values)
    equal(m:step().kind, "tick")
    equal(m:step().kind, "tick")
end)

test("preferences preserve false and zero across reload", function()
    local db = database()
    local s = Settings.new(db)
    s:set("enabled", false); s:set("tickVolume", 0); s:set("tickCount", 100)
    local restored = Settings.new(db)
    equal(restored:get("enabled"), false)
    equal(restored:get("tickVolume"), 0)
    equal(restored:get("tickCount"), 100)
end)

test("corrupt saved preferences fall back individually", function()
    local s = Settings.new(database({tickCount = 0, tickVolume = 101, tockVolume = "loud", enabled = 1}))
    equal(s:get("tickCount"), 1); equal(s:get("tickVolume"), 38)
    equal(s:get("tockVolume"), 0); equal(s:get("enabled"), true)
end)

test("invalid writes cannot change preferences", function()
    local s = Settings.new(database())
    for _, value in ipairs({0, -1, 101, 2.5, "3", math.huge, 0/0}) do
        equal(pcall(function() s:set("tickCount", value) end), false)
    end
    equal(pcall(function() s:set("unknown", 1) end), false)
    equal(s:get("tickCount"), 1)
end)

test("settings notify once only when value changes", function()
    local s = Settings.new(database())
    local changes = 0
    s.onChange = function(name, value)
        equal(name, "tickCount"); equal(value, 3); changes = changes + 1
    end
    s:set("tickCount", 3); s:set("tickCount", 3)
    equal(changes, 1)
end)

test("overlay placement persists independently of playback settings", function()
    local db = database()
    local s = Settings.new(db)
    local changes = 0
    s.onChange = function() changes = changes + 1 end
    s:setPosition(1920, 1080)
    local restored = Settings.new(db)
    equal(restored:get("overlayX"), 1920); equal(restored:get("overlayY"), 1080)
    equal(changes, 0)
    equal(s:get("tickCount"), 1)
end)

test("invalid saved positions fall back and invalid moves cannot partially save", function()
    local s = Settings.new(database({overlayX = -10, overlayY = "bottom"}))
    equal(s:get("overlayX"), 420); equal(s:get("overlayY"), 80)
    for _, value in ipairs({-1, 32768, 1.5, math.huge, 0/0}) do
        equal(pcall(function() s:setPosition(900, value) end), false)
        equal(s:get("overlayX"), 420)
    end
end)

dofile("tests/client_test.lua")
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
