-- WGA Companion: gathering map. Every herb and ore node you gather is remembered (name and spot), shown
-- on the world map and minimap, and a gathering run points the arrow from node to node around the zone,
-- skipping ones you picked in the last few minutes.
local _, CM = ...
local GA = CM:NewModule("Gather")

local MERGE_YARDS = 18     -- two finds this close are the same node
local ARRIVE_YARDS = 12    -- close enough to count as visited on a run
local RESPAWN = 300        -- seconds before a run sends you back to a node
local SPELLS = { [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
  [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore" }
local NAMES = { ["herb gathering"] = "herb", herbalism = "herb", mining = "ore" }
local LABEL = { herb = "Herb", ore = "Ore" }

local function S() return CM.db.settings end
local function db()
  local g = CM.db.global
  g.nodes = g.nodes or {}   -- [uiMapID] = { { x, y, kind, name, count, lastSeen } }
  return g.nodes
end

local function world(m, x, y)
  if CM.Arrow and CM.Arrow.WorldPos then return CM.Arrow.WorldPos(m, x, y) end
end
local function dist(c1, x1, y1, c2, x2, y2)
  if not c1 or c1 ~= c2 then return math.huge end
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end
local function here()
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local x, y = p:GetXY()
  return m, x, y
end

local function kindOf(spellID)
  local k = spellID and SPELLS[spellID]
  if k then return k end
  local name
  if C_Spell and C_Spell.GetSpellInfo then
    local info = spellID and C_Spell.GetSpellInfo(spellID)
    name = info and info.name
  end
  return name and NAMES[name:lower()]
end

-- Remembering nodes --------------------------------------------------------------------------------
function GA:Record(kind, name)
  local m, x, y = here()
  if not m then return end
  local c, wx, wy = world(m, x, y)
  local list = db()[m] or {}
  db()[m] = list
  for _, n in ipairs(list) do
    if n[3] == kind then
      local nc, nx, ny = world(m, n[1], n[2])
      if dist(c, wx, wy, nc, nx, ny) < MERGE_YARDS then
        n[5] = (n[5] or 1) + 1
        n[6] = time()
        if name and name ~= "" then n[4] = name end
        self:Visited(n)
        return
      end
    end
  end
  local n = { math.floor(x * 10000) / 10000, math.floor(y * 10000) / 10000, kind, name or LABEL[kind], 1, time() }
  list[#list + 1] = n
  self:Visited(n)
  self:Redraw()
end

local casts = {}
CM:On("UNIT_SPELLCAST_SENT", function(_, unit, target, castGUID, spellID)
  if unit ~= "player" then return end
  local kind = kindOf(CM:Safe(spellID))
  target = CM:Safe(target)
  if kind and castGUID then casts[castGUID] = { kind, target } end
end)
CM:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID)
  if unit ~= "player" or not castGUID then return end
  local c = casts[castGUID]
  if c then casts[castGUID] = nil; GA:Record(c[1], c[2]) end
end)
CM:On("UNIT_SPELLCAST_FAILED", function(_, unit, castGUID) if castGUID then casts[castGUID] = nil end end)
CM:On("UNIT_SPELLCAST_INTERRUPTED", function(_, unit, castGUID) if castGUID then casts[castGUID] = nil end end)

-- Your gathering professions decide what to show (both when you have neither)
function GA:Wanted()
  local want, any = {}, false
  if GetProfessions and GetProfessionInfo then
    for _, i in ipairs({ GetProfessions() }) do
      local name = i and GetProfessionInfo(i)
      name = name and name:lower()
      if name == "herbalism" then want.herb, any = true, true end
      if name == "mining" then want.ore, any = true, true end
    end
  end
  if not any then want.herb, want.ore = true, true end
  return want
end

-- Map pins (drawn by the quest map and minimap code) -------------------------------------------------
local rects = {}
local function rectOn(sm, mapID)
  local key = sm * 100000 + mapID
  if rects[key] == nil then
    rects[key] = false
    if C_Map.GetMapRectOnMap then
      local ok, x1, x2, y1, y2 = pcall(C_Map.GetMapRectOnMap, sm, mapID)
      if ok and x1 and x2 and y1 and y2 and x2 > x1 and y2 > y1 then rects[key] = { x1, x2, y1, y2 } end
    end
  end
  return rects[key] or nil
end

local function ago(t)
  if not t then return "" end
  local d = time() - t
  if d < 3600 then return string.format("%d min ago", math.floor(d / 60)) end
  if d < 86400 then return string.format("%d h ago", math.floor(d / 3600)) end
  return string.format("%d days ago", math.floor(d / 86400))
end

function GA:Collect(mapID, emit)
  if S().gatherPins == false then return end
  local want = self:Wanted()
  for sm, list in pairs(db()) do
    local r = sm ~= mapID and rectOn(sm, mapID)
    if sm == mapID or r then
      for _, n in ipairs(list) do
        if want[n[3]] then
          local x, y = n[1], n[2]
          if r then x, y = r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3]) end
          emit(x, y, n[3], n[4] or LABEL[n[3]],
            string.format("%s node  ·  gathered %d time%s, last %s", LABEL[n[3]], n[5] or 1, (n[5] or 1) == 1 and "" or "s", ago(n[6])))
        end
      end
    end
  end
