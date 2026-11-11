-- WGA Companion: Smart Guide. Builds a Zygor-style route on the fly from the quest database,
-- your quest log, your level and where you stand: turn in what's done, finish what's open,
-- pick up what's nearby, in the order that walks the least.
local _, CM = ...
local SG = CM:NewModule("SmartGuide")
local QL = C_QuestLog

local NEARBY_YARDS = 900   -- quests to pick up within this range (or anywhere on your map)
local MAX_ACCEPT = 6
local MAX_STEPS = 14

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
      steps[#steps + 1] = step
    end
  end
  -- Quests to pick up nearby
  if QD:Has() and CM.db.settings.smartAccept ~= false then
    local offers = {}
    for _, id in ipairs(QD:Available()) do
      local m, x, y, who = QD:Nearest(QD:Starters(id), pm, px, py)
      if m and not inLog[id] then
        local d = pm and px and yards({ m = pm, x = px, y = py }, { m = m, x = x, y = y })
        if m == pm or (d and d < NEARBY_YARDS) then
          offers[#offers + 1] = { kind = "accept", verb = "Accept", quest = id, title = QD:Title(id), m = m, x = x, y = y,
            npc = who, npcID = CM.Visuals and CM.Visuals:NpcID(who), level = QD:Level(id), d = d or math.huge }
        end
      end
    end
    table.sort(offers, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#offers, MAX_ACCEPT) do steps[#steps + 1] = offers[i] end
  end
  return steps, pm, px, py
end

-- Greedy nearest-next route from where you stand; steps without a location go last.
function SG:Route()
  local steps, pm, px, py = self:Collect()
  local placed, rest = {}, {}
  for _, s in ipairs(steps) do
    if s.m and s.x then placed[#placed + 1] = s else rest[#rest + 1] = s end
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
  while #route > MAX_STEPS do table.remove(route) end
  return route
end

-- Totals for the header: quests done in this zone vs. known in the database
function SG:Summary()
  local level = UnitLevel("player") or 1
  local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 1
  return level, xpMax > 0 and xp / xpMax or 0
end
