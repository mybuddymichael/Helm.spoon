--- === Helm ===
---
--- Helm Spoon for Hammerspoon.

local Helm = {}
Helm.__index = Helm

Helm.name = "Helm"
Helm.version = "0.1"
Helm.author = "Michael Hanson"
Helm.license = "MIT - https://opensource.org/licenses/MIT"

--- Helm.logger
--- Variable
--- Logger object for debugging
Helm.logger = hs.logger.new(Helm.name)

--- Helm:init()
--- Method
--- Initializes the Spoon.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Helm object
function Helm:init()
	return self
end

--- Helm:start()
--- Method
--- Starts the Spoon's background activity.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Helm object
function Helm:start()
	return self
end

--- Helm:stop()
--- Method
--- Stops the Spoon's background activity.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Helm object
function Helm:stop()
	return self
end

--- Helm:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for Helm.
---
--- Parameters:
---  * mapping - A table with action names as keys and hotkey specs as values
---
--- Returns:
---  * The Helm object
function Helm:bindHotkeys(mapping)
	local spec = {}
	hs.spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

return Helm
