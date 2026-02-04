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

local winLogger = dofile(hs.spoons.resourcePath("logger.lua"))

--- Ordered list of window IDs for layout
Helm.windowIds = {}

--- Window filter for watching window events
Helm.windowFilter = nil

function Helm:_distributeWindows()
	self.logger.d("=== Distributing windows ===")

	if not self.windowFilter then
		self.logger.d("No window filter available")
		return
	end

	local windows = self.windowFilter:getWindows()
	self.logger.d("Total filtered windows: " .. #windows)

	-- Group windows by their current screen
	local windowsByScreen = {}
	for _, win in ipairs(windows) do
		local screen = win:screen()
		if screen then
			local screenId = screen:id()
			if not windowsByScreen[screenId] then
				windowsByScreen[screenId] = { screen = screen, windows = {} }
			end
			table.insert(windowsByScreen[screenId].windows, win)
		end
	end

	-- Distribute windows on each screen independently
	for screenId, group in pairs(windowsByScreen) do
		local frame = group.screen:frame()
		local count = #group.windows

		winLogger.logScreenInfo(group.screen, self.logger)
		self.logger.d("  " .. count .. " windows:")
		for i, win in ipairs(group.windows) do
			self.logger.d("  [" .. i .. "]")
			winLogger.logWindowDetails(win, self.logger, "    ")
		end

		if count > 0 then
			local width = frame.w / count

			for i, win in ipairs(group.windows) do
				local x = frame.x + (i - 1) * width
				win:setFrame({ x = x, y = frame.y, w = width, h = frame.h })
			end
		end
	end

	self.logger.d("=== Distribution complete ===")
end

function Helm:init()
	return self
end

function Helm:start()
	if not self.windowFilter then
		self.windowFilter = hs.window.filter.new(function(win)
			return win:isStandard()
		end)
		-- Log all windows currently allowed by the filter
		local windows = self.windowFilter:getWindows()
		self.logger.d("Window filter created with " .. #windows .. " windows:")
		for i, win in ipairs(windows) do
			local screen = win:screen()
			local screenName = screen and screen:name() or "Unknown"
			self.logger.d("  [" .. i .. "]")
			self.logger.d('    Screen: "' .. screenName .. '" (ID: ' .. (screen and screen:id() or "nil") .. ")")
			winLogger.logWindowDetails(win, self.logger, "    ")
		end
		self.windowFilter:subscribe("windowFocused", function(win)
			-- self:_distributeWindows()
		end)
		self.windowFilter:subscribe("windowCreated", function(win)
			self:_distributeWindows()
		end)
		self.windowFilter:subscribe("windowDestroyed", function(win)
			self:_distributeWindows()
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

--- Focus the window to the left (west) of the current window
function Helm:focusLeft()
	if self.windowFilter then
		self.windowFilter:focusWindowWest()
	end
end

--- Focus the window to the right (east) of the current window
function Helm:focusRight()
	if self.windowFilter then
		self.windowFilter:focusWindowEast()
	end
end

function Helm:bindHotkeys(mapping)
	local spec = {
		focusLeft = function()
			self:focusLeft()
		end,
		focusRight = function()
			self:focusRight()
		end,
	}
	hs.spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

return Helm
