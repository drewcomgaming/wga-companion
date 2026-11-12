-- WGA Companion: rare tracker. Every rare's spawn spots on the world map, coloured by your progress:
--   red    = not seen yet
--   pink   = seen (or killed, but you still miss some of its loot)
--   green  = killed and you have every uncommon-or-better item it's known to drop (with a check mark)
-- Spawn data comes from QuestieDB (GPL-3.0). Drop chances are learned from kills: every time you loot
-- a rare, WGA counts the kill and what dropped. Nothing is taken from other rare addons.
local _, CM = ...
local RM = CM:NewModule("RareMap")
local T = CM.Theme
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

RM.COLORS = { unseen = { 1, 0.22, 0.22 }, seen = { 1, 0.45, 0.85 }, done = { 0.3, 1, 0.4 } }
local STATUS_TEXT = { unseen = "Not seen yet", seen = "Seen, still worth hunting", done = "Done: killed and all its loot collected" }

local function G() return CM.db.global end
local function db() return CM.Data.QDB and CM.Data.QDB.r or {} end
function RM:All() return db() end
function RM:Info(id) return db()[id] end

local function npcID(guid)
  return CM.RareButton and CM.RareButton.NpcID(guid)
end

-- Spawn points per map, unpacked once: [npcID][uiMapID] = { x1, y1, x2, y2, ... } (0-1)
local spawnCache = {}
function RM:Spawns(id)
  local s = spawnCache[id]
  if s then return s end
  s = {}
  local e = db()[id]
  for m, packed in pairs(e and e[5] or {}) do
    local list = {}
    for x, y in packed:gmatch("([%d%.]+),([%d%.]+)") do
      list[#list + 1] = tonumber(x) / 100; list[#list + 1] = tonumber(y) / 100
    end
    s[m] = list
  end
  spawnCache[id] = s
  return s
end

-- Spots merged so a rare with many nearby spawns gets one icon per area.
function RM:Clusters(id, mapID)
  local pts = self:Spawns(id)[mapID]
  if not pts then return {} end
  local out = {}
  for i = 1, #pts, 2 do
    local x, y, merged = pts[i], pts[i + 1], false
    for _, c in ipairs(out) do
      if math.abs(c[1] - x) < 0.04 and math.abs(c[2] - y) < 0.04 then
        c.n = c.n + 1
        c[1], c[2] = c[1] + (x - c[1]) / c.n, c[2] + (y - c[2]) / c.n
        merged = true
        break
      end
    end
    if not merged then out[#out + 1] = { x, y, n = 1 } end
  end
  return out
end

-- Rares on one map, sorted by level then name.
function RM:OnMap(mapID)
  local out = {}
  for id, e in pairs(db()) do
    if e[5] and e[5][mapID] then out[#out + 1] = id end
  end
  table.sort(out, function(a, b)
    local ea, eb = db()[a], db()[b]
    if (ea[2] or 0) ~= (eb[2] or 0) then return (ea[2] or 0) > (eb[2] or 0) end
    return ea[1] < eb[1]
  end)
  return out
end

-- Progress --------------------------------------------------------------------------------------------
local function state(id)
  local s = G().rareState[id]
  if not s then s = {}; G().rareState[id] = s end
  return s
end

function RM:Drops(id)
  local d = G().rareDrops[id]
  local list = {}
  if not d then return list, 0 end
  for item, n in pairs(d.items or {}) do
    local _, _, quality = CM.GetItemInfo(item)
    list[#list + 1] = { id = item, n = n, chance = d.kills > 0 and (n / d.kills * 100) or 0, quality = quality }
  end
  table.sort(list, function(a, b)
    if (a.quality or 1) >= 2 ~= ((b.quality or 1) >= 2) then return (a.quality or 1) >= 2 end
    return a.chance > b.chance
  end)
  return list, d.kills or 0
end

function RM:Have(item)
  return G().obtained[item] or (CM.GetItemCount(item, true) or 0) > 0
end

-- Uncommon-or-better items it drops that you don't have yet.
function RM:Missing(id)
  local missing, total = 0, 0
  for _, e in ipairs(self:Drops(id)) do
    if (e.quality or 0) >= 2 then
      total = total + 1
      if not self:Have(e.id) then missing = missing + 1 end
    end
  end
  return missing, total
end

function RM:Status(id)
  local s = G().rareState[id]
  if s and s.killed and self:Missing(id) == 0 then return "done" end
  if s and (s.seen or s.killed) then return "seen" end
  return "unseen"
end

function RM:MarkSeen(id)
  if not id or not db()[id] then return end
  local s = state(id)
  if not s.seen then s.seen = time(); self:Dirty() end
  s.lastSeen = time()
end

function RM:MarkKilled(id)
  if not id or not db()[id] then return end
  local s = state(id)
  s.seen = s.seen or time()
  if not s.killed then self:Dirty() end
  s.killed = time()
end

-- Seen: nameplates, target, mouseover (any rare in the database, whatever the game calls it)
local function checkUnit(unit)
  if not CM.db then return end
  local guid = CM:Safe(UnitGUID(unit))
  local id = guid and npcID(guid)
  if not id or not db()[id] then return end
  RM:MarkSeen(id)
  if CM:Safe(UnitIsDead(unit)) then RM:MarkKilled(id) end
end
CM:On("NAME_PLATE_UNIT_ADDED", function(_, unit) checkUnit(unit) end)
CM:On("PLAYER_TARGET_CHANGED", function() checkUnit("target") end)
CM:On("UPDATE_MOUSEOVER_UNIT", function() checkUnit("mouseover") end)

-- Killed + drop counting: looting a rare's corpse counts one kill and everything on it.
local counted = {} -- [guid] = true, so reopening the same corpse doesn't count twice
CM:On("LOOT_OPENED", function()
  if not CM.db or not GetLootSourceInfo then return end
  local perGuid = {}
  for slot = 1, GetNumLootItems() do
    local item = CM:ItemIDFromLink(GetLootSlotLink(slot))
    local src = { GetLootSourceInfo(slot) }
    for i = 1, #src, 2 do
      local guid = src[i]
      local id = npcID(guid)
      if id and db()[id] then
        perGuid[guid] = perGuid[guid] or { id = id, items = {} }
        if item then perGuid[guid].items[item] = true end
      end
    end
  end
  for guid, e in pairs(perGuid) do
    RM:MarkKilled(e.id)
    if not counted[guid] then
      counted[guid] = true
      local d = G().rareDrops[e.id] or { kills = 0, items = {} }
      G().rareDrops[e.id] = d
      d.kills = d.kills + 1
      for item in pairs(e.items) do d.items[item] = (d.items[item] or 0) + 1 end
    end
  end
end)
CM:On("CHAT_MSG_LOOT", function(_, msg)
  if not CM.db or type(msg) ~= "string" then return end
  if not (LOOT_ITEM_SELF and msg:find((LOOT_ITEM_SELF:gsub("%%s.*", "")), 1, true)) and not msg:find("^You ") then return end
  local id = CM:ItemIDFromLink(msg)
  if id then G().obtained[id] = true end
end)

-- World map icons ------------------------------------------------------------------------------------
local pins, dots = {}, {}

local function newPin(canvas)
  local p = CreateFrame("Button", nil, canvas)
  p.bg = p:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints()
  p.bg:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\halo")
  p.skull = p:CreateTexture(nil, "ARTWORK")
  p.skull:SetPoint("TOPLEFT", 3, -3); p.skull:SetPoint("BOTTOMRIGHT", -3, 3)
  p.skull:SetTexture(SKULL)
  p.check = p:CreateTexture(nil, "OVERLAY")
  p.check:SetTexture(CHECK)
  p.check:SetPoint("BOTTOMRIGHT", 4, -4)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnEnter", function(self) RM:Tooltip(self, self.rare) end)
  p:SetScript("OnLeave", GameTooltip_Hide)
  p:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      RM.selected = self.rare
      CM.UI:Show("Rares")
    elseif CM.Arrow then
      CM.Arrow:Point(self.m, self.x, self.y, db()[self.rare][1], 600)
    end
  end)
  pins[#pins + 1] = p
  return p
end

local function newDot(canvas)
  local d = canvas:CreateTexture(nil, "OVERLAY")
  d:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\node")
  dots[#dots + 1] = d
  return d
end

function RM:DrawMap()
  for _, p in ipairs(pins) do p:Hide() end
  for _, d in ipairs(dots) do d:Hide() end
  local wm = WorldMapFrame
  if not CM.db or CM.db.settings.rareMapPins == false or not wm or not wm:IsShown() then return end
  local mapID = wm:GetMapID()
  local canvas = wm:GetCanvas()
  if not mapID or not canvas then return end
  local w, h = canvas:GetSize()
  local cs = canvas:GetEffectiveScale()
  local unit = (CM.db.settings.pinScale or 1) * (cs > 0 and UIParent:GetEffectiveScale() / cs or 1)
  local np, nd = 0, 0
  local hideDone = CM.db.settings.rareHideDone
  for _, id in ipairs(self:OnMap(mapID)) do
    local st = self:Status(id)
    if not (hideDone and st == "done") then
      local c = self.COLORS[st]
      -- faint dots on every spawn spot: the area it wanders in
      local pts = self:Spawns(id)[mapID]
      if #pts > 2 then
        for i = 1, #pts, 2 do
          nd = nd + 1
          local d = dots[nd] or newDot(canvas)
          d:SetParent(canvas)
          d:SetSize(9 * unit, 9 * unit)
          d:SetVertexColor(c[1], c[2], c[3], 0.45)
          d:ClearAllPoints()
          d:SetPoint("CENTER", canvas, "TOPLEFT", pts[i] * w, -pts[i + 1] * h)
          d:Show()
        end
      end
      for _, cl in ipairs(self:Clusters(id, mapID)) do
        np = np + 1
        local p = pins[np] or newPin(canvas)
        p:SetParent(canvas)
        p:SetFrameLevel(canvas:GetFrameLevel() + 2050)
        p:SetSize(22 * unit, 22 * unit)
        p.bg:SetVertexColor(c[1], c[2], c[3], 0.9)
        p.skull:SetVertexColor(1, 1, 1, 1)
        p.check:SetSize(12 * unit, 12 * unit)
        p.check:SetShown(st == "done")
        p.rare, p.m, p.x, p.y = id, mapID, cl[1], cl[2]
        p:ClearAllPoints()
        p:SetPoint("CENTER", canvas, "TOPLEFT", cl[1] * w, -cl[2] * h)
        p:Show()
      end
    end
  end
end

function RM:Tooltip(owner, id)
  local e = db()[id]
  if not e then return end
  local st = self:Status(id)
  local c = self.COLORS[st]
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local lvl = e[2] == e[3] and tostring(e[2]) or string.format("%s-%s", e[2] or "?", e[3] or "?")
  GameTooltip:AddLine(string.format("%s  |cffaaaaaa(%s%s)|r", e[1], lvl, e[4] == 2 and " elite" or ""))
  GameTooltip:AddLine(STATUS_TEXT[st], c[1], c[2], c[3])
  local drops, kills = self:Drops(id)
  if kills > 0 then GameTooltip:AddLine(string.format("Looted %d time(s)", kills), 0.8, 0.8, 0.8) end
  for i = 1, math.min(#drops, 6) do
    local d = drops[i]
    local name = CM.GetItemInfo(d.id) or ("item " .. d.id)
    GameTooltip:AddDoubleLine((self:Have(d.id) and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " or "") .. name,
      string.format("%.1f%%", d.chance), 1, 1, 1, 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("Click: arrow here   Right-click: open in the hub", 0.5, 0.75, 1)
  GameTooltip:Show()
end

local dirty
function RM:Dirty()
  if dirty then return end
  dirty = true
  C_Timer.After(0.5, function()
    dirty = false
    RM:DrawMap()
    if CM.UI and CM.UI.current == "Rares" and CM.UI.frame and CM.UI.frame:IsShown() then RM:FillPage() end
  end)
end

function RM:OnInit()
  local g = G()
  g.rareState = g.rareState or {}
  g.rareDrops = g.rareDrops or {}
  g.obtained = g.obtained or {}
end

function RM:OnLogin()
  if CM.QuestNav and CM.QuestNav.DrawMap then
    hooksecurefunc(CM.QuestNav, "DrawMap", function() RM:DrawMap() end)
  end
end

-- Hub page: zone list, map and loot ---------------------------------------------------------------
local function scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf.child = child
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, d)
    self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - d * 40)))
  end)
  return sf
end

local function zoneName(m)
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  return info and info.name or ("Map " .. m)
end

function RM:Zones()
  if self.zones then return self.zones end
  local set = {}
  for _, e in pairs(db()) do for m in pairs(e[5] or {}) do set[m] = true end end
  local list = {}
  for m in pairs(set) do list[#list + 1] = m end
  table.sort(list, function(a, b) return zoneName(a) < zoneName(b) end)
  self.zones = list
  return list
end

local function playerZone()
  local m = C_Map.GetBestMapForUnit("player")
  local info = m and C_Map.GetMapInfo(m)
  while info and info.mapType and info.mapType > 3 and info.parentMapID and info.parentMapID > 0 do
    m = info.parentMapID; info = C_Map.GetMapInfo(m)
  end
  return m
end

function RM:BuildPage(body)
  if self.page then return self.page end
  local page = CreateFrame("Frame", nil, body)
  page:SetAllPoints()
  page:Hide()
  self.page = page

  local function btn(label, w, fn)
    local b = T:Button(page, label, 12, fn)
    b:SetSize(w, 24); b.text:ClearAllPoints(); b.text:SetPoint("CENTER")
    T:Skin(b, "panel", "border")
    return b
  end
  page.prev = btn("<", 26, function() RM:StepZone(-1) end)
  page.prev:SetPoint("TOPLEFT", 14, -12)
  page.zone = T:Text(page, 15, "heading")
  page.zone:SetPoint("LEFT", page.prev, "RIGHT", 10, 0)
  page.next = btn(">", 26, function() RM:StepZone(1) end)
  page.next:SetPoint("LEFT", page.prev, "RIGHT", 230, 0)
  page.here = btn("My zone", 80, function() RM.zone = playerZone(); RM.selected = nil; RM:FillPage() end)
  page.here:SetPoint("LEFT", page.next, "RIGHT", 8, 0)
  page.summary = T:Text(page, 11, "muted")
  page.summary:SetPoint("TOPRIGHT", -14, -18)

  -- left: rares in this zone
  page.listBg = CreateFrame("Frame", nil, page)
  page.listBg:SetPoint("TOPLEFT", 12, -46); page.listBg:SetPoint("BOTTOMLEFT", 12, 12); page.listBg:SetWidth(196)
  T:Skin(page.listBg, "panel", "border")
  page.list = scroll(page.listBg)
  page.list:SetPoint("TOPLEFT", 4, -4); page.list:SetPoint("BOTTOMRIGHT", -4, 4)
  page.rows = {}

  -- right: drops
  page.lootBg = CreateFrame("Frame", nil, page)
  page.lootBg:SetPoint("TOPRIGHT", -12, -46); page.lootBg:SetPoint("BOTTOMRIGHT", -12, 12); page.lootBg:SetWidth(220)
  T:Skin(page.lootBg, "panel", "border")
  page.lootHead = T:Text(page.lootBg, 10, "muted")
  page.lootHead:SetPoint("TOPLEFT", 8, -8); page.lootHead:SetPoint("RIGHT", -8, 0)
  page.loot = scroll(page.lootBg)
  page.loot:SetPoint("TOPLEFT", 4, -26); page.loot:SetPoint("BOTTOMRIGHT", -4, 4)
  page.lootRows = {}
  page.lootNone = T:Text(page.lootBg, 11, "muted")
  page.lootNone:SetPoint("TOPLEFT", 10, -30); page.lootNone:SetPoint("RIGHT", -10, 0)
  page.lootNone:SetText("No drops recorded yet.\n\nEvery time you loot a rare, WGA counts the kill and what dropped, and works out the chance of each item from that.")

  -- centre: map, then the rare
  page.center = CreateFrame("Frame", nil, page)
  page.center:SetPoint("TOPLEFT", page.listBg, "TOPRIGHT", 8, 0)
  page.center:SetPoint("BOTTOMRIGHT", page.lootBg, "BOTTOMLEFT", -8, 0)
  T:Skin(page.center, "panel", "border")
  page.title = T:Text(page.center, 17, "heading")
  page.title:SetPoint("TOPLEFT", 10, -8); page.title:SetPoint("RIGHT", -10, 0)
  page.title:SetWordWrap(false)
  page.map = CreateFrame("Frame", nil, page.center)
  page.map:SetPoint("TOPLEFT", 6, -32); page.map:SetPoint("TOPRIGHT", -6, -32)
  page.map:SetHeight(210)
  page.map:SetClipsChildren(true)
  page.mapPins = {}
  page.modelBg = CreateFrame("Frame", nil, page.center)
  page.modelBg:SetPoint("TOPLEFT", page.map, "BOTTOMLEFT", 2, -8); page.modelBg:SetPoint("BOTTOMLEFT", 8, 8)
  page.modelBg:SetWidth(120)
  T:Skin(page.modelBg, "bg", "border")
  page.model = CreateFrame("PlayerModel", nil, page.modelBg)
  page.model:SetPoint("TOPLEFT", 1, -1); page.model:SetPoint("BOTTOMRIGHT", -1, 1)
  page.info = T:Text(page.center, 12, "text")
  page.info:SetPoint("TOPLEFT", page.modelBg, "TOPRIGHT", 10, -2); page.info:SetPoint("RIGHT", -10, 0)
  page.info:SetJustifyV("TOP")
  page.info:SetSpacing(4)
  page.arrow = T:Button(page.center, "Arrow to it", 12, function()
    local id = RM.selected
    local cl = id and RM:Clusters(id, RM.zone)[1]
    if cl and CM.Arrow then CM.Arrow:Point(RM.zone, cl[1], cl[2], db()[id][1], 600) end
  end)
  page.arrow.primary = true
  page.arrow:SetSize(110, 24); page.arrow.text:ClearAllPoints(); page.arrow.text:SetPoint("CENTER")
  T:PaintButton(page.arrow)
  page.arrow:SetPoint("BOTTOMRIGHT", -10, 10)
  T:OnChange(function() if page:IsShown() then RM:FillPage() end end)
  return page
end

function RM:StepZone(d)
  local zones = self:Zones()
  if #zones == 0 then return end
  local idx = 1
  for i, m in ipairs(zones) do if m == self.zone then idx = i end end
  self.zone = zones[(idx - 1 + d) % #zones + 1]
  self.selected = nil
  self:FillPage()
end

function RM:FillPage()
  local page = self.page
  if not page then return end
  if not self.zone then
    local here = playerZone()
    self.zone = (here and #self:OnMap(here) > 0) and here or self:Zones()[1]
  end
  if self.selected and not (db()[self.selected] and db()[self.selected][5][self.zone]) then
    -- opened from a map icon on another zone
    for m in pairs(db()[self.selected] and db()[self.selected][5] or {}) do self.zone = m break end
  end
  local list = self:OnMap(self.zone or 0)
  self.selected = self.selected or list[1]
  page.zone:SetText(self.zone and zoneName(self.zone) or "")
  local done = 0
  for _, id in ipairs(list) do if self:Status(id) == "done" then done = done + 1 end end
  page.summary:SetText(string.format("%d of %d done in this zone", done, #list))

  for _, r in ipairs(page.rows) do r:Hide() end
  for i, id in ipairs(list) do
    local r = page.rows[i]
    if not r then
      r = T:Button(page.list.child, "", 12)
      r:SetSize(184, 30)
      r.skull = r:CreateTexture(nil, "ARTWORK"); r.skull:SetSize(20, 20); r.skull:SetPoint("LEFT", 6, 0)
      r.skullBg = r:CreateTexture(nil, "BORDER"); r.skullBg:SetSize(26, 26); r.skullBg:SetPoint("CENTER", r.skull)
      r.skullBg:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\halo")
      r.skull:SetTexture(SKULL)
      r.check = r:CreateTexture(nil, "OVERLAY"); r.check:SetSize(14, 14); r.check:SetPoint("RIGHT", -6, 0); r.check:SetTexture(CHECK)
      r.text:ClearAllPoints(); r.text:SetPoint("LEFT", 34, 0); r.text:SetPoint("RIGHT", -22, 0)
      r.text:SetWordWrap(false)
      r.bar = r:CreateTexture(nil, "OVERLAY"); r.bar:SetTexture(WHITE)
      r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
      r:SetScript("OnClick", function(self) RM.selected = self.rare; RM:FillPage() end)
      r:HookScript("OnEnter", function(self) RM:Tooltip(self, self.rare) end)
      r:HookScript("OnLeave", GameTooltip_Hide)
      page.rows[i] = r
    end
    local e, st = db()[id], self:Status(id)
    local c = self.COLORS[st]
    r.rare = id
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
    r.text:SetText(string.format("%s - %s", e[2] or "?", e[1]))
    r.skullBg:SetVertexColor(c[1], c[2], c[3], 0.9)
    r.check:SetShown(st == "done")
    r.selected = id == self.selected
    T:PaintButton(r)
    r:Show()
  end
  page.list.child:SetSize(184, #list * 32)
  C_Timer.After(0, function() RM:FillMapAndLoot() end)
end

function RM:FillMapAndLoot()
  local page = self.page
  local id = self.selected
  local e = id and db()[id]
  page.title:SetText(e and e[1] or "No rares known here")
  -- map
  for _, p in ipairs(page.mapPins) do p:Hide() end
  local art = CM.Journal and CM.Journal.DrawMap(page.map, self.zone)
  local n = 0
  local function pin(x, y, size, c, alpha, tex)
    n = n + 1
    local p = page.mapPins[n]
    if not p then p = page.map:CreateTexture(nil, "OVERLAY"); page.mapPins[n] = p end
    p:SetTexture(tex)
    p:SetSize(size, size)
    p:SetVertexColor(c[1], c[2], c[3], alpha)
    p:ClearAllPoints()
    p:SetPoint("CENTER", art, "TOPLEFT", x * art:GetWidth(), -y * art:GetHeight())
    p:Show()
  end
  if art then
    for _, other in ipairs(self:OnMap(self.zone)) do
      if other ~= id then
        for _, cl in ipairs(self:Clusters(other, self.zone)) do pin(cl[1], cl[2], 8, self.COLORS[self:Status(other)], 0.5, "Interface\\AddOns\\WGACompanion\\Icons\\node") end
      end
    end
    if id then
      local c = self.COLORS[self:Status(id)]
      local pts = self:Spawns(id)[self.zone] or {}
      for i = 1, #pts, 2 do pin(pts[i], pts[i + 1], 26, c, 0.35, "Interface\\AddOns\\WGACompanion\\Icons\\halo") end
      for _, cl in ipairs(self:Clusters(id, self.zone)) do
        pin(cl[1], cl[2], 22, c, 1, "Interface\\AddOns\\WGACompanion\\Icons\\halo")
        pin(cl[1], cl[2], 16, { 1, 1, 1 }, 1, SKULL)
      end
    end
  end
  -- model and info
  local ok = id and pcall(page.model.SetCreature, page.model, id)
  page.model:SetShown(ok and true or false)
  page.arrow:SetShown(id ~= nil)
  if e then
    local st = self:Status(id)
    local s = G().rareState[id] or {}
    local drops, kills = self:Drops(id)
    local missing, total = self:Missing(id)
    local c = self.COLORS[st]
    local lines = {
      string.format("Level %s%s", e[2] == e[3] and tostring(e[2]) or ((e[2] or "?") .. "-" .. (e[3] or "?")), e[4] == 2 and "  ·  elite" or ""),
      string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, STATUS_TEXT[st]),
      s.lastSeen and ("Last seen " .. CM:Age(s.lastSeen)) or "Not seen yet",
      s.killed and ("Last killed " .. CM:Age(s.killed)) or "Not killed yet",
      total > 0 and string.format("Loot collected: %d of %d", total - missing, total) or "",
    }
    page.info:SetText(T:Recolor(table.concat(lines, "\n")))
    page.lootHead:SetText(kills > 0 and string.format("DROPS  ·  from %d kill%s", kills, kills == 1 and "" or "s") or "DROPS")
    self:FillLoot(drops)
  else
    page.info:SetText("")
    page.lootHead:SetText("DROPS")
    self:FillLoot({})
  end
end

function RM:FillLoot(drops)
  local page = self.page
  for _, r in ipairs(page.lootRows) do r:Hide() end
  page.lootNone:SetShown(#drops == 0)
  for i, d in ipairs(drops) do
    local r = page.lootRows[i]
    if not r then
      r = T:Button(page.loot.child, "", 12)
      r:SetSize(208, 32)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT", 3, 0)
      r.text:ClearAllPoints(); r.text:SetPoint("LEFT", 34, 0); r.text:SetPoint("RIGHT", -58, 0)
      r.text:SetWordWrap(false)
      r.pct = T:Text(r, 11, "text"); r.pct:SetPoint("RIGHT", -6, 0)
      r.check = r:CreateTexture(nil, "OVERLAY"); r.check:SetSize(12, 12); r.check:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMLEFT", -2, -2)
      r.check:SetTexture(CHECK)
      r:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetItemByID(self.item)
        GameTooltip:AddLine(string.format("Dropped %d time(s)", self.n or 0), 0.6, 0.8, 1); GameTooltip:Show()
      end)
      r:HookScript("OnLeave", GameTooltip_Hide)
      r:SetScript("OnClick", function(self)
        local _, link = CM.GetItemInfo(self.item)
        if link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
      end)
      page.lootRows[i] = r
    end
    local name, _, quality, _, _, _, _, _, _, icon = CM.GetItemInfo(d.id)
    r.item, r.n = d.id, d.n
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
    r.icon:SetTexture(icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(d.id)) or 134400)
    r.text:SetText(name or ("item " .. d.id))
    local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if qc then r.text:SetTextColor(qc.r, qc.g, qc.b) end
    r.pct:SetText(string.format(d.chance >= 10 and "%.0f%%" or "%.1f%%", d.chance))
    r.check:SetShown(self:Have(d.id))
    r:Show()
  end
  page.loot.child:SetSize(208, #drops * 34)
end
