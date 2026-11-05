-- Client API substitutes for running plugin tests without RuneScape.
local TestClient = {}

function TestClient.new(saved)
    local client = {saved = saved or {}, writes = {}, played = {}, views = {}, resources = {}, logs = {}, available = true}
    client.parent = {name = "game"}
    _G.GameState = {GAME = 30, LOBBY = 20, RECONNECTING = 35, LOADING = 40}
    _G.Player = {IsAvailable = function() return client.available end}
    _G.game = {options = {
        VolumeMaster = {setting = 255, max = 255},
        VolumeMainEffects = {setting = 255, max = 255},
    }}
    _G.log = function(message) table.insert(client.logs, message) end
    _G.id = {Component = {TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = 1}}
    _G.ui = {Interfaces = {GetComponent = function() return client.parent end}}
    _G.PersistentDB = {
        GetBool = function(_, name) return client.saved[name] end,
        GetInt = function(_, name) return client.saved[name] end,
        SetBool = function(_, name, value) client.saved[name] = value; return true end,
        SetInt = function(_, name, value)
            client.saved[name] = value
            client.writes[name] = (client.writes[name] or 0) + 1
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
    function client:emitEvent(name, payload)
        for _, callback in pairs(Event[name].handlers) do callback(payload) end
    end
    for _, name in ipairs({"tick", "tock"}) do
        client.resources[name] = {
            name = name,
            Load = function(self) self.loaded = true; return "success" end,
            Unload = function(self) self.loaded = false end,
        }
    end
    _G.Plugin = {resources = client.resources}
    _G.audio = {
        SoundType = {SCRIPT = 7}, AudioBus = {SFX = 1}, EmitterShape = {NONE = 4},
        SoundPlaybackParams = {new = function() return {} end},
        Play = function(soundID, params)
            assert(type(soundID) == "number", "audio.Play must use a built-in numeric sound ID")
            local sound = {id = #client.played + 1, soundID = soundID,
                kind = soundID == 36970 and "tick" or "tock", volume = params.volume, params = params}
            function sound:Stop() error("expired SoundInstance must not be used") end
            table.insert(client.played, sound)
            return sound
        end,
        Stop = function(instanceID)
            assert(type(instanceID) == "number")
            if client.played[instanceID] then client.played[instanceID].stopped = true end
        end,
    }

    local function createView(parent, options)
        local view = {root = {parent = parent, x = options.x or 0, y = options.y or 0},
            options = options, labels = {}, buttons = {}, sliders = {}}
        view.dock = {root = view.root, background = {}, container = {}, scroll = {}}
        function view.dock.scroll:SetClickthrough(value) self.clickthrough = value end
        -- PrettyUI's Alt-drag capture is a sibling of the display root.
        view.dockDragLayer = {parent = parent, enabled = true}
        function view:AddText(options)
            local label = {content = options.text, rgba = options.colour}
            table.insert(self.labels, label)
            return label
        end
        function view:AddSimpleButton(text, callback)
            self.buttons[text] = callback
            return {}
        end
        function view:AddCheckboxButton(items, options)
            local checkbox = {items = items, options = options}
            function checkbox:SetSelected(name, selected, notify)
                if notify ~= false then self.options.onChange(self, {}, name, selected) end
            end
            self.checkbox = checkbox
            return checkbox
        end
        function view:AddSlider(options)
            local slider = {value = options.value, options = options}
            function slider:SetValue(value, notify)
                self.value = value
                if notify ~= false then self.options.onChange(self, value) end
            end
            table.insert(self.sliders, slider)
            return slider
        end
        function view:Destroy() self.destroyed = true; self.root.parent = nil end
        table.insert(client.views, view)
        return view
    end
    _G.prettyui = {Panel = {new = createView}, SimpleView = {new = createView}}
    return client
end

return TestClient
