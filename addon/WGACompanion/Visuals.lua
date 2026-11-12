-- WGA Companion: page art and 3D models for the hub.
-- Everything shown is the game's own art, loaded from the client at runtime (map tiles, icons,
-- creature models), so nothing is copied into the addon.
local _, CM = ...
local V = CM:NewModule("Visuals")
local T = CM.Theme

-- Lookups --------------------------------------------------------------------------------------------
local npcByName -- [lower name] = npcID, from the bundled quest database
function V:NpcID(name)
  if not name then return nil end
  if not npcByName then
    npcByName = {}
    local d = CM.Data.QDB
    for id, e in pairs(d and d.n or {}) do
      local k = e[1] and e[1]:lower()
      if k and (not npcByName[k] or id < npcByName[k]) then npcByName[k] = id end
    end
  end
  return npcByName[name:lower()]
end

local mapByName -- [lower name] = uiMapID, every map under Azeroth (zones and dungeons)
function V:MapID(name)
  if not name or not C_Map or not C_Map.GetMapChildrenInfo then return nil end
  if not mapByName then
    mapByName = {}
    for _, root in ipairs({ 947, 946 }) do
      local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
      for _, m in ipairs(ok and kids or {}) do
        local k = m.name and m.name:lower()
        -- prefer dungeon maps (type 4) over zones with the same name
        if k and (not mapByName[k] or m.mapType == 4) then mapByName[k] = m.mapID end
      end
    end
  end
  name = name:lower():gsub("^the ", "")
  return mapByName[name] or mapByName["the " .. name]
end

-- Boss strings like "Graveyard: A, B", "X & Y", "Sneed's Shredder / Sneed", "Name (rare)".
function V:Bosses(d)
  local out = {}
  for _, s in ipairs(d.bosses or {}) do
    s = s:gsub("%b()", ""):gsub("^[^:]+:%s*", "")
    for part in (s .. ","):gmatch("([^,&/]+)[,&/]") do
      local n = part:gsub("^%s+", ""):gsub("%s+$", "")
      if n ~= "" and not n:lower():find("pending") then
        out[#out + 1] = { name = n, npc = self:NpcID(n) }
      end
    end
  end
  return out
end

-- Icons ----------------------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
V.tabIcons = {
  Guides = I .. "INV_Misc_Book_09", Leveling = I .. "INV_Misc_Map_01", Dungeons = I .. "INV_Misc_Key_03",
  Professions = I .. "Trade_BlackSmithing", Crafting = I .. "Trade_Engineering", Gold = I .. "INV_Misc_Coin_01",
  Market = I .. "INV_Misc_Coin_02", Flips = I .. "INV_Misc_Bag_10", Rares = I .. "Ability_Hunter_BeastTracking",
  Settings = I .. "INV_Misc_Gear_01",
}
local PROF = {
  mining = "Trade_Mining", herbalism = "Trade_Herbalism", skinning = "INV_Misc_Pelt_Wolf_01", fishing = "Trade_Fishing",
  ["first aid"] = "Spell_Holy_SealOfSacrifice", alchemy = "Trade_Alchemy", tailoring = "Trade_Tailoring",
  blacksmithing = "Trade_BlackSmithing", engineering = "Trade_Engineering", enchanting = "Trade_Engraving",
  leatherworking = "INV_Misc_ArmorKit_17", cooking = "INV_Misc_Food_15", gold = "INV_Misc_Coin_01",
  overview = "INV_Misc_Book_11",
}
function V:Icon(tab, entry)
  local title = entry and (entry.title or entry.name)
  if tab == "Professions" and title then
    local t = title:lower()
    for k, icon in pairs(PROF) do if t:find(k, 1, true) then return I .. icon end end
  end
  if tab == "Leveling" and title then
    local t = title:lower()
    if t:find("alliance") then return I .. "INV_BannerPVP_02" end
    if t:find("horde") then return I .. "INV_BannerPVP_01" end
    if t:find("gold") then return I .. "INV_Misc_Coin_01" end
  end
  return self.tabIcons[tab] or I .. "INV_Misc_QuestionMark"
end

-- Banner: map art behind a title, with a themed wash so text stays readable --------------------------
function V:BuildBanner(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetHeight(96)
  b:SetClipsChildren(true)
  T:Skin(b, "panel", "border")
  b.art = CreateFrame("Frame", nil, b)
  b.tiles = {}
  b.wash = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.wash:SetAllPoints()
  b.wash:SetTexture("Interface\\Buttons\\WHITE8x8")
  b.iconFrame = CreateFrame("Frame", nil, b)
  b.iconFrame:SetSize(62, 62)
  b.iconFrame:SetPoint("LEFT", 16, 0)
  b.iconFrame:SetFrameLevel(b:GetFrameLevel() + 3)
  T:Skin(b.iconFrame, "bg", "accent")
  b.icon = b.iconFrame:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local textHolder = CreateFrame("Frame", nil, b)
  textHolder:SetAllPoints()
  textHolder:SetFrameLevel(b:GetFrameLevel() + 3)
  b.title = T:Text(textHolder, 20, "heading")
  b.title:SetPoint("TOPLEFT", b.iconFrame, "TOPRIGHT", 14, -6)
  b.title:SetPoint("RIGHT", b, "RIGHT", -14, 0)
  b.title:SetWordWrap(false)
  b.sub = T:Text(textHolder, 12, "text")
  b.sub:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -6)
  b.sub:SetPoint("RIGHT", b, "RIGHT", -14, 0)
  b.sub:SetWordWrap(false)
  b.line = textHolder:CreateTexture(nil, "OVERLAY")
  b.line:SetHeight(2)
  b.line:SetPoint("BOTTOMLEFT", 1, 1); b.line:SetPoint("BOTTOMRIGHT", -1, 1)
  T:Gradient(b.line)
  local function wash()
    local p = T:Get()
    local c = p.panel
    local ok = pcall(b.wash.SetGradient, b.wash, "HORIZONTAL", CreateColor(c[1], c[2], c[3], 0.92), CreateColor(c[1], c[2], c[3], 0.25))
    if not ok then b.wash:SetVertexColor(c[1], c[2], c[3], 0.6) end
  end
  wash()
  T:OnChange(wash)

  function b:SetMap(mapID)
    for _, t in ipairs(self.tiles) do t:Hide() end
    if not mapID or not C_Map.GetMapArtLayers then return end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    local L = ok and layers and layers[1]
    if not L or not L.tileWidth or L.tileWidth == 0 then return end
    local ok2, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not ok2 or not files or #files == 0 then return end
    local cols = math.ceil(L.layerWidth / L.tileWidth)
    local w = self:GetWidth()
    if w <= 0 then w = 500 end
    local scale = w / L.layerWidth
    local tw, th = L.tileWidth * scale, L.tileHeight * scale
    local fullH = L.layerHeight * scale
    -- show a band from about 35% down the map, where most zones have their middle
    local bh = self:GetHeight()
    local offset = math.max(0, math.min(fullH - bh, fullH * 0.35 - bh / 2))
    self.art:ClearAllPoints()
    self.art:SetPoint("TOPLEFT", 0, offset)
    self.art:SetSize(w, fullH)
    for i, file in ipairs(files) do
      local t = self.tiles[i]
      if not t then
        t = self.art:CreateTexture(nil, "BACKGROUND", nil, 1)
        self.tiles[i] = t
      end
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      t:SetTexture(file)
      t:SetSize(tw, th)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self.art, "TOPLEFT", col * tw, -row * th)
      t:Show()
    end
  end

  function b:Set(icon, title, sub, mapID)
    self.icon:SetTexture(icon)
    self.title:SetText(title or "")
    self.sub:SetText(T:Recolor(sub or ""))
    self:SetMap(mapID)
  end
  return b
