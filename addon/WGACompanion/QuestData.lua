-- WGA Companion: lookups over the bundled quest database (Data/QuestDB.lua, from QuestieDB, GPL-3.0).
-- Answers "where is this objective", "where do I turn this in" and "which quests can I pick up here".
local _, CM = ...
local QD = CM:NewModule("QData")
local QL = C_QuestLog

local Q_NAME, Q_REQ, Q_LVL, Q_SIDE, Q_CLASS, Q_STARTS, Q_ENDS, Q_OBJS, Q_PREG, Q_PRES, Q_EXCL, Q_NEXT, Q_FLAGS, Q_SKILL =
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14

local function db() return CM.Data.QDB end
function QD:Has() return db() ~= nil end
function QD:Quest(id) local d = db(); return d and d.q[id] end

-- Spawn lists are stored as "x,y x,y" strings per uiMapID; unpacked on first use.
local unpacked = { n = {}, o = {} }
function QD:Spawns(kind, id)
  local cache = unpacked[kind]
  local s = cache[id]
  if s ~= nil then return s or nil end
  local d = db()
  local e = d and d[kind][id]
  if not e or not e[2] then cache[id] = false return nil end
  s = {}
  for m, packed in pairs(e[2]) do
    local list = {}
    for x, y in packed:gmatch("([%d%.]+),([%d%.]+)") do
      list[#list + 1] = tonumber(x) / 100
      list[#list + 1] = tonumber(y) / 100
    end
    s[m] = list
  end
  cache[id] = s
  return s
end

function QD:Name(kind, id)
  local d = db()
  local e = d and d[kind] and d[kind][id]
  return e and e[1]
end

-- Entities ({kind, id}) where a Questie objective can be done.
local function entitiesFor(o, out)
  local kind, id = o[1], o[2]
  if kind == "n" or kind == "o" then
    table.insert(out, { kind, id })
  elseif kind == "k" then
    for _, n in ipairs(id) do table.insert(out, { "n", n }) end
  elseif kind == "i" then
    local it = db().i[id]
    if it then
      for _, n in ipairs(it[2] or {}) do table.insert(out, { "n", n }) end
      for _, ob in ipairs(it[3] or {}) do table.insert(out, { "o", ob }) end
    end
  end
  return out
end

local function objName(o)
  if o[3] and o[3] ~= "" then return o[3] end
  local kind, id = o[1], o[2]
  if kind == "k" then return QD:Name("n", id[1]) end
  return QD:Name(kind == "i" and "i" or kind, id)
end

-- Entities for the game's objective number `idx` of a quest (matched by name, then by position).
function QD:ObjectiveEntities(questID, idx)
  local q = self:Quest(questID)
  if not q or not q[Q_OBJS] or #q[Q_OBJS] == 0 then return nil end
  local objs = QL.GetQuestObjectives(questID) or {}
  local game = objs[idx]
  local text = game and game.text and game.text:lower() or ""
  for _, o in ipairs(q[Q_OBJS]) do
    local name = objName(o)
    if name and text ~= "" and text:find(name:lower(), 1, true) then return entitiesFor(o, {}) end
  end
  if #objs == #q[Q_OBJS] and q[Q_OBJS][idx] then return entitiesFor(q[Q_OBJS][idx], {}) end
  local out = {}
  for _, o in ipairs(q[Q_OBJS]) do entitiesFor(o, out) end
  return out
end

function QD:Finishers(questID)
  local q = self:Quest(questID)
  if not q then return nil end
  local out = {}
  for _, n in ipairs(q[Q_ENDS][1] or {}) do table.insert(out, { "n", n }) end
  for _, o in ipairs(q[Q_ENDS][2] or {}) do table.insert(out, { "o", o }) end
  return out
end

-- Nearest spawn of any entity: prefers the player's map, else the first map that has one.
-- Returns m, x, y (0-1), name
function QD:Nearest(entities, pm, px, py)
  local best, bd, other
  for _, e in ipairs(entities or {}) do
    local sp = self:Spawns(e[1], e[2])
    if sp then
      local here = pm and sp[pm]
      if here and px then
        for i = 1, #here, 2 do
          local d = (here[i] - px) ^ 2 + (here[i + 1] - py) ^ 2
          if not bd or d < bd then bd, best = d, { pm, here[i], here[i + 1], self:Name(e[1], e[2]) } end
        end
      elseif not other then
        for m, list in pairs(sp) do
          if #list >= 2 then other = { m, list[1], list[2], self:Name(e[1], e[2]) } break end
        end
      end
    end
  end
  local r = best or other
  if r then return r[1], r[2], r[3], r[4] end
end

-- Available quests ----------------------------------------------------------------------------
local avail -- cached list of questIDs
local function done(id) return QL.IsQuestFlaggedCompleted(id) end
local function active(id) return QL.IsOnQuest(id) end

local function greyBelow(level)
  local ok, g = pcall(function() return GetQuestGreenRange and GetQuestGreenRange() end)
  return level - ((ok and g) or 8)
end

function QD:IsAvailable(id, q, level, side, classBit)
  if done(id) or active(id) then return false end
  if (q[Q_REQ] or 1) > level then return false end
  if q[Q_LVL] and q[Q_LVL] > 0 and q[Q_LVL] < greyBelow(level) then return false end
  if q[Q_SIDE] and q[Q_SIDE] ~= side then return false end
  if q[Q_CLASS] and q[Q_CLASS] > 0 and classBit and bit.band(q[Q_CLASS], classBit) == 0 then return false end
  if q[Q_SKILL] then return false end                       -- profession quests: not shown yet
  if q[Q_FLAGS] and bit.band(q[Q_FLAGS], 2) ~= 0 then return false end -- needs a world event
  for _, p in ipairs(q[Q_PREG] or {}) do if not done(p) then return false end end
  if q[Q_PRES] then
    local any = false
    for _, p in ipairs(q[Q_PRES]) do if done(p) then any = true break end end
    if not any then return false end
  end
  for _, x in ipairs(q[Q_EXCL] or {}) do if done(x) or active(x) then return false end end
  if q[Q_NEXT] and (done(q[Q_NEXT]) or active(q[Q_NEXT])) then return false end
  return true
end

function QD:Available()
  if avail then return avail end
  avail = {}
  local d = db()
  if not d then return avail end
  local level = UnitLevel("player") or 1
  local side = ({ Alliance = "A", Horde = "H" })[UnitFactionGroup("player") or ""]
  local classID = select(3, UnitClass("player"))
  local classBit = classID and bit.lshift(1, classID - 1)
  for id, q in pairs(d.q) do
    if (q[Q_STARTS][1][1] or q[Q_STARTS][2][1]) and self:IsAvailable(id, q, level, side, classBit) then
      table.insert(avail, id)
    end
  end
  return avail
end

function QD:Invalidate() avail = nil end
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE" }) do
  CM:On(e, function() avail = nil end)
end

function QD:Starters(id)
  local q = self:Quest(id)
  local out = {}
  for _, n in ipairs(q[Q_STARTS][1] or {}) do table.insert(out, { "n", n }) end
  for _, o in ipairs(q[Q_STARTS][2] or {}) do table.insert(out, { "o", o }) end
  return out
end

function QD:Level(id) local q = self:Quest(id); return q and q[Q_LVL] end
function QD:Title(id) local q = self:Quest(id); return q and q[Q_NAME] end
