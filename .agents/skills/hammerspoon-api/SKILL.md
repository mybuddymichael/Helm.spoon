---
name: hammerspoon-api
description: "Hammerspoon macOS automation API reference. Use when writing Lua scripts for Hammerspoon, looking up hs.* modules, or automating macOS with keyboard shortcuts, window management, or system events."
---

# Hammerspoon API Overview

Hammerspoon bridges macOS system APIs into Lua for desktop automation.

## Configuration

- Config file: `~/.hammerspoon/init.lua`
- Reload config: `hs.reload()` or menu bar → Reload Config
- Console: menu bar → Console (for testing)

## Core Patterns

### Hotkey Binding
```lua
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "W", function()
  hs.alert.show("Hello!")
end)
```

### Variable Lifecycle
Objects must be stored in global variables to avoid garbage collection:
```lua
-- WRONG: will be garbage collected
hs.pathwatcher.new(...):start()

-- CORRECT: survives until reload
myWatcher = hs.pathwatcher.new(...):start()
```

### Colon Syntax
Use `:` for method calls (passes self), `.` for static functions:
```lua
local win = hs.window.focusedWindow()  -- static function
local f = win:frame()                   -- method call
```

## Key Modules

### Window Management
| Module | Purpose |
|--------|---------|
| `hs.window` | Get/manipulate windows |
| `hs.window.filter` | Filter/watch windows by criteria |
| `hs.screen` | Screen info and geometry |
| `hs.layout` | Multi-window layouts |
| `hs.grid` | Grid-based window positioning |

```lua
-- Move window to left half
local win = hs.window.focusedWindow()
local screen = win:screen():frame()
win:setFrame({x=screen.x, y=screen.y, w=screen.w/2, h=screen.h})
```

### Input Events
| Module | Purpose |
|--------|---------|
| `hs.hotkey` | Global keyboard shortcuts |
| `hs.hotkey.modal` | Modal shortcut environments |
| `hs.eventtap` | Low-level input events |
| `hs.mouse` | Mouse position/control |
| `hs.keycodes` | Key string/code conversion |

### System Control
| Module | Purpose |
|--------|---------|
| `hs.caffeinate` | Prevent sleep, lock screen |
| `hs.audiodevice` | Volume, input/output devices |
| `hs.brightness` | Display brightness |
| `hs.battery` | Power/battery info |
| `hs.spaces` | macOS Spaces control |

### Applications
| Module | Purpose |
|--------|---------|
| `hs.application` | Launch, focus, control apps |
| `hs.application.watcher` | App launch/quit events |
| `hs.appfinder` | Find apps/windows by name |

```lua
-- React to app activation
appWatcher = hs.application.watcher.new(function(name, event, app)
  if event == hs.application.watcher.activated and name == "Finder" then
    app:selectMenuItem({"Window", "Bring All to Front"})
  end
end):start()
```

### Watchers (Event Handlers)
| Module | Purpose |
|--------|---------|
| `hs.pathwatcher` | File/directory changes |
| `hs.wifi.watcher` | WiFi network changes |
| `hs.usb.watcher` | USB device connect/disconnect |
| `hs.caffeinate.watcher` | Sleep/wake events |
| `hs.screen.watcher` | Display changes |
| `hs.battery.watcher` | Power state changes |

### UI Elements
| Module | Purpose |
|--------|---------|
| `hs.alert` | On-screen text alerts |
| `hs.notify` | macOS notifications |
| `hs.menubar` | Menu bar icons |
| `hs.chooser` | Spotlight-like picker |
| `hs.dialog` | Dialog boxes, file pickers |
| `hs.canvas` | Draw on screen |

### Data & Network
| Module | Purpose |
|--------|---------|
| `hs.http` | HTTP requests |
| `hs.json` | JSON encode/decode |
| `hs.pasteboard` | Clipboard access |
| `hs.settings` | Persist Lua values |
| `hs.socket` | TCP/UDP sockets |
| `hs.websocket` | WebSocket client |

### Scripting
| Module | Purpose |
|--------|---------|
| `hs.applescript` | Run AppleScript |
| `hs.osascript` | AppleScript/JavaScript |
| `hs.task` | Run shell commands |
| `hs.urlevent` | Handle `hammerspoon://` URLs |

## Spoons (Plugins)

Spoons are pre-made plugins installed to `~/.hammerspoon/Spoons/`.

```lua
-- Load and use a Spoon
hs.loadSpoon("ReloadConfiguration")
spoon.ReloadConfiguration:start()

-- Access Spoon methods
hs.loadSpoon("AClock")
spoon.AClock:toggleShow()
```

Browse available Spoons: https://www.hammerspoon.org/Spoons/

## Common Recipes

### Auto-reload Config
```lua
configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, file in pairs(files) do
    if file:sub(-4) == ".lua" then hs.reload() end
  end
end):start()
```

### Window Layout
```lua
hs.layout.apply({
  {"Safari", nil, "Built-in Display", hs.layout.left50, nil, nil},
  {"Mail", nil, "Built-in Display", hs.layout.right50, nil, nil},
})
```

### Menu Bar Item
```lua
menuItem = hs.menubar.new()
menuItem:setTitle("🔴")
menuItem:setClickCallback(function() hs.alert.show("Clicked!") end)
```

### Defeat Paste Blocking
```lua
hs.hotkey.bind({"cmd", "alt"}, "V", function()
  hs.eventtap.keyStrokes(hs.pasteboard.getContents())
end)
```

## API Documentation

Full API docs: https://www.hammerspoon.org/docs/

Look up specific modules by reading:
- `https://www.hammerspoon.org/docs/hs.<module>.html`

Example: For `hs.window` → https://www.hammerspoon.org/docs/hs.window.html
