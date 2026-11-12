-- WGA Companion: dungeon journal (the hub's Dungeons page).
-- Dungeon art, bosses, boss models, loot and boss map positions come from the game's own
-- Encounter Journal API; dungeon quests come from the bundled quest database (QuestieDB, GPL-3.0).
-- Our own design and code: nothing is taken from other journal addons.
local _, CM = ...
local J = CM:NewModule("Journal")
local T = CM.Theme
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function S() return CM.db.settings end

-- Data -------------------------------------------------------------------------------------------
local function hasEJ() return EJ_GetInstanceByIndex and EJ_SelectTier and EJ_GetNumTiers end

local function norm(name) return ((name or ""):lower():gsub("^new:%s*", ""):gsub("^the ", "")) end
local levelsByName
local function staticEntry(name)
  if not levelsByName then
    levelsByName = {}
    for _, d in ipairs(CM.Data.Dungeons or {}) do levelsByName[norm(d.name)] = d end
  end
  return levelsByName[norm(name)]
end

-- List of dungeons (or raids): { name, ejID, button, lore, mapID, levels, zone, static }
-- The journal's data can live in Blizzard's journal addon; load it once if the list is empty.
local triedLoad
local function ensureEJ()
  if not hasEJ() then return false end
  if (EJ_GetNumTiers() or 0) == 0 and not triedLoad then
    triedLoad = true
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_EncounterJournal") end
  end
  return (EJ_GetNumTiers() or 0) > 0
end
J.EnsureEJ = ensureEJ

function J:Instances(raids)
  local out, seen = {}, {}
  if ensureEJ() then
    local tiers = EJ_GetNumTiers() or 0
    for tier = 1, tiers do
      pcall(EJ_SelectTier, tier)
      for i = 1, 200 do
        local ok, id, name, _, _, button, lore, _, mapID = pcall(EJ_GetInstanceByIndex, i, raids and true or false)
        if not ok or not id then break end
        if not seen[id] then
          seen[id] = true
          local st = staticEntry(name)
          out[#out + 1] = { name = name, ejID = id, button = button, lore = lore, mapID = mapID,
            levels = st and st.levels, zone = st and st.zone, static = st, isNew = st and st.name:find("^NEW:") and true }
        end
      end
    end
  end
  -- anything from our own list the client's journal doesn't have
  if not raids then
    for _, d in ipairs(CM.Data.Dungeons or {}) do
      if not d.raid and d.bosses and not d.name:find("pending") then
        local found = false
        for _, e in ipairs(out) do if e.static == d then found = true break end end
        if not found then
          local name = d.name:gsub("^NEW:%s*", "")
          -- no journal entry: show the dungeon's own map, or failing that the zone it's in
          local mapID = CM.Visuals:MapID(name)
          if not mapID and CM.QData:Has() then mapID = CM.QData:DungeonEntrance(name) end
          out[#out + 1] = { name = name, levels = d.levels, zone = d.zone, static = d, isNew = name ~= d.name,
            mapID = mapID }
        end
      end
    end
  end
  local function lo(e) return tonumber((e.levels or ""):match("^(%d+)")) or 99 end
  table.sort(out, function(a, b) if lo(a) ~= lo(b) then return lo(a) < lo(b) end return a.name < b.name end)
  return out
end

-- Bosses: { name, encID, portrait, displayInfo, npc }
function J:Bosses(inst)
  local out = {}
  if inst.ejID and EJ_GetEncounterInfoByIndex then
    pcall(EJ_SelectInstance, inst.ejID)
    for i = 1, 40 do
      local ok, name, desc, encID = pcall(EJ_GetEncounterInfoByIndex, i, inst.ejID)
      if not ok or not name then break end
      local _, _, _, _, displayInfo, icon = pcall(EJ_GetCreatureInfo, 1, encID)
      out[#out + 1] = { name = name, desc = desc, encID = encID, portrait = icon, displayInfo = displayInfo,
        npc = CM.Visuals:NpcID(name) }
    end
  end
  if #out == 0 and inst.static then
    for _, b in ipairs(CM.Visuals:Bosses(inst.static)) do out[#out + 1] = { name = b.name, npc = b.npc } end
  end
  return out
end

-- Loot for one boss: { itemID, name, quality, icon, slot, armorType, link }
function J:Loot(boss)
  local out = {}
  if boss.encID and EJ_SelectEncounter and EJ_GetNumLoot and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
    pcall(EJ_SelectEncounter, boss.encID)
    if S().journalClassOnly and EJ_SetLootFilter then
      local classID = select(3, UnitClass("player"))
      pcall(EJ_SetLootFilter, classID, 0)
    elseif EJ_ResetLootFilter then
      pcall(EJ_ResetLootFilter)
    end
    local ok, n = pcall(EJ_GetNumLoot)
    for i = 1, (ok and n or 0) do
      local ok2, info = pcall(C_EncounterJournal.GetLootInfoByIndex, i)
      if ok2 and info and info.itemID then out[#out + 1] = info end
    end
  end
  -- loot WGA has seen this boss drop (fills in where the journal has none)
  if #out == 0 then
    for id in pairs(CM.db.global.rareLoot[boss.name] or {}) do
      local name, link, quality, _, _, _, _, _, slot, icon = CM.GetItemInfo(id)
      out[#out + 1] = { itemID = id, name = name or ("item " .. id), itemQuality = quality, icon = icon, link = link,
        slot = slot and _G[slot] or "", learned = true }
    end
  end
  return out
end

-- Boss positions on a dungeon map: { encID, x, y }
local function bossPins(mapID)
  if not (C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap and mapID) then return {} end
  local ok, list = pcall(C_EncounterJournal.GetEncountersOnMap, mapID)
  return ok and list or {}
end

-- Widgets ----------------------------------------------------------------------------------------
local function scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf.child = child
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, d)
    self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - d * 50)))
  end)
  return sf
