-- WGA Companion: Smart Guide. Builds a Zygor-style route on the fly from the quest database,
-- your quest log, your level and where you stand: turn in what's done, finish what's open,
-- pick up what's nearby, in the order that walks the least.
local _, CM = ...
local SG = CM:NewModule("SmartGuide")
local QL = C_QuestLog

local NEARBY_YARDS = 900   -- quests to pick up within this range (or anywhere on your map)
-- Two styles: "efficient" picks only quests worth the time for levelling, "completionist" picks everything.
-- accept: quests to pick up at once; steps: how long the route may get (your log is never cut)
local LIMITS = {
  efficient = { accept = 15, steps = 60 },
  completionist = { accept = 25, steps = 80 },
}
local FLIGHT_GRAB = 600     -- an unlearned flight master this close (yards) gets added to the route

function SG:Style()
  return CM.db.settings.guideEfficient == false and "completionist" or "efficient"
end
function SG:SetStyle(style)
  CM.db.settings.guideEfficient = style ~= "completionist"
  CM:Print("Smart Guide style: %s.", self:Style() == "efficient" and "Efficient levelling (only quests worth the time)"
    or "Completionist (every quest)")
  if CM.Companion then CM.Companion.lastKey = nil end
  if CM.GuideWindow then CM.GuideWindow:Refresh() end
end

local function S(v) return CM:Safe(v) end

-- Zone lock ---------------------------------------------------------------------------------------
-- The zone a map belongs to (walks up from sub-zones and dungeons/caves to the zone).
local zoneCache = {}
local function zoneOf(m)
  if not m then return nil end
  if zoneCache[m] ~= nil then return zoneCache[m] or nil end
  local cur, z = m, nil
  for _ = 1, 6 do
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
    if not info then break end
    if info.mapType == 3 then z = cur break end
    if (info.mapType or 0) < 3 then break end
    cur = info.parentMapID
  end
  zoneCache[m] = z or false
  return z
end
SG.ZoneOf = zoneOf

local function lockDB() return WGACompanionCharDB end
-- Levelling path ----------------------------------------------------------------------------------
-- The usual zone order per faction and continent: { zone name, min level, max level }.
local PATHS = {
  Alliance = {
    ["Eastern Kingdoms"] = {
      { "Elwynn Forest", 1, 10 }, { "Dun Morogh", 1, 10 }, { "Westfall", 10, 20 }, { "Loch Modan", 10, 20 },
      { "Redridge Mountains", 15, 25 }, { "Duskwood", 18, 30 }, { "Wetlands", 20, 30 },
      { "Hillsbrad Foothills", 20, 30 }, { "Arathi Highlands", 30, 40 }, { "Alterac Mountains", 30, 40 },
      { "Stranglethorn Vale", 30, 45 }, { "Badlands", 35, 45 }, { "Swamp of Sorrows", 35, 45 },
      { "The Riverglades", 35, 45 }, { "The Hinterlands", 40, 50 }, { "Searing Gorge", 43, 50 },
      { "Blasted Lands", 45, 55 }, { "Burning Steppes", 50, 58 }, { "Western Plaguelands", 51, 58 },
      { "Eastern Plaguelands", 53, 60 },
    },
    Kalimdor = {
      { "Teldrassil", 1, 10 }, { "Darkshore", 10, 20 }, { "Ashenvale", 18, 30 }, { "Stonetalon Mountains", 15, 27 },
      { "Desolace", 30, 40 }, { "Dustwallow Marsh", 35, 45 }, { "Feralas", 40, 50 }, { "Tanaris", 40, 50 },
      { "Azshara", 45, 55 }, { "Un'Goro Crater", 48, 55 }, { "Felwood", 48, 55 }, { "Winterspring", 55, 60 },
      { "Silithus", 55, 60 },
    },
  },
  Horde = {
    ["Eastern Kingdoms"] = {
      { "Tirisfal Glades", 1, 10 }, { "Silverpine Forest", 10, 20 }, { "Hillsbrad Foothills", 20, 30 },
      { "Arathi Highlands", 30, 40 }, { "Alterac Mountains", 30, 40 }, { "Stranglethorn Vale", 30, 45 },
      { "Badlands", 35, 45 }, { "Swamp of Sorrows", 35, 45 }, { "The Riverglades", 35, 45 },
      { "The Hinterlands", 40, 50 }, { "Searing Gorge", 43, 50 }, { "Burning Steppes", 50, 58 },
      { "Western Plaguelands", 51, 58 }, { "Eastern Plaguelands", 53, 60 },
    },
    Kalimdor = {
      { "Durotar", 1, 10 }, { "Mulgore", 1, 10 }, { "The Barrens", 10, 25 }, { "Stonetalon Mountains", 15, 27 },
      { "Ashenvale", 18, 30 }, { "Thousand Needles", 25, 35 }, { "Desolace", 30, 40 }, { "Dustwallow Marsh", 35, 45 },
      { "Feralas", 40, 50 }, { "Tanaris", 40, 50 }, { "Azshara", 45, 55 }, { "Un'Goro Crater", 48, 55 },
      { "Felwood", 48, 55 }, { "Winterspring", 55, 60 }, { "Silithus", 55, 60 },
    },
  },
}
SG.PATHS = PATHS
-- Where each race starts
local START = {
  Human = { "Eastern Kingdoms", "Elwynn Forest" }, Dwarf = { "Eastern Kingdoms", "Dun Morogh" },
  Gnome = { "Eastern Kingdoms", "Dun Morogh" }, NightElf = { "Kalimdor", "Teldrassil" },
  Orc = { "Kalimdor", "Durotar" }, Troll = { "Kalimdor", "Durotar" }, Tauren = { "Kalimdor", "Mulgore" },
  Scourge = { "Eastern Kingdoms", "Tirisfal Glades" },
}

