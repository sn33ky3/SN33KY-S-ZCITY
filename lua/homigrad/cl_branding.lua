--[[
	Server branding. Everything the UI shows as the server's name or links to
	comes from here, so this is the only file you need to edit.

	Leave a URL as "" to hide the button that uses it.
]]

ZC_BRANDING = {
	-- Main menu title, drawn as  <name>  <suffix>  in the original menu font
	name   = "RaySn33ky's",
	suffix = "Z-City",

	-- Shown at the bottom of the main menu, one line each (top to bottom).
	-- Two lines fit comfortably; the original Z-City authors are from its git history.
	credits = {
		"Z-City: uzelezz123, sadsalat, Mannytko & co.",
		"Based on Homigrad  |  Edited by RaySn33ky",
	},

	-- Link under the credits. Point this at YOUR fork. Under the AGPL you need to
	-- offer your modified source to players, and this link is how you do it.
	github = "https://github.com/sn33ky3/SN33KY-S-ZCITY",

	-- Your Discord invite (main menu "Discord", scoreboard "DISCORD")
	discord = "",

	-- Your donation page (main menu "Support Us", scoreboard "SUPPORT US")
	support = "",

	-- Your Workshop collection (main menu "Workshop Collection", scoreboard "WORKSHOP")
	workshop = "",

	-- Player guide (main menu "Guide", scoreboard "GUIDE")
	guide = "",
}
