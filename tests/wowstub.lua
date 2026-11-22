-- Minimal stand-ins for the WoW API the core files use (Core/*.lua), to run them outside the game.
-- Only what the core needs: the engine (Engine/) is never loaded here.
local stub = { frames = {}, timers = {}, loadedAddOns = {}, errors = {}, printed = {} }

function stub.reset()
	stub.frames, stub.timers, stub.errors, stub.printed = {}, {}, {}, {}
	stub.loadedAddOns = {}
end

-- frames: only event registration and scripts
local Frame = {}
Frame.__index = Frame
function Frame:RegisterEvent(event)
	if event:match("^UNKNOWN") then error("unknown event " .. event) end
	self.events[event] = true
end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:IsEventRegistered(event) return self.events[event] == true end

function CreateFrame()
	local f = setmetatable({ events = {}, scripts = {} }, Frame)
	stub.frames[#stub.frames + 1] = f
	return f
end

-- sends a game event to every frame that registered it
function stub.fire(event, ...)
	for _, f in ipairs(stub.frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

-- timers: run by stub.runTimers()
local Timer = {}
Timer.__index = Timer
function Timer:Cancel() self.cancelled = true end
C_Timer = {}
function C_Timer.NewTimer(seconds, fn)
	local t = setmetatable({ seconds = seconds, fn = fn }, Timer)
	stub.timers[#stub.timers + 1] = t
	return t
end
function C_Timer.NewTicker(seconds, fn)
	local t = C_Timer.NewTimer(seconds, fn)
	t.ticker = true
	return t
end
function C_Timer.After(seconds, fn) C_Timer.NewTimer(seconds, fn) end
function stub.runTimers()
	local list = stub.timers
	stub.timers = {}
	for _, t in ipairs(list) do
		if not t.cancelled then
			t.fn()
			if t.ticker then stub.timers[#stub.timers + 1] = t end
		end
	end
end
function stub.liveTimers()
	local n = 0
	for _, t in ipairs(stub.timers) do if not t.cancelled then n = n + 1 end end
	return n
end

C_AddOns = {}
function C_AddOns.IsAddOnLoaded(name) return stub.loadedAddOns[name] == true end

function GetLocale() return stub.locale or "enUS" end
function geterrorhandler() return function(err) stub.errors[#stub.errors + 1] = tostring(err) end end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

return stub
