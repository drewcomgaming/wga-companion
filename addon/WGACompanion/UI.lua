-- WGA Companion: main window
local _, CM = ...
local UI = CM:NewModule("UI")

local LIST_TABS = { Guides = true, Leveling = true, Dungeons = true, Professions = true, Gold = true }
local MODEL_TABS = { Dungeons = true, Rares = true }
local PAGE = { -- banner text for tabs without a list
  Market = { "Auction prices", "Prices from your own scans and the hourly region data" },
  Crafting = { "Crafting profit", "Open a profession window to see cost, value and profit per recipe" },
  Flips = { "Vendor flips", "Items vendors sell for less than the auction house pays" },
  Rares = { "Rares & treasures", "Alerts, recent sightings and the loot WGA has seen them drop" },
}
local WIDTH, HEIGHT, SIDE_W, LIST_W = 900, 580, 168, 210

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
    "Open the auction house and click |cff00ff00WGA Scan|r (or /wga scan). Browsing the AH also records prices.", "",
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

-- Window ------------------------------------------------------------------------------------------------
local T = CM.Theme
local NAV = {
  { label = "QUESTING" }, { tab = "Guides" }, { tab = "Leveling" }, { tab = "Dungeons" },
  { label = "PROFESSIONS & GOLD" }, { tab = "Professions" }, { tab = "Crafting" }, { tab = "Gold", text = "Gold making" },
  { label = "MARKET" }, { tab = "Market", text = "Auction prices" }, { tab = "Flips", text = "Vendor flips" },
  { label = "WORLD" }, { tab = "Rares", text = "Rares & treasures" },
}

-- Scroll area driven by the mouse wheel, with a slim themed thumb.
local function makeScroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf.child = child
  local thumb = sf:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
  thumb:SetWidth(3)
  sf.thumb = thumb
  function sf:UpdateThumb()
    local range = self:GetVerticalScrollRange()
    local h = self:GetHeight()
    if range <= 0 or h <= 0 then thumb:Hide() return end
    local p = T:Get()
    thumb:SetVertexColor(p.accent[1], p.accent[2], p.accent[3], 0.7)
    local th = math.max(20, h * h / (h + range))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(h - th) * (self:GetVerticalScroll() / range))
    thumb:Show()
  end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local v = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40))
    self:SetVerticalScroll(v)
    self:UpdateThumb()
  end)
  sf:SetScript("OnScrollRangeChanged", function(self) self:UpdateThumb() end)
  return sf
end

local function makeScrollText(parent)
  local sf = makeScroll(parent)
  local fs = T:Text(sf.child, 13, "text")
  fs:SetPoint("TOPLEFT", 6, -4)
  fs:SetJustifyV("TOP")
  fs:SetSpacing(4)
  sf.text = fs
  function sf:SetLines(lines)
    local w = self:GetWidth() - 18
    self.child:SetWidth(w)
    fs:SetWidth(w)
    fs:SetText(T:Recolor(table.concat(lines, "\n")))
    self.child:SetHeight(fs:GetStringHeight() + 16)
    self:SetVerticalScroll(0)
    self:UpdateThumb()
  end
  return sf
end

