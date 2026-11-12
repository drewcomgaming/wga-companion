-- WGA Companion: rare alert card. Shows the rare's 3D model, where it is, the loot WGA players have
-- seen it drop, and a Target button. Our own take on the idea; no code or data from other addons.
-- The Target button is a secure button, so it can only appear or change outside combat.
local _, CM = ...
local RB = CM:NewModule("RareButton")
local T = CM.Theme

local function S() return CM.db.settings end

local function npcIDFromGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
RB.NpcID = npcIDFromGUID

-- Loot learning: anything looted from a rare we alerted on is remembered by rare name.
local alerted = {} -- [guid] = name
function RB:Remember(guid, name) if guid then alerted[guid] = name end end

CM:On("LOOT_OPENED", function()
  if not GetNumLootItems or not GetLootSourceInfo then return end
  local store = CM.db.global.rareLoot
  for slot = 1, GetNumLootItems() do
    local id = CM:ItemIDFromLink(GetLootSlotLink(slot))
    if id then
      local src = { GetLootSourceInfo(slot) }
      for i = 1, #src, 2 do
        local name = alerted[src[i]]
        if name then
          store[name] = store[name] or {}
          store[name][id] = (store[name][id] or 0) + 1
        end
      end
    end
  end
end)

function RB:Loot(name)
  local list = {}
  for id, n in pairs(CM.db.global.rareLoot[name] or {}) do list[#list + 1] = { id = id, n = n } end
  table.sort(list, function(a, b)
    local va, vb = CM.PriceDB:NetAH(a.id) or CM.PriceDB:Vendor(a.id) or 0, CM.PriceDB:NetAH(b.id) or CM.PriceDB:Vendor(b.id) or 0
    if va ~= vb then return va > vb end
    return a.n > b.n
  end)
  return list
end

-- Card -----------------------------------------------------------------------------------------------
local LOOT_SLOTS = 6

function RB:Build()
  if self.card then return end
  local c = CreateFrame("Frame", "WGACompanionRareCard", UIParent)
  c:SetSize(300, 104)
  c:SetFrameStrata("HIGH")
  c:SetClampedToScreen(true)
  c:SetMovable(true)
  c:EnableMouse(true)
  c:RegisterForDrag("LeftButton")
  c:SetScript("OnDragStart", function(f) f.dragged = true; f:StartMoving() end)
  c:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint()
    S().rareCardPos = { point, x, y }
  end)
  T:Skin(c, "panel", "accent")

  c.stripe = c:CreateTexture(nil, "ARTWORK")
  c.stripe:SetHeight(3)
  c.stripe:SetPoint("TOPLEFT", 1, -1); c.stripe:SetPoint("TOPRIGHT", -1, -1)
  T:Gradient(c.stripe)

  c.modelBg = CreateFrame("Frame", nil, c)
  c.modelBg:SetSize(78, 78)
  c.modelBg:SetPoint("TOPLEFT", 8, -12)
  T:Skin(c.modelBg, "bg", "border")
  c.model = CreateFrame("PlayerModel", nil, c.modelBg)
  c.model:SetPoint("TOPLEFT", 1, -1); c.model:SetPoint("BOTTOMRIGHT", -1, 1)
  c.icon = c.modelBg:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(48, 48); c.icon:SetPoint("CENTER")

  c.tag = T:Text(c, 11, "warn")
  c.tag:SetPoint("TOPLEFT", c.modelBg, "TOPRIGHT", 10, 0)
  c.name = T:Text(c, 15, "heading")
  c.name:SetPoint("TOPLEFT", c.tag, "BOTTOMLEFT", 0, -2)
  c.name:SetPoint("RIGHT", c, "RIGHT", -26, 0)
  c.name:SetWordWrap(false)
  c.where = T:Text(c, 11, "muted")
  c.where:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
  c.where:SetPoint("RIGHT", c, "RIGHT", -10, 0)
  c.where:SetWordWrap(false)

  c.loot = {}
  for i = 1, LOOT_SLOTS do
    local b = CreateFrame("Button", nil, c)
    b:SetSize(20, 20)
    b:SetPoint("BOTTOMLEFT", c.modelBg, "BOTTOMRIGHT", 10 + (i - 1) * 23, 0)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetItemByID(self.itemID)
      GameTooltip:AddLine(string.format("Seen dropping %d time(s) by WGA", self.n or 0), 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    c.loot[i] = b
  end
  c.noLoot = T:Text(c, 10, "muted")
  c.noLoot:SetPoint("BOTTOMLEFT", c.modelBg, "BOTTOMRIGHT", 10, 4)
  c.noLoot:SetText("Loot shows here once someone loots it")

  c.close = T:Button(c, "x", 13, function() RB:Hide() end)
  c.close:SetSize(20, 20)
  c.close:SetPoint("TOPRIGHT", -3, -5)
  c.close.text:ClearAllPoints(); c.close.text:SetPoint("CENTER")

  -- Non-secure clicks on the card: right-click dismiss, shift-right-click ignore forever, left-click arrow.
  c:SetScript("OnMouseUp", function(_, button)
    if c.dragged then c.dragged = false return end
    if button == "RightButton" then
      if IsShiftKeyDown() and c.rareName then
        S().rareIgnore[c.rareName:lower()] = true
        CM:Print("Ignoring %s. |cff00ff00/wga rares unignore %s|r to undo.", c.rareName, c.rareName)
      end
      RB:Hide()
    elseif button == "LeftButton" and c.mapID and c.x and CM.Arrow then
      CM.Arrow:Point(c.mapID, c.x, c.y, c.rareName, 90)
    end
  end)
  c:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(self.rareName or "Rare")
    GameTooltip:AddLine("Target button: target it (outside combat)", 1, 1, 1)
    GameTooltip:AddLine("Click: point the arrow at it", 1, 1, 1)
    GameTooltip:AddLine("Right-click: dismiss", 1, 1, 1)
    GameTooltip:AddLine("Shift + right-click: never alert for this one", 1, 1, 1)
    GameTooltip:AddLine("Drag: move", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", GameTooltip_Hide)
  c:Hide()
  self.card = c

  -- Secure Target button, its own top-level frame anchored to the card.
  local t = CreateFrame("Button", "WGACompanionRareTarget", UIParent, "SecureActionButtonTemplate")
  t:SetSize(70, 20)
  t:SetFrameStrata("DIALOG")
  t:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 8)
  t:RegisterForClicks("AnyUp", "AnyDown")
  t:SetAttribute("type1", "macro")
  t.bg = t:CreateTexture(nil, "BACKGROUND")
  t.bg:SetAllPoints()
  t.label = T:Text(t, 12, "bg")
  t.label:SetPoint("CENTER")
  t.label:SetText("Target")
  local function paint()
    local p = T:Get()
    local a = t.hover and p.accent2 or p.accent
    t.bg:SetColorTexture(a[1], a[2], a[3], 1)
    T:Font(t.label, 12, (T:Key() == "light" or T:Key() == "hclight") and "panel" or "bg")
  end
  t:HookScript("OnEnter", function() t.hover = true; paint() end)
  t:HookScript("OnLeave", function() t.hover = false; paint() end)
  T:OnChange(paint)
  paint()
  t:Hide()
  self.target = t
  self:Place()
end

function RB:Place()
  local c = self.card
  c:ClearAllPoints()
  local pos = S().rareCardPos
  if pos then c:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else c:SetPoint("TOP", UIParent, "TOP", 0, -150) end
end

-- Secure changes wait for combat to end.
local pending
local function syncTarget()
  if InCombatLockdown() then pending = true return end
  pending = false
  local t, c = RB.target, RB.card
  if not t then return end
  if c:IsShown() and c.rareName and not c.isTreasure then
    t:SetAttribute("macrotext1", "/cleartarget\n/targetexact " .. c.rareName)
    t:Show()
  else
    t:Hide()
  end
end
CM:On("PLAYER_REGEN_ENABLED", function() if pending then syncTarget() end end)

function RB:Show(info)
  if S().rareButton == false then return end
  self:Build()
  local c = self.card
  c.rareName, c.mapID, c.x, c.y = info.name, info.mapID, info.x, info.y
  c.isTreasure = info.tag == "Treasure"
  c.tag:SetText((info.tag or "Rare"):upper() .. (info.level and ("  ·  level " .. info.level) or ""))
  c.name:SetText(info.name)
  c.where:SetText(info.where or "")
  local npc = info.npcID
  if npc and pcall(c.model.SetCreature, c.model, npc) then
    c.model:Show(); c.icon:Hide()
    pcall(c.model.SetPortraitZoom, c.model, 0.6)
  else
    c.model:Hide(); c.icon:Show()
    c.icon:SetTexture(c.isTreasure and "Interface\\Icons\\INV_Box_02" or "Interface\\AddOns\\WGACompanion\\Icons\\logo")
  end
  local loot = self:Loot(info.name)
  for i, b in ipairs(c.loot) do
    local e = loot[i]
    if e then
      b.itemID, b.n = e.id, e.n
      b.tex:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id) or 134400)
      b:Show()
    else
      b:Hide()
    end
  end
  c.noLoot:SetShown(#loot == 0 and not c.isTreasure)
  c:Show()
  c.shownAt = GetTime()
  syncTarget()
  -- Fade away after a while unless the mouse is on it.
  local token = c.shownAt
  C_Timer.After(S().rareCardSeconds or 90, function()
    if c.shownAt == token and c:IsShown() and not c:IsMouseOver() then RB:Hide() end
  end)
end

function RB:Hide()
  if not self.card then return end
  self.card:Hide()
  self.card.shownAt = nil
  syncTarget()
end

function RB:Test()
  self:Show({ name = "Mother Fang", tag = "Rare", level = 10, where = "Elwynn Forest 62.0, 49.5", npcID = 471,
    mapID = 1429, x = 0.62, y = 0.495 })
end

function RB:OnInit()
  CM.db.global.rareLoot = CM.db.global.rareLoot or {}
  S().rareIgnore = S().rareIgnore or {}
end
