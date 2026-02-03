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

--- Ordered list of window IDs for layout
Helm.windowIds = {}

--- Window filter for watching window events
Helm.windowFilter = nil

function Helm:init()
	return self
end

function Helm:start()
	self:collectWindows()
	self:arrangeWindows()
	self:startWatching()
	return self
end

function Helm:startWatching()
	self.windowFilter = hs.window.filter.new():setDefaultFilter()
	self.windowFilter:subscribe(hs.window.filter.windowCreated, function(win)
		self:handleWindowCreated(win)
	end)
	self.windowFilter:subscribe(hs.window.filter.windowDestroyed, function(win)
		self:handleWindowDestroyed(win)
	end)
	return self
end

function Helm:stopWatching()
	if self.windowFilter then
		self.windowFilter:unsubscribeAll()
		self.windowFilter = nil
	end
	return self
end

function Helm:handleWindowCreated(win)
	if not win or not win:isStandard() then
		return self
	end
	self:stopWatching()
	table.insert(self.windowIds, win:id())
	self:arrangeWindows()
	self:startWatching()
	return self
end

function Helm:handleWindowDestroyed(win)
	if not win then
		return self
	end
	self:stopWatching()
	local winId = win:id()
	for i, id in ipairs(self.windowIds) do
		if id == winId then
			table.remove(self.windowIds, i)
			break
		end
	end
	self:arrangeWindows()
	self:startWatching()
	return self
end

function Helm:collectWindows()
	self.windowIds = {}
	local windows = hs.window.allWindows()
	for _, win in ipairs(windows) do
		if win:isStandard() then
			table.insert(self.windowIds, win:id())
		end
	end
	return self
end

function Helm:arrangeWindows()
	local count = #self.windowIds
	if count == 0 then
		return self
	end

	local screen = hs.screen.mainScreen():frame()
	local width = screen.w / count

	for i, winId in ipairs(self.windowIds) do
		local win = hs.window.get(winId)
		self.logger.d("Window ID: " .. winId .. " (" .. i .. "/" .. count .. ")")
		if win then
			local x = screen.x + (i - 1) * width
			win:setFrame({ x = x, y = screen.y, w = width, h = screen.h })
		end
	end
	return self
end

function Helm:stop()
	self:stopWatching()
	return self
end

-- function Helm:bindHotkeys(mapping)
-- 	local spec = {}
-- 	hs.spoons.bindHotkeysToSpec(spec, mapping)
-- 	return self
-- end

return Helm