function UI:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionFrame", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("HIGH")
  f:SetScale(CM.db.settings.uiScale or 1)
  f:Hide()
  tinsert(UISpecialFrames, "WGACompanionFrame") -- close with Escape
  T:Skin(f, "bg", "border")
  self.frame = f

  -- Header: logo, title, theme switch, close
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
  header:SetHeight(54)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() f:StartMoving() end)
  header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  T:Skin(header, "sidebar")
  local logo = header:CreateTexture(nil, "ARTWORK")
  logo:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\logo")
  logo:SetSize(38, 38)
  logo:SetPoint("LEFT", 12, 0)
  local title = T:Text(header, 17, "heading")
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -3)
  title:SetText("WGA Companion")
  local sub = T:Text(header, 11, "muted")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText("Whirlwind Gaming Academy   v" .. CM.version)
  local line = header:CreateTexture(nil, "ARTWORK")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(2)
  T:Gradient(line)

  local close = T:Button(header, "X", 14, function() f:Hide() end)
  close:SetSize(34, 34)
  close:SetPoint("RIGHT", -8, 0)
  close.text:ClearAllPoints(); close.text:SetPoint("CENTER")
  local theme = T:Button(header, "", 11, function() T:Cycle() end)
  theme:SetSize(170, 26)
  theme:SetPoint("RIGHT", close, "LEFT", -8, 0)
  theme.textKey = "muted"
  T:Skin(theme, "panel", "border")
  local function themeLabel() theme.text:SetText("Theme:  " .. T:Get().name) end
  themeLabel()
  T:OnChange(themeLabel)

  -- Sidebar navigation
  local side = CreateFrame("Frame", nil, f)
  side:SetPoint("TOPLEFT", 0, -54)
  side:SetPoint("BOTTOMLEFT")
  side:SetWidth(SIDE_W)
  T:Skin(side, "sidebar")
  self.nav = {}
  local y = -10
  for _, item in ipairs(NAV) do
    if item.label then
      local fs = T:Text(side, 10, "muted")
      fs:SetPoint("TOPLEFT", 14, y - 8)
      fs:SetText(item.label)
      y = y - 24
    else
      local b = T:Button(side, item.text or item.tab, 13, function() UI:Show(item.tab) end)
      b:SetPoint("TOPLEFT", 0, y)
      b:SetSize(SIDE_W, 26)
      b.text:SetPoint("LEFT", 18, 0)
      b.bar = b:CreateTexture(nil, "OVERLAY")
      b.bar:SetTexture("Interface\\Buttons\\WHITE8x8")
      b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
      b.bar:SetWidth(3)
      self.nav[item.tab] = b
      y = y - 27
    end
  end
  local settings = T:Button(side, "Settings", 13, function() UI:Show("Settings") end)
  settings:SetPoint("BOTTOMLEFT", 0, 10)
  settings:SetSize(SIDE_W, 28)
  settings.text:SetPoint("LEFT", 18, 0)
  settings.bar = settings:CreateTexture(nil, "OVERLAY")
  settings.bar:SetTexture("Interface\\Buttons\\WHITE8x8")
  settings.bar:SetPoint("TOPLEFT"); settings.bar:SetPoint("BOTTOMLEFT")
  settings.bar:SetWidth(3)
  self.nav.Settings = settings

  -- Content area
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", SIDE_W, -54)
  body:SetPoint("BOTTOMRIGHT")
  self.body = body

  -- Market search box
  local search = CreateFrame("EditBox", nil, body)
  search:SetSize(300, 26)
  search:SetPoint("TOPLEFT", 16, -14)
  search:SetAutoFocus(false)
  search:SetTextInsets(10, 10, 0, 0)
  T:Skin(search, "panel", "border")
  local sfs = T:Text(search, 13, "text")
  search:SetFontObject(GameFontHighlight)
  search:SetFont(sfs:GetFont())
  local ph = T:Text(search, 12, "muted")
  ph:SetPoint("LEFT", 10, 0)
  ph:SetText("Search item prices, press Enter")
  search:SetScript("OnTextChanged", function(s) ph:SetShown(s:GetText() == "") end)
  search:SetScript("OnEnterPressed", function(s) s:ClearFocus(); UI:Refresh() end)
  search:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus(); UI:Refresh() end)
  self.search = search
  local function searchColor() local c = T:Get().text; search:SetTextColor(c[1], c[2], c[3]) end
  searchColor()
  T:OnChange(searchColor)

  -- Left list for guide-style tabs
  local listPanel = CreateFrame("Frame", nil, body)
  listPanel:SetPoint("TOPLEFT", 12, -12)
  listPanel:SetPoint("BOTTOMLEFT", 12, 52)
  listPanel:SetWidth(LIST_W)
  T:Skin(listPanel, "panel", "border")
  local list = makeScroll(listPanel)
  list:SetPoint("TOPLEFT", 4, -4)
  list:SetPoint("BOTTOMRIGHT", -4, 4)
  list.child:SetWidth(LIST_W - 8)
  list.buttons = {}
  list.panel = listPanel
  self.list = list

  self.text = makeScrollText(body)
  self.banner = CM.Visuals:BuildBanner(body)
  self.modelPanel = CM.Visuals:BuildModelPanel(body)

  local load = T:Button(body, "Load this guide", 13, function()
    local g = CM.Guides.list[UI.selection.Guides or 1]
    if g then CM.Guides:Load(g.name) end
  end)
  load.primary = true
  load:SetSize(LIST_W, 30)
  load:SetPoint("BOTTOMLEFT", 12, 12)
  load.text:ClearAllPoints(); load.text:SetPoint("CENTER")
  T:PaintButton(load)
  self.loadButton = load

  self.settingsPage = self:BuildSettings(body)
  T:OnChange(function() if f:IsShown() then UI:Refresh() end end)
