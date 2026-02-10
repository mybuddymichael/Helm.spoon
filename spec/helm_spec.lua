--- Tests for Helm Spoon window handling
local mock = require("spec.mock_hammerspoon")

describe("Helm", function()
	local Helm

	before_each(function()
		mock.reset()
		package.loaded["init"] = nil
		Helm = require("init")
	end)

	describe("_hideWindow", function()
		it("should move window without resizing", function()
			local win = mock.addMockWindow(1, true)
			local originalFrame = { x = 100, y = 100, w = 800, h = 600 }
			win.frame = function() return originalFrame end

			local capturedFrame = nil
			win.setFrame = function(self, frame)
				capturedFrame = frame
			end

			Helm:_hideWindow(win)

			assert.is_not_nil(capturedFrame)
			assert.are.equal(originalFrame.w, capturedFrame.w, "width should be preserved")
			assert.are.equal(originalFrame.h, capturedFrame.h, "height should be preserved")
			-- Position should be at bottom-right corner
			local screenFrame = hs.screen.mainScreen():frame()
			assert.are.equal(screenFrame.x + screenFrame.w - Helm.hiddenWindowSize, capturedFrame.x)
			assert.are.equal(screenFrame.y + screenFrame.h - Helm.hiddenWindowSize, capturedFrame.y)
		end)

		it("should handle nil window gracefully", function()
			-- Should not throw an error
			Helm:_hideWindow(nil)
		end)

		it("should handle window with nil screen gracefully", function()
			local win = {
				screen = function() return nil end,
			}
			-- Should not throw an error
			Helm:_hideWindow(win)
		end)
	end)

	describe("handleWindowDestroyed", function()
		it("handles nil window gracefully", function()
			Helm.windowIds = { 1, 2, 3 }
			Helm:handleWindowDestroyed(nil)
			assert.are.same({ 1, 2, 3 }, Helm.windowIds)
		end)

		it("handles window with nil id gracefully", function()
			Helm.windowIds = { 1, 2, 3 }
			local fakeWin = { id = function() return nil end }
			Helm:handleWindowDestroyed(fakeWin)
			assert.are.same({ 1, 2, 3 }, Helm.windowIds)
		end)

		it("removes window id when window has valid id", function()
			Helm.windowIds = { 1, 2, 3 }
			local fakeWin = { id = function() return 2 end }
			Helm:handleWindowDestroyed(fakeWin)
			assert.are.same({ 1, 3 }, Helm.windowIds)
		end)
	end)

	describe("application quit cleanup", function()
		before_each(function()
			Helm:_initSpaces()
			-- Set up space 1 with windows from different apps
			-- Modify the existing space table (don't create a new one) to keep the reference
			Helm.spaces[1].windowIds = { 10, 20, 30 }
			Helm.spaces[1].lastFocusedWindowId = 10
			Helm.spaces[1].zoomedWindowId = nil
			Helm.spaces[1].zoomedWindowOriginalFrame = nil
			Helm.spaces[1].columns = { { windowIds = { 10, 20 } }, { windowIds = { 30 } } }
			Helm.activeSpaceId = 1
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1 }
			Helm.windowColumnMap = { [10] = 1, [20] = 1, [30] = 2 }
			-- Sync from active space to get the correct table references
			Helm:_syncFromActiveSpace()
			-- Create windows with different PIDs (simulating different apps)
			mock.addMockWindowWithApp(10, true, 1001) -- App A (PID 1001)
			mock.addMockWindowWithApp(20, true, 1001) -- App A (PID 1001)
			mock.addMockWindowWithApp(30, true, 1002) -- App B (PID 1002)
			-- Manually create app watcher (without calling start() which would re-initialize window order)
			Helm.appWatcher = hs.application.watcher.new(function(appName, eventType, app)
				Helm:_handleAppTerminated(appName, eventType, app)
			end)
		end)

		it("should clean up all windows from an app when it quits", function()
			-- Simulate app A (PID 1001) terminating
			mock.simulateAppTerminated(1001)

			-- Both windows from app A should be removed
			assert.are.same({ 30 }, Helm.windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].windowIds)
			assert.is_nil(Helm.windowSpaceMap[10])
			assert.is_nil(Helm.windowSpaceMap[20])
			assert.are.equal(1, Helm.windowSpaceMap[30])
		end)

		it("should clean up column structure when app quits", function()
			-- Simulate app A (PID 1001) terminating
			mock.simulateAppTerminated(1001)

			-- Column structure should be updated
			assert.are.same({ { windowIds = { 30 } } }, Helm.columns)
			assert.are.equal(1, Helm.windowColumnMap[30])
			assert.is_nil(Helm.windowColumnMap[10])
			assert.is_nil(Helm.windowColumnMap[20])
		end)

		it("should handle app quit when app has no tracked windows", function()
			-- Simulate app C (PID 9999) terminating - no windows tracked
			mock.simulateAppTerminated(9999)

			-- All windows should remain
			assert.are.same({ 10, 20, 30 }, Helm.windowIds)
		end)

		it("should clean up zoomed window state if app with zoomed window quits", function()
			-- Set window 10 as zoomed
			Helm.zoomedWindowId = 10
			Helm.zoomedWindowOriginalFrame = { x = 0, y = 0, w = 800, h = 600 }
			Helm:_syncToActiveSpace()

			-- Simulate app A (PID 1001) terminating
			mock.simulateAppTerminated(1001)

			-- Zoomed state should be cleared
			assert.is_nil(Helm.zoomedWindowId)
			assert.is_nil(Helm.zoomedWindowOriginalFrame)
		end)
	end)

	describe("handleWindowCreated", function()
		before_each(function()
			-- Initialize spaces for these tests
			Helm:_initSpaces()
		end)

		it("handles nil window gracefully", function()
			Helm.windowIds = {}
			Helm.spaces[1].windowIds = {}
			Helm:handleWindowCreated(nil)
			assert.are.same({}, Helm.windowIds)
		end)

		it("handles non-standard window gracefully", function()
			Helm.windowIds = {}
			Helm.spaces[1].windowIds = {}
			local fakeWin = {
				isStandard = function() return false end,
				id = function() return 1 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({}, Helm.windowIds)
		end)

		it("adds window id to end when no last focused window", function()
			Helm.windowIds = { 10, 20 }
			Helm.spaces[1].windowIds = { 10, 20 }
			Helm.lastFocusedWindowId = nil
			Helm.spaces[1].lastFocusedWindowId = nil
			local fakeWin = {
				isStandard = function() return true end,
				id = function() return 42 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({ 10, 20, 42 }, Helm.windowIds)
		end)

		it("adds window id after last focused window", function()
			Helm.windowIds = { 10, 20, 30 }
			Helm.spaces[1].windowIds = { 10, 20, 30 }
			Helm.lastFocusedWindowId = 20
			Helm.spaces[1].lastFocusedWindowId = 20
			local fakeWin = {
				isStandard = function() return true end,
				id = function() return 42 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({ 10, 20, 42, 30 }, Helm.windowIds)
		end)

		it("does not add duplicate window id", function()
			Helm.windowIds = { 10, 42, 30 }
			Helm.spaces[1].windowIds = { 10, 42, 30 }
			Helm.lastFocusedWindowId = 10
			Helm.spaces[1].lastFocusedWindowId = 10
			-- Mark 42 as already in space 1
			Helm.windowSpaceMap[42] = 1
			local fakeWin = {
				isStandard = function() return true end,
				id = function() return 42 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({ 10, 42, 30 }, Helm.windowIds)
		end)
	end)

        describe("virtual spaces", function()
		before_each(function()
			-- Initialize spaces first
			Helm:_initSpaces()
			-- Set up initial spaces state with columns
			Helm.spaces[1] = { id = 1, name = "space1", windowIds = { 10, 20 }, lastFocusedWindowId = 10, zoomedWindowId = nil, zoomedWindowOriginalFrame = nil, columns = { { windowIds = { 10 } }, { windowIds = { 20 } } } }
			Helm.spaces[2] = { id = 2, name = "space2", windowIds = { 30, 40 }, lastFocusedWindowId = 30, zoomedWindowId = nil, zoomedWindowOriginalFrame = nil, columns = { { windowIds = { 30 } }, { windowIds = { 40 } } } }
			Helm.activeSpaceId = 1
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 2, [40] = 2 }
			Helm.windowColumnMap = { [10] = 1, [20] = 2, [30] = 1, [40] = 2 }
			Helm.windowIds = { 10, 20 }
			Helm.lastFocusedWindowId = 10
			Helm.columns = Helm.spaces[1].columns
			-- Set up windowFilter mock
			Helm.windowFilter = hs.window.filter.new()
		end)

		describe("activateSpace", function()
			it("should hide windows from other spaces and restore windows in active space", function()
				-- Create mock windows for both spaces
				local win10 = mock.addMockWindow(10, true)
				local win20 = mock.addMockWindow(20, true)
				local win30 = mock.addMockWindow(30, true)
				local win40 = mock.addMockWindow(40, true)

				local hiddenWindows = {}
				local distributedWindows = {}

				-- Override setFrame to track hide/show
				win10.setFrame = function() table.insert(hiddenWindows, 10) end
				win20.setFrame = function() table.insert(hiddenWindows, 20) end

				-- Override _distributeWindows to track distribution
				local originalDistribute = Helm._distributeWindows
				Helm._distributeWindows = function(self)
					for _, id in ipairs(self.windowIds) do
						table.insert(distributedWindows, id)
					end
				end

				Helm:activateSpace(2)

				-- Restore original function
				Helm._distributeWindows = originalDistribute

				assert.are.equal(2, Helm.activeSpaceId)
				assert.are.same({ 30, 40 }, Helm.windowIds)
				-- Windows from space 1 should be hidden
				assert.are.same({ 10, 20 }, hiddenWindows)
				-- Windows from space 2 should be distributed
				assert.are.same({ 30, 40 }, distributedWindows)
			end)

			it("should not resize windows when hiding during space switch", function()
				local win10 = mock.addMockWindow(10, true)
				local win20 = mock.addMockWindow(20, true)
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)

				-- Set up specific window frames
				local frame10 = { x = 0, y = 0, w = 600, h = 400 }
				local frame20 = { x = 600, y = 0, w = 800, h = 600 }
				win10.frame = function() return frame10 end
				win20.frame = function() return frame20 end

				local capturedFrames = {}
				win10.setFrame = function(self, frame)
					capturedFrames[10] = frame
				end
				win20.setFrame = function(self, frame)
					capturedFrames[20] = frame
				end

				Helm:activateSpace(2)

				-- Verify windows were moved but not resized
				assert.is_not_nil(capturedFrames[10])
				assert.is_not_nil(capturedFrames[20])
				assert.are.equal(frame10.w, capturedFrames[10].w, "win10 width should be preserved")
				assert.are.equal(frame10.h, capturedFrames[10].h, "win10 height should be preserved")
				assert.are.equal(frame20.w, capturedFrames[20].w, "win20 width should be preserved")
				assert.are.equal(frame20.h, capturedFrames[20].h, "win20 height should be preserved")
			end)

			it("should update lastFocusedWindowId to the space's tracked window", function()
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)

				Helm:activateSpace(2)

				assert.are.equal(30, Helm.lastFocusedWindowId)
			end)
		end)

		describe("logWindowDebugInfo", function()
			local logs

			before_each(function()
				Helm:_initSpaces()
				logs = {}
				Helm.logger = {
					d = function(message)
						table.insert(logs, message)
					end,
				}
			end)

			it("logs window details with space and screen info", function()
				local win1 = mock.addMockWindow(10, true)
				local win2 = mock.addMockWindow(20, true)

				Helm.windowFilter = hs.window.filter.new()
				Helm.windowSpaceMap = { [10] = 1, [20] = 2 }

				hs.spaces = {
					windowSpaces = function()
						return { 7 }
					end,
				}

				Helm:logWindowDebugInfo()

				local output = table.concat(logs, "\n")
				assert.is_true(output:find("Window Debug Info", 1, true) ~= nil)
				assert.is_true(output:find("Virtual Space: 1", 1, true) ~= nil)
				assert.is_true(output:find("Virtual Space: 2", 1, true) ~= nil)
				assert.is_true(output:find('Screen: "Mock Screen" (ID: 1)', 1, true) ~= nil)
				assert.is_true(output:find("macOS Spaces: 7", 1, true) ~= nil)
				assert.is_true(output:find("Window Properties:", 1, true) ~= nil)

				assert.is_not_nil(win1)
				assert.is_not_nil(win2)
			end)
		end)

                describe("moveWindowToSpace", function()
			it("should update windowSpaceMap and redistribute", function()
				local win10 = mock.addMockWindow(10, true)
				local win20 = mock.addMockWindow(20, true)
				local win30 = mock.addMockWindow(30, true)
				local win40 = mock.addMockWindow(40, true)

				local distributed = false
				Helm._distributeWindows = function() distributed = true end

				Helm:moveWindowToSpace(win10, 2)

				assert.are.equal(2, Helm.windowSpaceMap[10])
				assert.are.same({ 20 }, Helm.spaces[1].windowIds)
				assert.are.same({ 30, 40, 10 }, Helm.spaces[2].windowIds)
				assert.is_true(distributed)
			end)

			it("should hide window when moving to inactive space", function()
				local win10 = mock.addMockWindow(10, true)
				mock.addMockWindow(20, true)
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)

				local hiddenWindows = {}
				win10.setFrame = function() table.insert(hiddenWindows, 10) end

				Helm:moveWindowToSpace(win10, 2)

				assert.are.same({ 10 }, hiddenWindows)
			end)

			it("should not resize window when hiding (preserve original dimensions)", function()
				local win10 = mock.addMockWindow(10, true)
				mock.addMockWindow(20, true)
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)

				-- Set up a specific window frame
				local originalFrame = { x = 100, y = 100, w = 800, h = 600 }
				win10.frame = function() return originalFrame end

				local capturedFrame = nil
				win10.setFrame = function(self, frame)
					capturedFrame = frame
				end

				Helm:moveWindowToSpace(win10, 2)

				-- Verify the window was moved but not resized
				assert.is_not_nil(capturedFrame)
				assert.are.equal(originalFrame.w, capturedFrame.w, "width should be preserved")
				assert.are.equal(originalFrame.h, capturedFrame.h, "height should be preserved")
				-- Position should be at bottom-right corner (screen w/h - hiddenWindowSize)
				local screenFrame = hs.screen.mainScreen():frame()
				assert.are.equal(screenFrame.x + screenFrame.w - Helm.hiddenWindowSize, capturedFrame.x)
				assert.are.equal(screenFrame.y + screenFrame.h - Helm.hiddenWindowSize, capturedFrame.y)
			end)
		end)

		describe("auto-activation on window focus", function()
			it("should detect and activate space when focusing a window in another space", function()
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)
				mock.addMockWindow(10, true)
				mock.addMockWindow(20, true)

				local activatedSpace = nil
				Helm.activateSpace = function(self, spaceId)
					activatedSpace = spaceId
				end

				-- Simulate focusing window 30 which is in space 2
				mock.setFocusedWindow(30)
				Helm:_handleWindowFocused(hs.window.focusedWindow())

				assert.are.equal(2, activatedSpace)
			end)
		end)

		describe("handleWindowCreated with spaces", function()
			it("should add new window to active space", function()
				local fakeWin = {
					isStandard = function() return true end,
					id = function() return 50 end,
				}
				mock.addMockWindow(50, true)

				-- Set lastFocusedWindowId to nil so window gets added at end
				Helm.lastFocusedWindowId = nil
				Helm.spaces[1].lastFocusedWindowId = nil

				Helm:handleWindowCreated(fakeWin)

				assert.are.equal(1, Helm.windowSpaceMap[50])
				assert.are.same({ 10, 20, 50 }, Helm.spaces[1].windowIds)
			end)
		end)

		describe("lastFocusedWindowId per space", function()
			it("should track last focused window per space independently", function()
				mock.addMockWindow(10, true)
				mock.addMockWindow(20, true)
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)

				-- Focus window 20 in space 1
				mock.setFocusedWindow(20)
				Helm:_handleWindowFocused(hs.window.focusedWindow())

				assert.are.equal(20, Helm.spaces[1].lastFocusedWindowId)
				assert.are.equal(30, Helm.spaces[2].lastFocusedWindowId) -- unchanged

				-- Switch to space 2 and focus window 40
				Helm.activeSpaceId = 2
				Helm.windowIds = Helm.spaces[2].windowIds
				mock.setFocusedWindow(40)
				Helm:_handleWindowFocused(hs.window.focusedWindow())

				assert.are.equal(40, Helm.spaces[2].lastFocusedWindowId)
				assert.are.equal(20, Helm.spaces[1].lastFocusedWindowId) -- unchanged
			end)
		end)

		describe("space state persistence", function()
			it("should persist windowIds for each space", function()
				assert.are.same({ 10, 20 }, Helm.spaces[1].windowIds)
				assert.are.same({ 30, 40 }, Helm.spaces[2].windowIds)
			end)

			it("should persist lastFocusedWindowId for each space", function()
				assert.are.equal(10, Helm.spaces[1].lastFocusedWindowId)
				assert.are.equal(30, Helm.spaces[2].lastFocusedWindowId)
			end)

			it("should persist zoom state per space", function()
				Helm.spaces[1].zoomedWindowId = 10
				Helm.spaces[1].zoomedWindowOriginalFrame = { x = 0, y = 0, w = 100, h = 100 }
				Helm.spaces[2].zoomedWindowId = 40
				Helm.spaces[2].zoomedWindowOriginalFrame = { x = 200, y = 200, w = 300, h = 300 }

				assert.are.equal(10, Helm.spaces[1].zoomedWindowId)
				assert.are.same({ x = 0, y = 0, w = 100, h = 100 }, Helm.spaces[1].zoomedWindowOriginalFrame)
				assert.are.equal(40, Helm.spaces[2].zoomedWindowId)
				assert.are.same({ x = 200, y = 200, w = 300, h = 300 }, Helm.spaces[2].zoomedWindowOriginalFrame)
			end)
		end)

		describe("activateSpace focus behavior", function()
			it("should focus the first window when space has no lastFocusedWindowId", function()
				-- Set up space 2 with no last focused window
				Helm.spaces[2].lastFocusedWindowId = nil
				Helm.lastFocusedWindowId = nil

				local win30 = mock.addMockWindow(30, true)
				local win40 = mock.addMockWindow(40, true)
				mock.addMockWindow(10, true)
				mock.addMockWindow(20, true)

				local focusedWindow = nil
				win30.focus = function() focusedWindow = 30 end
				win40.focus = function() focusedWindow = 40 end

				Helm:activateSpace(2)

				-- Should focus the first window in the space (30)
				assert.are.equal(30, focusedWindow)
			end)

			it("should focus lastFocusedWindowId when available", function()
				local win30 = mock.addMockWindow(30, true)
				local win40 = mock.addMockWindow(40, true)
				mock.addMockWindow(10, true)
				mock.addMockWindow(20, true)

				local focusedWindow = nil
				win30.focus = function() focusedWindow = 30 end
				win40.focus = function() focusedWindow = 40 end

				Helm:activateSpace(2)

				-- Should focus window 30 (the lastFocusedWindowId for space 2)
				assert.are.equal(30, focusedWindow)
			end)
		end)

		describe("focusLeft and focusRight", function()
			before_each(function()
				-- Set up mock windows in current space (space 1)
				local win10 = mock.addMockWindow(10, true)
				local win20 = mock.addMockWindow(20, true)
				-- Set up mock windows in other space (space 2)
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)

				-- Track which window gets focused
				win10.focus = function() mock.setFocusedWindow(10) end
				win20.focus = function() mock.setFocusedWindow(20) end
			end)

			it("focusLeft should only consider windows in the current space", function()
				-- Start focused on window 20
				mock.setFocusedWindow(20)

				-- Mock _getWindowsInCurrentSpace to return only space 1 windows
				local originalGetWindows = Helm._getWindowsInCurrentSpace
				Helm._getWindowsInCurrentSpace = function()
					return {
						{ id = function() return 10 end, focus = function() mock.setFocusedWindow(10) end },
						{ id = function() return 20 end, focus = function() mock.setFocusedWindow(20) end },
					}
				end

				Helm:focusLeft()

				-- Should focus window 10 (the other window in space 1)
				assert.are.equal(10, hs.window.focusedWindow():id())

				Helm._getWindowsInCurrentSpace = originalGetWindows
			end)

			it("focusRight should only consider windows in the current space", function()
				-- Start focused on window 10
				mock.setFocusedWindow(10)

				-- Mock _getWindowsInCurrentSpace to return only space 1 windows
				local originalGetWindows = Helm._getWindowsInCurrentSpace
				Helm._getWindowsInCurrentSpace = function()
					return {
						{ id = function() return 10 end, focus = function() mock.setFocusedWindow(10) end },
						{ id = function() return 20 end, focus = function() mock.setFocusedWindow(20) end },
					}
				end

				Helm:focusRight()

				-- Should focus window 20 (the other window in space 1)
				assert.are.equal(20, hs.window.focusedWindow():id())

				Helm._getWindowsInCurrentSpace = originalGetWindows
			end)
		end)

		describe("focusLeft and focusRight with spatial ordering bug", function()
			it("should navigate based on spatial position, not windowIds order", function()
				-- This test demonstrates the bug: windowIds order doesn't match visual layout
				-- Windows are arranged left-to-right visually as: [win30] [win10] [win20]
				-- But windowIds order is: 10, 20, 30 (creation/focus order)

				local win10 = mock.addMockWindow(10, true)
				local win20 = mock.addMockWindow(20, true)
				local win30 = mock.addMockWindow(30, true)

				-- Set up windowSpaceMap - all windows in space 1
				Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1 }
				Helm.windowIds = { 10, 20, 30 }  -- Order: 10, 20, 30
				Helm.spaces[1].windowIds = { 10, 20, 30 }

				-- Mock frames to simulate visual layout: [30] [10] [20]
				-- Window 30 at x=0 (left), window 10 at x=400 (middle), window 20 at x=800 (right)
				win30.frame = function() return { x = 0, y = 0, w = 300, h = 600 } end
				win10.frame = function() return { x = 400, y = 0, w = 300, h = 600 } end
				win20.frame = function() return { x = 800, y = 0, w = 300, h = 600 } end

				-- Track focus
				local focusedId = nil
				win10.focus = function() focusedId = 10 end
				win20.focus = function() focusedId = 20 end
				win30.focus = function() focusedId = 30 end

				-- Test 1: Focus window 10 (middle), press left -> should go to window 30 (leftmost)
				mock.setFocusedWindow(10)
				focusedId = nil

				Helm:focusLeft()

				-- BUG: Currently returns 10 (windowIds order: 10 is at index 1, so no window to the left)
				-- EXPECTED: Should return 30 (spatially to the left of 10)
				assert.are.equal(30, focusedId, "focusLeft from middle window should go to leftmost window")

				-- Test 2: Focus window 10 (middle), press right -> should go to window 20 (rightmost)
				mock.setFocusedWindow(10)
				focusedId = nil

				Helm:focusRight()

				-- BUG: Currently returns 20 (this happens to work because 20 is right of 10 in windowIds)
				-- But this is coincidental - it works because windowIds order happens to match here
				assert.are.equal(20, focusedId, "focusRight from middle window should go to rightmost window")

				-- Test 3: Focus window 30 (leftmost), press right -> should go to window 10 (middle)
				mock.setFocusedWindow(30)
				focusedId = nil

				Helm:focusRight()

				-- BUG: Currently returns nil (window 30 is at end of windowIds, so no window to the right)
				-- EXPECTED: Should return 10 (spatially to the right of 30)
				assert.are.equal(10, focusedId, "focusRight from leftmost window should go to middle window")
			end)
		end)
	end)
end)
