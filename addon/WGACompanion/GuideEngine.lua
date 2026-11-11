-- WGA Companion: step-by-step guide engine (Zygor-style), quest-aware with auto-advance.
--
-- Guide format (register from any data file):
--   CM.Guides:Register({ name = "Elwynn 1-6", faction = "Alliance", levels = "1-6", next = "Elwynn 6-10",
--     steps = {
--       { t = "accept",   quest = 783, text = "A Threat Within", npc = "Marshal McBride", m = 1429, x = 48.9, y = 41.6 },
--       { t = "complete", quest = 7,   text = "Kill Kobold Vermin", m = 1429, x = 47.0, y = 35.0 },
--       { t = "turnin",   quest = 7,   ... },
--       { t = "goto",     m = 1429, x = 42.1, y = 65.9, text = "Run to Goldshire" },
--       { t = "level",    level = 6 },
--       { t = "collect",  item = 2589, count = 10, text = "Linen Cloth for First Aid" },
--       { t = "note",     text = "Train skills" },  -- manual, click to complete
--     } })
--   m = uiMapID (Elwynn 1429, Dun Morogh 1426, Teldrassil 1438, Durotar 1411, Mulgore 1412, Tirisfal 1420 ...)
local _, CM = ...
local G = CM:NewModule("Guides")

G.list, G.byName = {}, {}

function G:Register(guide)
  if not guide or not guide.name or self.byName[guide.name] then return end
  table.insert(self.list, guide)
  self.byName[guide.name] = guide
end

-- Quest state helpers ---------------------------------------------------------------
local turnedIn = {} -- turn-ins this session (server flag can lag a moment)

function G:IsQuestDone(id)
  if turnedIn[id] then return true end
  return C_QuestLog.IsQuestFlaggedCompleted(id)
end

local QL = C_QuestLog

function G:InLog(id) return QL.IsOnQuest(id) end

function G:ObjectivesDone(id)
  return QL.IsOnQuest(id) and (QL.ReadyForTurnIn and QL.ReadyForTurnIn(id) or QL.IsComplete(id))
end

function G:ObjectiveText(id)
  local objs = QL.GetQuestObjectives(id)
  if not objs or #objs == 0 then return nil end
  local out = {}
  for _, o in ipairs(objs) do
    if o.text and o.text ~= "" then table.insert(out, (o.finished and "|cff40ff40" or "|cffffffff") .. o.text .. "|r") end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

local function itemCount(id) return CM.GetItemCount(id) or 0 end

-- A step is done when the game state says so; manual steps when the player clicks them.
function G:StepDone(step, idx)
  local prog = self:Progress()
  if prog.manual[idx] then return true end
  local t = step.t
  if t == "accept" then return self:InLog(step.quest) or self:IsQuestDone(step.quest)
  elseif t == "complete" then return self:ObjectivesDone(step.quest) or self:IsQuestDone(step.quest)
  elseif t == "turnin" then return self:IsQuestDone(step.quest)
  elseif t == "level" then return UnitLevel("player") >= step.level
  elseif t == "collect" then return itemCount(step.item) >= (step.count or 1)
  elseif t == "goto" then return self.arrived == idx
  end
  return false
end

-- Progress (per character) ---------------------------------------------------------
function G:Progress()
  local c = WGACompanionCharDB
  c.guide = c.guide or {}
  local name = c.guide.name
  c.guide.progress = c.guide.progress or {}
  local p = name and c.guide.progress[name]
  if name and not p then p = { step = 1, manual = {} }; c.guide.progress[name] = p end
  return p or { step = 1, manual = {} }
end

function G:Current()
  local name = WGACompanionCharDB.guide and WGACompanionCharDB.guide.name
  return name and self.byName[name]
end

function G:Load(name)
  if not self.byName[name] then CM:Print("No guide named '%s'. /wga guides lists them.", name); return end
  WGACompanionCharDB.guide = WGACompanionCharDB.guide or {}
  WGACompanionCharDB.guide.name = name
  WGACompanionCharDB.guide.mode = "guide"
  self.arrived = nil
  self:Update()
  if CM.GuideWindow then CM.GuideWindow:Show() end
  CM:Print("Guide loaded: %s", name)
end

-- Pick a sensible guide for this character (faction + level) the first time.
function G:Suggest()
  local faction, level = UnitFactionGroup("player"), UnitLevel("player")
  for _, g in ipairs(self.list) do
    local lo, hi = (g.levels or ""):match("(%d+)%-(%d+)")
    lo, hi = tonumber(lo) or 1, tonumber(hi) or 60
    if (not g.faction or g.faction == faction) and level >= lo and level < hi then return g.name end
  end
end

