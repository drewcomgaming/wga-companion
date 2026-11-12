-- WGA Companion: how far you are through each zone and dungeon. Counts the quests your faction
-- (and class) can do there, from the quest database, and how many of them you've already handed in.
local _, CM = ...
local P = CM:NewModule("Progress")

local Q_SIDE, Q_CLASS, Q_STARTS, Q_FLAGS, Q_SKILL = 4, 5, 6, 13, 14
local byZone   -- [zone name] = { questIDs }

local function mapName(m)
  local info = m and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return info and info.name
end

-- Quests by the zone their giver stands in, built once per session (a few thousand quests).
function P:Build()
  if byZone then return byZone end
  byZone = {}
  local d, QD, SG = CM.Data.QDB, CM.QData, CM.SmartGuide
  if not (d and QD and SG and SG.ZoneOf) then return byZone end
  local side = ({ Alliance = "A", Horde = "H" })[UnitFactionGroup("player") or ""]
  local classID = select(3, UnitClass("player"))
  local classBit = classID and bit.lshift(1, classID - 1)
  for id, q in pairs(d.q) do
    local st = q[Q_STARTS]
    local ok = st and (st[1][1] or st[2][1])
      and (not q[Q_SIDE] or q[Q_SIDE] == side)
      and not q[Q_SKILL]
      and not (q[Q_FLAGS] and bit.band(q[Q_FLAGS], 2) ~= 0)
      and not (q[Q_CLASS] and q[Q_CLASS] > 0 and classBit and bit.band(q[Q_CLASS], classBit) == 0)
    if ok then
      for _, e in ipairs(QD:Starters(id)) do
        local sp = QD:Spawns(e[1], e[2])
        local name = sp and mapName(SG.ZoneOf(next(sp)))
        if name then
          local list = byZone[name] or {}
          list[#list + 1] = id
          byZone[name] = list
          break
        end
      end
    end
  end
  return byZone
end

local function count(list)
  local done = 0
  local flagged = C_QuestLog.IsQuestFlaggedCompleted
  for _, id in ipairs(list or {}) do if flagged(id) then done = done + 1 end end
  return done, #(list or {})
end

-- done, total for a zone by name (total 0 when we know no quests there)
function P:Zone(name) return count(self:Build()[name]) end

-- done, total for a dungeon's quests
function P:Dungeon(name)
  if not (CM.QData and CM.QData:Has()) then return 0, 0 end
  return count(CM.QData:DungeonQuests((name or ""):gsub("^NEW:%s*", "")))
end

-- "13/14  92%" and a 0..1 fraction
function P:Label(done, total)
  if not total or total == 0 then return "", 0 end
  local f = done / total
  return string.format("%d/%d  %d%%", done, total, math.floor(f * 100 + 0.5)), f
end
