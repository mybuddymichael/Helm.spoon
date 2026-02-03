---
name: building-spoons
description: "Creates Hammerspoon Spoon plugins following official conventions. Use when building, scaffolding, or packaging a Hammerspoon Spoon."
---

# Building Hammerspoon Spoons

Spoons are pure-Lua plugins for Hammerspoon with standardized APIs.

## Spoon Structure

Minimal structure:
```
MySpoon.spoon/
└── init.lua
```

Full structure:
```
MySpoon.spoon/
├── init.lua          # Main entry point (required)
├── docs.json         # Generated documentation
└── images/           # Optional assets
    └── icon.png
```

Install location: `~/.hammerspoon/Spoons/`

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Spoon name | TitleCase | `WindowManager`, `USBObserver` |
| Methods/variables | camelCase | `bindHotkeys`, `showAlert` |
| Directory | `Name.spoon/` | `WindowManager.spoon/` |

## Required Metadata

```lua
local obj = {}
obj.__index = obj

obj.name = "MySpoon"
obj.version = "1.0"
obj.author = "Your Name <email@example.com>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/user/MySpoon"  -- optional

return obj
```

## Lifecycle Methods

| Method | Called | Purpose |
|--------|--------|---------|
| `init()` | Automatically by `hs.loadSpoon()` | Setup resources, no background work |
| `start()` | Manually by user | Start timers, watchers, background tasks |
| `stop()` | Manually by user | Stop all background activity |

```lua
function obj:init()
  -- Prepare resources, don't start watchers/timers here
  self.watcher = nil
  return self
end

function obj:start()
  self.watcher = hs.application.watcher.new(function(...) 
    self:handleEvent(...) 
  end):start()
  return self
end

function obj:stop()
  if self.watcher then
    self.watcher:stop()
    self.watcher = nil
  end
  return self
end
```

## Hotkey Binding

Use `hs.spoons.bindHotkeysToSpec()` for standard hotkey binding:

```lua
function obj:bindHotkeys(mapping)
  local spec = {
    show = hs.fnutils.partial(self.show, self),
    hide = hs.fnutils.partial(self.hide, self),
    toggle = hs.fnutils.partial(self.toggle, self),
  }
  hs.spoons.bindHotkeysToSpec(spec, mapping)
  return self
end
```

User calls with:
```lua
spoon.MySpoon:bindHotkeys({
  show = {{"cmd", "alt"}, "s"},
  hide = {{"cmd", "alt"}, "h", message = "Hidden"},
})
```

## Loading Resources

```lua
-- Get Spoon's directory path
obj.spoonPath = hs.spoons.scriptPath()

-- Load bundled assets
local imagePath = hs.spoons.resourcePath("images/icon.png")
obj.icon = hs.image.imageFromPath(imagePath)

-- Load additional Lua files (NOT require())
dofile(hs.spoons.resourcePath("helpers.lua"))
```

## Docstring Format

Document all public API using Hammerspoon's docstring format:

```lua
--- MySpoon:doSomething(param1[, param2])
--- Method
--- Brief description of what this method does
---
--- Parameters:
---  * param1 - A string describing the first parameter
---  * param2 - An optional number for the second parameter
---
--- Returns:
---  * The MySpoon object (for chaining)
```

### Docstring Types

| Type | Header Format |
|------|---------------|
| Method | `--- Spoon:method()` then `--- Method` |
| Variable | `--- Spoon.variable` then `--- Variable` |
| Constant | `--- Spoon.CONSTANT` then `--- Constant` |

## Complete Template

```lua
--- === MySpoon ===
---
--- Brief description of what this Spoon does.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MySpoon"
obj.version = "1.0"
obj.author = "Your Name <email@example.com>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/user/MySpoon"

--- MySpoon.logger
--- Variable
--- Logger object for debugging
obj.logger = hs.logger.new("MySpoon")

--- MySpoon:init()
--- Method
--- Initializes the Spoon
---
--- Parameters:
---  * None
---
--- Returns:
---  * The MySpoon object
function obj:init()
  return self
end

--- MySpoon:start()
--- Method
--- Starts the Spoon's background activity
---
--- Parameters:
---  * None
---
--- Returns:
---  * The MySpoon object
function obj:start()
  return self
end

--- MySpoon:stop()
--- Method
--- Stops the Spoon's background activity
---
--- Parameters:
---  * None
---
--- Returns:
---  * The MySpoon object
function obj:stop()
  return self
end

--- MySpoon:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for MySpoon
---
--- Parameters:
---  * mapping - A table with action names as keys and hotkey specs as values
---
--- Returns:
---  * The MySpoon object
function obj:bindHotkeys(mapping)
  local spec = {
    -- action = hs.fnutils.partial(self.method, self),
  }
  hs.spoons.bindHotkeysToSpec(spec, mapping)
  return self
end

return obj
```

## Generating Documentation

```bash
cd /path/to/MySpoon.spoon
hs -c "hs.doc.builder.genJSON(\"$(pwd)\")" | grep -v "^--" > docs.json
```

## Distribution

1. Ensure Spoon directory ends with `.spoon`
2. Include `docs.json` for documentation
3. Zip the `.spoon` directory for distribution
4. Users double-click to install to `~/.hammerspoon/Spoons/`

## References

- Full Spoon documentation: https://github.com/Hammerspoon/hammerspoon/blob/master/SPOONS.md
