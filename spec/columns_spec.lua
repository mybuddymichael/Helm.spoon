--- Tests for Helm Spoon column functionality (slurp/barf)
local mock = require("spec.mock_hammerspoon")

describe("Helm columns", function()
	local Helm

	before_each(function()
		mock.reset()
		package.loaded["init"] = nil
		Helm = require("init")
		Helm:_initSpaces()
	end)

	describe("data model", function()
		it("should initialize with empty columns list in each space", function()
			assert.are.same({}, Helm.spaces[1].columns)
			assert.are.same({}, Helm.spaces[2].columns)
		end)

		it("should initialize with empty windowColumnMap", function()
			assert.are.same({}, Helm.windowColumnMap)
		end)
	end)

	describe("handleWindowCreated with columns", function()
		it("should create single-window column when adding first window", function()
			local fakeWin = {
				isStandard = function() return true end,
				id = function() return 10 end,
			}
			mock.addMockWindow(10, true)

			Helm:handleWindowCreated(fakeWin)

			assert.are.equal(1, #Helm.spaces[1].columns)
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.equal(1, Helm.windowColumnMap[10])
		end)

		it("should create separate column for each new window", function()
			local fakeWin1 = { isStandard = function() return true end, id = function() return 10 end }
			local fakeWin2 = { isStandard = function() return true end, id = function() return 20 end }
			mock.addMockWindow(10, true)
			mock.addMockWindow(20, true)

			Helm:handleWindowCreated(fakeWin1)
			Helm:handleWindowCreated(fakeWin2)

			assert.are.equal(2, #Helm.spaces[1].columns)
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 20 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.equal(1, Helm.windowColumnMap[10])
			assert.are.equal(2, Helm.windowColumnMap[20])
		end)

		it("should insert after last focused window's column", function()
			-- First window
			local fakeWin1 = { isStandard = function() return true end, id = function() return 10 end }
			mock.addMockWindow(10, true)
			Helm:handleWindowCreated(fakeWin1)

			-- Second window
			local fakeWin2 = { isStandard = function() return true end, id = function() return 20 end }
			mock.addMockWindow(20, true)
			Helm:handleWindowCreated(fakeWin2)

			-- Set last focused to first window
			Helm.spaces[1].lastFocusedWindowId = 10
			Helm.lastFocusedWindowId = 10

			-- Third window should be inserted after first window's column
			local fakeWin3 = { isStandard = function() return true end, id = function() return 30 end }
			mock.addMockWindow(30, true)
			Helm:handleWindowCreated(fakeWin3)

			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 20 }, Helm.spaces[1].columns[3].windowIds)
		end)
	end)

	describe("handleWindowDestroyed with columns", function()
		it("should remove window from its column", function()
			-- Set up space with columns
			Helm.spaces[1].columns = {
				{ windowIds = { 10, 20 } },
				{ windowIds = { 30 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 1, [30] = 2 }
			Helm.windowIds = { 10, 20, 30 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1 }

			local fakeWin = { id = function() return 20 end }
			Helm:handleWindowDestroyed(fakeWin)

			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[2].windowIds)
			assert.is_nil(Helm.windowColumnMap[20])
		end)

		it("should remove empty column when last window is destroyed", function()
			Helm.spaces[1].columns = {
				{ windowIds = { 10 } },
				{ windowIds = { 20 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 2 }
			Helm.windowIds = { 10, 20 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1 }

			local fakeWin = { id = function() return 10 end }
			Helm:handleWindowDestroyed(fakeWin)

			assert.are.equal(1, #Helm.spaces[1].columns)
			assert.are.same({ 20 }, Helm.spaces[1].columns[1].windowIds)
			assert.is_nil(Helm.windowColumnMap[10])
		end)
	end)

	describe("slurp", function()
		before_each(function()
			-- Set up space with multiple single-window columns
			Helm.spaces[1].columns = {
				{ windowIds = { 10 } },
				{ windowIds = { 20 } },
				{ windowIds = { 30 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 2, [30] = 3 }
			Helm.windowIds = { 10, 20, 30 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1 }
			Helm.activeSpaceId = 1
			Helm.columns = Helm.spaces[1].columns
			mock.addMockWindow(10, true)
			mock.addMockWindow(20, true)
			mock.addMockWindow(30, true)
		end)

		it("should merge focused window into column to the left", function()
			-- Focus window 20 (second column)
			mock.setFocusedWindow(20)

			Helm:slurp()

			-- Window 20 should now be in column 1 (at the bottom)
			assert.are.equal(2, #Helm.spaces[1].columns)
			assert.are.same({ 10, 20 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.equal(1, Helm.windowColumnMap[20])
		end)

		it("should do nothing if window is already in multi-window column", function()
			-- Set up window 20 already in a multi-window column
			Helm.spaces[1].columns = {
				{ windowIds = { 10 } },
				{ windowIds = { 20, 25 } },
				{ windowIds = { 30 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 2, [25] = 2, [30] = 3 }

			mock.setFocusedWindow(20)

			Helm:slurp()

			-- Nothing should change
			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 20, 25 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[3].windowIds)
		end)

		it("should do nothing if no column to the left", function()
			-- Focus window 10 (first column)
			mock.setFocusedWindow(10)

			Helm:slurp()

			-- Nothing should change
			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
		end)

		it("should do nothing if single window in space", function()
			Helm.spaces[1].columns = {
				{ windowIds = { 10 } },
			}
			Helm.windowColumnMap = { [10] = 1 }
			mock.setFocusedWindow(10)

			Helm:slurp()

			assert.are.equal(1, #Helm.spaces[1].columns)
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
		end)

		it("should keep focus on slurped window", function()
			-- Get the existing window 20 from mock
			local win20 = hs.window.get(20)
			local focused = false
			win20.focus = function() focused = true end
			mock.setFocusedWindow(20)

			Helm:slurp()

			assert.is_true(focused)
		end)
	end)

	describe("barf", function()
		before_each(function()
			-- Set up space with a multi-window column
			Helm.spaces[1].columns = {
				{ windowIds = { 10, 20, 30 } },
				{ windowIds = { 40 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 1, [30] = 1, [40] = 2 }
			Helm.windowIds = { 10, 20, 30, 40 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1, [40] = 1 }
			Helm.activeSpaceId = 1
			Helm.columns = Helm.spaces[1].columns
			mock.addMockWindow(10, true)
			mock.addMockWindow(20, true)
			mock.addMockWindow(30, true)
			mock.addMockWindow(40, true)
		end)

		it("should push focused window out to new column on the right", function()
			-- Focus window 20 (middle of first column)
			mock.setFocusedWindow(20)

			Helm:barf()

			-- Window 20 should now be in its own column between 10 and 40
			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 10, 30 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 20 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 40 }, Helm.spaces[1].columns[3].windowIds)
			assert.are.equal(2, Helm.windowColumnMap[20])
		end)

		it("should do nothing if window is alone in its column", function()
			-- Focus window 40 (alone in its column)
			mock.setFocusedWindow(40)

			Helm:barf()

			-- Nothing should change
			assert.are.equal(2, #Helm.spaces[1].columns)
			assert.are.same({ 10, 20, 30 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 40 }, Helm.spaces[1].columns[2].windowIds)
		end)

		it("should keep focus on barfed window", function()
			-- Get the existing window 20 from mock
			local win20 = hs.window.get(20)
			local focused = false
			win20.focus = function() focused = true end
			mock.setFocusedWindow(20)

			Helm:barf()

			assert.is_true(focused)
		end)

		it("should handle barfing last window in column", function()
			-- Focus window 30 (last in first column)
			mock.setFocusedWindow(30)

			Helm:barf()

			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 10, 20 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 40 }, Helm.spaces[1].columns[3].windowIds)
		end)

		it("should handle barfing first window in column", function()
			-- Focus window 10 (first in first column)
			mock.setFocusedWindow(10)

			Helm:barf()

			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 20, 30 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 10 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 40 }, Helm.spaces[1].columns[3].windowIds)
		end)
	end)

	describe("moveWindowLeft with columns", function()
		before_each(function()
			-- Set up space with columns
			Helm.spaces[1].columns = {
				{ windowIds = { 10, 20 } },
				{ windowIds = { 30 } },
				{ windowIds = { 40, 50 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 1, [30] = 2, [40] = 3, [50] = 3 }
			Helm.windowIds = { 10, 20, 30, 40, 50 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1, [40] = 1, [50] = 1 }
			Helm.activeSpaceId = 1
			Helm.columns = Helm.spaces[1].columns
			mock.addMockWindow(10, true)
			mock.addMockWindow(20, true)
			mock.addMockWindow(30, true)
			mock.addMockWindow(40, true)
			mock.addMockWindow(50, true)
		end)

		it("should swap entire column with column to the left", function()
			-- Focus window 30 (in second column)
			mock.setFocusedWindow(30)

			Helm:moveWindowLeft()

			-- Columns 1 and 2 should be swapped
			assert.are.same({ 30 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 10, 20 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 40, 50 }, Helm.spaces[1].columns[3].windowIds)
			-- Column map should be updated
			assert.are.equal(2, Helm.windowColumnMap[10])
			assert.are.equal(2, Helm.windowColumnMap[20])
			assert.are.equal(1, Helm.windowColumnMap[30])
		end)

		it("should do nothing if already in leftmost column", function()
			-- Focus window 10 (in first column)
			mock.setFocusedWindow(10)

			Helm:moveWindowLeft()

			-- Nothing should change
			assert.are.same({ 10, 20 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 40, 50 }, Helm.spaces[1].columns[3].windowIds)
		end)
	end)

	describe("moveWindowRight with columns", function()
		before_each(function()
			Helm.spaces[1].columns = {
				{ windowIds = { 10, 20 } },
				{ windowIds = { 30 } },
				{ windowIds = { 40, 50 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 1, [30] = 2, [40] = 3, [50] = 3 }
			Helm.windowIds = { 10, 20, 30, 40, 50 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1, [40] = 1, [50] = 1 }
			Helm.activeSpaceId = 1
			Helm.columns = Helm.spaces[1].columns
			mock.addMockWindow(10, true)
			mock.addMockWindow(20, true)
			mock.addMockWindow(30, true)
			mock.addMockWindow(40, true)
			mock.addMockWindow(50, true)
		end)

		it("should swap entire column with column to the right", function()
			-- Focus window 30 (in second column)
			mock.setFocusedWindow(30)

			Helm:moveWindowRight()

			-- Columns 2 and 3 should be swapped
			assert.are.same({ 10, 20 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 40, 50 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[3].windowIds)
			assert.are.equal(3, Helm.windowColumnMap[30])
			assert.are.equal(2, Helm.windowColumnMap[40])
			assert.are.equal(2, Helm.windowColumnMap[50])
		end)

		it("should do nothing if already in rightmost column", function()
			-- Focus window 40 (in last column)
			mock.setFocusedWindow(40)

			Helm:moveWindowRight()

			-- Nothing should change
			assert.are.same({ 10, 20 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 40, 50 }, Helm.spaces[1].columns[3].windowIds)
		end)
		end)

		describe("moveWindowToSpace with columns", function()
		before_each(function()
			-- Set up two spaces with columns
			Helm.spaces[1].columns = {
				{ windowIds = { 10, 20 } },
				{ windowIds = { 30 } },
			}
			Helm.spaces[2].columns = {
				{ windowIds = { 40 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 1, [30] = 2, [40] = 1 }
			Helm.windowIds = { 10, 20, 30 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1, [40] = 2 }
			Helm.activeSpaceId = 1
			Helm.columns = Helm.spaces[1].columns
			mock.addMockWindow(10, true)
			mock.addMockWindow(20, true)
			mock.addMockWindow(30, true)
			mock.addMockWindow(40, true)
		end)

		it("should barf window first if in multi-window column", function()
			-- Get existing window 20
			local win20 = hs.window.get(20)

			Helm:moveWindowToSpace(win20, 2)

			-- Window 20 should be barfed from column 1 first
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[2].windowIds)
			-- Then moved to space 2 as new column
			assert.are.equal(2, #Helm.spaces[2].columns)
			assert.are.same({ 40 }, Helm.spaces[2].columns[1].windowIds)
			assert.are.same({ 20 }, Helm.spaces[2].columns[2].windowIds)
			assert.are.equal(2, Helm.windowSpaceMap[20])
			assert.are.equal(2, Helm.windowColumnMap[20])
		end)

		it("should move window normally if already alone in column", function()
			-- Get existing window 30
			local win30 = hs.window.get(30)

			Helm:moveWindowToSpace(win30, 2)

			-- Window 30 should just be moved (no barf needed)
			assert.are.same({ 10, 20 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.equal(1, #Helm.spaces[1].columns)
			assert.are.equal(2, #Helm.spaces[2].columns)
			assert.are.same({ 40 }, Helm.spaces[2].columns[1].windowIds)
			assert.are.same({ 30 }, Helm.spaces[2].columns[2].windowIds)
		end)
		end)

		describe("focus navigation with columns", function()
			before_each(function()
				Helm.spaces[1].columns = {
					{ windowIds = { 10, 20, 30 } },
					{ windowIds = { 40 } },
					{ windowIds = { 50, 60 } },
				}
				Helm.windowColumnMap = {
					[10] = 1,
					[20] = 1,
					[30] = 1,
					[40] = 2,
					[50] = 3,
					[60] = 3,
				}
				Helm.windowIds = { 10, 20, 30, 40, 50, 60 }
				Helm.windowSpaceMap = {
					[10] = 1,
					[20] = 1,
					[30] = 1,
					[40] = 1,
					[50] = 1,
					[60] = 1,
				}
				Helm.activeSpaceId = 1
				Helm.columns = Helm.spaces[1].columns
				local win10 = mock.addMockWindow(10, true)
				local win20 = mock.addMockWindow(20, true)
				local win30 = mock.addMockWindow(30, true)
				local win40 = mock.addMockWindow(40, true)
				local win50 = mock.addMockWindow(50, true)
				local win60 = mock.addMockWindow(60, true)
				win10.focus = function() mock.setFocusedWindow(10) end
				win20.focus = function() mock.setFocusedWindow(20) end
				win30.focus = function() mock.setFocusedWindow(30) end
				win40.focus = function() mock.setFocusedWindow(40) end
				win50.focus = function() mock.setFocusedWindow(50) end
				win60.focus = function() mock.setFocusedWindow(60) end
			end)

			it("focusUp should move within a column", function()
				mock.setFocusedWindow(20)

				Helm:focusUp()

				assert.are.equal(10, hs.window.focusedWindow():id())
			end)

			it("focusUp should do nothing at top of column", function()
				mock.setFocusedWindow(10)

				Helm:focusUp()

				assert.are.equal(10, hs.window.focusedWindow():id())
			end)

			it("focusDown should move within a column", function()
				mock.setFocusedWindow(20)

				Helm:focusDown()

				assert.are.equal(30, hs.window.focusedWindow():id())
			end)

			it("focusDown should do nothing at bottom of column", function()
				mock.setFocusedWindow(30)

				Helm:focusDown()

				assert.are.equal(30, hs.window.focusedWindow():id())
			end)

			it("focusRight should move to the next column", function()
				mock.setFocusedWindow(20)

				Helm:focusRight()

				assert.are.equal(40, hs.window.focusedWindow():id())
			end)

			it("focusLeft should move to the previous column", function()
				mock.setFocusedWindow(40)

				Helm:focusLeft()

				assert.are.equal(10, hs.window.focusedWindow():id())
			end)

                        it("focusLeft should do nothing at leftmost column", function()
                                mock.setFocusedWindow(10)
                                Helm:focusLeft()
                                assert.are.equal(10, hs.window.focusedWindow():id())
                        end)

                        it("focusLeft should return to last focused window in target column", function()
                                mock.setFocusedWindow(20)
                                Helm:_handleWindowFocused(hs.window.focusedWindow())

                                mock.setFocusedWindow(40)
                                Helm:_handleWindowFocused(hs.window.focusedWindow())

                                Helm:focusLeft()

                                assert.are.equal(20, hs.window.focusedWindow():id())
                        end)

                        it("focusRight should return to last focused window in target column", function()
                                mock.setFocusedWindow(60)
                                Helm:_handleWindowFocused(hs.window.focusedWindow())

                                mock.setFocusedWindow(40)
                                Helm:_handleWindowFocused(hs.window.focusedWindow())

                                Helm:focusRight()

                                assert.are.equal(60, hs.window.focusedWindow():id())
                        end)

                        it("focusRight should do nothing at rightmost column", function()
                                mock.setFocusedWindow(60)
                                Helm:focusRight()
                                assert.are.equal(60, hs.window.focusedWindow():id())
			end)
		end)

		describe("_distributeWindows with columns", function()
		before_each(function()
			Helm.windowFilter = hs.window.filter.new()
			Helm.activeSpaceId = 1
			Helm.columns = Helm.spaces[1].columns
		end)

		it("should distribute columns horizontally", function()
			-- Set up 3 columns
			Helm.spaces[1].columns = {
				{ windowIds = { 10 } },
				{ windowIds = { 20 } },
				{ windowIds = { 30 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 2, [30] = 3 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1 }
			-- Sync to active space
			Helm.columns = Helm.spaces[1].columns

			local win10 = mock.addMockWindow(10, true)
			local win20 = mock.addMockWindow(20, true)
			local win30 = mock.addMockWindow(30, true)

			local frames = {}
			win10.setFrame = function(_, f) frames[10] = f end
			win20.setFrame = function(_, f) frames[20] = f end
			win30.setFrame = function(_, f) frames[30] = f end

			Helm:_distributeWindows()

			-- Each column should have roughly 1/3 of the width
			local screenFrame = hs.screen.mainScreen():frame()
			local availableWidth = screenFrame.w - (2 * Helm.screenPadding) - (2 * Helm.windowGap)
			local expectedWidth = availableWidth / 3

			assert.is_not_nil(frames[10])
			assert.is_not_nil(frames[20])
			assert.is_not_nil(frames[30])
			-- All windows in single-window columns should have same width
			assert.are.equal(expectedWidth, frames[10].w)
			assert.are.equal(expectedWidth, frames[20].w)
			assert.are.equal(expectedWidth, frames[30].w)
		end)

		it("should stack windows vertically within multi-window columns", function()
			-- Set up 2 columns, one with 2 windows
			Helm.spaces[1].columns = {
				{ windowIds = { 10, 20 } },
				{ windowIds = { 30 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 1, [30] = 2 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1, [30] = 1 }
			-- Sync to active space
			Helm.columns = Helm.spaces[1].columns

			local win10 = mock.addMockWindow(10, true)
			local win20 = mock.addMockWindow(20, true)
			local win30 = mock.addMockWindow(30, true)

			local frames = {}
			win10.setFrame = function(_, f) frames[10] = f end
			win20.setFrame = function(_, f) frames[20] = f end
			win30.setFrame = function(_, f) frames[30] = f end

			Helm:_distributeWindows()

			local screenFrame = hs.screen.mainScreen():frame()
			local availableWidth = screenFrame.w - (2 * Helm.screenPadding) - Helm.windowGap
			local colWidth = availableWidth / 2
			local availableHeight = screenFrame.h - (2 * Helm.screenPadding) - Helm.windowGap
			local rowHeight = availableHeight / 2

			-- Windows 10 and 20 should be in same column, stacked vertically
			assert.are.equal(colWidth, frames[10].w)
			assert.are.equal(colWidth, frames[20].w)
			assert.are.equal(rowHeight, frames[10].h)
			assert.are.equal(rowHeight, frames[20].h)
			-- Window 10 should be above window 20
			assert.is_true(frames[10].y < frames[20].y)
			-- Window 30 should have full height (single window in column)
			assert.are.equal(screenFrame.h - (2 * Helm.screenPadding), frames[30].h)
		end)
	end)

	describe("sync functions with columns", function()
		it("should sync columns from active space", function()
			Helm.spaces[1].columns = {
				{ windowIds = { 10, 20 } },
				{ windowIds = { 30 } },
			}
			Helm.activeSpaceId = 1

			Helm:_syncFromActiveSpace()

			assert.are.same(Helm.spaces[1].columns, Helm.columns)
		end)

		it("should sync columns to active space", function()
			Helm.columns = {
				{ windowIds = { 10, 20 } },
				{ windowIds = { 30 } },
			}
			Helm.activeSpaceId = 1

			Helm:_syncToActiveSpace()

			assert.are.same(Helm.columns, Helm.spaces[1].columns)
		end)
	end)

	describe("startup initialization", function()
		it("should populate columns when initializing window order from current positions", function()
			-- Simulate existing windows at startup (before _initSpaces)
			local win10 = mock.addMockWindow(10, true)
			local win20 = mock.addMockWindow(20, true)
			local win30 = mock.addMockWindow(30, true)

			-- Manually set positions so they sort predictably
			win10.frame = function() return { x = 100, y = 0, w = 400, h = 600 } end
			win20.frame = function() return { x = 500, y = 0, w = 400, h = 600 } end
			win30.frame = function() return { x = 900, y = 0, w = 400, h = 600 } end

			-- Call the initialization function that runs at startup
			local allWindows = { win10, win20, win30 }
			Helm:_initializeWindowOrderFromCurrentPositions(allWindows)

			-- Verify columns were created for each window
			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 10 }, Helm.spaces[1].columns[1].windowIds)
			assert.are.same({ 20 }, Helm.spaces[1].columns[2].windowIds)
			assert.are.same({ 30 }, Helm.spaces[1].columns[3].windowIds)

			-- Verify column map was populated
			assert.are.equal(1, Helm.windowColumnMap[10])
			assert.are.equal(2, Helm.windowColumnMap[20])
			assert.are.equal(3, Helm.windowColumnMap[30])
		end)

		it("should populate columns when discovering new windows in _getOrderedWindowsByScreen", function()
			-- Set up window filter with existing windows
			Helm.windowFilter = hs.window.filter.new()
			mock.addMockWindow(10, true)
			mock.addMockWindow(20, true)

			-- Pre-populate space with first two windows
			Helm.spaces[1].columns = {
				{ windowIds = { 10 } },
				{ windowIds = { 20 } },
			}
			Helm.windowColumnMap = { [10] = 1, [20] = 2 }
			Helm.windowIds = { 10, 20 }
			Helm.windowSpaceMap = { [10] = 1, [20] = 1 }

			-- Now add a new window that wasn't in windowIds
			local win30 = mock.addMockWindow(30, true)

			-- Call _getOrderedWindowsByScreen which discovers new windows
			Helm:_getOrderedWindowsByScreen()

			-- Verify the new window was added as a column
			assert.are.equal(3, #Helm.spaces[1].columns)
			assert.are.same({ 30 }, Helm.spaces[1].columns[3].windowIds)
			assert.are.equal(3, Helm.windowColumnMap[30])
		end)
	end)
end)
