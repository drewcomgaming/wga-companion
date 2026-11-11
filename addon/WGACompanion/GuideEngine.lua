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
  self.arrived = nil
  self:Update()
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
  if not guide then if self.frame then self.frame:Hide() end; if CM.Arrow then CM.Arrow:SetTarget(nil) end; return end
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
  -- steps without coordinates borrow them from the quest database / harvested locations
  if step and not step.x and step.quest and CM.QuestDB then
    local m, x, y, npc = CM.QuestDB:Location(step)
    if m then step.m, step.x, step.y = m, x, y; step.npc = step.npc or npc end
  end
  if CM.Arrow then
    if step and step.m and step.x then CM.Arrow:SetTarget(step.m, step.x / 100, step.y / 100, self:StepTitle(step)) else CM.Arrow:SetTarget(nil) end
  end
  self:RefreshFrame()
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

-- Viewer frame ---------------------------------------------------------------------
function G:BuildFrame()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionGuideFrame", UIParent, "BackdropTemplate")
  f:SetSize(320, 150)
  f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
  f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0, 0, 0, 0.75)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)

  f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.header:SetPoint("TOPLEFT", 8, -7); f.header:SetPoint("TOPRIGHT", -60, -7); f.header:SetJustifyH("LEFT")

  local function btn(label, x, fn, tip)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(20, 18); b:SetPoint("TOPRIGHT", x, -4); b:SetText(label); b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end)
    b:SetScript("OnLeave", GameTooltip_Hide)
  end
  btn(">", -6, function() G:Skip(1) end, "Skip this step")
  btn("<", -28, function() G:Skip(-1) end, "Previous step")
  btn("x", -50, function() f:Hide(); if CM.Arrow then CM.Arrow:SetTarget(nil) end end, "Hide (/wga guide to show)")

  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.body:SetPoint("TOPLEFT", 8, -26); f.body:SetPoint("TOPRIGHT", -8, -26)
  f.body:SetJustifyH("LEFT"); f.body:SetJustifyV("TOP"); f.body:SetSpacing(2)

  -- clicking the frame completes a manual step
  f:SetScript("OnMouseUp", function(_, button)
    local guide = G:Current(); if not guide then return end
    local step = guide.steps[G:Progress().step]
    if button == "LeftButton" and step and (step.t == "note" or step.t == "goto") then G:Skip(1) end
  end)
  self.frame = f
end

function G:RefreshFrame()
  local guide = self:Current()
  if not guide then return end
  self:BuildFrame()
  local f = self.frame
  local p = self:Progress()
  f.header:SetText(string.format("%s  |cff808080%d/%d|r", guide.name, math.min(p.step, #guide.steps), #guide.steps))
  local lines = {}
  for i = p.step, math.min(p.step + 2, #guide.steps) do
    local sl = self:StepLines(guide.steps[i])
    if i > p.step then for k, l in ipairs(sl) do sl[k] = "|cff999999" .. l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r" end; sl = { sl[1] } end
    for _, l in ipairs(sl) do table.insert(lines, l) end
  end
  if p.step > #guide.steps then lines = { "|cff40ff40Guide complete.|r Pick another with /wga guides." } end
  f.body:SetText(table.concat(lines, "\n"))
  f:SetHeight(f.body:GetStringHeight() + 36)
  if not WGACompanionCharDB.guide.hidden then f:Show() end
end

function G:Toggle()
  if not self:Current() then
    local s = self:Suggest()
    if s then self:Load(s) else CM:Print("No guide for your level/faction yet. /wga guides lists them.") end
    return
  end
  self:BuildFrame()
  local hidden = self.frame:IsShown()
  WGACompanionCharDB.guide.hidden = hidden
  if hidden then self.frame:Hide(); CM.Arrow:SetTarget(nil) else self:Update(); self.frame:Show() end
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
