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

--- Number of virtual spaces
Helm.numSpaces = 5

--- Virtual spaces configuration (each space has windowIds, lastFocusedWindowId, zoom state)
Helm.spaces = {}

--- Currently active space ID (1-numSpaces)
Helm.activeSpaceId = 1

--- Map of window ID to space ID
Helm.windowSpaceMap = {}

--- Ordered list of window IDs for layout (current active space only, for backward compatibility)
Helm.windowIds = {}

--- Window filter for watching window events
Helm.windowFilter = nil

--- Track the previously focused window for insertion logic (current active space)
Helm.lastFocusedWindowId = nil

--- Track zoomed state and original frame for toggle functionality (current active space only)
Helm.zoomedWindowId = nil
Helm.zoomedWindowOriginalFrame = nil

--- Padding configuration (in pixels)
Helm.screenPadding = 12
Helm.windowGap = 12

--- Size of visible pixel when window is hidden (macOS doesn't allow completely hiding windows)
Helm.hiddenWindowSize = 1

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

--- Get the space object for a given space ID
function Helm:_getSpace(spaceId)
	return self.spaces[spaceId]
end

--- Get the active space object
function Helm:_getActiveSpace()
	return self:_getSpace(self.activeSpaceId)
end

--- Sync current space state from active space object to instance variables
function Helm:_syncFromActiveSpace()
	local space = self:_getActiveSpace()
	if space then
		self.windowIds = space.windowIds
		self.lastFocusedWindowId = space.lastFocusedWindowId
		self.zoomedWindowId = space.zoomedWindowId
		self.zoomedWindowOriginalFrame = space.zoomedWindowOriginalFrame
	end
end

--- Sync current instance variables to active space object
function Helm:_syncToActiveSpace()
	local space = self:_getActiveSpace()
	if space then
		space.windowIds = self.windowIds
		space.lastFocusedWindowId = self.lastFocusedWindowId
		space.zoomedWindowId = self.zoomedWindowId
		space.zoomedWindowOriginalFrame = self.zoomedWindowOriginalFrame
	end
end

--- Hide a window by moving it to bottom-right corner with minimal visible size
function Helm:_hideWindow(win)
	if not win then
		return
	end
	local screen = win:screen()
	if not screen then
		return
	end
	local frame = screen:frame()
	local size = self.hiddenWindowSize
	local x = frame.x + frame.w - size
	local y = frame.y + frame.h - size
	win:setFrame({ x = x, y = y, w = size, h = size })
end

--- Restore zoomed window to its original position if focus changes away
function Helm:_restoreZoomedWindowIfNeeded(newFocusedId)
	if self.zoomedWindowId and self.zoomedWindowId ~= newFocusedId then
		local windows = self.windowFilter:getWindows()
		for _, win in ipairs(windows) do
			if win:id() == self.zoomedWindowId then
				win:setFrame(self.zoomedWindowOriginalFrame)
				break
			end
		end
		self.zoomedWindowId = nil
		self.zoomedWindowOriginalFrame = nil
		self:_syncToActiveSpace()
	end
end

--- Public handler for window destroyed events
function Helm:handleWindowDestroyed(win)
	self:_removeWindowFromOrder(win)
	-- Clean up zoomed state if destroyed window was zoomed
	if win and win:id() and self.zoomedWindowId == win:id() then
		self.zoomedWindowId = nil
		self.zoomedWindowOriginalFrame = nil
		self:_syncToActiveSpace()
	end
	-- Remove from windowSpaceMap
	if win and win:id() then
		self.windowSpaceMap[win:id()] = nil
	end
end

--- Public handler for window created events
function Helm:handleWindowCreated(win)
	if not win or not win.isStandard or not win:isStandard() then
		return
	end
	local newId = win:id()
	if not newId then
		return
	end

	-- Check if already in windowSpaceMap (already assigned to a space)
	if self.windowSpaceMap[newId] then
		return
	end

	-- Assign to active space
	local activeSpace = self:_getActiveSpace()
	if not activeSpace then
		return
	end

	self.windowSpaceMap[newId] = self.activeSpaceId

	-- Check if already in active space's order
	for _, existingId in ipairs(activeSpace.windowIds) do
		if existingId == newId then
			return
		end
	end

	-- Use the previously focused window (before this new window took focus)
	local insertAfterId = activeSpace.lastFocusedWindowId

	if insertAfterId then
		-- Find the previously focused window's position and insert after it
		for i, existingId in ipairs(activeSpace.windowIds) do
			if existingId == insertAfterId then
				table.insert(activeSpace.windowIds, i + 1, newId)
				self:_syncFromActiveSpace()
				return
			end
		end
	end

	-- Fallback: add to the end if no previous focus or not in our order
	table.insert(activeSpace.windowIds, newId)
	self:_syncFromActiveSpace()
end

--- Get ordered list of windows based on windowIds, grouped by screen
function Helm:_getOrderedWindowsByScreen()
	local allWindows = self.windowFilter:getWindows()
	local windowsById = {}
	for _, win in ipairs(allWindows) do
		windowsById[win:id()] = win
	end

	-- Create ordered list of valid windows that exist in windowIds
	-- Only include windows that belong to the active space
	local orderedWindows = {}
	for _, id in ipairs(self.windowIds) do
		local win = windowsById[id]
		if win and self.windowSpaceMap[id] == self.activeSpaceId then
			table.insert(orderedWindows, win)
		end
	end

	-- Add any new windows not yet in windowIds or windowSpaceMap (at the end)
	-- These will be assigned to the active space
	local idSet = self:_buildWindowIdSet()
	for _, win in ipairs(allWindows) do
		local winId = win:id()
		if not idSet[winId] and not self.windowSpaceMap[winId] then
			table.insert(orderedWindows, win)
			-- Also add to active space's windowIds for next time
			table.insert(self.windowIds, winId)
			self.windowSpaceMap[winId] = self.activeSpaceId
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

--- Initialize spaces data structures
function Helm:_initSpaces()
	self.spaces = {}
	for i = 1, self.numSpaces do
		self.spaces[i] = {
			id = i,
			name = "space" .. i,
			windowIds = {},
			lastFocusedWindowId = nil,
			zoomedWindowId = nil,
			zoomedWindowOriginalFrame = nil,
		}
	end
	self.activeSpaceId = 1
	self.windowSpaceMap = {}
	self:_syncFromActiveSpace()
end

--- Activate a virtual space by ID (1-numSpaces)
function Helm:activateSpace(spaceId)
	if spaceId < 1 or spaceId > self.numSpaces then
		self.logger.w("Invalid space ID: " .. tostring(spaceId))
		return
	end

	if spaceId == self.activeSpaceId then
		return
	end

	self.logger.d("Activating space " .. spaceId)

	-- Save current space state
	self:_syncToActiveSpace()

	-- Hide all windows from current active space
	local allWindows = self.windowFilter:getWindows()
	for _, win in ipairs(allWindows) do
		local winId = win:id()
		if self.windowSpaceMap[winId] == self.activeSpaceId then
			self:_hideWindow(win)
		end
	end

	-- Switch to new space
	self.activeSpaceId = spaceId
	self:_syncFromActiveSpace()

	-- Restore and distribute windows in the new active space
	self:_distributeWindows()

	-- Focus the last focused window in this space
	if self.lastFocusedWindowId then
		for _, win in ipairs(allWindows) do
			if win:id() == self.lastFocusedWindowId then
				win:focus()
				break
			end
		end
	end
end

--- Move a window to a different space
function Helm:moveWindowToSpace(win, targetSpaceId)
	if not win then
		return
	end
	local winId = win:id()
	if not winId then
		return
	end

	if targetSpaceId < 1 or targetSpaceId > self.numSpaces then
		self.logger.w("Invalid target space ID: " .. tostring(targetSpaceId))
		return
	end

	local sourceSpaceId = self.windowSpaceMap[winId]
	if not sourceSpaceId then
		self.logger.w("Window " .. winId .. " not assigned to any space")
		return
	end

	if sourceSpaceId == targetSpaceId then
		return
	end

	self.logger.d("Moving window " .. winId .. " from space " .. sourceSpaceId .. " to space " .. targetSpaceId)

	-- Remove from source space
	local sourceSpace = self:_getSpace(sourceSpaceId)
	if sourceSpace then
		local newOrder = {}
		for _, id in ipairs(sourceSpace.windowIds) do
			if id ~= winId then
				table.insert(newOrder, id)
			end
		end
		sourceSpace.windowIds = newOrder
		-- Clear last focused if it was this window
		if sourceSpace.lastFocusedWindowId == winId then
			sourceSpace.lastFocusedWindowId = nil
		end
		-- Clear zoom state if it was this window
		if sourceSpace.zoomedWindowId == winId then
			sourceSpace.zoomedWindowId = nil
			sourceSpace.zoomedWindowOriginalFrame = nil
		end
	end

	-- Add to target space
	local targetSpace = self:_getSpace(targetSpaceId)
	if targetSpace then
		table.insert(targetSpace.windowIds, winId)
	end

	-- Update windowSpaceMap
	self.windowSpaceMap[winId] = targetSpaceId

	-- If moving to the active space, redistribute
	if targetSpaceId == self.activeSpaceId then
		self:_syncFromActiveSpace()
		self:_distributeWindows()
	else
		-- Hide the window if moving to an inactive space
		self:_hideWindow(win)
		-- If moving from active space, need to redistribute remaining windows
		if sourceSpaceId == self.activeSpaceId then
			self:_syncFromActiveSpace()
			self:_distributeWindows()
		end
	end
end

--- Handle window focus event - auto-activate space if needed
function Helm:_handleWindowFocused(win)
	if not win then
		return
	end
	local winId = win:id()
	if not winId then
		return
	end

	local spaceId = self.windowSpaceMap[winId]
	if spaceId and spaceId ~= self.activeSpaceId then
		self.logger.d("Window " .. winId .. " belongs to space " .. spaceId .. ", auto-activating")
		self:activateSpace(spaceId)
	end

	-- Update last focused window for the current (possibly new) active space
	local currentSpace = self:_getActiveSpace()
	if currentSpace then
		currentSpace.lastFocusedWindowId = winId
		self.lastFocusedWindowId = winId
	end
end

function Helm:init()
	self:_initSpaces()
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
			local currentFocused = hs.window.focusedWindow()
			local currentId = currentFocused and currentFocused:id()
			-- Restore any zoomed window if focus changed to a different window
			self:_restoreZoomedWindowIfNeeded(currentId)
			-- Handle window focus (auto-activate space and track last focused)
			self:_handleWindowFocused(currentFocused)
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
			self:_syncToActiveSpace()
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
			self:_syncToActiveSpace()
			self:_distributeWindows()
			return
		end
	end
end

--- Toggle making the current window full screen at 80% width
function Helm:makeFullScreen()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	if self.zoomedWindowId == id then
		-- Restore original frame
		win:setFrame(self.zoomedWindowOriginalFrame)
		self.zoomedWindowId = nil
		self.zoomedWindowOriginalFrame = nil
		self:_syncToActiveSpace()
	else
		-- Restore any previously zoomed window first
		if self.zoomedWindowId then
			self:_restoreZoomedWindowIfNeeded(id)
		end
		-- Store current frame and make full screen at 80% width, 100% height (minus padding)
		local originalFrame = win:frame()
		local screen = win:screen()
		local screenFrame = screen:frame()

		local newWidth = screenFrame.w * 0.8
		local newHeight = screenFrame.h - (2 * self.screenPadding)
		local x = screenFrame.x + (screenFrame.w - newWidth) / 2
		local y = screenFrame.y + self.screenPadding

		self.zoomedWindowId = id
		self.zoomedWindowOriginalFrame = originalFrame
		self:_syncToActiveSpace()
		win:setFrame({ x = x, y = y, w = newWidth, h = newHeight })
	end
end

--- Move the focused window to a specific space by number (1-5)
function Helm:moveFocusedWindowToSpace(spaceNum)
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	self:moveWindowToSpace(win, spaceNum)
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
		makeFullScreen = function()
			self:makeFullScreen()
		end,
		activateSpace1 = function()
			self:activateSpace(1)
		end,
		activateSpace2 = function()
			self:activateSpace(2)
		end,
		activateSpace3 = function()
			self:activateSpace(3)
		end,
		activateSpace4 = function()
			self:activateSpace(4)
		end,
		activateSpace5 = function()
			self:activateSpace(5)
		end,
		moveWindowToSpace1 = function()
			self:moveFocusedWindowToSpace(1)
		end,
		moveWindowToSpace2 = function()
			self:moveFocusedWindowToSpace(2)
		end,
		moveWindowToSpace3 = function()
			self:moveFocusedWindowToSpace(3)
		end,
		moveWindowToSpace4 = function()
			self:moveFocusedWindowToSpace(4)
		end,
		moveWindowToSpace5 = function()
			self:moveFocusedWindowToSpace(5)
		end,
	}
	hs.spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

return Helm
