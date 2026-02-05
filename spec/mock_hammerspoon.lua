--- Mock Hammerspoon environment for testing
local M = {}

local pendingTimers = {}
local mockWindows = {}
local focusedWindowId = nil

local function createMockLogger()
	return {
		d = function() end,
		i = function() end,
		w = function() end,
		e = function() end,
	}
end

local screenIdCounter = 0
local mainScreen = nil

local function createMockScreen()
	screenIdCounter = screenIdCounter + 1
	return {
		_id = screenIdCounter,
		frame = function()
			return { x = 0, y = 0, w = 1920, h = 1080 }
		end,
		id = function(self)
			return self._id
		end,
	}
end

local function getMainScreen()
	if not mainScreen then
		mainScreen = createMockScreen()
	end
	return mainScreen
end

local mockWindowFilter = nil
local mockAppWatcher = nil
local appWatcherCallback = nil

local function createMockAppWatcher()
	mockAppWatcher = {
		started = false,
		callback = nil,
	}
	function mockAppWatcher:start()
		self.started = true
		return self
	end
	function mockAppWatcher:stop()
		self.started = false
		return self
	end
	return mockAppWatcher
end

local function createMockWindowFilter()
	-- Return existing filter if one exists, to ensure singleton behavior
	if mockWindowFilter then
		return mockWindowFilter
	end
	
	mockWindowFilter = {
		subscriptions = {},
		windows = {},
	}
	function mockWindowFilter:setDefaultFilter()
		return self
	end
	function mockWindowFilter:subscribe(event, callback)
		self.subscriptions[event] = callback
		return self
	end
	function mockWindowFilter:unsubscribeAll()
		self.subscriptions = {}
		return self
	end
	function mockWindowFilter:getWindows()
		return self.windows
	end
	function mockWindowFilter:focusWindowWest()
		return self
	end
	function mockWindowFilter:focusWindowEast()
		return self
	end
	return mockWindowFilter
end

function M.reset()
	pendingTimers = {}
	mockWindows = {}
	focusedWindowId = nil
	mockWindowFilter = nil
	mockAppWatcher = nil
	appWatcherCallback = nil
	mockApplications = {}
	nextPid = 1000
	screenIdCounter = 0
	mainScreen = nil

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
				return getMainScreen()
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
			focusedWindow = function()
				if focusedWindowId then
					for _, win in ipairs(mockWindows) do
						if win:id() == focusedWindowId then
							return win
						end
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
		application = {
			watcher = {
				terminated = "terminated",
				new = function(callback)
					appWatcherCallback = callback
					return createMockAppWatcher()
				end,
			},
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

local mockApplications = {}
local nextPid = 1000

local function createMockApplication(pid)
	local appPid = pid or nextPid
	if not pid then
		nextPid = nextPid + 1
	end
	return {
		name = function() return "MockApp" end,
		bundleID = function() return "com.mock.app" end,
		pid = function() return appPid end,
	}
end

function M.simulateAppTerminated(pid)
	if appWatcherCallback then
		appWatcherCallback(nil, hs.application.watcher.terminated, createMockApplication(pid))
	end
end

function M.addMockWindowWithApp(id, isStandard, appPid)
	local app = createMockApplication(appPid)
	mockApplications[appPid] = app
	local win = {
		_id = id,
		id = function(self)
			return self._id
		end,
		isStandard = function()
			return isStandard ~= false
		end,
		setFrame = function() end,
		screen = function()
			return getMainScreen()
		end,
		focus = function() end,
		application = function()
			return app
		end,
		title = function() return "Mock Window " .. id end,
		role = function() return "AXWindow" end,
		subrole = function() return "AXStandardWindow" end,
		frame = function() return { x = 0, y = 0, w = 800, h = 600 } end,
		isVisible = function() return true end,
		isMinimized = function() return false end,
		isFullScreen = function() return false end,
		isMaximizable = function() return true end,
		tabCount = function() return 0 end,
	}
	table.insert(mockWindows, win)
	if mockWindowFilter then
		mockWindowFilter.windows = mockWindows
	end
	return win
end

function M.addMockWindow(id, isStandard)
	local win = {
		_id = id,
		id = function(self)
			return self._id
		end,
		isStandard = function()
			return isStandard ~= false
		end,
		setFrame = function() end,
		screen = function()
			return getMainScreen()
		end,
		focus = function() end,
		application = function()
			return createMockApplication()
		end,
		title = function() return "Mock Window " .. id end,
		role = function() return "AXWindow" end,
		subrole = function() return "AXStandardWindow" end,
		frame = function() return { x = 0, y = 0, w = 800, h = 600 } end,
		isVisible = function() return true end,
		isMinimized = function() return false end,
		isFullScreen = function() return false end,
		isMaximizable = function() return true end,
		tabCount = function() return 0 end,
	}
	table.insert(mockWindows, win)
	-- Also add to windowFilter if it exists
	if mockWindowFilter then
		mockWindowFilter.windows = mockWindows
	end
	return win
end

function M.setFocusedWindow(id)
	focusedWindowId = id
end

return M
