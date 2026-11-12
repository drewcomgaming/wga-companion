-- WGA Companion: Smart Guide. Builds a Zygor-style route on the fly from the quest database,
-- your quest log, your level and where you stand: turn in what's done, finish what's open,
-- pick up what's nearby, in the order that walks the least.
local _, CM = ...
local SG = CM:NewModule("SmartGuide")
local QL = C_QuestLog

local NEARBY_YARDS = 900   -- quests to pick up within this range (or anywhere on your map)
-- Two styles: "efficient" picks only quests worth the time for levelling, "completionist" picks everything.
local LIMITS = {
  efficient = { accept = 6, steps = 14 },
  completionist = { accept = 12, steps = 22 },
}

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
function SG:LockedZone()
  local l = lockDB().zoneLock
  return l and l.id, l and l.name
end
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
      if lock and not ready and step.m and zoneOf(step.m) ~= lock then
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
        local lock = self:LockedZone()
        local inRange
        if lock then inRange = zoneOf(m) == lock else inRange = m == pm or (d and d < NEARBY_YARDS) end
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
  return steps, pm, px, py
end

-- Routing ---------------------------------------------------------------------------------------
local HUB_RADIUS = 450     -- town stops this close (chained) are done together before heading out
local HUB_CHAIN = 220      -- how far apart two stops can be and still count as the same town
local DETOUR = 150         -- a town stop this close to where you are mid-run gets picked up on the way

local function isTown(s) return s.kind == "turnin" or s.kind == "accept" end

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
  while #route > LIMITS[self:Style()].steps do table.remove(route) end
  -- how to get to the first stop: run, fly or hearth
  if route[1] and here and route[1].m then route[1].travel = self:Travel(here, route[1]) end
  return route
end

-- Travel: flight paths and hearthstone ----------------------------------------------------------
local HEARTHSTONE = 6948
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

local function hearthReady()
  if (C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE) or 0) == 0 then return false end
  local start, duration = 0, 0
  if C_Container and C_Container.GetItemCooldown then start, duration = C_Container.GetItemCooldown(HEARTHSTONE) end
  return not start or start == 0 or (start + duration - GetTime()) <= 0
end

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
    local h = travelDB().hearth
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
  local h = travelDB().hearth
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
