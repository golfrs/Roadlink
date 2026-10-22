-- Traffic light timing. Each signalised junction alternates between its east-west ("X")
-- and north-south ("Z") approaches: green -> yellow -> all-red -> other axis.
local Shared = script.Parent
local TrafficConfig = require(Shared:WaitForChild("TrafficConfig"))

local TrafficSignals = {}

function TrafficSignals.cycleLength()
	local s = TrafficConfig.Signal
	return 2 * (s.Green + s.Yellow + s.AllRed)
end

-- Returns "green" | "yellow" | "red" and the seconds left in that state.
function TrafficSignals.state(node, axis, now)
	local s = TrafficConfig.Signal
	local cycle = TrafficSignals.cycleLength()
	local t = (now + node.phaseSeed * cycle) % cycle
	if axis == "Z" then
		t = (t + cycle / 2) % cycle
	end
	if t < s.Green then
		return "green", s.Green - t
	end
	t -= s.Green
	if t < s.Yellow then
		return "yellow", s.Yellow - t
	end
	return "red", cycle - s.Green - s.Yellow - t
end

return TrafficSignals