end

function GA:Redraw()
  local N = CM.QuestNav
  if not N then return end
  if WorldMapFrame and WorldMapFrame:IsShown() then N:DrawMap() end
  N:CollectMinimap()
end

-- Gathering run ----------------------------------------------------------------------------------------
-- The arrow goes to the nearest node in your zone you haven't picked in the last 5 minutes.
local run   -- { kind = "herb"|"ore"|nil, visited = { [node] = time }, target = node }

local function zoneOf(m) return CM.SmartGuide and CM.SmartGuide.ZoneOf and CM.SmartGuide.ZoneOf(m) or m end

function GA:Visited(n)
  if run then run.visited[n] = GetTime(); if run.target == n then run.target = nil end end
end

function GA:NextNode()
  local m, x, y = here()
  if not m then return nil end
  local zone = zoneOf(m)
  local pc, px, py = world(m, x, y)
  local want = self:Wanted()
  local best, bd, bm
  for sm, list in pairs(db()) do
    if zoneOf(sm) == zone then
      for _, n in ipairs(list) do
        local ok = (run.kind and n[3] == run.kind) or (not run.kind and want[n[3]])
        local seen = run.visited[n]
        if ok and not (seen and GetTime() - seen < RESPAWN) then
          local c, wx, wy = world(sm, n[1], n[2])
          local d = dist(pc, px, py, c, wx, wy)
          if d < (bd or math.huge) then best, bd, bm = n, d, sm end
        end
      end
    end
  end
  return best, bm, bd
end

function GA:Step()
  if not run then return end
  local n, m = run.target, run.targetMap
  if n then
    local pm, px, py = here()
    local c, wx, wy = world(m, n[1], n[2])
    local pc, pwx, pwy = world(pm, px, py)
    if dist(pc, pwx, pwy, c, wx, wy) < ARRIVE_YARDS then self:Visited(n) n = nil end
  end
  if not n then
    n, m = self:NextNode()
    run.target, run.targetMap = n, m
    if not n then
      if not run.waiting then
        run.waiting = true
        CM:Print("Gathering run: no fresh nodes here right now. I'll point you on as they respawn.")
      end
      return
    end
    run.waiting = nil
  end
  if CM.Arrow then CM.Arrow:Point(m, n[1], n[2], (n[4] or LABEL[n[3]]) .. " (gathering run)", 120) end
end

function GA:StartRun(kind)
  local count = 0
  local m = C_Map.GetBestMapForUnit("player")
  local zone = m and zoneOf(m)
  for sm, list in pairs(db()) do if zoneOf(sm) == zone then count = count + #list end end
  if count == 0 then
    CM:Print("I don't know any herb or ore nodes in this zone yet. Gather a few and I'll remember them.")
    return
  end
  run = { kind = kind, visited = {} }
  if not self.ticker then self.ticker = C_Timer.NewTicker(1, function() GA:Step() end) end
  CM:Print("Gathering run on: %d known nodes in this zone. The arrow takes you to the nearest fresh one. /wga gather stop to end.", count)
  self:Step()
end

function GA:StopRun()
  run = nil
  if self.ticker then self.ticker:Cancel(); self.ticker = nil end
  if CM.Arrow and CM.Arrow.ClearTemp then CM.Arrow:ClearTemp() end
  CM:Print("Gathering run off.")
end

function GA:Running() return run ~= nil end
function GA:ToggleRun() if run then self:StopRun() else self:StartRun() end end

function GA:Count()
  local herb, ore = 0, 0
  for _, list in pairs(db()) do
    for _, n in ipairs(list) do if n[3] == "herb" then herb = herb + 1 else ore = ore + 1 end end
  end
  return herb, ore
end

-- /wga gather [herb|ore|stop|pins|clear]
function GA:Command(arg)
  arg = (arg or ""):lower()
  if arg == "stop" or arg == "off" then self:StopRun()
  elseif arg == "herb" or arg == "herbs" then self:StartRun("herb")
  elseif arg == "ore" or arg == "mining" then self:StartRun("ore")
  elseif arg == "pins" then
    S().gatherPins = S().gatherPins == false
    CM:Print("Gathering nodes on the map %s.", S().gatherPins and "on" or "off")
    self:Redraw()
  elseif arg == "clear" then
    local m = C_Map.GetBestMapForUnit("player")
    local zone = m and zoneOf(m)
    for sm in pairs(db()) do if zoneOf(sm) == zone then db()[sm] = nil end end
    CM:Print("Forgot the nodes in this zone.")
    self:Redraw()
  elseif arg == "" or arg == "run" or arg == "start" then self:ToggleRun()
  else
    local h, o = self:Count()
    CM:Print("Known nodes: %d herb, %d ore. /wga gather [herb|ore|stop|pins|clear]", h, o)
  end
end
