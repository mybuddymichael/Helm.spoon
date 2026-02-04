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
		it("handles nil window gracefully", function()
			Helm.windowIds = {}
			Helm:handleWindowCreated(nil)
			assert.are.same({}, Helm.windowIds)
		end)

		it("handles non-standard window gracefully", function()
			Helm.windowIds = {}
			local fakeWin = {
				isStandard = function() return false end,
				id = function() return 1 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({}, Helm.windowIds)
		end)

		it("adds window id to end when no last focused window", function()
			Helm.windowIds = { 10, 20 }
			Helm.lastFocusedWindowId = nil
			local fakeWin = {
				isStandard = function() return true end,
				id = function() return 42 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({ 10, 20, 42 }, Helm.windowIds)
		end)

		it("adds window id after last focused window", function()
			Helm.windowIds = { 10, 20, 30 }
			Helm.lastFocusedWindowId = 20
			local fakeWin = {
				isStandard = function() return true end,
				id = function() return 42 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({ 10, 20, 42, 30 }, Helm.windowIds)
		end)

		it("does not add duplicate window id", function()
			Helm.windowIds = { 10, 42, 30 }
			Helm.lastFocusedWindowId = 10
			local fakeWin = {
				isStandard = function() return true end,
				id = function() return 42 end,
			}
			Helm:handleWindowCreated(fakeWin)
			assert.are.same({ 10, 42, 30 }, Helm.windowIds)
		end)
	end)
end)
