-- WGA Companion: "new skills at your trainer". Each visit to your class trainer teaches WGA what they
-- sell (name, rank, level, cost, icon) and what you've already bought. On level up a small card lists
-- the spells you can now learn, what they cost in total, and an arrow to the nearest trainer.
local _, CM = ...
local Tr = CM:NewModule("Trainer")
local T = CM.Theme

local function myClass() local _, c = UnitClass("player"); return c end
local function S() return CM.db.settings end
local function store()
  local g = CM.db.global
  g.trainer = g.trainer or {}
  local c = myClass() or "?"
  g.trainer[c] = g.trainer[c] or {}
  return g.trainer[c]
end
local function charDB()
  local c = WGACompanionCharDB
  c.trainerLearned = c.trainerLearned or {}
  c.trainerSkip = c.trainerSkip or {}
  return c
end

-- Reading the trainer ---------------------------------------------------------------------------
local busy
function Tr:Learn()
  if busy or not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  if IsTradeskillTrainer and IsTradeskillTrainer() then return end
  busy = true
  -- show every service while we read, then put the trainer window's filters back
  local saved = {}
  local canFilter = GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter
  if canFilter then
    for _, t in ipairs({ "available", "unavailable", "used" }) do
      saved[t] = GetTrainerServiceTypeFilter(t) and true or false
      if not saved[t] then pcall(SetTrainerServiceTypeFilter, t, 1) end
    end
  end
  local db, learned, n = store(), charDB().trainerLearned, 0
  for i = 1, GetNumTrainerServices() or 0 do
    local name, rank, kind = GetTrainerServiceInfo(i)
    if name and kind ~= "header" then
      local key = name .. "|" .. (rank or "")
      db[key] = { name, rank or "", GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 1,
        GetTrainerServiceCost and GetTrainerServiceCost(i) or 0, GetTrainerServiceIcon and GetTrainerServiceIcon(i) }
      learned[key] = kind == "used" or nil
      n = n + 1
    end
  end
  if canFilter then
    for t, on in pairs(saved) do if not on then pcall(SetTrainerServiceTypeFilter, t, 0) end end
  end
  busy = nil
  self.lastLearn = GetTime()
  -- remember where this trainer stands, for the arrow
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if p and n > 0 then
    local x, y = p:GetXY()
    local g = CM.db.global
    g.trainerSpots = g.trainerSpots or {}
    local list = g.trainerSpots[myClass()] or {}
    g.trainerSpots[myClass()] = list
    local who = UnitName("npc") or "Trainer"
    local found
    for _, s in ipairs(list) do if s.name == who then s.m, s.x, s.y, found = m, x, y, true end end
    if not found then list[#list + 1] = { m = m, x = x, y = y, name = who } end
  end
  if self.frame and self.frame:IsShown() then self:Fill() end
end

-- What you can learn now ------------------------------------------------------------------------
local function rankNum(r) return tonumber((r or ""):match("(%d+)")) end

-- Spells grouped by name: { name, icon, cost, lo, hi (ranks), level, keys }
function Tr:Available(lvl)
  lvl = lvl or UnitLevel("player") or 1
  local c = charDB()
  local by = {}
  for key, e in pairs(store()) do
    local name, rank, level, cost, icon = e[1], e[2], e[3], e[4], e[5]
    if level <= lvl and not c.trainerLearned[key] and not c.trainerSkip[name] then
      local g = by[name] or { name = name, icon = icon, cost = 0, level = 0, keys = {} }
      g.cost = g.cost + (cost or 0)
      g.level = math.max(g.level, level)
      local r = rankNum(rank)
      if r then g.lo, g.hi = math.min(g.lo or r, r), math.max(g.hi or r, r) end
      g.keys[#g.keys + 1] = key
      by[name] = g
    end
  end
  local out = {}
  for _, g in pairs(by) do out[#out + 1] = g end
  table.sort(out, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.name < b.name end)
  return out
end

function Tr:HasData() return next(store()) ~= nil end

function Tr:Skip(name)
  charDB().trainerSkip[name] = true
  self:Fill()
end

-- Nearest trainer: one you've visited, else one from the quest database
function Tr:Nearest()
  local A = CM.Arrow
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  local pc, px, py
  if p and A and A.WorldPos then pc, px, py = A.WorldPos(m, p:GetXY()) end
  local best, bd
  local function consider(sm, x, y, name)
    local c, wx, wy
    if A and A.WorldPos then c, wx, wy = A.WorldPos(sm, x, y) end
    local d = (c and pc and c == pc) and ((wx - px) ^ 2 + (wy - py) ^ 2) or math.huge
    if not best or d < bd then best, bd = { m = sm, x = x, y = y, name = name }, d end
  end
  for _, s in ipairs((CM.db.global.trainerSpots or {})[myClass()] or {}) do consider(s.m, s.x, s.y, s.name) end
  local side = UnitFactionGroup("player") == "Horde" and "H" or "A"
  for _, t in pairs(CM.Data.QDB and CM.Data.QDB.t or {}) do
    if t[3] == myClass() and (not t[2] or t[2]:find(side, 1, true)) then
      for sm, packed in pairs(t[4] or {}) do
        local x, y = packed:match("([%d%.]+),([%d%.]+)")
        if x then consider(sm, tonumber(x) / 100, tonumber(y) / 100, t[1]) end
      end
    end
  end
  return best
end

function Tr:ArrowToTrainer()
  local t = self:Nearest()
  if not (t and CM.Arrow) then CM:Print("I don't know where a trainer for your class is yet.") return end
  local cls = UnitClass("player")
  CM.Arrow:Point(t.m, t.x, t.y, string.format("%s (%s trainer)", t.name or "Trainer", cls or ""), 900)
  CM:Print("Arrow: %s, your %s trainer.", t.name or "trainer", cls or "class")
end

-- The card --------------------------------------------------------------------------------------
local ROWS = 7
function Tr:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionTrainerCard", UIParent)
  f:SetSize(340, 120)
  f:SetPoint("TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, "WGACompanionTrainerCard")
  T:Skin(f, "bg", "border")
  local top = f:CreateTexture(nil, "ARTWORK")
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
  T:Gradient(top)
  f.title = T:Text(f, 15, "heading")
  f.title:SetPoint("TOP", 0, -12)
  f.title:SetText("New skills at your trainer")
  local close = T:Button(f, "X", 13, function() f:Hide() end)
  close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -6, -6)
  close.text:ClearAllPoints(); close.text:SetPoint("CENTER")
  f.note = T:Text(f, 11, "muted")
  f.note:SetPoint("TOPLEFT", 14, -38); f.note:SetPoint("RIGHT", -14, 0)
  f.note:SetWordWrap(true)
  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(312, 38)
    r:SetPoint("TOPLEFT", 14, -38 - (i - 1) * 40)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(32, 32); r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = T:Text(r, 13, "text")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1); r.name:SetPoint("RIGHT", -30, 0)
    r.name:SetWordWrap(false)
    r.cost = T:Text(r, 12, "text")
    r.cost:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
    r.skip = T:Button(r, "-", 14, nil)
    r.skip:SetSize(22, 22); r.skip:SetPoint("RIGHT")
    r.skip.text:ClearAllPoints(); r.skip.text:SetPoint("CENTER")
    T:Skin(r.skip, "panel", "border")
    r.skip:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine("Don't remind me about this spell"); GameTooltip:Show()
    end)
    r.skip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = r
  end
  f.more = T:Text(f, 11, "muted")
  f.total = T:Text(f, 12, "text")
  local go = T:Button(f, "Arrow to my trainer", 12, function() Tr:ArrowToTrainer() end)
  go.primary = true
  go:SetSize(150, 26)
  go.text:ClearAllPoints(); go.text:SetPoint("CENTER")
  T:PaintButton(go)
  f.go = go
  self.frame = f
end

function Tr:Fill()
  local f = self.frame
  if not f then return end
  local list = self:Available()
  for _, r in ipairs(f.rows) do r:Hide() end
  local y = -38
  if not self:HasData() then
    f.note:SetText("Visit your class trainer once and I'll remember what they teach, then tell you each level what's new and what it costs.")
    f.note:Show()
    y = y - f.note:GetStringHeight() - 10
  elseif #list == 0 then
    f.note:SetText("Nothing new to learn right now. I'll tell you when there is.")
    f.note:Show()
    y = y - f.note:GetStringHeight() - 10
  else
    f.note:Hide()
  end
  local total = 0
  for _, g in ipairs(list) do total = total + g.cost end
  for i = 1, math.min(ROWS, #list) do
    local g, r = list[i], f.rows[i]
    r.icon:SetTexture(g.icon or 134400)
    local ranks = g.lo and (g.lo == g.hi and (" rank " .. g.lo) or string.format(" ranks %d-%d", g.lo, g.hi)) or ""
    r.name:SetText(g.name .. "|cff999999" .. ranks .. "|r")
    r.cost:SetText(g.cost > 0 and CM:Money(g.cost) or "|cff808080free|r")
    r.skip:SetScript("OnClick", function() Tr:Skip(g.name) end)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 14, y)
    r:Show()
    y = y - 40
  end
  f.more:SetShown(#list > ROWS)
  if #list > ROWS then
    f.more:SetText(string.format("+%d more at the trainer", #list - ROWS))
    f.more:ClearAllPoints(); f.more:SetPoint("TOPLEFT", 14, y - 2)
    y = y - 18
  end
  local money = GetMoney and GetMoney() or 0
  f.total:SetShown(#list > 0)
  f.total:ClearAllPoints(); f.total:SetPoint("TOPLEFT", 14, y - 8)
  f.total:SetText(string.format("Total %s   ·   you have %s%s", CM:Money(total), CM:Money(money),
    money < total and "  |cffff6060(short)|r" or ""))
  if #list > 0 then y = y - 26 end
  f.go:ClearAllPoints(); f.go:SetPoint("TOPLEFT", 14, y - 8)
  f:SetHeight(-y + 46)
end

function Tr:Show()
  self:Build()
  self.frame:Show()
  self:Fill()
end

function Tr:Toggle()
  self:Build()
  if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

CM:On("TRAINER_SHOW", function() C_Timer.After(0.2, function() Tr:Learn() end) end)
CM:On("TRAINER_UPDATE", function()
  -- our own filter switching fires this too; only react to real changes (buying a spell)
  if Tr.pending or (Tr.lastLearn and GetTime() - Tr.lastLearn < 1.5) then return end
  Tr.pending = true
  C_Timer.After(0.5, function() Tr.pending = nil; Tr:Learn() end)
end)

-- Level up: show the card when something new opened up at this level
CM:On("PLAYER_LEVEL_UP", function(_, newLevel)
  if S().trainerCard == false then return end
  C_Timer.After(3, function()
    local lvl = newLevel or UnitLevel("player")
    for _, g in ipairs(Tr:Available(lvl)) do
      if g.level == lvl then Tr:Show() return end
    end
  end)
end)
