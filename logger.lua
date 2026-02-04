--- Window logging utilities for Helm Spoon

local logger = {}

--- Log detailed window properties for debugging
-- @param win hs.window object or mock window with same methods
-- @param loggerObj hs.logger instance or mock logger
-- @param prefix string prefix for log messages (optional, defaults to "  ")
function logger.logWindowDetails(win, loggerObj, prefix)
	if not win then
		return
	end

	prefix = prefix or "  "
	local app = win:application()
	local appName = app and app:name() or "Unknown"
	local appBundleID = app and app:bundleID() or "Unknown"
	local winFrame = win:frame()

	loggerObj.d(prefix .. "Window Properties:")
	loggerObj.d(prefix .. "    ID: " .. win:id())
	loggerObj.d(prefix .. '    Title: "' .. win:title() .. '"')
	loggerObj.d(prefix .. '    App: "' .. appName .. '"')
	loggerObj.d(prefix .. '    BundleID: "' .. appBundleID .. '"')
	loggerObj.d(prefix .. '    Role: "' .. win:role() .. '"')
	loggerObj.d(prefix .. '    Subrole: "' .. win:subrole() .. '"')
	loggerObj.d(
		prefix .. "    Frame: x=" .. winFrame.x .. ", y=" .. winFrame.y .. ", w=" .. winFrame.w .. ", h=" .. winFrame.h
	)
	loggerObj.d(prefix .. "    isVisible: " .. tostring(win:isVisible()))
	loggerObj.d(prefix .. "    isMinimized: " .. tostring(win:isMinimized()))
	loggerObj.d(prefix .. "    isFullScreen: " .. tostring(win:isFullScreen()))
	loggerObj.d(prefix .. "    isMaximizable: " .. tostring(win:isMaximizable()))
	loggerObj.d(prefix .. "    isStandard: " .. tostring(win:isStandard()))
	loggerObj.d(prefix .. "    tabCount: " .. win:tabCount())
end

--- Log screen information
-- @param screen hs.screen object
-- @param loggerObj hs.logger instance or mock logger
-- @param prefix string prefix for log messages
function logger.logScreenInfo(screen, loggerObj, prefix)
	if not screen then
		return
	end

	prefix = prefix or "  "
	local frame = screen:frame()
	loggerObj.d(prefix .. "Screen " .. screen:id() .. " (" .. frame.w .. "x" .. frame.h .. ")")
end

return logger
