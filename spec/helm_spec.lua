--- Tests for Helm Spoon window handling
local mock = require("spec.mock_hammerspoon")

describe("Helm", function()
	local Helm

	before_each(function()
		mock.reset()
		package.loaded["init"] = nil
		Helm = require("init")
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
			-- Set up initial spaces state
			Helm.spaces[1] = { id = 1, name = "space1", windowIds = { 10, 20 }, lastFocusedWindowId = 10, zoomedWindowId = nil, zoomedWindowOriginalFrame = nil }
			Helm.spaces[2] = { id = 2, name = "space2", windowIds = { 30, 40 }, lastFocusedWindowId = 30, zoomedWindowId = nil, zoomedWindowOriginalFrame = nil }
			Helm.activeSpaceId = 1
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 2, [40] = 2 }
			Helm.windowIds = { 10, 20 }
			Helm.lastFocusedWindowId = 10
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

			it("should update lastFocusedWindowId to the space's tracked window", function()
				mock.addMockWindow(30, true)
				mock.addMockWindow(40, true)

				Helm:activateSpace(2)

				assert.are.equal(30, Helm.lastFocusedWindowId)
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
		end)
end)