end

local function smallButton(parent, label, w, onClick)
  local b = T:Button(parent, label, 12, onClick)
  b:SetSize(w, 24)
  b.text:ClearAllPoints(); b.text:SetPoint("CENTER")
  T:Skin(b, "panel", "border")
  return b
end

local function qualityColor(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return T:C("text")
end

-- Map art fitted into a frame, keeping its shape.
function J.DrawMap(holder, mapID) return J._drawMap(holder, mapID) end
local function drawMap(holder, mapID)
  holder.tiles = holder.tiles or {}
  for _, t in ipairs(holder.tiles) do t:Hide() end
  holder.art = holder.art or CreateFrame("Frame", nil, holder)
  if not mapID or not C_Map.GetMapArtLayers then return nil end
  local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
  local L = ok and layers and layers[1]
  local ok2, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
  if not L or not ok2 or not files or #files == 0 or (L.tileWidth or 0) == 0 then return nil end
  local W, H = holder:GetWidth(), holder:GetHeight()
  local scale = math.min(W / L.layerWidth, H / L.layerHeight)
  local w, h = L.layerWidth * scale, L.layerHeight * scale
  holder.art:ClearAllPoints()
  holder.art:SetPoint("CENTER")
  holder.art:SetSize(w, h)
  local cols = math.ceil(L.layerWidth / L.tileWidth)
  for i, file in ipairs(files) do
    local t = holder.tiles[i]
    if not t then t = holder.art:CreateTexture(nil, "ARTWORK"); holder.tiles[i] = t end
    t:SetTexture(file)
    t:SetSize(L.tileWidth * scale, L.tileHeight * scale)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", holder.art, "TOPLEFT", ((i - 1) % cols) * L.tileWidth * scale, -math.floor((i - 1) / cols) * L.tileHeight * scale)
    t:Show()
  end
  return holder.art
end

J._drawMap = drawMap
-- Page --------------------------------------------------------------------------------------------
function J:Build(body)
  if self.page then return self.page end
  local page = CreateFrame("Frame", nil, body)
  page:SetAllPoints()
  page:Hide()
  self.page = page

  -- Top bar
  local search = CreateFrame("EditBox", nil, page)
  search:SetSize(240, 26)
  search:SetPoint("TOPLEFT", 14, -12)
  search:SetAutoFocus(false)
  search:SetTextInsets(10, 10, 0, 0)
  T:Skin(search, "panel", "border")
  search:SetFontObject(ChatFontNormal)
  local ph = T:Text(search, 12, "muted")
  ph:SetPoint("LEFT", 10, 0)
  ph:SetText("Search dungeons or bosses")
  search:SetScript("OnTextChanged", function(s) ph:SetShown(s:GetText() == ""); J:FillGrid() end)
  search:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  local function color() local c = T:Get().text; search:SetTextColor(c[1], c[2], c[3]) end
  color(); T:OnChange(color)
  page.search = search

  page.back = smallButton(page, "<  All dungeons", 130, function() J:Open(nil) end)
  page.back:SetPoint("TOPLEFT", 14, -12)

  page.kind = smallButton(page, "Dungeons", 90, function()
    J.raids = not J.raids
    page.kind.text:SetText(J.raids and "Raids" or "Dungeons")
    J:FillGrid()
  end)
  page.kind:SetPoint("TOPRIGHT", -14, -12)
  page.classOnly = T:Toggle(page, "Only loot my class can use", function() return S().journalClassOnly == true end,
    function(v) S().journalClassOnly = v; if J.boss then J:ShowBoss(J.boss) end end)
  page.classOnly:SetWidth(210)
  page.classOnly:SetPoint("RIGHT", page.kind, "LEFT", -12, 0)

  -- Grid of dungeon cards
  local grid = scroll(page)
  grid:SetPoint("TOPLEFT", 12, -48)
  grid:SetPoint("BOTTOMRIGHT", -12, 12)
  grid.cards = {}
  page.grid = grid

  -- Detail view
  local detail = CreateFrame("Frame", nil, page)
  detail:SetPoint("TOPLEFT", 12, -48)
  detail:SetPoint("BOTTOMRIGHT", -12, 12)
  detail:Hide()
  page.detail = detail

  local head = CreateFrame("Frame", nil, detail)
  head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT")
  head:SetHeight(64)
  head:SetClipsChildren(true)
  T:Skin(head, "panel", "border")
  head.art = head:CreateTexture(nil, "BACKGROUND", nil, 1)
  head.art:SetAllPoints()
  head.wash = head:CreateTexture(nil, "ARTWORK")
  head.wash:SetAllPoints()
  head.wash:SetTexture(WHITE)
  local function wash()
    local c = T:Get().panel
    if not pcall(head.wash.SetGradient, head.wash, "HORIZONTAL", CreateColor(c[1], c[2], c[3], 0.95), CreateColor(c[1], c[2], c[3], 0.35)) then
      head.wash:SetVertexColor(c[1], c[2], c[3], 0.7)
    end
  end
  wash(); T:OnChange(wash)
  local holder = CreateFrame("Frame", nil, head)
  holder:SetAllPoints(); holder:SetFrameLevel(head:GetFrameLevel() + 2)
  head.title = T:Text(holder, 20, "heading")
  head.title:SetPoint("TOPLEFT", 14, -10)
  head.sub = T:Text(holder, 11, "text")
  head.sub:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -5)
  head.line = holder:CreateTexture(nil, "OVERLAY")
  head.line:SetHeight(2); head.line:SetPoint("BOTTOMLEFT", 1, 1); head.line:SetPoint("BOTTOMRIGHT", -1, 1)
  T:Gradient(head.line)
  detail.head = head

  detail.tabs = {}
  local x = -10
  for _, name in ipairs({ "Quests", "Bosses", "Map" }) do
    local b = T:Button(holder, name, 12, function() J:Tab(name) end)
    b:SetSize(82, 26)
    b.text:ClearAllPoints(); b.text:SetPoint("CENTER")
    T:Skin(b, "bg", "border")
    b:SetPoint("RIGHT", holder, "RIGHT", x, 0)
    x = x - 88
    detail.tabs[name] = b
  end
  detail.entrance = smallButton(holder, "Entrance", 82, function()
    local inst = J.inst
    local m, ex, ey = inst and CM.QData:DungeonEntrance(inst.name)
    if m and CM.Arrow then CM.Arrow:Point(m, ex, ey, inst.name .. " entrance", 600); CM:Print("Arrow points to the %s entrance.", inst.name) end
  end)
  detail.entrance:SetPoint("RIGHT", holder, "RIGHT", x, 0)

  -- Panes under the header
  local function pane()
    local p = CreateFrame("Frame", nil, detail)
    p:SetPoint("TOPLEFT", 0, -72)
    p:SetPoint("BOTTOMRIGHT")
    p:Hide()
    return p
  end

  -- Bosses pane: list on the left, model + loot on the right
  local bp = pane()
  bp.listBg = CreateFrame("Frame", nil, bp)
  bp.listBg:SetPoint("TOPLEFT"); bp.listBg:SetPoint("BOTTOMLEFT"); bp.listBg:SetWidth(230)
  T:Skin(bp.listBg, "panel", "border")
  bp.list = scroll(bp.listBg)
  bp.list:SetPoint("TOPLEFT", 4, -4); bp.list:SetPoint("BOTTOMRIGHT", -4, 4)
  bp.rows = {}
  bp.right = CreateFrame("Frame", nil, bp)
  bp.right:SetPoint("TOPLEFT", bp.listBg, "TOPRIGHT", 8, 0); bp.right:SetPoint("BOTTOMRIGHT")
  T:Skin(bp.right, "panel", "border")
  bp.modelBg = CreateFrame("Frame", nil, bp.right)
  bp.modelBg:SetPoint("TOPLEFT", 8, -8); bp.modelBg:SetSize(170, 200)
  T:Skin(bp.modelBg, "bg", "border")
  bp.model = CreateFrame("PlayerModel", nil, bp.modelBg)
  bp.model:SetPoint("TOPLEFT", 1, -1); bp.model:SetPoint("BOTTOMRIGHT", -1, 1)
  bp.model.facing = 0.4
  bp.model:EnableMouse(true)
  bp.model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
  bp.model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
  bp.model:SetScript("OnUpdate", function(self)
    if not self.dragX then return end
    local cx = GetCursorPosition()
    self.facing = self.facing + (cx - self.dragX) * 0.02
    self.dragX = cx
    self:SetFacing(self.facing)
  end)
  bp.name = T:Text(bp.right, 16, "heading")
  bp.name:SetPoint("TOPLEFT", bp.modelBg, "TOPRIGHT", 12, 0)
  bp.name:SetPoint("RIGHT", -10, 0)
  bp.desc = T:Text(bp.right, 11, "muted")
  bp.desc:SetPoint("TOPLEFT", bp.name, "BOTTOMLEFT", 0, -6)
  bp.desc:SetPoint("RIGHT", -10, 0)
  bp.desc:SetHeight(176)
  bp.desc:SetJustifyV("TOP")
  bp.lootLabel = T:Text(bp.right, 10, "muted")
  bp.lootLabel:SetPoint("TOPLEFT", bp.modelBg, "BOTTOMLEFT", 2, -10)
  bp.loot = scroll(bp.right)
  bp.loot:SetPoint("TOPLEFT", bp.modelBg, "BOTTOMLEFT", 0, -26)
  bp.loot:SetPoint("BOTTOMRIGHT", -8, 8)
  bp.lootRows = {}
  detail.Bosses = bp

  -- Map pane
  local mp = pane()
  T:Skin(mp, "panel", "border")
  mp.holder = CreateFrame("Frame", nil, mp)
  mp.holder:SetPoint("TOPLEFT", 90, -8); mp.holder:SetPoint("BOTTOMRIGHT", -8, 8)
  mp.floors = {}
  mp.pins = {}
  mp.none = T:Text(mp, 13, "muted")
  mp.none:SetPoint("CENTER")
  mp.none:SetText("No map for this one")
  detail.Map = mp

  -- Quests pane
  local qp = pane()
  qp.listBg = CreateFrame("Frame", nil, qp)
  qp.listBg:SetPoint("TOPLEFT"); qp.listBg:SetPoint("BOTTOMLEFT"); qp.listBg:SetWidth(270)
  T:Skin(qp.listBg, "panel", "border")
  qp.list = scroll(qp.listBg)
  qp.list:SetPoint("TOPLEFT", 4, -4); qp.list:SetPoint("BOTTOMRIGHT", -4, 4)
  qp.rows = {}
  qp.right = CreateFrame("Frame", nil, qp)
  qp.right:SetPoint("TOPLEFT", qp.listBg, "TOPRIGHT", 8, 0); qp.right:SetPoint("BOTTOMRIGHT")
  T:Skin(qp.right, "panel", "border")
  qp.text = scroll(qp.right)
  qp.text:SetPoint("TOPLEFT", 12, -12); qp.text:SetPoint("BOTTOMRIGHT", -12, 44)
  qp.body = T:Text(qp.text.child, 12, "text")
  qp.body:SetPoint("TOPLEFT")
  qp.body:SetJustifyV("TOP")
  qp.body:SetSpacing(4)
  qp.arrow = smallButton(qp.right, "Arrow to quest giver", 170, function() J:ArrowToQuest() end)
  qp.arrow.primary = true; T:PaintButton(qp.arrow)
  qp.arrow:SetPoint("BOTTOMLEFT", 12, 10)
  qp.share = smallButton(qp.right, "Open in quest log", 140, function()
    if J.quest and QuestMapFrame_OpenToQuestDetails and C_QuestLog.IsOnQuest(J.quest) then QuestMapFrame_OpenToQuestDetails(J.quest) end
  end)
  qp.share:SetPoint("LEFT", qp.arrow, "RIGHT", 8, 0)
  qp.none = T:Text(qp, 13, "muted")
  qp.none:SetPoint("CENTER")
  qp.none:SetText("No quests known for this dungeon yet")
  detail.Quests = qp

  CM:On("EJ_LOOT_DATA_RECIEVED", function() if J.boss and page:IsVisible() then J:ShowLoot(J.boss) end end)
  T:OnChange(function() if page:IsShown() then J:Refresh() end end)
  return page
