-- Minimal boundary doubles for the client-owned APIs; production modules run unchanged.
local Client = {}

function Client.new(saved)
    local c = {saved = saved or {}, writes = {}, played = {}, views = {}, resources = {}, logs = {}, available = true}
    c.parent = {name = "game"}
    _G.GameState = {GAME = 30, LOBBY = 20, RECONNECTING = 35, LOADING = 40}
    _G.Player = {IsAvailable = function() return c.available end}
    _G.game = {options = {
        VolumeMaster = {setting = 255, max = 255},
        VolumeMainEffects = {setting = 255, max = 255},
    }}
    _G.log = function(message) table.insert(c.logs, message) end
    _G.id = {Component = {TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = 1}}
    _G.ui = {Interfaces = {GetComponent = function() return c.parent end}}
    _G.PersistentDB = {
        GetBool = function(_, name) return c.saved[name] end,
        GetInt = function(_, name) return c.saved[name] end,
        SetBool = function(_, name, value) c.saved[name] = value; return true end,
        SetInt = function(_, name, value)
            c.saved[name] = value
            c.writes[name] = (c.writes[name] or 0) + 1
            return true
        end,
    }
    _G.Event = {}
    for _, name in ipairs({"Logic", "ServerLogic", "GameStateChanged", "SettingsLayerReady", "ContentLayerReady"}) do
        local handlers = {}
        Event[name] = {
            handlers = handlers,
            Subscribe = function(key, callback) handlers[key] = callback end,
            Unsubscribe = function(key) handlers[key] = nil end,
        }
    end
    function c:emit(name, payload)
        for _, callback in pairs(Event[name].handlers) do callback(payload) end
    end
    for _, name in ipairs({"tick", "tock"}) do
        c.resources[name] = {
            name = name,
            Load = function(self) self.loaded = true; return "success" end,
            Unload = function(self) self.loaded = false end,
        }
    end
    _G.Plugin = {resources = c.resources}
    _G.audio = {
        SoundType = {SCRIPT = 7}, AudioBus = {SFX = 1}, EmitterShape = {NONE = 4},
        SoundPlaybackParams = {new = function() return {} end},
        Play = function(soundID, params)
            assert(type(soundID) == "number", "audio.Play must use a built-in numeric sound ID")
            local sound = {id = #c.played + 1, soundID = soundID,
                kind = soundID == 36970 and "tick" or "tock", volume = params.volume, params = params}
            function sound:Stop() error("expired SoundInstance must not be used") end
            table.insert(c.played, sound)
            return sound
        end,
        Stop = function(instanceID)
            assert(type(instanceID) == "number")
            if c.played[instanceID] then c.played[instanceID].stopped = true end
        end,
    }

    local function view(parent, options)
        local v = {root = {parent = parent, x = options.x or 0, y = options.y or 0},
            options = options, labels = {}, buttons = {}, sliders = {}}
        v.dock = {root = v.root, background = {}, container = {}, scroll = {}}
        function v.dock.scroll:SetClickthrough(value) self.clickthrough = value end
        -- PrettyUI's Alt-drag capture is a sibling of the display root.
        v.dockDragLayer = {parent = parent, enabled = true}
        function v:AddText(opts)
            local label = {content = opts.text, rgba = opts.colour}
            table.insert(self.labels, label)
            return label
        end
        function v:AddSimpleButton(text, callback)
            self.buttons[text] = callback
            return {}
        end
        function v:AddCheckboxButton(items, opts)
            local box = {items = items, options = opts}
            function box:SetSelected(name, selected, notify)
                if notify ~= false then self.options.onChange(self, {}, name, selected) end
            end
            self.checkbox = box
            return box
        end
        function v:AddSlider(opts)
            local slider = {value = opts.value, options = opts}
            function slider:SetValue(value, notify)
                self.value = value
                if notify ~= false then self.options.onChange(self, value) end
            end
            table.insert(self.sliders, slider)
            return slider
        end
        function v:Destroy() self.destroyed = true; self.root.parent = nil end
        table.insert(c.views, v)
        return v
    end
    _G.prettyui = {Panel = {new = view}, SimpleView = {new = view}}
    return c
end

return Client