end

function UI:LayoutFor(tab)
  local isList = LIST_TABS[tab]
  local isMarket = tab == "Market"
  local isSettings = tab == "Settings"
  self.search:SetShown(isMarket)
  self.list.panel:SetShown(isList)
  self.loadButton:SetShown(tab == "Guides" and #CM.Guides.list > 0)
  self.settingsPage:SetShown(isSettings)
  self.text:SetShown(not isSettings)
  local left = isList and (LIST_W + 24) or 12
  local top = isMarket and -48 or -12
  self.banner:SetShown(not isSettings)
  self.banner:ClearAllPoints()
  self.banner:SetPoint("TOPLEFT", left, top)
  self.banner:SetPoint("TOPRIGHT", -12, top)
  local hasModel = MODEL_TABS[tab] and true or false
  self.modelPanel:SetShown(hasModel)
  self.modelPanel:ClearAllPoints()
  self.modelPanel:SetPoint("TOPRIGHT", self.banner, "BOTTOMRIGHT", 0, -8)
  self.modelPanel:SetPoint("BOTTOMRIGHT", -12, 12)
  self.text:ClearAllPoints()
  self.text:SetPoint("TOPLEFT", self.banner, "BOTTOMLEFT", 6, -10)
  self.text:SetPoint("BOTTOMRIGHT", hasModel and (-12 - 220 - 8) or -12, 12)
  for name, b in pairs(self.nav) do
    b.selected = name == tab
    T:PaintButton(b)
  end
end

function UI:FillList(tab)
  local data, key = listSource(tab)
  local buttons = self.list.buttons
  for _, b in ipairs(buttons) do b:Hide() end
  if not data then return end
  local sel = self.selection[tab] or 1
  local w = LIST_W - 8
  for i, entry in ipairs(data) do
    local b = buttons[i]
    if not b then
      b = T:Button(self.list.child, "", 12)
      b:SetSize(w - 6, 22)
      b:SetPoint("TOPLEFT", 0, -(i - 1) * 23)
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetSize(16, 16)
      b.icon:SetPoint("LEFT", 6, 0)
      b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      b.text:SetPoint("LEFT", 28, 0)
      b.text:SetWidth(w - 40)
      b.text:SetWordWrap(false)
      buttons[i] = b
    end
    b.text:SetText(entry[key])
    b.icon:SetTexture(CM.Visuals:Icon(tab, entry))
    b.selected = i == sel
    T:PaintButton(b)
    b:SetScript("OnClick", function() UI.selection[tab] = i; UI:Refresh() end)
    b:Show()
  end
  self.list.child:SetHeight(math.max(10, #data * 23))
  self.list:UpdateThumb()
end

-- Settings page --------------------------------------------------------------------------------------------
local function setting(key, onChange)
  return function() return CM.db.settings[key] ~= false end,
    function(v) CM.db.settings[key] = v; if onChange then onChange(v) end end
end

function UI:BuildSettings(body)
  local page = CreateFrame("Frame", nil, body)
  page:SetPoint("TOPLEFT", 18, -14)
  page:SetPoint("BOTTOMRIGHT", -18, 14)
  page:Hide()

  local function heading(text, x, y)
    local fs = T:Text(page, 14, "heading")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
  end

  -- Appearance: theme cards
  heading("Appearance", 0, 0)
  local cards = {}
  for i, key in ipairs(T.order) do
    local pal = T.palettes[key]
    local c = CreateFrame("Button", nil, page)
    c:SetSize(158, 64)
    c:SetPoint("TOPLEFT", (i - 1) * 168, -26)
    c.swatch = c:CreateTexture(nil, "ARTWORK")
    c.swatch:SetPoint("TOPLEFT", 6, -6); c.swatch:SetPoint("BOTTOMRIGHT", -6, 24)
    c.swatch:SetColorTexture(pal.bg[1], pal.bg[2], pal.bg[3], 1)
    c.a1 = c:CreateTexture(nil, "OVERLAY")
    c.a1:SetSize(40, 6); c.a1:SetPoint("TOPLEFT", c.swatch, "TOPLEFT", 8, -8)
    c.a1:SetColorTexture(pal.accent[1], pal.accent[2], pal.accent[3], 1)
    c.t1 = c:CreateTexture(nil, "OVERLAY")
    c.t1:SetSize(90, 4); c.t1:SetPoint("TOPLEFT", c.a1, "BOTTOMLEFT", 0, -6)
    c.t1:SetColorTexture(pal.text[1], pal.text[2], pal.text[3], 1)
    c.t2 = c:CreateTexture(nil, "OVERLAY")
    c.t2:SetSize(60, 4); c.t2:SetPoint("TOPLEFT", c.t1, "BOTTOMLEFT", 0, -4)
    c.t2:SetColorTexture(pal.muted[1], pal.muted[2], pal.muted[3], 1)
    c.label = T:Text(c, 11, "text")
    c.label:SetPoint("BOTTOM", 0, 6)
    c.label:SetText(pal.name)
    c:SetScript("OnClick", function() T:Set(key) end)
    c.key = key
    cards[i] = c
  end
  local function paintCards()
    for _, c in ipairs(cards) do T:Skin(c, "panel", c.key == T:Key() and "accent" or "border") end
  end
  paintCards()
  T:OnChange(paintCards)

  -- Size steppers
  local function stepper(label, key, min, max, step, x, y, apply)
    local fs = T:Text(page, 12, "text")
    fs:SetPoint("TOPLEFT", x, y)
    local function show() fs:SetText(string.format("%s:  %d%%", label, math.floor((CM.db.settings[key] or 1) * 100 + 0.5))) end
    local minus = T:Button(page, "-", 14, function()
      CM.db.settings[key] = math.max(min, (CM.db.settings[key] or 1) - step); show(); apply()
    end)
    minus:SetSize(26, 22); minus:SetPoint("LEFT", fs, "LEFT", 170, 0)
    minus.text:ClearAllPoints(); minus.text:SetPoint("CENTER")
    T:Skin(minus, "panel", "border")
    local plus = T:Button(page, "+", 14, function()
      CM.db.settings[key] = math.min(max, (CM.db.settings[key] or 1) + step); show(); apply()
    end)
    plus:SetSize(26, 22); plus:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    plus.text:ClearAllPoints(); plus.text:SetPoint("CENTER")
    T:Skin(plus, "panel", "border")
    show()
  end
  stepper("Window size", "uiScale", 0.7, 1.5, 0.05, 0, -104, function() UI.frame:SetScale(CM.db.settings.uiScale) end)
  stepper("Text size", "fontScale", 0.8, 1.5, 0.05, 340, -104, function() T:Restyle() end)
  stepper("Map icon size", "pinScale", 0.5, 3, 0.1, 0, -134, function() CM.QuestNav:DrawMap() end)
  stepper("Tracker size", "trackerScale", 0.6, 1.6, 0.05, 340, -134, function() if CM.Tracker then CM.Tracker:ApplyScale() end end)

  -- Feature switches: every module can be turned off here
  local cols = {
    { "Quest helper", {
      { "Quest arrow", "questArrow", function() CM.QuestNav:UpdateArrow() end },
      { "Quest icons on world map", "questPins", function() CM.QuestNav:DrawMap() end },
      { "Quest icons on minimap", "questMinimap", function() CM.QuestNav:CollectMinimap() end },
      { "Quests you can pick up", "questAvailable", function() CM.QuestNav:DrawMap(); CM.QuestNav:CollectMinimap() end },
      { "Mark mobs you still need", "questPlates" },
      { "WGA quest tracker", "tracker", function() if CM.Tracker then CM.Tracker:Update() end end },
      { "Hide Blizzard's tracker", "hideBlizzTracker", function() if CM.Tracker then CM.Tracker:ApplyBlizzard() end end },
      { "Guide window", "guideWindow", function(v) if v then CM.GuideWindow:Show() else CM.GuideWindow:Hide() end end },
      { "Guide suggests new quests", "smartAccept", function() CM.GuideWindow:Refresh() end },
    } },
    { "Economy", {
      { "Prices in tooltips", "tooltip" },
      { "Auto-sell grey items", "autoSellJunk" },
      { "Bags-full loot swap", "lootSwap" },
      { "AH shopping lists", "shopping", function(v) if CM.Shopping.frame then CM.Shopping.frame:SetShown(v) end end },
      { "Minimap button", "minimapButton", function(v) CM.MinimapButton:SetShown(v) end },
    } },
    { "Rares & treasures", {
      { "Rare alerts", "rareAlerts" },
      { "Alert card with Target", "rareButton", function(v) if not v and CM.RareButton then CM.RareButton:Hide() end end },
      { "Treasure alerts", "treasureAlerts" },
      { "Alert sound", "rareSound" },
      { "Arrow to rares", "rareArrow" },
    } },
  }
  for ci, col in ipairs(cols) do
    local x = (ci - 1) * 232
    heading(col[1], x, -172)
    for ri, row in ipairs(col[2]) do
      local get, set = setting(row[2], row[3])
      local tg = T:Toggle(page, row[1], get, set)
      tg:SetPoint("TOPLEFT", x, -196 - (ri - 1) * 28)
      tg:SetWidth(224)
    end
  end
  local foot = T:Text(page, 11, "muted")
  foot:SetPoint("BOTTOMLEFT", 0, 0)
  foot:SetText("Tip: right-click the minimap button for quick toggles. /wga keep <item> protects an item. Quest data from QuestieDB (GPL-3.0).")
  return page
end

function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  local tab = self.current
  self:LayoutFor(tab)
  if tab == "Settings" then return end
  if LIST_TABS[tab] then self:FillList(tab) end
  self:FillVisuals(tab)
  self.text:SetLines(contentLines(tab))
end

-- Banner art and the 3D model panel for the current page.
local function playerZoneMap()
  local m = C_Map.GetBestMapForUnit("player")
  local info = m and C_Map.GetMapInfo(m)
  -- climb out of sub-zones and buildings to the zone map, which has the nicest art
  while info and info.mapType and info.mapType > 3 and info.parentMapID and info.parentMapID > 0 do
    m = info.parentMapID
    info = C_Map.GetMapInfo(m)
  end
  return m
end

function UI:FillVisuals(tab)
  local V = CM.Visuals
  local data, key = listSource(tab)
  local entry = data and data[UI.selection[tab] or 1]
  local icon = V:Icon(tab, entry)
  if tab == "Dungeons" and entry then
    local zone = entry.zone and entry.zone:gsub("%s*%b()", "")
    local map = V:MapID(entry.name) or V:MapID(zone)
    self.banner:Set(icon, entry.name, string.format("Level %s   ·   %s%s", entry.levels or "?", entry.zone or "",
      entry.faction and ("   ·   " .. entry.faction) or ""), map)
    local bosses = V:Bosses(entry)
    self.modelPanel:SetItems("BOSSES", bosses, "No bosses listed yet")
  elseif entry then
    local title = entry[key]
    local sub = tab == "Guides" and string.format("%s   ·   levels %s   ·   %d steps", entry.faction or "Both factions", entry.levels or "?", #(entry.steps or {}))
      or (tab == "Leveling" and "Leveling guide") or (tab == "Professions" and "Profession guide") or "Gold making"
    self.banner:Set(icon, title, sub, playerZoneMap())
  else
    local page = PAGE[tab] or { tab, "" }
    self.banner:Set(icon, page[1], page[2], playerZoneMap())
  end
  if tab == "Rares" then
    local items = {}
    for _, e in ipairs(CM.RareFinder.log) do
      if e.npc then items[#items + 1] = { name = e.name, npc = e.npc } end
    end
    self.modelPanel:SetItems("RECENT RARES", items, "Rares you spot this session show up here")
  end
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
