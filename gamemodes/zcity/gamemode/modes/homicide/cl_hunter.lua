--[[
	Hunter traitor (RaySn33ky's Z-City) - Tracker ability, client side.

	Draws the footprints sent by sv_hunter.lua on the ground. Only the Hunter
	ever receives them. They are hidden behind walls like normal world
	geometry, so you have to actually follow the trail.
]]

local LIFETIME = 12   -- seconds a footprint stays visible
local FADE_IN = 0.15
local MAX_PRINTS = 400

local SOLE_W, SOLE_L = 3.2, 6.5 -- front of the foot (units)
local HEEL_W, HEEL_L = 2.6, 3.2 -- heel
local HEEL_GAP = 1.2
local SIDE_OFFSET = 3.5         -- distance of each foot from the walking line

local COLOR = Color(150, 200, 70) -- same green as the Hunter's role colour

local prints = {}

local function addPrint(pos, yaw, rightFoot)
	-- snap the print onto the ground below the footstep
	local tr = util.TraceLine({
		start = pos + Vector(0, 0, 10),
		endpos = pos - Vector(0, 0, 40),
		mask = MASK_SOLID_BRUSHONLY,
	})
	if not tr.Hit then return end

	local n = tr.HitNormal
	local fwd = Angle(0, yaw, 0):Forward()
	fwd = (fwd - n * fwd:Dot(n)):GetNormalized() -- flatten onto the slope
	local right = fwd:Cross(n):GetNormalized()

	local center = tr.HitPos + n * 0.4 + right * (rightFoot and SIDE_OFFSET or -SIDE_OFFSET)

	if #prints >= MAX_PRINTS then table.remove(prints, 1) end
	prints[#prints + 1] = {
		center = center,
		fwd = fwd,
		right = right,
		born = CurTime(),
	}
end

net.Receive("HMCD_HunterTracks", function()
	local count = net.ReadUInt(7)
	for _ = 1, count do
		local pos = net.ReadVector()
		local yaw = net.ReadUInt(9)
		local rightFoot = net.ReadBit() == 1
		addPrint(pos, yaw, rightFoot)
	end
end)

-- one rectangle, drawn with both windings so it shows from either side
local function drawRect(c, fwd, right, w, l, col)
	local f = fwd * (l / 2)
	local r = right * (w / 2)
	local a, b, d, e = c + f - r, c + f + r, c - f + r, c - f - r
	render.DrawQuad(a, b, d, e, col)
	render.DrawQuad(e, d, b, a, col)
end

local drawCol = Color(COLOR.r, COLOR.g, COLOR.b, 0)

hook.Add("PostDrawTranslucentRenderables", "HMCD_HunterTracks", function(depth, skybox)
	if depth or skybox or #prints == 0 then return end

	local now = CurTime()
	render.SetColorMaterial()

	for i = #prints, 1, -1 do
		local p = prints[i]
		local age = now - p.born

		if age >= LIFETIME then
			table.remove(prints, i)
		else
			local alpha = math.min(age / FADE_IN, 1) * (1 - age / LIFETIME) ^ 0.7
			drawCol.a = 170 * alpha

			-- sole in front, heel behind with a small gap
			drawRect(p.center + p.fwd * (HEEL_L + HEEL_GAP) / 2, p.fwd, p.right, SOLE_W, SOLE_L, drawCol)
			drawRect(p.center - p.fwd * (SOLE_L / 2 + HEEL_GAP / 2), p.fwd, p.right, HEEL_W, HEEL_L, drawCol)
		end
	end
end)

-- clear the trail when you die (Z-City fires Player_Death on every client).
-- Anything left over from a previous round fades out on its own within LIFETIME.
hook.Add("Player_Death", "HMCD_HunterTracks", function(ply)
	if ply == LocalPlayer() then prints = {} end
end)
