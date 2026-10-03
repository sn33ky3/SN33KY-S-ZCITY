--[[
	Hunter traitor (RaySn33ky's Z-City) - Tracker ability, server side.

	Every footstep taken by a living non-traitor near a living Hunter is sent to
	that Hunter. cl_hunter.lua draws them on the ground as footprints that fade
	out. Nobody else receives them, so other players see nothing.

	Footsteps come from Z-City's own HG_PlayerFootstep_Notify hook
	(lua/homigrad/movement/sh_footsteps.lua), which fires once per real step.
]]

local MODE = MODE

MODE.HunterTrackRange = 1500    -- only steps this close to the Hunter are sent (units, ~28 m)
MODE.HunterTrackSendRate = 0.25 -- footprints are batched and sent this often (seconds)

util.AddNetworkString("HMCD_HunterTracks")

local rangeSqr = MODE.HunterTrackRange ^ 2
local queues = {} -- [hunter] = { {pos, yaw, foot}, ... }

local function roundActive()
	local mode = CurrentRound and CurrentRound()
	return mode and mode.name == "hmcd" and zb and zb.ROUND_STATE == 1
end

local function isActiveHunter(ply)
	return IsValid(ply) and ply:Alive() and ply.isTraitor and MODE.IsHunterRole(ply.SubRole)
end

hook.Add("HG_PlayerFootstep_Notify", "HMCD_HunterTracks", function(ply, pos, foot)
	-- _Notify hook: never return anything from here
	if not IsValid(ply) or not ply:Alive() or ply.isTraitor then return end
	if not roundActive() then return end

	-- walking direction, falling back to where they face when standing still
	local vel = ply:GetVelocity()
	vel.z = 0
	local yaw = vel:LengthSqr() > 100 and vel:Angle().y or ply:EyeAngles().y

	for _, hunter in player.Iterator() do
		if hunter ~= ply and isActiveHunter(hunter) and hunter:GetPos():DistToSqr(pos) <= rangeSqr then
			local q = queues[hunter]
			if not q then
				q = {}
				queues[hunter] = q
			end

			if #q < 64 then
				q[#q + 1] = {pos, yaw, foot}
			end
		end
	end
end)

timer.Create("HMCD_HunterTracksSend", MODE.HunterTrackSendRate, 0, function()
	for hunter, q in pairs(queues) do
		if IsValid(hunter) and #q > 0 and isActiveHunter(hunter) then
			net.Start("HMCD_HunterTracks")
				net.WriteUInt(#q, 7)
				for i = 1, #q do
					local step = q[i]
					net.WriteVector(step[1])
					net.WriteUInt(math.floor(step[2] % 360), 9)
					net.WriteBit(step[3] == 1)
				end
			net.Send(hunter)
		end

		queues[hunter] = nil
	end
end)
