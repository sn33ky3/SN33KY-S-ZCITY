--[[
	DayZ-style death screen.

	The moment you die the screen goes fully black and all game audio is cut.
	After a second "You are dead" fades in. After 4 seconds (zc_deathscreen_time)
	the screen and audio come back and you're spectating as normal.

	Z-City's own systems (organism sound code, knockout timer, spectator audio)
	keep re-issuing "soundfade" commands that would bring the sound back after
	a second or two. While the death screen is up, this file swallows those
	commands so the silence sticks. Nothing in Z-City's own files is changed.

	Server convars:
		zc_deathscreen        1/0  enable the death screen
		zc_deathscreen_time   seconds of black + silence after death (default 4, 0 = until respawn)
]]

local cv_enabled = CreateConVar("zc_deathscreen", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "DayZ-style black screen and silence on death")
local cv_hold = CreateConVar("zc_deathscreen_time", "4", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Seconds of black screen and silence after death. 0 = until you respawn", 0)

if SERVER then return end

-- ============================================================
-- CLIENT
-- ============================================================

local CFG = {
	text       = "You are dead",
	textDelay  = 1.0, -- seconds of pure black before the text starts to appear
	textFadeIn = 1.5, -- how long the text takes to fade in
	fadeOut    = 0.5, -- how long the black takes to clear when it ends
	maxWaitForDeath = 3, -- safety: give up if the game never reports us as dead
}

surface.CreateFont("PAT_DeathScreen", {
	font = "Roboto",
	size = math.max(28, math.floor(ScrH() / 22)),
	weight = 300,
	antialias = true,
	extended = true,
})

local active = false     -- black screen + silence currently on
local startTime = 0
local seenDead = false   -- has LocalPlayer():Alive() actually gone false since we started?
local fadeOutStart = nil -- set while the black is clearing

-- Wrap Player:ConCommand so nothing can un-mute us while we're dead.
-- The original is kept on the metatable so a Lua reload doesn't wrap it twice.
local PLAYER = FindMetaTable("Player")
PLAYER.PAT_OrigConCommand = PLAYER.PAT_OrigConCommand or PLAYER.ConCommand
local origConCommand = PLAYER.PAT_OrigConCommand

function PLAYER:ConCommand(cmd, ...)
	if active and isstring(cmd) and string.find(cmd, "^%s*soundfade") then return end
	return origConCommand(self, cmd, ...)
end

-- Only real deaths during a live round count. Between rounds Z-City silently
-- kills everyone (KillSilent in MODE:Intermission) and respawns them for the
-- role reveal; that must never trigger the death screen.
local function roundLive()
	return zb == nil or zb.ROUND_STATE == nil or zb.ROUND_STATE == 1
end

local function startDeath()
	if active or not cv_enabled:GetBool() then return end
	if not roundLive() then return end

	local lp = LocalPlayer()
	if not IsValid(lp) then return end

	active = true
	seenDead = not lp:Alive()
	startTime = RealTime()
	fadeOutStart = nil

	-- 100% faded, held for ~27 hours, no fade time = instant silence
	origConCommand(lp, "soundfade 100 99999")
end

local function endDeath()
	if not active then return end
	active = false
	fadeOutStart = RealTime()

	local lp = LocalPlayer()
	if IsValid(lp) then
		-- same restore command Z-City's spectator code uses
		origConCommand(lp, "soundfade 0 0.1")
	end
end

-- Z-City fires this on every client when someone is actually killed
-- (entity_killed). Silent round-reset kills don't fire it, which is what we want.
hook.Add("Player_Death", "PAT_DeathScreen", function(ply)
	if ply == LocalPlayer() then startDeath() end
end)

hook.Add("Think", "PAT_DeathScreen", function()
	if not active then return end

	local lp = LocalPlayer()
	if not IsValid(lp) then return end

	local alive = lp:Alive()

	if not cv_enabled:GetBool() then endDeath() return end

	-- round ended or a new one is being set up: get out of the way immediately
	if not roundLive() then endDeath() return end
	if not alive then seenDead = true end

	-- respawned
	if alive and seenDead then endDeath() return end

	-- the death event fired but we never actually died (shouldn't happen, but don't trap the player)
	if alive and not seenDead and RealTime() - startTime > CFG.maxWaitForDeath then endDeath() return end

	local hold = cv_hold:GetFloat()
	if hold > 0 and RealTime() - startTime >= hold then endDeath() end
end)

-- DrawOverlay draws on top of everything, including the HUD and other menus
hook.Add("DrawOverlay", "PAT_DeathScreen", function()
	if gui.IsGameUIVisible() then return end -- don't cover the Escape menu

	local alpha
	if active then
		alpha = 255
	elseif fadeOutStart then
		local t = (RealTime() - fadeOutStart) / CFG.fadeOut
		if t >= 1 then
			fadeOutStart = nil
			return
		end
		alpha = 255 * (1 - t)
	else
		return
	end

	surface.SetDrawColor(0, 0, 0, alpha)
	surface.DrawRect(0, 0, ScrW(), ScrH())

	if active then
		local textAlpha = math.Clamp((RealTime() - startTime - CFG.textDelay) / CFG.textFadeIn, 0, 1) * 200
		if textAlpha > 0 then
			draw.SimpleText(CFG.text, "PAT_DeathScreen", ScrW() / 2, ScrH() / 2, Color(255, 255, 255, textAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end)
