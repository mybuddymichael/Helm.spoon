--- === Helm ===
---
--- Helm Spoon for Hammerspoon.

local Helm = {}
Helm.__index = Helm

Helm.name = "Helm"
Helm.version = "0.1"
Helm.author = "Michael Hanson"
Helm.license = "MIT - https://opensource.org/licenses/MIT"

Helm.logger = hs.logger.new(Helm.name)

--- Ordered list of window IDs for layout
Helm.windowIds = {}

--- Window filter for watching window events
Helm.windowFilter = nil

function Helm:init()
	return self
end

function Helm:start()
	if not self.windowFilter then
		self.windowFilter = hs.window.filter.new()
		self.windowFilter:subscribe("windowFocused", function(win)
			-- Helm.logger.d("windowFocused", win)
		end)
	end
	return self
end

function Helm:stop()
	if self.windowFilter then
		self.windowFilter:unsubscribeAll()
		self.windowFilter = nil
	end
	return self
end

function Helm:bindHotkeys(mapping)
	local spec = {}
	hs.spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

return Helm