end

-- Grid ---------------------------------------------------------------------------------------------
local CARD_W, CARD_H = 344, 112

function J:FillGrid()
  local page = self.page
  if not page or not page.grid:IsShown() then return end
  local grid = page.grid
  local q = tostring(page.search:GetText() or ""):lower()
  self.list = self:Instances(self.raids)
  local shown = {}
  for _, inst in ipairs(self.list) do
    local hit = q == "" or inst.name:lower():find(q, 1, true)
    if not hit and q ~= "" and inst.static then
      for _, b in ipairs(inst.static.bosses or {}) do if b:lower():find(q, 1, true) then hit = true break end end
    end
    if hit then shown[#shown + 1] = inst end
  end
  for _, c in ipairs(grid.cards) do c:Hide() end
  local w = grid:GetWidth()
  local cols = math.max(1, math.floor((w + 8) / (CARD_W + 8)))
  local cw = math.floor((w - (cols - 1) * 8) / cols)
  for i, inst in ipairs(shown) do
    local c = grid.cards[i]
    if not c then
      c = CreateFrame("Button", nil, grid.child)
      c.art = c:CreateTexture(nil, "BACKGROUND", nil, 2)
      c.art:SetPoint("TOPLEFT", 1, -1); c.art:SetPoint("BOTTOMRIGHT", -1, 1)
      c.mapHolder = CreateFrame("Frame", nil, c)
      c.mapHolder:SetPoint("TOPLEFT", 1, -1); c.mapHolder:SetPoint("BOTTOMRIGHT", -1, 1)
      c.mapHolder:SetClipsChildren(true)
      c.over = CreateFrame("Frame", nil, c)
      c.over:SetAllPoints()
      c.over:SetFrameLevel(c:GetFrameLevel() + 4)
      c.fade = c.over:CreateTexture(nil, "BACKGROUND")
      c.fade:SetPoint("TOPLEFT", 1, -1); c.fade:SetPoint("BOTTOMRIGHT", -1, 1)
      c.fade:SetTexture(WHITE)
      c.name = T:Text(c.over, 16, "heading")
      c.name:SetPoint("TOPLEFT", 12, -10)
      c.level = T:Text(c.over, 11, "text")
      c.level:SetPoint("BOTTOMLEFT", 12, 9)
      c.quests = T:Text(c.over, 11, "text")
      c.quests:SetPoint("TOPRIGHT", -12, -12)
      c.hl = c.over:CreateTexture(nil, "HIGHLIGHT")
      c.hl:SetAllPoints(); c.hl:SetTexture(WHITE); c.hl:SetVertexColor(1, 1, 1, 0.08)
      c:SetScript("OnClick", function(self) J:Open(self.inst) end)
      grid.cards[i] = c
    end
    c.inst = inst
    c:SetSize(cw, CARD_H)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", ((i - 1) % cols) * (cw + 8), -math.floor((i - 1) / cols) * (CARD_H + 8))
    T:Skin(c, "panel", "border")
    local hasArt = inst.button and c.art:SetTexture(inst.button) ~= false
    c.art:SetShown(hasArt and true or false)
    c.art:SetTexCoord(0, 0.68, 0, 0.75)
    if not hasArt then
      c.mapHolder:Show()
      c.mapHolder.tiles = c.mapHolder.tiles or {}
      drawMap(c.mapHolder, inst.mapID)
    else
      c.mapHolder:Hide()
    end
    if not pcall(c.fade.SetGradient, c.fade, "VERTICAL", CreateColor(0, 0, 0, 0.75), CreateColor(0, 0, 0, 0.05)) then
      c.fade:SetVertexColor(0, 0, 0, 0.35)
    end
    c.name:SetText(inst.name)
    c.name:SetTextColor(1, 0.86, 0.45)
    c.level:SetText((inst.levels and ("LEVEL " .. inst.levels) or "") .. (inst.isNew and "   ·   |cff66ddffNEW IN FOREVER|r" or ""))
    c.level:SetTextColor(0.9, 0.9, 0.9)
    local nq = #CM.QData:DungeonQuests(inst.name)
    c.quests:SetText(string.format("|TInterface\\GossipFrame\\AvailableQuestIcon:14|t %d quest%s", nq, nq == 1 and "" or "s"))
    c.quests:SetTextColor(0.9, 0.9, 0.9)
    c:Show()
  end
  grid.child:SetSize(w, math.ceil(#shown / cols) * (CARD_H + 8))
end

-- Detail -----------------------------------------------------------------------------------------
function J:Open(inst)
  local page = self.page
  self.inst, self.boss, self.quest = inst, nil, nil
  page.grid:SetShown(inst == nil)
  page.search:SetShown(inst == nil)
  page.kind:SetShown(inst == nil)
  page.back:SetShown(inst ~= nil)
  page.detail:SetShown(inst ~= nil)
  page.classOnly:SetShown(inst ~= nil)
  if not inst then C_Timer.After(0, function() J:FillGrid() end) return end
  local head = page.detail.head
  head.title:SetText(inst.name)
  local nq = #CM.QData:DungeonQuests(inst.name)
  head.sub:SetText(T:Recolor(string.format("%s%s   ·   %d quests", inst.levels and ("Level " .. inst.levels) or "",
    inst.zone and ("   ·   " .. inst.zone) or "", nq)))
  local hasArt = inst.lore and head.art:SetTexture(inst.lore) ~= false
  head.art:SetShown(hasArt and true or false)
  head.art:SetTexCoord(0, 1, 0.25, 0.6)
  page.detail.entrance:SetShown(CM.QData:DungeonEntrance(inst.name) ~= nil)
  self.bosses = self:Bosses(inst)
  self:Tab(self.tab or "Bosses")
end

function J:Tab(name)
  self.tab = name
  local d = self.page.detail
  for n, b in pairs(d.tabs) do
    b.selected = n == name
    T:PaintButton(b)
    d[n]:SetShown(n == name)
  end
  if name == "Bosses" then self:FillBosses()
  elseif name == "Map" then C_Timer.After(0, function() J:FillMap() end)
  else self:FillQuests() end
end

function J:FillBosses()
  local bp = self.page.detail.Bosses
  for _, r in ipairs(bp.rows) do r:Hide() end
  local w = 222
  for i, b in ipairs(self.bosses or {}) do
    local r = bp.rows[i]
    if not r then
      r = T:Button(bp.list.child, "", 13)
      r:SetSize(w - 6, 44)
      r.portrait = r:CreateTexture(nil, "ARTWORK")
      r.portrait:SetSize(64, 32); r.portrait:SetPoint("LEFT", 2, 0)
      r.text:ClearAllPoints(); r.text:SetPoint("LEFT", 72, 0); r.text:SetPoint("RIGHT", -6, 0)
      r.text:SetWordWrap(false)
      r.bar = r:CreateTexture(nil, "OVERLAY"); r.bar:SetTexture(WHITE)
      r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
      r:SetScript("OnClick", function(self) J:ShowBoss(self.boss) end)
      bp.rows[i] = r
    end
    r.boss = b
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 46)
    r.text:SetText(b.name)
    if b.portrait then r.portrait:SetTexture(b.portrait); r.portrait:Show() else
      r.portrait:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01"); r.portrait:SetTexCoord(0.07, 0.93, 0.3, 0.7)
    end
    r:Show()
  end
  bp.list.child:SetSize(w, #(self.bosses or {}) * 46)
  self:ShowBoss(self.boss or (self.bosses or {})[1])
end

function J:ShowBoss(b)
  local bp = self.page.detail.Bosses
  self.boss = b
  for _, r in ipairs(bp.rows) do r.selected = r.boss == b; T:PaintButton(r) end
  if not b then
    bp.name:SetText("No bosses listed"); bp.desc:SetText(""); bp.model:Hide()
    self:ShowLoot(nil)
    return
  end
  bp.name:SetText(b.name)
  bp.desc:SetText(b.desc or "")
  local ok
  if b.displayInfo then ok = pcall(bp.model.SetDisplayInfo, bp.model, b.displayInfo) end
  if not ok and b.npc then ok = pcall(bp.model.SetCreature, bp.model, b.npc) end
  bp.model:SetShown(ok and true or false)
  if ok then bp.model:SetFacing(bp.model.facing) end
  self:ShowLoot(b)
end

function J:ShowLoot(b)
  local bp = self.page.detail.Bosses
  for _, r in ipairs(bp.lootRows) do r:Hide() end
  local loot = b and self:Loot(b) or {}
  local learned = loot[1] and loot[1].learned
  bp.lootLabel:SetText(#loot == 0 and "NO LOOT LISTED YET" or (learned and "LOOT SEEN BY WGA" or "LOOT"))
  local w = bp.loot:GetWidth()
  if w <= 0 then w = 400 end
  for i, it in ipairs(loot) do
    local r = bp.lootRows[i]
    if not r then
      r = T:Button(bp.loot.child, "", 12)
      r:SetSize(w, 34)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(28, 28); r.icon:SetPoint("LEFT", 3, 0)
      r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", 38, -3); r.text:SetPoint("RIGHT", -6, 0)
      r.text:SetWordWrap(false)
      r.sub = T:Text(r, 10, "muted"); r.sub:SetPoint("BOTTOMLEFT", 38, 4)
      r:SetScript("OnClick", function(self)
        if self.item and self.item.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.item.link) end
        if self.item and self.item.link and IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then DressUpItemLink(self.item.link) end
      end)
      r:HookScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item.link then GameTooltip:SetHyperlink(self.item.link) else GameTooltip:SetItemByID(self.item.itemID) end
        GameTooltip:Show()
      end)
      r:HookScript("OnLeave", GameTooltip_Hide)
      bp.lootRows[i] = r
    end
    r.item = it
    r:SetWidth(w)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 36)
    r.icon:SetTexture(it.icon or 134400)
    r.text:SetText(it.name or "")
    r.text:SetTextColor(qualityColor(it.itemQuality))
    local parts = {}
    if it.slot and it.slot ~= "" then parts[#parts + 1] = it.slot end
    if it.armorType and it.armorType ~= "" then parts[#parts + 1] = it.armorType end
    local v = CM.PriceDB and (CM.PriceDB:Market(it.itemID) or CM.PriceDB:Vendor(it.itemID))
    if v then parts[#parts + 1] = T:Recolor(CM:Money(v, true)) end
    r.sub:SetText(table.concat(parts, "   ·   "))
    r:Show()
  end
  bp.loot.child:SetSize(w, #loot * 36)
end

function J:FillMap()
  local mp = self.page.detail.Map
  local inst = self.inst
  for _, p in ipairs(mp.pins) do p:Hide() end
  for _, f in ipairs(mp.floors) do f:Hide() end
  local mapID = inst and inst.mapID
  -- floors of the same dungeon
  local floors = {}
  local gid = mapID and C_Map.GetMapGroupID and C_Map.GetMapGroupID(mapID)
  if gid and C_Map.GetMapGroupMembersInfo then
    for _, m in ipairs(C_Map.GetMapGroupMembersInfo(gid) or {}) do floors[#floors + 1] = m end
    table.sort(floors, function(a, b) return (a.relativeHeightIndex or 0) < (b.relativeHeightIndex or 0) end)
  end
  self.floor = self.floor and self.floorInst == inst and self.floor or mapID
  self.floorInst = inst
  for i, m in ipairs(floors) do
    local b = mp.floors[i]
    if not b then
      b = smallButton(mp, "", 76, function(self) J.floor = self.mapID; J:FillMap() end)
      mp.floors[i] = b
    end
    b.mapID = m.mapID
    b.text:SetText(m.name ~= "" and m.name or ("Level " .. i))
    b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 28)
    b.selected = m.mapID == self.floor
    T:PaintButton(b)
    b:Show()
  end
  local art = drawMap(mp.holder, self.floor)
  mp.none:SetShown(art == nil)
  if not art then return end
  for i, e in ipairs(bossPins(self.floor)) do
    local p = mp.pins[i]
    if not p then
      p = CreateFrame("Button", nil, mp.holder)
      p:SetSize(40, 40)
      p:SetFrameLevel(mp.holder:GetFrameLevel() + 5)
      p.ring = p:CreateTexture(nil, "BACKGROUND"); p.ring:SetAllPoints(); p.ring:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\ring")
      p.face = p:CreateTexture(nil, "ARTWORK"); p.face:SetSize(30, 30); p.face:SetPoint("CENTER")
      p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.bossName or "Boss"); GameTooltip:AddLine("Click for loot", 1, 1, 1); GameTooltip:Show()
      end)
      p:SetScript("OnLeave", GameTooltip_Hide)
      p:SetScript("OnClick", function(self)
        for _, b in ipairs(J.bosses or {}) do if b.encID == self.encID then J.boss = b end end
        J:Tab("Bosses")
      end)
      mp.pins[i] = p
    end
    p.encID = e.encounterID
    local boss
    for _, b in ipairs(self.bosses or {}) do if b.encID == e.encounterID then boss = b end end
    p.bossName = boss and boss.name
    p.face:SetTexture(boss and boss.portrait or "Interface\\Icons\\INV_Misc_Head_Dragon_01")
    p.face:SetTexCoord(0.25, 0.75, 0, 1)
    p:ClearAllPoints()
    p:SetPoint("CENTER", art, "TOPLEFT", e.mapX * art:GetWidth(), -e.mapY * art:GetHeight())
    p:Show()
  end
end

local STATUS = {
  done = { "Done", "muted" }, active = { "You have it", "good" }, available = { "Available", "warn" },
  chain = { "Needs earlier quests", "bad" }, level = { "Level too low", "bad" },
}

function J:FillQuests()
  local qp = self.page.detail.Quests
  for _, r in ipairs(qp.rows) do r:Hide() end
  local list = CM.QData:DungeonQuests(self.inst.name)
  qp.none:SetShown(#list == 0)
  qp.listBg:SetShown(#list > 0); qp.right:SetShown(#list > 0)
  local w = 262
  for i, id in ipairs(list) do
    local r = qp.rows[i]
    if not r then
      r = T:Button(qp.list.child, "", 12)
      r:SetSize(w - 6, 40)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 6, 0)
      r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", 28, -5); r.text:SetPoint("RIGHT", -6, 0)
      r.text:SetWordWrap(false)
      r.sub = T:Text(r, 10, "muted"); r.sub:SetPoint("BOTTOMLEFT", 28, 5)
      r.bar = r:CreateTexture(nil, "OVERLAY"); r.bar:SetTexture(WHITE)
      r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
      r:SetScript("OnClick", function(self) J:ShowQuest(self.quest) end)
      qp.rows[i] = r
    end
    r.quest = id
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 42)
    r.text:SetText(CM.QData:Title(id) or ("Quest " .. id))
    local st = STATUS[CM.QData:Status(id)] or STATUS.available
    local c = T:Get()[st[2]]
    r.sub:SetText(string.format("Level %d   ·   |cff%02x%02x%02x%s|r", CM.QData:Level(id) or 0, c[1] * 255, c[2] * 255, c[3] * 255, st[1]))
    r.icon:SetTexture(CM.QData:Status(id) == "active" and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
    r.icon:SetDesaturated(CM.QData:Status(id) == "done")
    r:Show()
  end
  qp.list.child:SetSize(w, #list * 42)
  if #list > 0 then self:ShowQuest(self.quest or list[1]) end
end

local function npcWhere(ents)
  local pm = C_Map.GetBestMapForUnit("player")
  local m, x, y, who = CM.QData:Nearest(ents, pm)
  if not m then return who end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return string.format("%s, %s  (%.1f, %.1f)", who or "?", info and info.name or "?", x * 100, y * 100), m, x, y, who
end

function J:ShowQuest(id)
  local qp = self.page.detail.Quests
  self.quest = id
  for _, r in ipairs(qp.rows) do r.selected = r.quest == id; T:PaintButton(r) end
  local QD = CM.QData
  local st = STATUS[QD:Status(id)] or STATUS.available
  local lines = {
    "|cffffd100" .. (QD:Title(id) or "?") .. "|r",
    string.format("Quest level %d   ·   available from level %d   ·   %s", QD:Level(id) or 0, QD:ReqLevel(id) or 1, st[1]), "",
    "|cffffd100Objectives|r",
  }
  local objs = QD:ObjectiveNames(id)
  if #objs == 0 then lines[#lines + 1] = "   See the quest text" end
  for _, o in ipairs(objs) do lines[#lines + 1] = "   " .. o end
  local starts, sm, sx, sy, swho = npcWhere(QD:Starters(id))
  local ends = npcWhere(QD:Finishers(id) or {})
  self.questStart = sm and { sm, sx, sy, swho or "quest giver" }
  lines[#lines + 1] = ""
  lines[#lines + 1] = "|cffffd100Starts at|r"
  lines[#lines + 1] = "   " .. (starts or "unknown")
  lines[#lines + 1] = ""
  lines[#lines + 1] = "|cffffd100Turn in|r"
  lines[#lines + 1] = "   " .. (ends or "unknown")
  if QD:Status(id) == "chain" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffff6060Requires a quest chain first.|r"
    local q = QD:Quest(id)
    for _, p in ipairs((q and (q[9] or q[10])) or {}) do
      lines[#lines + 1] = "   " .. (QD:Title(p) or ("Quest " .. p)) .. (C_QuestLog.IsQuestFlaggedCompleted(p) and "  |cff40ff40done|r" or "")
    end
  end
  local w = qp.text:GetWidth()
  if w <= 0 then w = 380 end
  qp.body:SetWidth(w - 10)
  qp.body:SetText(T:Recolor(table.concat(lines, "\n")))
  qp.text.child:SetSize(w, qp.body:GetStringHeight() + 10)
  qp.arrow:SetShown(self.questStart ~= nil)
  qp.share:SetShown(C_QuestLog.IsOnQuest(id) and true or false)
end

function J:ArrowToQuest()
  local s = self.questStart
  if s and CM.Arrow then
    CM.Arrow:Point(s[1], s[2], s[3], s[4], 600)
    CM:Print("Arrow points to %s.", s[4])
  end
end

function J:Refresh()
  if not self.page then return end
  if self.inst then self:Open(self.inst) else self:Open(nil) end
end
