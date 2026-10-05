-- RaySn33ky's Z-City: loot containers for maps that ship with few or none.
--
-- 1. Admins can mark fixed loot spots per map with the Point Editor tool (ZBattle category),
--    point type "ZC_LOOTBOX". A random loot container spawns on every spot each round.
-- 2. Maps with no marked spots and fewer than zc_lootboxes_min containers get extra
--    containers scattered over the map's walkable area at round start.
-- Containers are normal loot props, so searching them (and the search minigame) works as usual.

zb = zb or {}
zb.Points = zb.Points or {}
zb.Points.ZC_LOOTBOX = zb.Points.ZC_LOOTBOX or {}
zb.Points.ZC_LOOTBOX.Color = Color(35, 225, 110)
zb.Points.ZC_LOOTBOX.Name = "ZC_LOOTBOX"

if CLIENT then return end

local cv_min = CreateConVar("zc_lootboxes_min", "20", FCVAR_ARCHIVE,
	"Top up maps that have fewer loot containers than this at round start (0 = off)", 0, 200)
local cv_spacing = CreateConVar("zc_lootboxes_spacing", "350", FCVAR_ARCHIVE,
	"Minimum distance between scattered loot containers", 64, 4096)

local function smallBoxModels()
	local list = {}
	for model, data in pairs(hg.loot_boxes or {}) do
		-- data[3] marks big/static containers; only use ones that sit nicely on the floor
		if istable(data) and not data[3] and util.IsValidModel(model) then list[#list + 1] = model end
	end
	return list
end

local function countMapContainers()
	local n = 0
	for _, ent in ipairs(ents.FindByClass("prop_physics")) do
		if hg.GetLootBoxData and hg.GetLootBoxData(ent) then n = n + 1 end
	end
	return n
end

local function spawnBox(models, pos, ang)
	local box = ents.Create("prop_physics")
	if not IsValid(box) then return end
	box:SetModel(models[math.random(#models)])
	box:SetPos(pos)
	box:SetAngles(ang or Angle(0, math.random(0, 359), 0))
	box:Spawn()
	box:Activate()
	-- lift it so it rests on the floor instead of clipping into it
	local mins = box:OBBMins()
	box:SetPos(pos - Vector(0, 0, mins.z) + Vector(0, 0, 2))
	local phys = box:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end
	-- give up on spots where the box would be stuck inside something
	local tr = util.TraceEntity({start = box:GetPos(), endpos = box:GetPos(), filter = box}, box)
	if tr.StartSolid then box:Remove() return end
	box.ZC_ScatteredLoot = true
	return box
end

-- walkable spots: the navmesh if the map has one (most reliable), otherwise the
-- RandomSpawns points Z-City already generates for every map
local function scatterCandidates()
	local c = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if not area:IsUnderwater() and area:GetSizeX() >= 32 and area:GetSizeY() >= 32 then
			c[#c + 1] = area:GetRandomPoint()
		end
	end
	if #c > 0 then return c end
	for _, p in ipairs(zb.GetMapPoints("RandomSpawns") or {}) do
		if istable(p) and isvector(p.pos) then c[#c + 1] = p.pos end
	end
	return c
end

function zb.ZC_SpawnLootSpots()
	local round = CurrentRound and CurrentRound()
	if not round or not round.LootSpawn then return end

	local models = smallBoxModels()
	if #models == 0 then return end

	-- admin-placed spots win
	local spots = zb.GetMapPoints("ZC_LOOTBOX") or {}
	if #spots > 0 then
		local made = 0
		for _, p in ipairs(spots) do
			if istable(p) and isvector(p.pos) and spawnBox(models, p.pos, p.ang) then made = made + 1 end
		end
		print("[ZC-Loot] spawned " .. made .. " loot containers on placed ZC_LOOTBOX spots")
		return
	end

	local want = cv_min:GetInt()
	if want <= 0 then return end
	local have = countMapContainers()
	if have >= want then return end

	local cand = scatterCandidates()
	local spacing = cv_spacing:GetFloat() ^ 2
	local placed = {}
	for _, ent in ipairs(ents.FindByClass("prop_physics")) do
		if hg.GetLootBoxData and hg.GetLootBoxData(ent) then placed[#placed + 1] = ent:GetPos() end
	end

	local need, tries = want - have, 0
	while need > 0 and #cand > 0 and tries < 600 do
		tries = tries + 1
		local pos = table.remove(cand, math.random(#cand))
		local ok = true
		for _, q in ipairs(placed) do
			if q:DistToSqr(pos) < spacing then ok = false break end
		end
		if ok and spawnBox(models, pos + Vector(0, 0, 4)) then
			placed[#placed + 1] = pos
			need = need - 1
		end
	end
	print(string.format("[ZC-Loot] map had %d loot containers, scattered %d more", have, (want - have) - need))
end

-- after the map cleanup at round change (and after map containers are converted at +0.5 s)
hook.Add("PostCleanupMap", "ZC_LootSpots", function()
	timer.Simple(1.5, function() zb.ZC_SpawnLootSpots() end)
end)

concommand.Add("zc_lootboxes_now", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	zb.ZC_SpawnLootSpots()
end)
