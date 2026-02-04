--- Mock Hammerspoon environment for testing
local M = {}

local pendingTimers = {}
local mockWindows = {}

local function createMockLogger()
	return {
		d = function() end,
		i = function() end,
		w = function() end,
		e = function() end,
	}
end

local function createMockScreen()
	return {
		frame = function()
			return { x = 0, y = 0, w = 1920, h = 1080 }
		end,
	}
end

local function createMockWindowFilter()
	local filter = {
		subscriptions = {},
	}
	function filter:setDefaultFilter()
		return self
	end
	function filter:subscribe(event, callback)
		self.subscriptions[event] = callback
		return self
	end
	function filter:unsubscribeAll()
		self.subscriptions = {}
		return self
	end
	return filter
end

function M.reset()
	pendingTimers = {}
	mockWindows = {}

	_G.hs = {
		spoons = {
			resourcePath = function(filename)
				return "./" .. filename
			end,
		},
		logger = {
			new = function()
				return createMockLogger()
			end,
		},
		screen = {
			mainScreen = function()
				return createMockScreen()
			end,
		},
		window = {
			filter = {
				new = function()
					return createMockWindowFilter()
				end,
				windowCreated = "windowCreated",
				windowDestroyed = "windowDestroyed",
			},
			allWindows = function()
				return mockWindows
			end,
			get = function(id)
				for _, win in ipairs(mockWindows) do
					if win:id() == id then
						return win
					end
				end
				return nil
			end,
		},
		timer = {
			doAfter = function(delay, callback)
				table.insert(pendingTimers, { delay = delay, callback = callback })
				return {}
			end,
		},
	}
end

function M.flushTimers()
	local timers = pendingTimers
	pendingTimers = {}
	for _, timer in ipairs(timers) do
		timer.callback()
	end
end

function M.addMockWindow(id, isStandard)
	local win = {
		id = function()
			return id
		end,
		isStandard = function()
			return isStandard ~= false
		end,
		setFrame = function() end,
	}
	table.insert(mockWindows, win)
	return win
end

return M
