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

--- Ordered list of window IDs for layout (global order across all screens)
Helm.windowIds = {}

--- Window filter for watching window events
Helm.windowFilter = nil

--- Padding configuration (in pixels)
Helm.screenPadding = 12
Helm.windowGap = 12

--- Build a set of valid window IDs for quick lookup
function Helm:_buildWindowIdSet()
	local set = {}
	for _, id in ipairs(self.windowIds) do
		set[id] = true
	end
	return set
end

--- Clean up windowIds by removing windows that no longer exist in the filter
function Helm:_cleanupWindowIds()
	local validWindows = self.windowFilter:getWindows()
	local validIds = {}
	for _, win in ipairs(validWindows) do
		validIds[win:id()] = true
	end

	local cleaned = {}
	for _, id in ipairs(self.windowIds) do
		if validIds[id] then
			table.insert(cleaned, id)
		end
	end
	self.windowIds = cleaned
end

--- Add a new window to the end of the order
function Helm:_addWindowToOrder(win)
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end
	-- Check if already in order
	for _, existingId in ipairs(self.windowIds) do
		if existingId == id then
			return
		end
	end
	table.insert(self.windowIds, id)
end

--- Remove a window from the order
function Helm:_removeWindowFromOrder(win)
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end
	local newOrder = {}
	for _, existingId in ipairs(self.windowIds) do
		if existingId ~= id then
			table.insert(newOrder, existingId)
		end
	end
	self.windowIds = newOrder
end

--- Public handler for window destroyed events
function Helm:handleWindowDestroyed(win)
	self:_removeWindowFromOrder(win)
end

--- Public handler for window created events
function Helm:handleWindowCreated(win)
	if not win or not win.isStandard or not win:isStandard() then
		return
	end
	self:_addWindowToOrder(win)
end

--- Get ordered list of windows based on windowIds, grouped by screen
function Helm:_getOrderedWindowsByScreen()
	local allWindows = self.windowFilter:getWindows()
	local windowsById = {}
	for _, win in ipairs(allWindows) do
		windowsById[win:id()] = win
	end

	-- Create ordered list of valid windows that exist in windowIds
	local orderedWindows = {}
	for _, id in ipairs(self.windowIds) do
		local win = windowsById[id]
		if win then
			table.insert(orderedWindows, win)
		end
	end

	-- Add any new windows not yet in windowIds (at the end)
	local idSet = self:_buildWindowIdSet()
	for _, win in ipairs(allWindows) do
		if not idSet[win:id()] then
			table.insert(orderedWindows, win)
			-- Also add to windowIds for next time
			table.insert(self.windowIds, win:id())
		end
	end

	-- Group by screen, preserving order within each screen
	local windowsByScreen = {}
	for _, win in ipairs(orderedWindows) do
		local screen = win:screen()
		if screen then
			local screenId = screen:id()
			if not windowsByScreen[screenId] then
				windowsByScreen[screenId] = { screen = screen, windows = {} }
			end
			table.insert(windowsByScreen[screenId].windows, win)
		end
	end

	return windowsByScreen
end

function Helm:_distributeWindows()
	self.logger.d("=== Distributing windows ===")

	if not self.windowFilter then
		self.logger.d("No window filter available")
		return
	end

	local windowsByScreen = self:_getOrderedWindowsByScreen()
	local totalWindows = 0
	for _, group in pairs(windowsByScreen) do
		totalWindows = totalWindows + #group.windows
	end
	self.logger.d("Total windows to distribute: " .. totalWindows)
	self.logger.d("Window order: " .. table.concat(self.windowIds, ", "))

	-- Distribute windows on each screen independently
	for screenId, group in pairs(windowsByScreen) do
		local frame = group.screen:frame()
		local count = #group.windows

		winLogger.logScreenInfo(group.screen, self.logger)
		self.logger.d("  " .. count .. " windows on this screen:")
		for i, win in ipairs(group.windows) do
			self.logger.d("  [" .. i .. "] ID: " .. win:id())
			winLogger.logWindowDetails(win, self.logger, "    ")
		end

		if count > 0 then
			local screenPadding = self.screenPadding
			local windowGap = self.windowGap

			-- Calculate available space after padding and gaps
			local totalGaps = (count - 1) * windowGap
			local availableWidth = frame.w - (2 * screenPadding) - totalGaps
			local width = availableWidth / count

			for i, win in ipairs(group.windows) do
				local x = frame.x + screenPadding + (i - 1) * (width + windowGap)
				local y = frame.y + screenPadding
				local h = frame.h - (2 * screenPadding)
				win:setFrame({ x = x, y = y, w = width, h = h })
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
			self:handleWindowCreated(win)
			self:_distributeWindows()
		end)
		self.windowFilter:subscribe("windowDestroyed", function(win)
			self:handleWindowDestroyed(win)
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

--- Move the current window left in the order
function Helm:moveWindowLeft()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	for i, existingId in ipairs(self.windowIds) do
		if existingId == id and i > 1 then
			-- Swap with previous window
			self.windowIds[i] = self.windowIds[i - 1]
			self.windowIds[i - 1] = id
			self:_distributeWindows()
			return
		end
	end
end

--- Move the current window right in the order
function Helm:moveWindowRight()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	for i, existingId in ipairs(self.windowIds) do
		if existingId == id and i < #self.windowIds then
			-- Swap with next window
			self.windowIds[i] = self.windowIds[i + 1]
			self.windowIds[i + 1] = id
			self:_distributeWindows()
			return
		end
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
		moveWindowLeft = function()
			self:moveWindowLeft()
		end,
		moveWindowRight = function()
			self:moveWindowRight()
		end,
	}
	hs.spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

return Helm