-- Move forward past completed steps; if the guide is finished, chain to the next guide.
function G:Update()
  local guide = self:Current()
  if guide then
    local p = self:Progress()
    local n = #guide.steps
    while p.step <= n and self:StepDone(guide.steps[p.step], p.step) do
      p.step = p.step + 1
    end
    if p.step > n then
      if guide.next and self.byName[guide.next] then
        CM:Print("Guide complete! Moving on to %s.", guide.next)
        return self:Load(guide.next)
      end
      CM:Print("Guide complete: %s", guide.name)
    end
    local step = guide.steps[p.step]
    -- steps without coordinates borrow them from the quest database / learned spots
    if step and not step.x and step.quest and CM.QuestNav then
      local m, x, y, _, who = CM.QuestNav:Location(step.quest)
      if m then step.m, step.x, step.y = m, x * 100, y * 100; step.npc = step.npc or who end
    end
  end
  -- the guide window owns the arrow and shows the steps
  if CM.GuideWindow then CM.GuideWindow:Refresh() end
end

function G:Skip(delta)
  local guide = self:Current(); if not guide then return end
  local p = self:Progress()
  if delta > 0 then p.manual[p.step] = true end
  p.step = math.max(1, math.min(#guide.steps, p.step + delta))
  if delta < 0 then p.manual[p.step] = nil end
  self.arrived = nil
  self:Update()
end

function G:Reset()
  local guide = self:Current(); if not guide then return end
  WGACompanionCharDB.guide.progress[guide.name] = nil
  self:Update()
end

-- Text ---------------------------------------------------------------------------
local ICON = {
  accept = "|TInterface\\GossipFrame\\AvailableQuestIcon:14|t",
  turnin = "|TInterface\\GossipFrame\\ActiveQuestIcon:14|t",
  complete = "|TInterface\\Icons\\Ability_DualWield:14|t",
  ["goto"] = "|TInterface\\Minimap\\Tracking\\FlightMaster:14|t",
  level = "|TInterface\\Icons\\Spell_Holy_SurgeOfLight:14|t",
  collect = "|TInterface\\Icons\\INV_Misc_Bag_08:14|t",
  note = "|TInterface\\Icons\\INV_Misc_Note_01:14|t",
}
local VERB = { accept = "Accept", complete = "Complete", turnin = "Turn in", ["goto"] = "Go to", level = "Reach level", collect = "Collect", note = "" }

function G:StepTitle(step)
  local body = step.text or ""
  if step.t == "level" then body = tostring(step.level) .. (step.text and (" - " .. step.text) or "")
  elseif step.t == "collect" then
    local name = CM.GetItemInfo(step.item) or step.text or ("item " .. step.item)
    body = string.format("%s (%d/%d)", name, itemCount(step.item), step.count or 1)
  end
  local v = VERB[step.t] or ""
  return (v ~= "" and (v .. " ") or "") .. body
end

function G:StepLines(step)
  local lines = { (ICON[step.t] or "") .. " |cffffd100" .. self:StepTitle(step) .. "|r" }
  if step.npc then table.insert(lines, "   |cffbbbbbbNPC:|r " .. step.npc) end
  if step.t == "complete" and step.quest then
    local obj = self:ObjectiveText(step.quest)
    if obj then table.insert(lines, "   " .. obj:gsub("\n", "\n   ")) end
  end
  if step.x then table.insert(lines, string.format("   |cff808080%.1f, %.1f|r", step.x, step.y)) end
  if step.tip then table.insert(lines, "   |cff80c0ff" .. step.tip .. "|r") end
  return lines
end

-- The window lives in GuideWindow.lua and shows either this guide or the Smart Guide.
function G:RefreshFrame() if CM.GuideWindow then CM.GuideWindow:Refresh() end end

function G:Toggle()
  local g = WGACompanionCharDB.guide
  if g and g.mode ~= "smart" and not self:Current() then
    local s = self:Suggest()
    if s then self:Load(s) end
  end
  CM.GuideWindow:Toggle()
end

function G:PrintList()
  CM:Print("Guides (|cff00ff00/wga guide <name>|r):")
  for _, g in ipairs(self.list) do
    CM:Print("  %s  |cff808080%s, levels %s|r", g.name, g.faction or "Both", g.levels or "?")
  end
end

-- Events --------------------------------------------------------------------------
local pending
local function queue()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function() pending = false; G:Update() end)
end

function G:OnInit()
  WGACompanionCharDB.guide = WGACompanionCharDB.guide or {}
end

function G:OnLogin()
  if not self:Current() then
    local s = self:Suggest()
    if s then WGACompanionCharDB.guide.name = s end
  end
  C_Timer.After(2, function() G:Update() end)
end

CM:On("QUEST_TURNED_IN", function(_, questID) if questID then turnedIn[questID] = true end; queue() end)
CM:On("QUEST_ACCEPTED", queue)
CM:On("QUEST_LOG_UPDATE", queue)
CM:On("PLAYER_LEVEL_UP", queue)
CM:On("BAG_UPDATE_DELAYED", queue)
CM:On("ZONE_CHANGED_NEW_AREA", queue)

-- goto steps complete when the arrow reports arrival
function G:OnArrive()
  local guide = self:Current(); if not guide then return end
  local idx = self:Progress().step
  local step = guide.steps[idx]
  if step and step.t == "goto" then self.arrived = idx; queue() end
end
