-- WGA Companion: quest location harvester + guide recorder.
--  * Always on: remembers where every quest was picked up, completed and turned in
--    (account-wide), so guide steps and the arrow can find quests without bundled coords.
--  * /wga record start|stop|export: records your own route as a ready-to-use guide.
local _, CM = ...
local Rec = CM:NewModule("Recorder")
local QDB = CM:NewModule("QuestDB")
local QL = C_QuestLog

local function here()
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local x, y = p:GetXY()
  return m, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function npcName()
  local n = CM:Safe(UnitName("questnpc")) or CM:Safe(UnitName("npc"))
  return n
end

-- Harvested locations: WGACompanionDB.global.quests[questID] = { title, a = {m,x,y,npc}, c = {...}, t = {...} }
local function store(questID, kind, npc)
  local m, x, y = here()
  if not m then return end
  local q = CM.db.global.quests[questID] or {}
  q.title = q.title or QL.GetTitleForQuestID(questID)
  if not q[kind] then q[kind] = { m, x, y, npc } end
  CM.db.global.quests[questID] = q
  return m, x, y
end

function QDB:Get(questID)
  return (CM.Data.Quests and CM.Data.Quests[questID]) or (CM.db.global.quests and CM.db.global.quests[questID])
end

-- Coordinates for a guide step that has none: accept -> giver, turnin -> ender, complete -> where it was finished
function QDB:Location(step)
  local q = step.quest and self:Get(step.quest)
  if not q then return nil end
  local e = (step.t == "accept" and q.a) or (step.t == "turnin" and q.t) or (step.t == "complete" and q.c)
  if e then return e[1], e[2], e[3], e[4] end
end

function QDB:OnInit()
  CM.db.global.quests = CM.db.global.quests or {}
end

-- Recording ------------------------------------------------------------------------
local function rec() return WGACompanionCharDB.recording end

local function addStep(t, questID, npc)
  local m, x, y = store(questID, t == "accept" and "a" or (t == "turnin" and "t" or "c"), npc)
  local r = rec()
  if r and r.on then
    table.insert(r.steps, { t = t, quest = questID, text = QL.GetTitleForQuestID(questID) or ("quest " .. questID), npc = npc, m = m, x = x, y = y })
  end
end

local ready = {} -- questID -> true once objectives done (to detect the transition)

CM:On("QUEST_ACCEPTED", function(_, a, b)
  local questID = b or a -- retail passes questID; some builds pass (logIndex, questID)
  if type(questID) ~= "number" then return end
  addStep("accept", questID, npcName())
end)

CM:On("QUEST_TURNED_IN", function(_, questID)
  if questID then addStep("turnin", questID, npcName()); ready[questID] = nil end
end)

CM:On("QUEST_LOG_UPDATE", function()
  if not CM.db then return end
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    if info and not info.isHeader and info.questID then
      local done = QL.ReadyForTurnIn and QL.ReadyForTurnIn(info.questID) or QL.IsComplete(info.questID)
      if done and not ready[info.questID] then
        ready[info.questID] = true
        if CM.loggedIn then addStep("complete", info.questID) end
      elseif not done then
        ready[info.questID] = nil
      end
    end
  end
end)

CM:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, function() CM.loggedIn = true end) end)

local function exportText(r)
  local out = {}
  table.insert(out, string.format('WGACompanion.Guides:Register({ name = "%s", faction = "%s", levels = "%d-%d",',
    r.name, UnitFactionGroup("player") or "", r.startLevel or 1, UnitLevel("player")))
  table.insert(out, "  steps = {")
  for _, s in ipairs(r.steps) do
    local parts = { string.format('t = "%s"', s.t) }
    if s.quest then table.insert(parts, "quest = " .. s.quest) end
    if s.text then table.insert(parts, string.format("text = %q", s.text)) end
    if s.npc then table.insert(parts, string.format("npc = %q", s.npc)) end
    if s.level then table.insert(parts, "level = " .. s.level) end
    if s.m then table.insert(parts, string.format("m = %d, x = %.1f, y = %.1f", s.m, s.x, s.y)) end
    table.insert(out, "    { " .. table.concat(parts, ", ") .. " },")
  end
  table.insert(out, "  } })")
  return table.concat(out, "\n")
end

function Rec:ShowExport(text)
  if not self.export then
    local f = CreateFrame("Frame", "WGACompanionExport", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(600, 400); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -30); sf:SetPoint("BOTTOMRIGHT", -32, 12)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(550); eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.eb = eb
    self.export = f
  end
  self.export.eb:SetText(text)
  self.export:Show()
  self.export.eb:HighlightText()
  self.export.eb:SetFocus()
end

function Rec:Command(arg)
  arg = (arg or ""):lower()
  if arg == "start" then
    WGACompanionCharDB.recording = { on = true, steps = {}, startLevel = UnitLevel("player"),
      name = string.format("%s %d+ (recorded)", GetZoneText() or "Route", UnitLevel("player")) }
    CM:Print("Recording your route. Quest accepts, completions, turn-ins and level-ups become guide steps. /wga record stop when done.")
  elseif arg == "stop" then
    local r = rec(); if r then r.on = false end
    CM:Print("Recording stopped (%d steps). /wga record export to copy it.", r and #r.steps or 0)
  elseif arg == "export" then
    local r = rec()
    if not r or #r.steps == 0 then CM:Print("Nothing recorded yet. /wga record start"); return end
    self:ShowExport(exportText(r))
  elseif arg == "load" then
    local r = rec()
    if not r or #r.steps == 0 then CM:Print("Nothing recorded yet."); return end
    CM.Guides:Register({ name = r.name, levels = string.format("%d-%d", r.startLevel or 1, UnitLevel("player")), steps = r.steps })
    CM.Guides:Load(r.name)
  else
    local r = rec()
    CM:Print("Recorder: %s, %d steps. Usage: /wga record start | stop | export | load",
      (r and r.on) and "|cff40ff40recording|r" or "off", r and #r.steps or 0)
    local n = 0
    for _ in pairs(CM.db.global.quests) do n = n + 1 end
    CM:Print("Quest locations harvested so far: %d", n)
  end
end

CM:On("PLAYER_LEVEL_UP", function(_, level)
  local r = rec()
  if r and r.on then table.insert(r.steps, { t = "level", level = level }) end
end)
