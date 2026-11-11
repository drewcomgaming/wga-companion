-- WGA Companion: main window
local _, CM = ...
local UI = CM:NewModule("UI")

local TABS = { "Guides", "Market", "Crafting", "Flips", "Rares", "Leveling", "Dungeons", "Professions", "Gold" }
local LIST_TABS = { Guides = true, Leveling = true, Dungeons = true, Professions = true, Gold = true }
local WIDTH, HEIGHT, LIST_W = 800, 500, 170

UI.current = "Guides"
UI.selection = {}

local function dungeonLines(d)
  local lines = { string.format("|cffffd100%s|r", d.name),
    string.format("Level %s  -  %s%s", d.levels, d.zone, d.faction and ("  (" .. d.faction .. ")") or ""), "",
    "|cffffd100Bosses|r" }
  for _, b in ipairs(d.bosses or {}) do table.insert(lines, "  - " .. b) end
  if d.tips then
    table.insert(lines, "")
    table.insert(lines, "|cffffd100Tips|r")
    for _, t in ipairs(d.tips) do table.insert(lines, "  - " .. t) end
  end
  return lines
end

local function guideLines(entry)
  local lines = { "|cffffd100" .. entry.title .. "|r", "" }
  for _, l in ipairs(entry.lines) do table.insert(lines, l) end
  return lines
end

