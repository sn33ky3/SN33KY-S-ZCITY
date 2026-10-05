--[[
	Search minigame for Z-City containers / bodies.

	Plugs into the existing hook in sh_inventory.lua:
		if PAT_SearchMinigame_OpenInv then PAT_SearchMinigame_OpenInv(ent) return end

	The loot window opens straight away with a search bar above it. Items you
	haven't found yet are hidden. A marker sweeps across the bar: left-click
	the bar while the marker is inside the green zone and the
	next hidden item appears in the loot window. Hitting the bright centre
	finds two. Missing locks you out for a moment and (optionally) makes a
	noise other players can hear.

	Difficulty is constant: the zone size and marker speed never change.

	Requires the sh_inventory.lua edits:
		- OpenInv exposed as hg.OpenInv and returning the window
		- ent.PAT_SearchMinigame makes unfound items wait in window.PAT_Hidden

	Server convars:
		zc_search_minigame     1/0  enable the minigame (0 = stock timed search)
		zc_search_miss_noise   1/0  missing makes a sound other players hear
]]

local cv_enabled = CreateConVar("zc_search_minigame", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable the timing minigame when searching containers and bodies")
local cv_noise = CreateConVar("zc_search_miss_noise", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Missing the search minigame makes a noise other players can hear")

if SERVER then
	util.AddNetworkString("pat_search_miss")

	local missSounds = {}
	for i = 1, 7 do
		missSounds[i] = "physics/cardboard/cardboard_box_impact_hard" .. i .. ".wav"
	end

	net.Receive("pat_search_miss", function(len, ply)
		if not cv_noise:GetBool() then return end
		if not IsValid(ply) or not ply:Alive() then return end

		-- rate limit so a client can't spam sounds
		if (ply.PAT_NextSearchNoise or 0) > CurTime() then return end
		ply.PAT_NextSearchNoise = CurTime() + 0.6

		local src = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply
		src:EmitSound(missSounds[math.random(#missSounds)], 70, math.random(90, 110), 0.8)
	end)

	return
end

-- ============================================================
-- CLIENT
-- ============================================================

-- Tuning. Difficulty is fixed: nothing here changes during a search.
local CFG = {
	zoneWidth   = 0.18, -- width of the green zone (fraction of the bar)
	perfectFrac = 0.30, -- bright centre = this fraction of the green zone
	speed       = 0.9,  -- full sweeps per second
	missLockout = 0.8,  -- seconds you can't search after a miss
	height      = 104,  -- height of the panel above the loot window
	gap         = 8,    -- space between the panel and the loot window
}

local COL = {
	panel      = Color(10, 12, 12, 215),
	outline    = Color(255, 255, 255, 18),
	corner     = Color(200, 40, 40, 230),
	title      = Color(235, 235, 235),
	sub        = Color(255, 255, 255, 90),
	track      = Color(255, 255, 255, 14),
	trackEdge  = Color(255, 255, 255, 30),
	tick       = Color(255, 255, 255, 22),
	zone       = Color(46, 170, 88),
	zoneGlow   = Color(46, 170, 88, 45),
	perfect    = Color(150, 255, 170),
	marker     = Color(255, 255, 255),
	locked     = Color(110, 110, 110),
	hit        = Color(90, 235, 130),
	perfectTxt = Color(255, 210, 90),
	miss       = Color(235, 60, 60),
	pipOn      = Color(90, 235, 130),
	pipOff     = Color(255, 255, 255, 30),
	key        = Color(255, 255, 255, 230),
	keyBg      = Color(255, 255, 255, 20),
}

-- Fonts: Bahnschrift, same family as the main menu
local fontScale = math.Clamp(ScrH() / 1080, 0.8, 1.3)
local function S(n) return math.Round(n * fontScale) end

surface.CreateFont("PAT_Search_Title", {font = "Bahnschrift", size = S(22), weight = 700, extended = true, antialias = true})
surface.CreateFont("PAT_Search_Small", {font = "Bahnschrift", size = S(15), weight = 500, extended = true, antialias = true})
surface.CreateFont("PAT_Search_Key",   {font = "Bahnschrift", size = S(15), weight = 800, extended = true, antialias = true})
surface.CreateFont("PAT_Search_Pop",   {font = "Bahnschrift", size = S(20), weight = 800, extended = true, antialias = true})

local gradUp = Material("vgui/gradient-u")

local activeBar

-- Left mouse on the bar is the search input (see OnMousePressed below).
-- Space is not used: Z-City closes the loot window on it.
hook.Remove("PlayerBindPress", "PAT_SearchMinigame")

local function countHidden(menu)
	local n = 0
	for _, btn in ipairs(menu.PAT_Hidden or {}) do
		if IsValid(btn) and btn.Created == nil then n = n + 1 end
	end
	return n
end

-- Reveal the next hidden item, in the order the window lays them out.
-- Setting Created = 0 makes the stock button Think show it (size, fade-in,
-- pouch sound) and mark it in ent.foundloot.
local function revealNext(menu)
	local list = menu.PAT_Hidden
	if not list then return false end

	while #list > 0 do
		local btn = table.remove(list, 1)
		if IsValid(btn) and btn.Created == nil then
			btn.Created = 0
			return true
		end
	end

	return false
end

local function easeOutBack(t)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function drawCorners(x, y, w, h, len, col)
	surface.SetDrawColor(col)
	surface.DrawRect(x, y, len, 2)
	surface.DrawRect(x, y, 2, len)
	surface.DrawRect(x + w - len, y, len, 2)
	surface.DrawRect(x + w - 2, y, 2, len)
	surface.DrawRect(x, y + h - 2, len, 2)
	surface.DrawRect(x, y + h - len, 2, len)
	surface.DrawRect(x + w - len, y + h - 2, len, 2)
	surface.DrawRect(x + w - 2, y + h - len, 2, len)
end

local function createBar(menu, ent)
	local total = countHidden(menu)
	local found = 0

	local pnl = vgui.Create("DPanel")
	activeBar = pnl
	pnl:SetSize(menu:GetWide(), S(CFG.height))
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(false) -- keep keys going to the game, same as the loot window

	local state = {
		pos = 0,
		dir = 1,
		zoneC = 0.5,
		zoneBorn = RealTime(), -- for the zone pop-in animation
		lockUntil = 0,
		pops = {},             -- floating "+1" / "MISS" texts
		done = false,
	}

	local function newZone()
		local half = CFG.zoneWidth / 2
		-- keep the new zone away from where the marker is right now,
		-- so you can't just mash the key
		for _ = 1, 8 do
			state.zoneC = math.Rand(half + 0.03, 1 - half - 0.03)
			if math.abs(state.zoneC - state.pos) > 0.25 then break end
		end
		state.zoneBorn = RealTime()
	end
	newZone()

	local function pop(text, col)
		state.pops[#state.pops + 1] = {text = text, col = col, x = state.pos, born = RealTime()}
	end

	function pnl:Attempt()
		if state.done then return end
		local now = RealTime()
		if state.lockUntil > now then return end

		local dist = math.abs(state.pos - state.zoneC)
		local half = CFG.zoneWidth / 2

		if dist <= half then
			local perfect = dist <= half * CFG.perfectFrac
			local got = 0
			for _ = 1, (perfect and 2 or 1) do
				if revealNext(menu) then got = got + 1 end
			end
			found = found + got

			if perfect and got > 1 then
				surface.PlaySound("buttons/blip1.wav")
				pop("PERFECT  +" .. got, COL.perfectTxt)
			else
				pop("+" .. got, COL.hit)
			end

			if countHidden(menu) == 0 then
				state.done = true
				state.doneAt = now
				-- let the "all found" state show briefly, then get out of the way
				timer.Simple(0.6, function()
					if IsValid(pnl) then pnl:Remove() end
				end)
			else
				newZone()
			end
		else
			surface.PlaySound("buttons/button10.wav")
			pop("MISS", COL.miss)
			state.lockUntil = now + CFG.missLockout

			net.Start("pat_search_miss")
			net.SendToServer()
		end
	end

	function pnl:Think()
		-- the bar lives and dies with the loot window
		if not IsValid(menu) or not IsValid(ent) then self:Remove() return end

		local x, y = menu:GetPos()
		self:SetPos(x, y - self:GetTall() - S(CFG.gap))
		if self:GetWide() ~= menu:GetWide() then self:SetWide(menu:GetWide()) end

		if state.done then return end

		state.pos = state.pos + state.dir * CFG.speed * 2 * RealFrameTime()
		if state.pos >= 1 then
			state.pos = 1
			state.dir = -1
		elseif state.pos <= 0 then
			state.pos = 0
			state.dir = 1
		end
	end

	function pnl:OnMousePressed(code)
		if code == MOUSE_LEFT then self:Attempt() end
	end

	function pnl:OnRemove()
		if activeBar == self then activeBar = nil end
	end

	function pnl:Paint(w, h)
		local now = RealTime()
		local pad = S(14)
		local locked = state.lockUntil > now

		-- background: blurred, dark, thin outline, red corner brackets like the loot window
		if hg and hg.DrawBlur then hg.DrawBlur(self, 4) end
		draw.RoundedBox(4, 0, 0, w, h, COL.panel)
		surface.SetDrawColor(COL.outline)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		drawCorners(0, 0, w, h, S(12), COL.corner)

		-- header: title on the left, progress on the right
		local headY = pad
		local title = state.done and "SEARCH COMPLETE" or "SEARCHING"
		draw.SimpleText(title, "PAT_Search_Title", pad, headY, state.done and COL.hit or COL.title, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

		local countTxt = found .. " / " .. total .. " FOUND"
		surface.SetFont("PAT_Search_Small")
		local cw, ch = surface.GetTextSize(countTxt)
		draw.SimpleText(countTxt, "PAT_Search_Small", w - pad, headY + S(4), COL.sub, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

		-- progress pips, one per item (skipped if there are too many to fit)
		if total > 0 and total <= 16 then
			local pip, pgap = S(8), S(4)
			local px = w - pad - cw - S(12) - total * (pip + pgap) + pgap
			local py = headY + S(4) + ch / 2 - pip / 2
			for i = 1, total do
				local c = i <= found and COL.pipOn or COL.pipOff
				draw.RoundedBox(2, px + (i - 1) * (pip + pgap), py, pip, pip, c)
			end
		end

		-- bar
		local bx, bw = pad, w - pad * 2
		local by, bh = headY + S(34), S(18)

		draw.RoundedBox(3, bx, by, bw, bh, COL.track)
		surface.SetDrawColor(COL.trackEdge)
		surface.DrawOutlinedRect(bx, by, bw, bh, 1)
		for i = 1, 9 do
			surface.SetDrawColor(COL.tick)
			surface.DrawRect(bx + bw * i / 10, by + bh - S(5), 1, S(5))
		end

		if not state.done then
			-- green zone pops in with a little overshoot each time it moves
			local t = math.Clamp((now - state.zoneBorn) / 0.25, 0, 1)
			local scale = easeOutBack(t)
			local zw = CFG.zoneWidth * bw * scale
			local zx = bx + state.zoneC * bw - zw / 2

			-- soft glow behind the zone
			surface.SetDrawColor(locked and Color(0, 0, 0, 0) or COL.zoneGlow)
			surface.DrawRect(zx - S(4), by - S(4), zw + S(8), bh + S(8))

			surface.SetDrawColor(locked and COL.locked or COL.zone)
			surface.DrawRect(zx, by, zw, bh)
			surface.SetMaterial(gradUp)
			surface.SetDrawColor(255, 255, 255, 40)
			surface.DrawTexturedRect(zx, by, zw, bh)

			local pw = zw * CFG.perfectFrac
			surface.SetDrawColor(locked and COL.locked or COL.perfect)
			surface.DrawRect(zx + (zw - pw) / 2, by, pw, bh)
		end

		-- marker: line with arrowheads above and below
		local mx = math.Round(bx + state.pos * bw)
		local mcol = locked and COL.locked or COL.marker
		surface.SetDrawColor(mcol)
		surface.DrawRect(mx - 1, by - S(3), 3, bh + S(6))
		draw.NoTexture()
		local a = S(5)
		surface.DrawPoly({{x = mx - a, y = by - S(3) - a}, {x = mx + a + 1, y = by - S(3) - a}, {x = mx + 0.5, y = by - S(3)}})
		surface.DrawPoly({{x = mx + 0.5, y = by + bh + S(3)}, {x = mx + a + 1, y = by + bh + S(3) + a}, {x = mx - a, y = by + bh + S(3) + a}})

		-- floating feedback
		for i = #state.pops, 1, -1 do
			local p = state.pops[i]
			local age = now - p.born
			if age > 0.8 then
				table.remove(state.pops, i)
			else
				local alpha = 255 * (1 - age / 0.8)
				local px = math.Clamp(bx + p.x * bw, bx + S(40), bx + bw - S(40))
				draw.SimpleText(p.text, "PAT_Search_Pop", px, by - S(6) - age * S(26), ColorAlpha(p.col, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			end
		end

		-- footer: key prompt, or the lockout draining away after a miss
		local fy = by + bh + S(16)
		if state.done then
			draw.SimpleText("Everything found", "PAT_Search_Small", w / 2, fy, COL.sub, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		elseif locked then
			local left = (state.lockUntil - now) / CFG.missLockout
			local lw = S(160)
			draw.RoundedBox(2, w / 2 - lw / 2, fy + S(6), lw, S(4), COL.track)
			draw.RoundedBox(2, w / 2 - lw / 2, fy + S(6), lw * left, S(4), COL.miss)
		else
			local key = "LMB"
			surface.SetFont("PAT_Search_Key")
			local kw, kh = surface.GetTextSize(key)
			local label = "  click when the marker is in the green zone"
			surface.SetFont("PAT_Search_Small")
			local lw = surface.GetTextSize(label)
			local boxW = kw + S(14)
			local startX = w / 2 - (boxW + lw) / 2

			draw.RoundedBox(3, startX, fy, boxW, kh + S(4), COL.keyBg)
			surface.SetDrawColor(COL.trackEdge)
			surface.DrawOutlinedRect(startX, fy, boxW, kh + S(4), 1)
			draw.SimpleText(key, "PAT_Search_Key", startX + boxW / 2, fy + S(2), COL.key, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			draw.SimpleText(label, "PAT_Search_Small", startX + boxW, fy + S(3), COL.sub, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end
	end

	return pnl
end

function PAT_SearchMinigame_OpenInv(ent)
	if IsValid(activeBar) then activeBar:Remove() end
	if not IsValid(ent) then return end

	if not hg.OpenInv then
		ErrorNoHalt("[search minigame] hg.OpenInv is missing - apply the sh_inventory.lua edits.\n")
		return
	end

	-- Minigame off, or one of the special search types (thief / live pickpocket):
	-- stock behaviour, untouched.
	if not cv_enabled:GetBool() or ent.PAT_SearchVisibleLootMask or ent.PAT_SearchLivePlayer then
		ent.PAT_SearchMinigame = nil
		hg.OpenInv(ent)
		return
	end

	ent.PAT_SearchMinigame = true
	local menu = hg.OpenInv(ent)
	if not IsValid(menu) then return end

	-- nothing left to find: just the loot window
	if countHidden(menu) == 0 then return end

	createBar(menu, ent)
end