end

-- Model viewer: drag to turn, wheel to zoom, arrows to step through a list ----------------------------
function V:BuildModelPanel(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetWidth(220)
  T:Skin(p, "panel", "border")
  p.head = T:Text(p, 11, "muted")
  p.head:SetPoint("TOPLEFT", 10, -8)
  p.model = CreateFrame("PlayerModel", nil, p)
  p.model:SetPoint("TOPLEFT", 4, -24)
  p.model:SetPoint("BOTTOMRIGHT", -4, 58)
  p.empty = T:Text(p, 11, "muted")
  p.empty:SetPoint("CENTER", p.model, "CENTER")
  p.empty:SetWidth(180)
  p.empty:SetJustifyH("CENTER")
  p.name = T:Text(p, 14, "heading")
  p.name:SetPoint("BOTTOMLEFT", 10, 34)
  p.name:SetPoint("RIGHT", -10, 0)
  p.name:SetJustifyH("CENTER")
  p.name:SetWordWrap(false)
  p.count = T:Text(p, 11, "muted")
  p.count:SetPoint("BOTTOM", 0, 12)
  local function step(d)
    if #p.items == 0 then return end
    p.index = (p.index - 1 + d) % #p.items + 1
    p:Show1()
  end
  p.prev = T:Button(p, "<", 14, function() step(-1) end)
  p.prev:SetSize(30, 22); p.prev:SetPoint("BOTTOMLEFT", 8, 8)
  p.prev.text:ClearAllPoints(); p.prev.text:SetPoint("CENTER")
  T:Skin(p.prev, "bg", "border")
  p.next = T:Button(p, ">", 14, function() step(1) end)
  p.next:SetSize(30, 22); p.next:SetPoint("BOTTOMRIGHT", -8, 8)
  p.next.text:ClearAllPoints(); p.next.text:SetPoint("CENTER")
  T:Skin(p.next, "bg", "border")

  local m = p.model
  m.facing, m.zoom = 0.4, 0
  m:EnableMouse(true)
  m:EnableMouseWheel(true)
  m:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
  m:SetScript("OnMouseUp", function(self) self.dragX = nil end)
  m:SetScript("OnUpdate", function(self)
    if not self.dragX then return end
    local x = GetCursorPosition()
    self.facing = self.facing + (x - self.dragX) * 0.02
    self.dragX = x
    self:SetFacing(self.facing)
  end)
  m:SetScript("OnMouseWheel", function(self, d)
    self.zoom = math.max(0, math.min(0.9, self.zoom + d * 0.1))
    pcall(self.SetPortraitZoom, self, self.zoom)
  end)

  p.items, p.index = {}, 1
  function p:SetItems(head, items, emptyText)
    self.head:SetText(head or "")
    self.items, self.index = items or {}, 1
    self.emptyText = emptyText
    self:Show1()
  end
  function p:Show1()
    local e = self.items[self.index]
    local multi = #self.items > 1
    self.prev:SetShown(multi); self.next:SetShown(multi)
    self.count:SetText(#self.items > 0 and string.format("%d / %d", self.index, #self.items) or "")
    if not e then
      self.model:Hide(); self.name:SetText("")
      self.empty:SetText(self.emptyText or ""); self.empty:Show()
      return
    end
    self.name:SetText(e.name)
    local ok = e.npc and pcall(self.model.SetCreature, self.model, e.npc)
    if ok then
      self.model:Show(); self.empty:Hide()
      self.model:SetFacing(self.model.facing)
      pcall(self.model.SetPortraitZoom, self.model, self.model.zoom)
    else
      self.model:Hide()
      self.empty:SetText("No model for this one yet"); self.empty:Show()
    end
  end
  return p
end