local function faction() return (UnitFactionGroup and UnitFactionGroup("player")) == "Horde" and "Horde" or "Alliance" end

function SG:PathContinent()
  local p = lockDB().pathContinent
  if p then return p end
  local race = UnitRace and select(2, UnitRace("player"))
  return START[race or ""] and START[race][1] or "Eastern Kingdoms"
end
function SG:SetPathContinent(c)
  lockDB().pathContinent = c
  CM:Print("Levelling path: %s.", c)
  if CM.GuideWindow then CM.GuideWindow:Refresh() end
end
-- Your own zone route (the Leveling guide page builds it): { "Elwynn Forest", "Westfall", ... }
local function rosterMode() local l = lockDB().zoneLock; return l and l.roster end
function SG:Roster()
  lockDB().roster = lockDB().roster or {}
  return lockDB().roster
end

function SG:Path()
  if rosterMode() and #self:Roster() > 0 then
    local out = {}
    for _, name in ipairs(self:Roster()) do
      local lo, hi = SG.ZoneRange(name)
      out[#out + 1] = { name, lo or 1, hi or 60 }
    end
    return out
  end
  return PATHS[faction()][self:PathContinent()] or {}
end

-- Every zone for a faction, both continents, by level: { name, lo, hi, continent }
function SG:AllZones(side)
  local out, seen = {}, {}
  for cont, list in pairs(PATHS[side or faction()] or {}) do
    for _, z in ipairs(list) do
      if not seen[z[1]] then seen[z[1]] = true; out[#out + 1] = { z[1], z[2], z[3], cont } end
    end
  end
  table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
  return out
end

-- Fill the route for you. Efficient: one zone per level band on one continent, moving on two
-- levels before a zone's top. Completionist: every zone on the continent in level order.
function SG:BuildRoster(style, cont)
  cont = cont or self:PathContinent()
  local list = PATHS[faction()][cont] or {}
  local out = {}
  local race = UnitRace and select(2, UnitRace("player"))
  local start = START[race or ""]
  if style == "completionist" then
    local sorted = {}
    for _, z in ipairs(list) do sorted[#sorted + 1] = z end
    table.sort(sorted, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    for _, z in ipairs(sorted) do
      if z[2] > 1 or (start and start[2] == z[1]) or not start then out[#out + 1] = z[1] end
    end
  else
    local used, cur = {}, 1
    if start and start[1] == cont then out[1] = start[2]; used[start[2]] = true; cur = 8 end
    for _ = 1, 20 do
      if cur >= 60 then break end
      local best
      -- the freshest zone for your level: the highest starting level you can already handle
      for _, z in ipairs(list) do
        if not used[z[1]] and z[2] > 1 and z[2] <= cur + 2 and z[3] > cur + 3
          and (not best or z[2] > best[2] or (z[2] == best[2] and z[3] > best[3])) then best = z end
      end
      if not best then
        for _, z in ipairs(list) do
          if not used[z[1]] and z[3] > cur and (z[2] > 1 or #out == 0) and (not best or z[2] < best[2]) then best = z end
        end
      end
      if not best then break end
      out[#out + 1] = best[1]; used[best[1]] = true
      if best[2] == 1 then cur = math.max(cur, 8) end
      -- stay until about 60% through its range, then move to the next fresh zone
      cur = math.max(cur + 3, math.floor(math.max(best[2], cur) + (best[3] - math.max(best[2], cur)) * 0.6 + 0.5))
    end
  end
  table.sort(out, function(a, b) return (SG.ZoneRange(a) or 0) < (SG.ZoneRange(b) or 0) end)
  lockDB().roster = out
  return out
end

function SG:RosterAdd(name)
  local r = self:Roster()
  for _, n in ipairs(r) do if n == name then return end end
  r[#r + 1] = name
  table.sort(r, function(a, b) return (SG.ZoneRange(a) or 0) < (SG.ZoneRange(b) or 0) end)
end
function SG:RosterRemove(i) table.remove(self:Roster(), i) end
function SG:RosterMove(i, d)
  local r = self:Roster()
  local j = i + d
  if j < 1 or j > #r then return end
  r[i], r[j] = r[j], r[i]
end
function SG:FollowRoster()
  if #self:Roster() == 0 then CM:Print("Your zone route is empty. Add zones on the Leveling guide page first.") return end
  lockDB().zoneLock = { auto = true, roster = true }
  local name, lo, hi = self:RecommendedZone()
  CM:Print("Smart Guide follows your zone route. Now: %s (%d-%d).", name or "?", lo or 0, hi or 0)
  if CM.Companion then CM.Companion.lastKey = nil end
  if CM.GuideWindow then CM.GuideWindow:Refresh() end
end
function SG:FollowingRoster() return rosterMode() and true or false end

local function rangeOf(name)
  for _, side in ipairs({ faction(), faction() == "Horde" and "Alliance" or "Horde" }) do
    for _, cont in pairs(PATHS[side]) do
      for _, z in ipairs(cont) do if z[1] == name then return z[2], z[3] end end
    end
  end
end
SG.ZoneRange = rangeOf

-- The zone to level in now: your race's start zone early on, then the first zone on the path that
-- fits your level with room to grow (not within 2 levels of its top).
function SG:RecommendedZone(level)
  level = level or UnitLevel("player") or 1
  local path = self:Path()
  local race = UnitRace and select(2, UnitRace("player"))
  local startOK = START[race or ""] and (rosterMode() and #self:Roster() > 0
    and (function() for _, z in ipairs(path) do if z[1] == START[race][2] then return true end end end)()
    or (not rosterMode() and START[race][1] == self:PathContinent()))
  if level < 10 and startOK then
    local name = START[race][2]
    return name, rangeOf(name)
  end
  for _, z in ipairs(path) do
    if level >= z[2] and level <= z[3] - 2 and z[2] > 1 then return z[1], z[2], z[3] end
  end
  for _, z in ipairs(path) do
    if level >= z[2] and level <= z[3] then return z[1], z[2], z[3] end
  end
  local last = path[#path]
  return last and last[1], last and last[2], last and last[3]
end

function SG:LockedZone()
  local l = lockDB().zoneLock
  if l and l.auto then
    local name = self:RecommendedZone()
    local id = name and CM.Visuals and CM.Visuals:MapID(name)
    if id then return id, name, true end
    return nil
  end
  return l and l.id, l and l.name, false
end

-- Zones the guide may send you to right now. A manual lock is just that zone. Following the path
-- it's the recommended zone plus the zone you're standing in while that zone still fits your level,
-- so you can finish what you started before moving on.
function SG:ZoneAllowed(m, pm)
  local lock, _, auto = self:LockedZone()
  if not lock then return true end
  local z = zoneOf(m)
  if z == lock then return true end
  if auto and pm and z and z == zoneOf(pm) then
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(z)
    local _, hi = rangeOf(info and info.name)
    if hi and (UnitLevel("player") or 1) <= hi then return true end
  end
  return false
end

function SG:FollowPath()
  lockDB().zoneLock = { auto = true }
  local name, lo, hi = self:RecommendedZone()
  CM:Print("Smart Guide follows the levelling path (%s). Now: %s (%d-%d).", self:PathContinent(), name or "?", lo or 0, hi or 0)
  if CM.Companion then CM.Companion.lastKey = nil end
  if CM.GuideWindow then CM.GuideWindow:Refresh() end
end

-- Locked to a zone you've outgrown? Suggest the next one (once per level).
function SG:MoveOnAdvice()
  local _, name, auto = self:LockedZone()
  if not name or auto then return nil end
  local _, hi = rangeOf(name)
  local level = UnitLevel("player") or 1
  if hi and level >= hi then
    local nxt, lo2, hi2 = self:RecommendedZone(level)
    if nxt and nxt ~= name then return string.format("You've outlevelled %s. Next up: %s (%d-%d).", name, nxt, lo2, hi2), nxt end
  end
end
CM:On("PLAYER_LEVEL_UP", function()
  C_Timer.After(4, function()
    local tip = SG:MoveOnAdvice()
    local auto = lockDB().zoneLock and lockDB().zoneLock.auto
    if tip and CM.Companion then CM.Companion:Remark(tip .. " Click Z on the guide to switch.") end
    if auto and CM.Companion then
      local name = SG:RecommendedZone()
      if name and name ~= SG.lastPathZone then
        if SG.lastPathZone then CM.Companion:Remark("We've outgrown " .. SG.lastPathZone .. ". Time to head to " .. name .. "!") end
      end
    end
    SG.lastPathZone = SG:RecommendedZone()
  end)
end)
function SG:LockZone(id)
  if not id then
    lockDB().zoneLock = nil
    CM:Print("Smart Guide: zone lock off, suggesting quests near you again.")
  else
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    lockDB().zoneLock = { id = id, name = info and info.name or ("map " .. id) }
    CM:Print("Smart Guide: locked to %s. New quests only come from there.", lockDB().zoneLock.name)
  end
  if CM.Companion then CM.Companion.lastKey = nil end
  if CM.GuideWindow then CM.GuideWindow:Refresh() end
end

-- Zones with quests for you right now: { {id, name, count, lo, hi}, ... } most quests first
function SG:ZoneChoices()
  local QD = CM.QData
  local by = {}
  if not QD:Has() then return {} end
  local level = UnitLevel("player") or 1
  for _, id in ipairs(QD:Available(false)) do
    if not QD:NotWorthIt(id, level) then
      for _, st in ipairs(QD:Starters(id)) do
        local spawns = QD:Spawns(st[1], st[2])
        local m = spawns and next(spawns)
        local z = zoneOf(m)
        if z then
          local e = by[z] or { id = z, count = 0, lo = 99, hi = 0 }
          e.count = e.count + 1
          local l = QD:Level(id) or level
          e.lo, e.hi = math.min(e.lo, l), math.max(e.hi, l)
          by[z] = e
          break
        end
      end
    end
  end
  local out = {}
  for _, e in pairs(by) do
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(e.id)
    e.name = info and info.name or ("map " .. e.id)
    out[#out + 1] = e
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out
end

local function here()
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if not p then return m end
  local x, y = p:GetXY()
  return m, x, y
end

local function world(m, x, y)
  if not (m and x and CM.Arrow and CM.Arrow.WorldPos) then return nil end
  return CM.Arrow.WorldPos(m, x, y)
end

-- Yards between two map points (same continent), or nil.
local function yards(a, b)
  local ca, ax, ay = world(a.m, a.x, a.y)
  local cb, bx, by = world(b.m, b.x, b.y)
  if not ca or ca ~= cb then return nil end
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
SG.Yards = yards

local KIND_BY_ENTITY = { slay = "kill", loot = "loot", object = "use" }

local function objectiveRows(id)
  local rows = {}
  for _, o in ipairs(QL.GetQuestObjectives(id) or {}) do
    if o.text and o.text ~= "" then
      rows[#rows + 1] = { text = o.text, done = S(o.finished) and true or false,
        have = S(o.numFulfilled), need = S(o.numRequired) }
    end
  end
  return rows
end

local function firstOpen(id)
  for idx, o in ipairs(QL.GetQuestObjectives(id) or {}) do
    if not S(o.finished) then return idx end
  end
end

-- One step per quest in the log, plus nearby quests to pick up.
function SG:Collect()
  local steps = {}
  local pm, px, py = here()
  local QD, N = CM.QData, CM.QuestNav
  local efficient = self:Style() == "efficient"
  local myLevel = UnitLevel("player") or 1
  self.skipped = {}
  local inLog = {}
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    local id = info and not info.isHeader and not info.isHidden and info.questID
    if id then
      inLog[id] = true
      local ready = QL.ReadyForTurnIn and QL.ReadyForTurnIn(id) or QL.IsComplete(id)
      local m, x, y, _, who = N:Location(id)
      local step = { quest = id, title = info.title or QL.GetTitleForQuestID(id) or ("Quest " .. id), m = m, x = x, y = y,
        npc = who, level = info.level or (QD:Has() and QD:Level(id)) }
      if ready then
        step.kind = "turnin"
        step.verb = "Turn in"
      else
        step.verb = "Complete"
        step.objectives = objectiveRows(id)
        local idx = firstOpen(id)
        local ents = idx and QD:Has() and QD:ObjectiveEntities(id, idx)
        local e = ents and ents[1]
        step.kind = (e and KIND_BY_ENTITY[e[3]]) or "complete"
      end
      if step.npc and CM.Visuals then step.npcID = CM.Visuals:NpcID(step.npc) end
      step.dungeon = QD:Has() and QD:IsDungeonQuest(id) or nil
      -- already in the log but poor value: keep it, at the end of the route
      if efficient and not ready and QD:Has() then step.later = QD:NotWorthIt(id, myLevel) end
      local lock, lockName = self:LockedZone()
      if lock and not ready and step.m and not self:ZoneAllowed(step.m, pm) then
        step.later = step.later or ("outside " .. lockName)
      end
      steps[#steps + 1] = step
    end
  end
  -- Quests to pick up nearby
  if QD:Has() and CM.db.settings.smartAccept ~= false then
    local offers = {}
    local dungeons = CM.db.settings.guideDungeons ~= false
    local seenSkip = {}
    for _, id in ipairs(QD:Available(not efficient)) do
      local m, x, y, who = QD:Nearest(QD:Starters(id), pm, px, py)
      if m and not inLog[id] then
        local d = pm and px and yards({ m = pm, x = px, y = py }, { m = m, x = x, y = y })
        local inRange
        if self:LockedZone() then inRange = self:ZoneAllowed(m, pm) else inRange = m == pm or (d and d < NEARBY_YARDS) end
        if inRange then
          local why = efficient and QD:NotWorthIt(id, myLevel)
          local dungeon = QD:IsDungeonQuest(id)
          if not why and efficient and dungeon and not dungeons then why = "dungeon quest (dungeons are off)" end
          if why then
            local t = QD:Title(id)
            if not seenSkip[t] then
              seenSkip[t] = true
              self.skipped[#self.skipped + 1] = { title = t, level = QD:Level(id), why = why }
            end
          else
            offers[#offers + 1] = { kind = "accept", verb = "Accept", quest = id, title = QD:Title(id), m = m, x = x, y = y,
              npc = who, npcID = CM.Visuals and CM.Visuals:NpcID(who), level = QD:Level(id), d = d or math.huge,
              dungeon = dungeon or nil }
          end
        end
      end
    end
    -- efficient: quests near your level first when the walk is similar
    local function cost(o)
      if not efficient then return o.d end
      local diff = math.abs((o.level or myLevel) - myLevel)
      return o.d * (1 + diff * 0.15)
    end
    table.sort(offers, function(a, b) return cost(a) < cost(b) end)
    for i = 1, math.min(#offers, LIMITS[self:Style()].accept) do steps[#steps + 1] = offers[i] end
    table.sort(self.skipped, function(a, b) return (a.title or "") < (b.title or "") end)
  end
  -- A flight path you haven't learned, close by: always worth grabbing
  local fp = pm and px and self:UnlearnedFlight(pm, px, py)
  if fp then steps[#steps + 1] = fp end
  return steps, pm, px, py
end

-- Routing ---------------------------------------------------------------------------------------
local HUB_RADIUS = 450     -- town stops this close (chained) are done together before heading out
local HUB_CHAIN = 220      -- how far apart two stops can be and still count as the same town
local DETOUR = 150         -- a town stop this close to where you are mid-run gets picked up on the way

local function isTown(s) return s.kind == "turnin" or s.kind == "accept" or s.kind == "flight" end

-- Nearest-next ordering of `list` from `cur`; returns ordered list and last position.
-- weight(s, d) can scale a candidate's distance.
local function nearestNext(list, cur, weight)
  local out = {}
  while #list > 0 do
    local bi, bd = 1, math.huge
    for i, s in ipairs(list) do
      local d = cur and yards(cur, s) or math.huge
      if weight and d ~= math.huge then d = weight(s, d) end
      if d < bd then bi, bd = i, d end
    end
    local s = table.remove(list, bi)
    out[#out + 1] = s
    cur = s
  end
  return out, cur
end

-- The town stops you can do right now as one batch: those near you, plus those near those.
local function townBatch(towns, cur)
  local batch, rest = {}, {}
  local inBatch = {}
  for _, s in ipairs(towns) do
    local d = cur and yards(cur, s)
    if d and d <= HUB_RADIUS then batch[#batch + 1] = s; inBatch[s] = true end
  end
  local grew = true
  while grew do
    grew = false
    for _, s in ipairs(towns) do
      if not inBatch[s] then
        for _, b in ipairs(batch) do
          local d = yards(b, s)
          if d and d <= HUB_CHAIN then batch[#batch + 1] = s; inBatch[s] = true; grew = true; break end
        end
      end
    end
  end
  for _, s in ipairs(towns) do if not inBatch[s] then rest[#rest + 1] = s end end
  return batch, rest
end

-- Efficient: hand in and pick up everything in town first, then the field run (grabbing any town
-- stop that's right on the way), then the far turn-ins. Completionist: plain nearest-next.
function SG:Route()
  local steps, pm, px, py = self:Collect()
  local placed, rest, later = {}, {}, {}
  for _, s in ipairs(steps) do
    if s.later then later[#later + 1] = s
    elseif s.m and s.x then placed[#placed + 1] = s else rest[#rest + 1] = s end
  end
  local here = pm and px and { m = pm, x = px, y = py }
  local route = {}
  if self:Style() == "efficient" then
    local towns, field = {}, {}
    for _, s in ipairs(placed) do if isTown(s) then towns[#towns + 1] = s else field[#field + 1] = s end end
    local batch, farTowns = townBatch(towns, here)
    local first, cur = nearestNext(batch, here, function(s, d) return s.kind == "turnin" and d * 0.85 or d end)
    for _, s in ipairs(first) do s.phase = "town"; route[#route + 1] = s end
    -- field run; a far town stop that is right next to you gets done on the way
    while #field > 0 do
      local took = false
      for i, t in ipairs(farTowns) do
        local d = cur and yards(cur, t)
        if d and d <= DETOUR then
          t.phase = "town"; route[#route + 1] = table.remove(farTowns, i); cur = t; took = true; break
        end
      end
      if not took then
        local bi, bd = 1, math.huge
        for i, f in ipairs(field) do
          local d = cur and yards(cur, f) or math.huge
          if d < bd then bi, bd = i, d end
        end
        local f = table.remove(field, bi)
        f.phase = "field"; route[#route + 1] = f; cur = f
      end
    end
    local tail = nearestNext(farTowns, cur, function(s, d) return s.kind == "turnin" and d * 0.85 or d end)
    for _, s in ipairs(tail) do s.phase = "return"; route[#route + 1] = s end
  else
    route = nearestNext(placed, here, function(s, d) return s.kind == "turnin" and d * 0.85 or d end)
  end
  for _, s in ipairs(route) do s.yards = here and yards(here, s) end
  for _, s in ipairs(rest) do route[#route + 1] = s end
  for _, s in ipairs(later) do route[#route + 1] = s end
  -- Too long: drop quests to pick up (furthest first), never quests already in your log
  local i = #route
  while #route > LIMITS[self:Style()].steps and i >= 1 do
    if route[i].kind == "accept" then table.remove(route, i) end
    i = i - 1
  end
  -- how to get to the first stop: run, fly or hearth
  if route[1] and here and route[1].m then route[1].travel = self:Travel(here, route[1]) end
  return route
end

-- Travel: flight paths and hearthstone ----------------------------------------------------------
local HEARTHSTONE = 6948  -- may be corrected from your bags
local FLY_SPEED, FLY_PATH, FLY_OVERHEAD = 30, 1.25, 12   -- yards/s, route bend, mount up + land
local HEARTH_TIME = 10 + 20                               -- cast + loading screen
local function travelDB()
  WGACompanionCharDB.travel = WGACompanionCharDB.travel or { nodes = {}, known = {}, cost = {} }
  local t = WGACompanionCharDB.travel
  t.nodes = t.nodes or {}; t.known = t.known or {}; t.cost = t.cost or {}
  return t
end
SG.TravelDB = travelDB

local function xy(pos)
  if not pos then return nil end
  if pos.GetXY then return pos:GetXY() end
  return pos.x, pos.y
end

-- Flight master opened: learn which flight points you know, where they are and what they cost
CM:On("TAXIMAP_OPENED", function()
  local t = travelDB()
  local mapID = GetTaxiMapID and GetTaxiMapID()
  if not mapID or not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
  local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
  if not ok or not nodes then return end
  local here
  for _, n in ipairs(nodes) do
    local x, y = xy(n.position)
    if n.nodeID and x then t.nodes[n.nodeID] = { name = n.name, m = mapID, x = x, y = y } end
    local state = n.state
    if state == 0 then here = n.nodeID end                -- Enum.FlightPathState.Current
    if n.nodeID and state ~= nil and state ~= 2 then t.known[n.nodeID] = true end
  end
  if here then
    for _, n in ipairs(nodes) do
      if n.slotIndex and n.state == 1 and TaxiNodeCost then
        local c = TaxiNodeCost(n.slotIndex)
        if c and c > 0 then t.cost[here .. ">" .. n.nodeID] = c end
      end
    end
  end
end)

-- Flight masters from the quest database that you haven't learned yet. A flight master counts as
-- learned once you've opened the flight map at it, or a flight point you know is right next to it.
function SG:FlightKnown(name, m, x, y)
  local t = travelDB()
  t.fm = t.fm or {}
  if t.fm[name] then return true end
  for id, n in pairs(t.nodes) do
    if t.known[id] and n.x then
      local d = yards({ m = m, x = x, y = y }, { m = n.m, x = n.x, y = n.y })
      if d and d < 120 then return true end
    end
  end
  return false
end

function SG:UnlearnedFlight(pm, px, py)
  local db = CM.Data.QDB and CM.Data.QDB.f
  if not db or CM.db.settings.grabFlights == false then return nil end
  local side = faction() == "Horde" and "H" or "A"
  local me = { m = pm, x = px, y = py }
  local best, bd
  for _, f in pairs(db) do
    if f[2] and f[2]:find(side, 1, true) then
      for m, packed in pairs(f[3] or {}) do
        local x, y = packed:match("([%d%.]+),([%d%.]+)")
        if x then
          local spot = { m = m, x = tonumber(x) / 100, y = tonumber(y) / 100 }
          local d = yards(me, spot)
          if d and d <= FLIGHT_GRAB and (not bd or d < bd) and not self:FlightKnown(f[1], spot.m, spot.x, spot.y) then
            best, bd = { kind = "flight", verb = "Get flight path", title = (f[1] or "Flight master") .. "'s flight path",
              npc = f[1], m = spot.m, x = spot.x, y = spot.y, d = d }, d
          end
        end
      end
    end
  end
  if best and CM.Visuals then best.npcID = CM.Visuals:NpcID(best.npc) end
  return best
end

-- Remember the flight master you talked to, so it isn't suggested again
CM:On("TAXIMAP_OPENED", function()
  local name = UnitName and UnitName("npc")
  if name then local t = travelDB(); t.fm = t.fm or {}; t.fm[name] = true end
end)

-- Hearthstone: remember where it takes you
local hearthing = false
CM:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if unit == "player" and spellID == 8690 then hearthing = true; SG.lastHearth = GetTime() end
end)
local function recordHearth()
  local m, x, y = here()
  if m and x then
    local t = travelDB()
    t.hearth = { m = m, x = x, y = y, name = GetBindLocation and GetBindLocation() }
  end
end
CM:On("PLAYER_ENTERING_WORLD", function()
  if hearthing then hearthing = false; C_Timer.After(2, recordHearth) end
end)
CM:On("ZONE_CHANGED_NEW_AREA", function()
  if hearthing then hearthing = false; C_Timer.After(2, recordHearth) end
end)
-- When your bind point changes you're standing at the innkeeper: remember that spot
function SG:CheckBind()
  local bind = GetBindLocation and GetBindLocation()
  if not bind then return end
  local t = travelDB()
  if t.hearth and t.hearth.name == bind then return end
  local sub = (GetSubZoneText and GetSubZoneText()) or ""
  local zone = (GetZoneText and GetZoneText()) or ""
  if sub == bind or zone == bind then recordHearth()
  else t.hearth = { name = bind } end   -- spot unknown until you hearth there once
end

-- Where your hearthstone takes you, before you've used it: the inn of the town you're bound to.
-- Towns map to innkeepers from the quest database; more are learned as you walk past inns.
local TOWN_INN = {
  ["Goldshire"] = 295, ["Kharanos"] = 1247, ["Menethil Harbor"] = 1464, ["Southshore"] = 2352,
  ["Tarren Mill"] = 2388, ["The Crossroads"] = 3934, ["Ironforge"] = 5111, ["Brill"] = 5688,
  ["Grom'gol Base Camp"] = 5814, ["Theramore Isle"] = 6272, ["Lakeshire"] = 6727, ["Thelsamar"] = 6734,
  ["Darnassus"] = 6735, ["Dolanaar"] = 6736, ["Auberdine"] = 6737, ["Astranaar"] = 6738,
  ["The Sepulcher"] = 6739, ["Stormwind City"] = 6740, ["Stormwind"] = 6740, ["Trade District"] = 6740,
  ["Undercity"] = 6741, ["Thunder Bluff"] = 6746, ["Bloodhoof Village"] = 6747, ["Darkshire"] = 6790,
  ["Ratchet"] = 6791, ["Booty Bay"] = 6807, ["Razor Hill"] = 6928, ["Orgrimmar"] = 6929,
  ["Valley of Strength"] = 6929, ["Stonard"] = 6930, ["Camp Taurajo"] = 7714, ["Sun Rock Retreat"] = 7731,
  ["Gadgetzan"] = 7733, ["Feathermoon Stronghold"] = 7736, ["Camp Mojache"] = 7737, ["Aerie Peak"] = 7744,
  ["Sentinel Hill"] = 8931, ["Kargath"] = 9356, ["Hammerfall"] = 9501, ["Nijel's Point"] = 11103,
  ["Shadowprey Village"] = 11106, ["Freewind Post"] = 11116, ["Everlook"] = 11118,
  ["Splintertree Post"] = 12196, ["Revantusk Village"] = 14731, ["Cenarion Hold"] = 15174,
  ["Light's Hope Chapel"] = 16256,
}
local function innSpot(id)
  local k = CM.Data.QDB and CM.Data.QDB.k and CM.Data.QDB.k[id]
  if not k then return nil end
  for m, packed in pairs(k[3] or {}) do
    local x, y = packed:match("([%d%.]+),([%d%.]+)")
    if x then return m, tonumber(x) / 100, tonumber(y) / 100 end
  end
end
function SG:HearthSpot()
  local t = travelDB()
  local h = t.hearth
  if h and h.m then return h end
  local bind = h and h.name or (GetBindLocation and GetBindLocation())
  if not bind then return nil end
  local id = TOWN_INN[bind] or (t.inns and t.inns[bind])
  local m, x, y = innSpot(id)
  if not m then return nil end
  return { m = m, x = x, y = y, name = bind, guess = true }
end
-- Walking past an inn teaches us the town's name for it
function SG:LearnInn()
  local k = CM.Data.QDB and CM.Data.QDB.k
  local sub = GetSubZoneText and GetSubZoneText()
  if not k or not sub or sub == "" or TOWN_INN[sub] then return end
  local t = travelDB()
  if t.inns and t.inns[sub] then return end
  local pm, px, py = here()
  if not px then return end
  for id in pairs(k) do
    local m, x, y = innSpot(id)
    local d = m and yards({ m = pm, x = px, y = py }, { m = m, x = x, y = y })
    if d and d < 30 then t.inns = t.inns or {}; t.inns[sub] = id return end
  end
end

local function hearthCount()
  local n = C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE) or 0
  if n > 0 then return n end
  -- some clients give the hearthstone another item ID: look for it by name in your bags
  for bag = 0, (CM.Bags and CM.Bags.Last or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local name = info and info.itemName or (info and info.hyperlink and info.hyperlink:match("%[(.-)%]"))
      if name == "Hearthstone" then HEARTHSTONE = info.itemID or HEARTHSTONE return 1 end
    end
  end
  return 0
end

local function hearthReady()
  if hearthCount() == 0 then return false, "no hearthstone in your bags" end
  local start, duration = 0, 0
  if C_Container and C_Container.GetItemCooldown then start, duration = C_Container.GetItemCooldown(HEARTHSTONE) end
  start, duration = CM:Safe(start) or 0, CM:Safe(duration) or 0
  local left = start > 0 and (start + duration - GetTime()) or 0
  if left > 2 then return false, string.format("on cooldown for %s", SG.Mins and SG.Mins(left) or math.floor(left) .. " s") end
  return true
end
SG.HearthReady = hearthReady
function SG:HearthItem() hearthCount(); return HEARTHSTONE end

local function runSpeed()
  local _, run = GetUnitSpeed and GetUnitSpeed("player")
  return math.max(run or 7, 7)
end

-- Nearest known flight point to a spot (same continent): node, yards
local function nearestFP(p)
  local t = travelDB()
  local bn, bd
  for id in pairs(t.known) do
    local n = t.nodes[id]
    if n then
      local d = yards(p, n)
      if d and (not bd or d < bd) then bn, bd = id, d end
    end
  end
  return bn, bd
end

local function flight(from, to)
  local t = travelDB()
  local a, da = nearestFP(from)
  local b, db = nearestFP(to)
  if not a or not b or a == b then return nil end
  local hop = yards(t.nodes[a], t.nodes[b])
  if not hop then return nil end
  local secs = da / runSpeed() + FLY_OVERHEAD + hop * FLY_PATH / FLY_SPEED + db / runSpeed()
  local cost = t.cost[a .. ">" .. b]
  local guess = not cost
  cost = cost or math.floor(math.max(10, hop * 0.03))
  return { secs = secs, cost = cost, guess = guess, from = t.nodes[a].name, to = t.nodes[b].name }
end

local function mins(secs)
  if secs < 90 then return string.format("%d s", math.floor(secs + 0.5)) end
  return string.format("%d min", math.floor(secs / 60 + 0.5))
end
SG.Mins = mins

-- Best way to get from `from` to `to`: { kind = "run"|"fly"|"hearth"|"hearthfly", secs, cost, text, saves }
-- Getting to another continent ----------------------------------------------------------------
-- Known routes by destination zone (from players; Forever-specific).
local ROUTES = {
  ["Zephras Isle"] = {
    Alliance = { "Take the portal to Dalaran in the Wizard's Sanctum (Mage Quarter, Stormwind)",
      "in Dalaran, board the airship to Valanaar on Zephras Isle (north-west side, near Khadgar's Tower)" },
  },
}
SG.ROUTES = ROUTES

local function continentOf(m, x, y)
  local c = world(m, x or 0.5, y or 0.5)
  return c
end

local function zoneNames(m)
  local names, seen = {}, 0
  while m and seen < 6 do
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    if not info then break end
    names[#names + 1] = info.name
    m = info.parentMapID; seen = seen + 1
  end
  return names
end

-- Learn portals, boats and zeppelins: when a loading screen moves you to another continent
-- (and you didn't hearth or fly), the spot you left from is a way there.
local lastSpot
C_Timer.NewTicker(3, function()
  pcall(SG.LearnInn, SG)
  if UnitOnTaxi and UnitOnTaxi("player") then return end
  local m, x, y = here()
  if m and x then lastSpot = { m = m, x = x, y = y, c = continentOf(m, x, y) } end
end)
local function learnLink()
  if not lastSpot or (SG.lastHearth and GetTime() - SG.lastHearth < 90) then return end
  local m, x, y = here()
  local c = m and x and continentOf(m, x, y)
  if c and lastSpot.c and c ~= lastSpot.c then
    local t = travelDB()
    t.links = t.links or {}
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    t.links[#t.links + 1] = { from = lastSpot, toC = c, toName = info and info.name }
    while #t.links > 30 do table.remove(t.links, 1) end
  end
end
CM:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, learnLink) end)

function SG:CrossContinent(from, to)
  local toC = continentOf(to.m, to.x, to.y)
  local fromC = continentOf(from.m, from.x, from.y)
  -- a way you've used before
  local best, bd
  for _, l in ipairs(travelDB().links or {}) do
    if l.toC == toC and l.from.c == fromC then
      local d = yards(from, l.from)
      if d and (not bd or d < bd) then best, bd = l, d end
    end
  end
  if best then
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(best.from.m)
    return { kind = "portal", via = best.from, cost = 0,
      text = string.format("Take the way you used before to %s (%s %.0f, %.0f)", best.toName or "there",
        info and info.name or "", best.from.x * 100, best.from.y * 100) }
  end
  -- a route we know about
  local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
  for _, name in ipairs(zoneNames(to.m)) do
    local r = ROUTES[name]
    if r and r[faction] then
      local legs = r[faction]
      return { kind = "portal", cost = 0, text = legs[1] .. ", then " .. table.concat(legs, ", then ", 2) }
    end
  end
  return { kind = "portal", cost = 0, text = "It's on another continent: take a boat, zeppelin or portal" }
end

function SG:Travel(from, to)
  self:CheckBind()
  local direct = yards(from, to)
  if not direct and to.m and from.m then
    -- other continent: hearth if your inn is over there, otherwise the known way across
    local h = SG:HearthSpot()
    if h and h.m and hearthReady() and yards(h, to) then
      return { kind = "hearth", cost = 0, secs = HEARTH_TIME,
        text = string.format("Hearth to %s, it's on that side of the world", h.name or "your inn") }
    end
    return self:CrossContinent(from, to)
  end
  local money = GetMoney and GetMoney() or 0
  local options = {}
  local walk
  if direct then
    walk = { kind = "run", secs = direct / runSpeed(), cost = 0 }
    options[#options + 1] = walk
  end
  local function affordable(o, saves)
    if o.cost <= 0 then return true end
    if o.cost <= money * 0.25 then return true end
    return o.cost <= money * 0.6 and saves >= 180
  end
  local f = flight(from, to)
  if f then
    f.kind = "fly"
    f.text = string.format("Fly %s to %s (%s%s)", f.from or "?", f.to or "?", f.guess and "about " or "", CM:Money(f.cost, true))
    options[#options + 1] = f
  end
  local h = SG:HearthSpot()
  if h and h.m and hearthReady() then
    local d = yards(h, to)
    if d then
      options[#options + 1] = { kind = "hearth", secs = HEARTH_TIME + d / runSpeed(), cost = 0,
        text = string.format("Hearth to %s", h.name or "your inn") }
    end
    local hf = flight(h, to)
    if hf then
      hf.kind = "hearthfly"; hf.secs = hf.secs + HEARTH_TIME
      hf.text = string.format("Hearth to %s, then fly to %s (%s%s)", h.name or "your inn", hf.to or "?",
        hf.guess and "about " or "", CM:Money(hf.cost, true))
      options[#options + 1] = hf
    end
  end
  local base = walk and walk.secs or math.huge
  local best = walk
  for _, o in ipairs(options) do
    local saves = base - o.secs
    if o.kind ~= "run" and affordable(o, saves) and o.secs < (best and best.secs or math.huge)
      and (base == math.huge or (saves >= 60 and saves >= base * 0.2)) then
      best = o
    end
  end
  if not best then return nil end
  best.saves = (base ~= math.huge) and (base - best.secs) or nil
  if best.kind == "run" then
    best.text = direct and direct > 300 and string.format("Run there, about %s", mins(best.secs)) or nil
  else
    best.text = best.text .. (best.saves and string.format(", saves about %s", mins(best.saves)) or "")
  end
  return best
end

-- Totals for the header: quests done in this zone vs. known in the database
function SG:Summary()
  local level = UnitLevel("player") or 1
  local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 1
  return level, xpMax > 0 and xp / xpMax or 0
end

-- /wga debug travel: why the guide suggests what it does for the current step
function SG:DebugTravel()
  local GW = CM.GuideWindow
  local cur = GW and GW.current
  local m, x, y = here()
  if not cur or not cur.m then CM:Print("Travel: no current step with a location.") return end
  local from, to = { m = m, x = x, y = y }, cur
  CM:Print("Travel to %s: straight line %s yd.", cur.title or "?", tostring(yards(from, to) and math.floor(yards(from, to)) or "unknown"))
  CM:Print("Bound to: %s.", tostring(GetBindLocation and GetBindLocation()))
  local h = self:HearthSpot()
  CM:Print("Hearth spot: %s", h and h.m and string.format("%s (map %d, %.1f %.1f)%s, %s yd from the step", h.name or "?", h.m, h.x * 100, h.y * 100,
    h.guess and " from the inn list" or " learned", tostring(yards(h, to) and math.floor(yards(h, to)) or "?")) or "unknown")
  local ok, why = hearthReady()
  CM:Print("Hearthstone: %s", ok and "ready" or why)
  local n = 0
  for _ in pairs(travelDB().known) do n = n + 1 end
  CM:Print("Flight points known: %d. Run speed %.1f yd/s.", n, runSpeed())
  local tr = self:Travel(from, to)
  CM:Print("Suggestion: %s", tr and (tr.kind .. ": " .. tostring(tr.text)) or "none")
end
