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
        if m == pm or (d and d < NEARBY_YARDS) then
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

-- Greedy nearest-next route from where you stand; steps without a location go last.
function SG:Route()
  local steps, pm, px, py = self:Collect()
  local placed, rest, later = {}, {}, {}
  for _, s in ipairs(steps) do
    if s.later then later[#later + 1] = s
    elseif s.m and s.x then placed[#placed + 1] = s else rest[#rest + 1] = s end
  end
  local route = {}
  local cur = pm and px and { m = pm, x = px, y = py }
  while #placed > 0 do
    local bi, bd = 1, math.huge
    for i, s in ipairs(placed) do
      local d = cur and yards(cur, s) or math.huge
      -- turn-ins first when it's close to a tie: they free up quest log space and give xp
      if s.kind == "turnin" and d ~= math.huge then d = d * 0.85 end
      if d < bd then bi, bd = i, d end
    end
    local s = table.remove(placed, bi)
    s.yards = cur and yards({ m = pm, x = px, y = py }, s)
    route[#route + 1] = s
    cur = s
  end
  for _, s in ipairs(rest) do route[#route + 1] = s end
  for _, s in ipairs(later) do route[#route + 1] = s end
  while #route > LIMITS[self:Style()].steps do table.remove(route) end
  return route
end

-- Totals for the header: quests done in this zone vs. known in the database
function SG:Summary()
  local level = UnitLevel("player") or 1
  local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 1
  return level, xpMax > 0 and xp / xpMax or 0
end