local function guideOverview(g)
  local lines = { "|cffffd100" .. g.name .. "|r", string.format("%s  -  levels %s  -  %d steps", g.faction or "Both factions", g.levels or "?", #g.steps), "",
    "Click |cff00ff00Load guide|r to follow it (step window + arrow).", "" }
  for i, st in ipairs(g.steps) do
    if i > 80 then table.insert(lines, "..."); break end
    table.insert(lines, string.format("|cff808080%d.|r %s", i, CM.Guides:StepTitle(st)))
  end
  return lines
end

local function listSource(tab)
  if tab == "Guides" then return CM.Guides.list, "name", guideOverview end
  if tab == "Dungeons" then return CM.Data.Dungeons, "name", dungeonLines end
  if tab == "Leveling" then return CM.Data.Leveling, "title", guideLines end
  if tab == "Professions" then return CM.Data.Professions, "title", guideLines end
  if tab == "Gold" then return CM.Data.GoldTips, "title", guideLines end
end

local function marketLines(query)
  local realm = CM:Realm()
  local count = 0
  for _ in pairs(realm.prices) do count = count + 1 end
  local lines = {
    string.format("|cffffd100Market data|r  -  %s  -  %d items priced, last full scan %s", CM:RealmKey(), count, CM:Age(realm.lastScan)),
    "Open the auction house and click |cff00ff00CM Scan|r (or /wga scan). Browsing the AH also records prices.", "",
  }
  if query and query ~= "" then
    local ids = CM.PriceDB:FindByName(query)
    table.insert(lines, string.format("|cffffd100Results for '%s'|r (%d)", query, #ids))
    for i = 1, math.min(#ids, 60) do
      local id = ids[i]
      local rec = CM.PriceDB:Get(id)
      table.insert(lines, string.format("%s  min %s  market %s  vendor %s  |cff808080%d listed, %s|r",
        CM.db.global.itemNames[id] or id, CM:Money(rec.m, true), CM:Money(CM.PriceDB:Market(id), true),
        CM:Money(CM.PriceDB:Vendor(id), true), rec.q or 0, CM:Age(rec.t)))
    end
    return lines
  end
  -- Default view: most valuable items by total listed value, a quick read of where gold sits on your realm.
  local top = {}
  for id, rec in pairs(realm.prices) do
    local mv = CM.PriceDB:Market(id)
    if mv and rec.q then table.insert(top, { id = id, mv = mv, total = mv * rec.q, q = rec.q }) end
  end
  table.sort(top, function(a, b) return a.total > b.total end)
  table.insert(lines, "|cffffd100Biggest markets on your realm|r (market value x quantity listed)")
  if #top == 0 then table.insert(lines, "|cff808080No data yet.|r") end
  for i = 1, math.min(#top, 40) do
    local t = top[i]
    table.insert(lines, string.format("%2d. %s  %s each, %d listed  (~%s)", i,
      CM.db.global.itemNames[t.id] or t.id, CM:Money(t.mv, true), t.q, CM:Money(t.total, true)))
  end
  return lines
end

local function contentLines(tab)
  if tab == "Market" then return marketLines(UI.search and UI.search:GetText()) end
  if tab == "Crafting" then return CM.Crafting:Lines() end
  if tab == "Flips" then return CM.Merchant:Lines() end
  if tab == "Rares" then return CM.RareFinder:Lines() end
  local data, key, render = listSource(tab)
  local idx = UI.selection[tab] or 1
  if tab == "Guides" and (not data or #data == 0) then
    return { "|cffffd100Step-by-step guides|r", "", "No guides installed yet.", "",
      "Record your own: |cff00ff00/wga record start|r, play, then |cff00ff00/wga record load|r to follow it",
      "or |cff00ff00/wga record export|r to share it. WGA Companion also remembers every quest giver and",
      "turn-in location you visit, so the arrow can point to quests on your other characters." }
  end
  return data and data[idx] and render(data[idx]) or { "No data." }
end

local function makeScrollText(parent)
  local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  if not ok then sf = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate") end
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", 4, -4)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetSpacing(3)
  sf.text, sf.child = fs, child
  function sf:SetLines(lines)
    local w = self:GetWidth() - 12
    child:SetWidth(w)
    fs:SetWidth(w)
    fs:SetText(table.concat(lines, "\n"))
    child:SetHeight(fs:GetStringHeight() + 12)
    self:SetVerticalScroll(0)
  end
  return sf
end

function UI:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("HIGH")
  f:Hide()
  tinsert(UISpecialFrames, "WGACompanionFrame") -- close with Escape
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)
  f.title:SetText("WGA Companion  |cff808080v" .. CM.version .. "|r")
  self.frame = f

  -- Tab buttons
  self.tabs = {}
  local x = 12
  for _, name in ipairs(TABS) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(84, 22)
    b:SetPoint("TOPLEFT", x, -30)
    b:SetText(name)
    b:SetScript("OnClick", function() UI:Show(name) end)
    self.tabs[name] = b
    x = x + 86
  end

  -- Market search box
  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(220, 20)
  search:SetPoint("TOPLEFT", 20, -60)
  search:SetAutoFocus(false)
  search:SetScript("OnEnterPressed", function(s) s:ClearFocus(); UI:Refresh() end)
  search:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus(); UI:Refresh() end)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  hint:SetPoint("LEFT", search, "RIGHT", 8, 0)
  hint:SetText("Search item prices, press Enter")
  search.hint = hint
  self.search = search

  -- Left list for guide tabs
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", 12, -60)
  list:SetSize(LIST_W, HEIGHT - 72)
  list.buttons = {}
  self.list = list

  self.text = makeScrollText(f)

  local load = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  load:SetSize(110, 22)
  load:SetPoint("BOTTOMLEFT", 14, 12)
  load:SetText("Load guide")
  load:SetScript("OnClick", function()
    local g = CM.Guides.list[UI.selection.Guides or 1]
    if g then CM.Guides:Load(g.name) end
  end)
  self.loadButton = load
end

function UI:LayoutFor(tab)
  local isList = LIST_TABS[tab]
  local isMarket = tab == "Market"
  self.search:SetShown(isMarket)
  self.search.hint:SetShown(isMarket)
  self.list:SetShown(isList)
  self.loadButton:SetShown(tab == "Guides" and #CM.Guides.list > 0)
  self.text:ClearAllPoints()
  local left = isList and (LIST_W + 20) or 16
  local top = isMarket and -88 or -62
  self.text:SetPoint("TOPLEFT", left, top)
  self.text:SetPoint("BOTTOMRIGHT", -32, 12)
  for name, b in pairs(self.tabs) do
    if name == tab then b:LockHighlight() else b:UnlockHighlight() end
  end
end

function UI:FillList(tab)
  local data, key = listSource(tab)
  local buttons = self.list.buttons
  for _, b in ipairs(buttons) do b:Hide() end
  if not data then return end
  local sel = self.selection[tab] or 1
  for i, entry in ipairs(data) do
    local b = buttons[i]
    if not b then
      b = CreateFrame("Button", nil, self.list)
      b:SetSize(LIST_W, 18)
      b:SetPoint("TOPLEFT", 0, -(i - 1) * 19)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.fs:SetPoint("LEFT", 4, 0)
      b.fs:SetWidth(LIST_W - 8)
      b.fs:SetJustifyH("LEFT")
      buttons[i] = b
    end
    b.fs:SetText((i == sel and "|cffffffff> " or "|cffffd100") .. entry[key] .. "|r")
    b:SetScript("OnClick", function() UI.selection[tab] = i; UI:Refresh() end)
    b:Show()
  end
end

function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  local tab = self.current
  self:LayoutFor(tab)
  if LIST_TABS[tab] then self:FillList(tab) end
  self.text:SetLines(contentLines(tab))
end

function UI:Show(tab)
  self:Build()
  if tab then self.current = tab end
  self.frame:Show()
  -- size is only valid after the frame is shown
  C_Timer.After(0, function() UI:Refresh() end)
  self:Refresh()
end

function UI:Toggle()
  self:Build()
  if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
