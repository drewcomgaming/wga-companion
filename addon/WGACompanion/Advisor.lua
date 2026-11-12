-- WGA Companion: Whirl's advice. Builds, stats, dungeons and gear for your class and level,
-- shaped by how you play (solo or group) and how much you know the game (new or veteran).
-- Addons can't reach the internet, so everything Whirl knows ships in Data/Knowledge.lua and
-- what the game itself tells us (your gear, your bags, the quest database).
local _, CM = ...
local Ad = CM:NewModule("Advisor")

local function S() return CM.db.settings end
local function K() return CM.Data.Knowledge or { classes = {}, newPlayer = {} } end
local function myClass() local _, c = UnitClass("player"); return c end
local function level() return UnitLevel("player") or 1 end
function Ad:Style() return S().groupPlay and "group" or "solo" end
function Ad:Experience() return S().veteranPlayer and "veteran" or "new" end

local function latest(list, lvl)
  local best
  for _, e in ipairs(list or {}) do if e[1] <= lvl then best = e end end
  return best
end

-- Talent and build advice
function Ad:Build()
  local c = K().classes[myClass() or ""]
  if not c then return "I don't have notes for your class yet." end
  local lvl = level()
  local solo, group = c.solo, c.group
  local lines = {}
  if lvl < 10 then
    lines[#lines + 1] = string.format("No talents until level 10. For levelling, plan on %s.", solo.spec)
  else
    local step = latest(solo.plan, lvl)
    lines[#lines + 1] = string.format("Levelling build: %s. %s", solo.spec, step and step[2] or "")
  end
  if self:Style() == "group" then
    lines[#lines + 1] = string.format("For groups you'd play %s as %s.", group.role, group.spec)
  end
  lines[#lines + 1] = "Use " .. solo.weapon .. "."
  if self:Experience() == "new" then
    local tip = (self:Style() == "group" and group.tips or solo.tips)
    if tip and tip[1] then lines[#lines + 1] = tip[(lvl % #tip) + 1] end
  end
  return table.concat(lines, " ")
end

function Ad:Stats()
  local c = K().classes[myClass() or ""]
  if not c then return "I don't have notes for your class yet." end
  local set = self:Style() == "group" and c.group or c.solo
  return string.format("Stats to look for (%s): %s.", self:Style() == "group" and set.role or "levelling",
    table.concat(set.stats, " > "))
end

-- Dungeons that fit your level and side
local function range(s) local lo, hi = (s or ""):match("(%d+)%D+(%d+)"); return tonumber(lo), tonumber(hi) end
function Ad:Dungeons()
  local lvl = level()
  local side = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
  local fits = {}
  for _, d in ipairs(CM.Data.Dungeons or {}) do
    local lo, hi = range(d.levels)
    local f = d.faction
    local mine = not f or f:find(side, 1, true)
    if lo and mine and not d.raid and lvl >= lo - 1 and lvl <= hi then
      local name = d.name:gsub("^NEW:%s*", "")
      local q = CM.QData and CM.QData.DungeonQuests and #CM.QData:DungeonQuests(name) or 0
      fits[#fits + 1] = string.format("%s (%s%s)", name, d.levels, q > 0 and (", " .. q .. " quests") or "")
    end
  end
  if #fits == 0 then return "No dungeon fits your level right now. Keep questing!" end
  local head = self:Style() == "group" and "Dungeons for you right now: " or "Dungeons at your level (you'll need a group): "
  local out = head .. table.concat(fits, ", ") .. "."
  if self:Style() == "solo" then out = out .. " Questing is faster solo; do these if a group comes along." end
  return out
end

-- Gear: upgrades sitting in your bags, judged like quest rewards
function Ad:Gear()
  local Rw = CM.Rewards
  if not (Rw and Rw.UpgradeBy and C_Container) then return "I can't check gear right now." end
  local _, class = UnitClass("player")
  local found = {}
  for bag = 0, (CM.Bags and CM.Bags.Last or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      local minLevel = link and select(5, C_Item.GetItemInfo(link))
      if link and (not minLevel or minLevel <= level()) then
        local ok, by, why = pcall(Rw.UpgradeBy, link, class, level())
        if ok and by and by > 0 then found[#found + 1] = { link = link, by = by, why = why } end
      end
    end
  end
  table.sort(found, function(a, b) return a.by > b.by end)
  if #found == 0 then return "Nothing in your bags beats what you're wearing." end
  local names = {}
  for i = 1, math.min(3, #found) do names[#names + 1] = found[i].link .. " (" .. found[i].why .. ")" end
  return "Upgrades in your bags: " .. table.concat(names, ", ") .. ". Equip them!"
end

function Ad:NewPlayerTip()
  local e = latest(K().newPlayer, level())
  return e and e[2]
end

-- Everything at once, for the chat window; Whirl says the short version
function Ad:All()
  local out = { self:Build(), self:Stats(), self:Dungeons(), self:Gear() }
  if self:Experience() == "new" then out[#out + 1] = self:NewPlayerTip() end
  return out
end

local function tell(text, speak)
  if not text then return end
  CM:Print("%s", text)
  if speak and CM.Companion then CM.Companion:Remark(text) end
end

function Ad:Command(cmd, arg)
  cmd = (cmd or ""):lower()
  if cmd == "advice" or cmd == "help" then
    for i, t in ipairs(self:All()) do tell(t, i == 1) end
    CM:Print("Based on classic knowledge; WoW Forever may have changed some talents and items.")
  elseif cmd == "build" or cmd == "talents" then tell(self:Build(), true)
  elseif cmd == "stats" then tell(self:Stats(), true)
  elseif cmd == "dungeons" or cmd == "dungeon" then tell(self:Dungeons(), true)
  elseif cmd == "gear" then tell(self:Gear(), true)
  elseif cmd == "style" then
    S().groupPlay = arg == "group"
    CM:Print("Whirl will advise for %s play.", self:Style())
  elseif cmd == "experience" or cmd == "exp" then
    S().veteranPlayer = arg == "veteran" or arg == "vet"
    CM:Print("Whirl will give %s.", S().veteranPlayer and "short, to-the-point advice" or "extra beginner tips")
  else
    return false
  end
  return true
end

-- Level-up advice: talent reminders and beginner tips at the right moments
CM:On("PLAYER_LEVEL_UP", function(_, newLevel)
  if S().companion == false or S().companionAdvice == false then return end
  C_Timer.After(9, function()
    local lvl = newLevel or level()
    local c = K().classes[myClass() or ""]
    if lvl >= 10 and c then
      local step = latest(c.solo.plan, lvl)
      if step and step[1] == lvl then
        CM.Companion:Remark("New talent advice: " .. step[2])
        return
      end
    end
    if Ad:Experience() == "new" then
      for _, e in ipairs(K().newPlayer) do
        if e[1] == lvl then CM.Companion:Remark(e[2]) return end
      end
      if lvl % 2 == 0 then CM.Companion:Remark("Level " .. lvl .. "! Your class trainer has new spells for you.") end
    end
  end)
end)

-- Watching your fights ----------------------------------------------------------------------------
-- Whirl notices which mobs you kill and where you are. Killing mobs no quest needs, or fighting far
-- from the guide's current step, gets a friendly "wrong place" note pointing at the right spot.
local DIRS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
local function where(step)
  if not (step and step.m and step.x and CM.Arrow) then return nil end
  local d, b = CM.Arrow:Compute({ m = step.m, x = step.x, y = step.y })
  if not d then return nil end
  local i = math.floor(((b % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8 + 1
  return d, string.format("about %d yards %s", math.floor(d / 10 + 0.5) * 10, DIRS[i])
end

-- Mob names your open quests still need (from the quest database)
function Ad:NeededMobs()
  local need = {}
  local QD, QL = CM.QData, C_QuestLog
  if not (QD and QD:Has()) then return need end
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    local id = info and not info.isHeader and info.questID
    if id and not QL.IsComplete(id) then
      for idx, o in ipairs(QL.GetQuestObjectives(id) or {}) do
        if not o.finished then
          for _, e in ipairs(QD:ObjectiveEntities(id, idx) or {}) do
            local n = e[1] == "n" and QD:Name("n", e[2])
            if n then need[n:lower()] = true end
          end
        end
      end
    end
  end
  return need
end

local OFF_COURSE = 250      -- yards from the current kill step before we call it the wrong place
local NAG_GAP = 150         -- seconds between "wrong place" notes
local watch = { names = {}, counted = {}, wasted = 0, lastNag = -NAG_GAP }

local function currentStep()
  local GW = CM.GuideWindow
  return GW and GW.current
end

function Ad:OnKill(name)
  if not name or S().companion == false or S().companionWatch == false then return end
  local need = self:NeededMobs()
  if next(need) == nil then return end          -- no kill quests open: nothing to judge
  if need[name:lower()] then watch.wasted = 0 return end
  watch.wasted = watch.wasted + 1
  watch.lastWasted = name
  if watch.wasted >= 3 then self:Nudge() end
end

function Ad:Nudge(force)
  local now = GetTime()
  if not force and now - watch.lastNag < NAG_GAP then return end
  local step = currentStep()
  local d, words = where(step)
  local msg
  if watch.wasted >= 3 and watch.lastWasted then
    msg = string.format("Those %s don't count for any of our quests.", watch.lastWasted)
    if step and step.npc and (step.kind == "kill" or step.kind == "loot") then
      msg = msg .. string.format(" For %s we need %s%s.", step.title or "our quest", step.npc, words and (", " .. words) or "")
    elseif step and step.title then
      msg = msg .. string.format(" Next up is %s%s.", step.title, words and (", " .. words) or "")
    end
  elseif watch.wasted >= 2 and step and d and d > OFF_COURSE and (step.kind == "kill" or step.kind == "loot" or step.kind == "use") then
    msg = string.format("We're a bit off course. %s for %s are %s.", step.npc or "What we need", step.title or "our quest", words)
  end
  if msg and CM.Companion then
    watch.lastNag, watch.wasted = now, 0
    CM.Companion:Remark(msg)
  end
end

-- Remember who you target (names can be hidden mid-combat), count them when they die
CM:On("PLAYER_TARGET_CHANGED", function()
  local guid = CM:Safe(UnitGUID and UnitGUID("target"))
  if guid and CM:Safe(UnitCanAttack("player", "target")) then
    watch.names[guid] = CM:Safe(UnitName("target")) or watch.names[guid]
  end
end)

local function checkTarget()
  local guid = CM:Safe(UnitGUID and UnitGUID("target"))
  if not guid or watch.counted[guid] or not watch.names[guid] then return end
  if CM:Safe(UnitIsDead("target")) and not CM:Safe(UnitIsTapDenied and UnitIsTapDenied("target")) then
    watch.counted[guid] = true
    Ad:OnKill(watch.names[guid])
  end
end

-- After a fight: are we where the guide wants us?
CM:On("PLAYER_REGEN_ENABLED", function()
  checkTarget()
  if S().companion == false or S().companionWatch == false then return end
  C_Timer.After(1, function() Ad:Nudge() end)
end)

function Ad:OnLogin()
  C_Timer.NewTicker(0.5, checkTarget)
  -- keep the memory small
  C_Timer.NewTicker(300, function() wipe(watch.names); wipe(watch.counted) end)
end
