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

--- Application watcher for detecting app quit events
Helm.appWatcher = nil

--- Track the previously focused window for insertion logic (current active space)
Helm.lastFocusedWindowId = nil

--- Track zoomed state and original frame for toggle functionality (current active space only)
Helm.zoomedWindowId = nil
Helm.zoomedWindowOriginalFrame = nil

--- Columns configuration: ordered list of columns for the active space
--- Each column is { windowIds = {id1, id2, ...} }
Helm.columns = {}

--- Map of window ID to column index for quick lookup
Helm.windowColumnMap = {}

--- Padding configuration (in pixels)
Helm.screenPadding = 12
Helm.windowGap = 12

--- Size of visible pixel when window is hidden (macOS doesn't allow completely hiding windows)
Helm.hiddenWindowSize = 1

--- Benchmark module for performance testing (loaded on demand)
Helm.benchmark = nil

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
	-- Sync to active space to maintain table reference consistency
	self:_syncToActiveSpace()
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
		self.columns = space.columns or {}
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
		-- Only sync columns if they have content (to avoid overwriting test setup)
		if self.columns and #self.columns > 0 then
			space.columns = self.columns
		end
	end
end

--- Hide a window by moving it so only a single top-left pixel is visible
function Helm:_hideWindow(win)
	if not win then
		return
	end
	local screen = win:screen()
	if not screen then
		return
	end
	local screenFrame = screen:frame()
	local winFrame = win:frame()
	local x = screenFrame.x + screenFrame.w - self.hiddenWindowSize
	local y = screenFrame.y + screenFrame.h - self.hiddenWindowSize
	win:setFrame({ x = x, y = y, w = winFrame.w, h = winFrame.h })
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
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	self:_removeWindowFromOrder(win)

	-- Remove from column structure
	local colIdx = self.windowColumnMap[id]
	if colIdx then
		local space = self:_getSpace(self.windowSpaceMap[id])
		if space and space.columns[colIdx] then
			local column = space.columns[colIdx]
			-- Remove window from column
			local newWindowIds = {}
			for _, wid in ipairs(column.windowIds) do
				if wid ~= id then
					table.insert(newWindowIds, wid)
				end
			end
			column.windowIds = newWindowIds
			-- Remove column if empty
			if #column.windowIds == 0 then
				table.remove(space.columns, colIdx)
				-- Update column indices for remaining windows
				self.windowColumnMap[id] = nil
				for wid, oldColIdx in pairs(self.windowColumnMap) do
					if oldColIdx > colIdx then
						self.windowColumnMap[wid] = oldColIdx - 1
					end
				end
			else
				self.windowColumnMap[id] = nil
			end
		end
	end

	-- Clean up zoomed state if destroyed window was zoomed
	if self.zoomedWindowId == id then
		self.zoomedWindowId = nil
		self.zoomedWindowOriginalFrame = nil
		self:_syncToActiveSpace()
	end
	-- Remove from windowSpaceMap
	self.windowSpaceMap[id] = nil
end

--- Handle application termination event to clean up all windows from the app
function Helm:_handleAppTerminated(appName, eventType, app)
	if eventType ~= hs.application.watcher.terminated then
		return
	end
	if not app then
		return
	end

	local pid = app:pid()
	if not pid then
		return
	end

	-- Find all windows belonging to this app and remove them
	-- We need to collect windows to remove first to avoid modifying while iterating
	local windowsToRemove = {}
	for id, _ in pairs(self.windowSpaceMap) do
		local win = hs.window.get(id)
		if win then
			local winApp = win:application()
			local winPid = winApp and winApp:pid()
			if winPid == pid then
				table.insert(windowsToRemove, win)
			end
		end
	end

	-- Now remove all collected windows
	for _, win in ipairs(windowsToRemove) do
		self:handleWindowDestroyed(win)
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
				-- Also insert as new column after the column containing insertAfterId
				local insertCol = self.windowColumnMap[insertAfterId]
				if insertCol then
					table.insert(activeSpace.columns, insertCol + 1, { windowIds = { newId } })
					self.windowColumnMap[newId] = insertCol + 1
					-- Update column indices for windows after the inserted column
					for wid, colIdx in pairs(self.windowColumnMap) do
						if colIdx > insertCol + 1 then
							self.windowColumnMap[wid] = colIdx + 1
						end
					end
				else
					-- Fallback: add to end
					table.insert(activeSpace.columns, { windowIds = { newId } })
					self.windowColumnMap[newId] = #activeSpace.columns
				end
				self:_syncFromActiveSpace()
				return
			end
		end
	end

	-- Fallback: add to the end if no previous focus or not in our order
	table.insert(activeSpace.windowIds, newId)
	table.insert(activeSpace.columns, { windowIds = { newId } })
	self.windowColumnMap[newId] = #activeSpace.columns
	self:_syncFromActiveSpace()
end

--- Slurp: merge focused window into the column to the left
function Helm:slurp()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	local space = self:_getActiveSpace()
	if not space then
		return
	end

	-- Check if window is in a multi-window column (can't slurp if already in one)
	local currentColIdx = self.windowColumnMap[id]
	if not currentColIdx then
		return
	end

	local currentCol = space.columns[currentColIdx]
	if not currentCol then
		return
	end

	-- Can't slurp if already in multi-window column
	if #currentCol.windowIds > 1 then
		return
	end

	-- Can't slurp if no column to the left
	if currentColIdx <= 1 then
		return
	end

	-- Can't slurp if single window in space
	if #space.columns <= 1 then
		return
	end

	-- Get target column (to the left)
	local targetColIdx = currentColIdx - 1
	local targetCol = space.columns[targetColIdx]

	-- Add window to bottom of target column
	table.insert(targetCol.windowIds, id)

	-- Remove the now-empty current column
	table.remove(space.columns, currentColIdx)

	-- Rebuild column map
	self:_rebuildColumnMap()

	self:_syncToActiveSpace()
	self:_distributeWindows()
	win:focus()
end

--- Barf: push focused window out to its own column on the right
function Helm:barf()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	local space = self:_getActiveSpace()
	if not space then
		return
	end

	-- Get current column
	local currentColIdx = self.windowColumnMap[id]
	if not currentColIdx then
		return
	end

	local currentCol = space.columns[currentColIdx]
	if not currentCol then
		return
	end

	-- Can't barf if alone in column
	if #currentCol.windowIds <= 1 then
		return
	end

	-- Remove window from current column
	local newWindowIds = {}
	local windowPos = nil
	for i, wid in ipairs(currentCol.windowIds) do
		if wid == id then
			windowPos = i
		else
			table.insert(newWindowIds, wid)
		end
	end
	currentCol.windowIds = newWindowIds

	-- Create new column with this window
	local newCol = { windowIds = { id } }
	table.insert(space.columns, currentColIdx + 1, newCol)

	-- Rebuild column map
	self:_rebuildColumnMap()

	self:_syncToActiveSpace()
	self:_distributeWindows()
	win:focus()
end

--- Rebuild the windowColumnMap from current columns structure
function Helm:_rebuildColumnMap()
	self.windowColumnMap = {}
	local space = self:_getActiveSpace()
	if not space then
		return
	end

	for colIdx, col in ipairs(space.columns) do
		for _, wid in ipairs(col.windowIds) do
			self.windowColumnMap[wid] = colIdx
		end
	end
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
	local space = self:_getActiveSpace()
	for _, win in ipairs(allWindows) do
		local winId = win:id()
		if not idSet[winId] and not self.windowSpaceMap[winId] then
			table.insert(orderedWindows, win)
			-- Also add to active space's windowIds for next time
			table.insert(self.windowIds, winId)
			self.windowSpaceMap[winId] = self.activeSpaceId
			-- Create a single-window column for this window
			if space then
				table.insert(space.columns, { windowIds = { winId } })
				self.windowColumnMap[winId] = #space.columns
			end
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

	local space = self:_getActiveSpace()
	if not space then
		return
	end

	local allWindows = self.windowFilter:getWindows()
	local windowsById = {}
	for _, win in ipairs(allWindows) do
		windowsById[win:id()] = win
	end

	-- Group columns by screen
	local columnsByScreen = {}
	for colIdx, col in ipairs(space.columns) do
		-- Get screen from first window in column
		if #col.windowIds > 0 then
			local firstWin = windowsById[col.windowIds[1]]
			if firstWin then
				local screen = firstWin:screen()
				if screen then
					local screenId = screen:id()
					if not columnsByScreen[screenId] then
						columnsByScreen[screenId] = { screen = screen, columns = {} }
					end
					table.insert(columnsByScreen[screenId].columns, col)
				end
			end
		end
	end

	-- Distribute columns on each screen
	for screenId, group in pairs(columnsByScreen) do
		local frame = group.screen:frame()
		local numColumns = #group.columns

		if numColumns > 0 then
			local screenPadding = self.screenPadding
			local windowGap = self.windowGap

			-- Calculate horizontal space for columns
			local totalGaps = (numColumns - 1) * windowGap
			local availableWidth = frame.w - (2 * screenPadding) - totalGaps
			local colWidth = availableWidth / numColumns

			-- Distribute each column
			for colIdx, col in ipairs(group.columns) do
				local numWindows = #col.windowIds
				if numWindows > 0 then
					local colX = frame.x + screenPadding + (colIdx - 1) * (colWidth + windowGap)

					-- Calculate vertical space for windows in this column
					local verticalGaps = (numWindows - 1) * windowGap
					local availableHeight = frame.h - (2 * screenPadding) - verticalGaps
					local winHeight = availableHeight / numWindows

					-- Distribute windows vertically within the column
					for winIdx, winId in ipairs(col.windowIds) do
						local win = windowsById[winId]
						if win then
							local x = colX
							local y = frame.y + screenPadding + (winIdx - 1) * (winHeight + windowGap)
							win:setFrame({ x = x, y = y, w = colWidth, h = winHeight })
						end
					end
				end
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
			columns = {},
		}
	end
	self.activeSpaceId = 1
	self.windowSpaceMap = {}
	self.windowColumnMap = {}
	self.columns = {}
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

	-- Focus the last focused window in this space, or the first window if none
	local windowToFocus = nil
	if self.lastFocusedWindowId then
		for _, win in ipairs(allWindows) do
			if win:id() == self.lastFocusedWindowId then
				windowToFocus = win
				break
			end
		end
	end

	-- If no last focused window found, focus the first window in the space
	if not windowToFocus then
		for _, win in ipairs(allWindows) do
			local winId = win:id()
			if winId and self.windowSpaceMap[winId] == self.activeSpaceId then
				windowToFocus = win
				break
			end
		end
	end

	if windowToFocus then
		windowToFocus:focus()
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

	-- Barf window first if it's in a multi-window column
	local sourceSpace = self:_getSpace(sourceSpaceId)
	if sourceSpace then
		local colIdx = self.windowColumnMap[winId]
		if colIdx then
			local column = sourceSpace.columns[colIdx]
			if column and #column.windowIds > 1 then
				-- Remove from current column
				local newWindowIds = {}
				for _, wid in ipairs(column.windowIds) do
					if wid ~= winId then
						table.insert(newWindowIds, wid)
					end
				end
				column.windowIds = newWindowIds
				-- Create new column with this window (at position after original column)
				table.insert(sourceSpace.columns, colIdx + 1, { windowIds = { winId } })
				self:_rebuildColumnMap()
			end
		end
	end

	-- Remove from source space
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
		-- Remove from source space columns
		local sourceColIdx = self.windowColumnMap[winId]
		if sourceColIdx and sourceSpace.columns[sourceColIdx] then
			table.remove(sourceSpace.columns, sourceColIdx)
		end
	end

	-- Add to target space
	local targetSpace = self:_getSpace(targetSpaceId)
	local targetColIdx = nil
	if targetSpace then
		table.insert(targetSpace.windowIds, winId)
		-- Add as new column at end
		table.insert(targetSpace.columns, { windowIds = { winId } })
		targetColIdx = #targetSpace.columns
	end

	-- Update windowSpaceMap and windowColumnMap
	self.windowSpaceMap[winId] = targetSpaceId
	self.windowColumnMap[winId] = targetColIdx

	-- Note: We don't call _rebuildColumnMap() here because it only rebuilds
	-- for the active space, and the window has been moved to targetSpace.
	-- The windowColumnMap[winId] is already set correctly above.

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

function Helm:_getWindowSpaceLabel(winId)
        local helmSpaceId = self.windowSpaceMap[winId]
        if helmSpaceId then
                return tostring(helmSpaceId)
        end

        return "unassigned"
end

function Helm:_getMacosSpaceLabel(win)
        if not hs.spaces or not hs.spaces.windowSpaces or not win then
                return "unknown"
        end

        local ok, spaces = pcall(hs.spaces.windowSpaces, win)
        if not ok or not spaces then
                return "unknown"
        end

        if #spaces == 0 then
                return "none"
        end

        local parts = {}
        for _, spaceId in ipairs(spaces) do
                table.insert(parts, tostring(spaceId))
        end
        return table.concat(parts, ", ")
end

function Helm:logWindowDebugInfo()
        local windows = self.windowFilter and self.windowFilter:getWindows() or {}
        self.logger.d("=== Window Debug Info (" .. #windows .. " windows) ===")
        if #windows == 0 then
                return
        end

        for index, win in ipairs(windows) do
                local winId = win:id()
                local screen = win:screen()
                local screenId = screen and screen:id() or "nil"
                local screenName = screen and screen:name() or "Unknown"
                local helmSpace = self:_getWindowSpaceLabel(winId)
                local macosSpaces = self:_getMacosSpaceLabel(win)

                self.logger.d("  [" .. index .. "]")
                self.logger.d('    Screen: "' .. screenName .. '" (ID: ' .. screenId .. ")")
                self.logger.d("    Virtual Space: " .. helmSpace)
                self.logger.d("    macOS Spaces: " .. macosSpaces)
                winLogger.logWindowDetails(win, self.logger, "    ")
        end
end

function Helm:init()
	self:_initSpaces()
	return self
end

function Helm:start()
	-- Load benchmark module on demand
	self.benchmark = dofile(hs.spoons.resourcePath("benchmark.lua"))

	if not self.windowFilter then
		-- Apps to exclude from window management
		local excludedApps = {
			["CleanShot X"] = true,
		}
		-- Start with default filter that allows standard windows, excluding specific apps
		self.windowFilter = hs.window.filter.new(function(win)
			if not win:isStandard() then
				return false
			end
			local app = win:application()
			if app and excludedApps[app:name()] then
				return false
			end
			return true
		end)
		local windows = self.windowFilter:getWindows()

		-- Initialize window order based on current x positions
		self:_initializeWindowOrderFromCurrentPositions(windows)

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

		-- Initial distribution of existing windows
		self:_distributeWindows()
	end

	-- Set up application watcher to detect app quits
	if not self.appWatcher then
		self.appWatcher = hs.application.watcher.new(function(appName, eventType, app)
			self:_handleAppTerminated(appName, eventType, app)
		end)
		self.appWatcher:start()
		self.logger.d("Application watcher started")
	end

	return self
end

--- Initialize window order from current window positions (sorted by x coordinate)
function Helm:_initializeWindowOrderFromCurrentPositions(windows)
	-- Sort windows by their x position (left to right)
	local sortedWindows = {}
	for _, win in ipairs(windows) do
		if win:isStandard() then
			table.insert(sortedWindows, win)
		end
	end

	table.sort(sortedWindows, function(a, b)
		local frameA = a:frame()
		local frameB = b:frame()
		return frameA.x < frameB.x
	end)

	-- Assign sorted windows to active space
	local activeSpace = self:_getActiveSpace()
	if activeSpace then
		for _, win in ipairs(sortedWindows) do
			local winId = win:id()
			if winId then
				-- Add to window order
				table.insert(activeSpace.windowIds, winId)
				-- Map to active space
				self.windowSpaceMap[winId] = self.activeSpaceId
				-- Create a single-window column for this window
				table.insert(activeSpace.columns, { windowIds = { winId } })
				-- Update column map
				self.windowColumnMap[winId] = #activeSpace.columns
			end
		end
		self:_syncFromActiveSpace()
		self.logger.d("Initialized " .. #sortedWindows .. " windows in order by x position")
	end
end

function Helm:stop()
	if self.windowFilter then
		self.windowFilter:unsubscribeAll()
		self.windowFilter = nil
	end
	if self.appWatcher then
		self.appWatcher:stop()
		self.appWatcher = nil
	end
	return self
end

--- Get windows that belong to the current space only, sorted by x-position (left-to-right)
function Helm:_getWindowsInCurrentSpace()
	if not self.windowFilter then
		return {}
	end

	local allWindows = self.windowFilter:getWindows()
	local currentSpaceWindows = {}

	-- Collect windows with cached x-position to avoid O(n log n) frame() calls
	for _, win in ipairs(allWindows) do
		local winId = win:id()
		if winId and self.windowSpaceMap[winId] == self.activeSpaceId then
			table.insert(currentSpaceWindows, {
				win = win,
				x = win:frame().x
			})
		end
	end

	-- Sort by cached x-position for left-to-right spatial navigation
	table.sort(currentSpaceWindows, function(a, b)
		return a.x < b.x
	end)

	-- Extract just the window objects
	for i, entry in ipairs(currentSpaceWindows) do
		currentSpaceWindows[i] = entry.win
	end

	return currentSpaceWindows
end

--- Focus the window to the left (west) of the current window (within current space only)
function Helm:focusLeft()
	local currentWin = hs.window.focusedWindow()
	if not currentWin then
		return
	end

	local currentId = currentWin:id()
	if not currentId then
		return
	end

	local spaceWindows = self:_getWindowsInCurrentSpace()
	if #spaceWindows <= 1 then
		return
	end

	-- Find current window position in the space windows list
	local currentIndex = nil
	for i, win in ipairs(spaceWindows) do
		if win:id() == currentId then
			currentIndex = i
			break
		end
	end

	if not currentIndex then
		return
	end

	-- Focus the previous window (stop at start, no wrap)
	if currentIndex > 1 then
		spaceWindows[currentIndex - 1]:focus()
	end
end

--- Focus the window to the right (east) of the current window (within current space only)
function Helm:focusRight()
	local currentWin = hs.window.focusedWindow()
	if not currentWin then
		return
	end

	local currentId = currentWin:id()
	if not currentId then
		return
	end

	local spaceWindows = self:_getWindowsInCurrentSpace()
	if #spaceWindows <= 1 then
		return
	end

	-- Find current window position in the space windows list
	local currentIndex = nil
	for i, win in ipairs(spaceWindows) do
		if win:id() == currentId then
			currentIndex = i
			break
		end
	end

	if not currentIndex then
		return
	end

	-- Focus the next window (stop at end, no wrap)
	if currentIndex < #spaceWindows then
		spaceWindows[currentIndex + 1]:focus()
	end
end

--- Move the current window left in the order (operates on entire columns)
function Helm:moveWindowLeft()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	local space = self:_getActiveSpace()
	if not space then
		return
	end

	-- Get the column containing this window
	local colIdx = self.windowColumnMap[id]
	if not colIdx then
		return
	end

	-- Can't move if already in leftmost column
	if colIdx <= 1 then
		return
	end

	-- Swap columns
	local temp = space.columns[colIdx]
	space.columns[colIdx] = space.columns[colIdx - 1]
	space.columns[colIdx - 1] = temp

	-- Rebuild column map
	self:_rebuildColumnMap()

	self:_syncToActiveSpace()
	self:_distributeWindows()
end

--- Move the current window right in the order (operates on entire columns)
function Helm:moveWindowRight()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	local id = win:id()
	if not id then
		return
	end

	local space = self:_getActiveSpace()
	if not space then
		return
	end

	-- Get the column containing this window
	local colIdx = self.windowColumnMap[id]
	if not colIdx then
		return
	end

	-- Can't move if already in rightmost column
	if colIdx >= #space.columns then
		return
	end

	-- Swap columns
	local temp = space.columns[colIdx]
	space.columns[colIdx] = space.columns[colIdx + 1]
	space.columns[colIdx + 1] = temp

	-- Rebuild column map
	self:_rebuildColumnMap()

	self:_syncToActiveSpace()
	self:_distributeWindows()
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
		slurp = function()
			self:slurp()
		end,
		barf = function()
			self:barf()
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
		logWindowDebugInfo = function()
			self:logWindowDebugInfo()
		end,
	}
	hs.spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

return Helm
