-- WGA Companion: keep list and full-bag loot swap.
-- Keep list: items you never want sold or dropped (your own picks plus items your open quests need).
-- Loot swap: when your bags are full and loot is left behind, offer to drop the cheapest bag item for it.
local _, CM = ...
local LS = CM:NewModule("LootSwap")
local T = CM.Theme
local QL = C_QuestLog

local HEARTHSTONE = 6948

-- Keep list -------------------------------------------------------------------------------------------
local questItems -- [itemID] = quest title, rebuilt when the quest log changes
local function buildQuestItems()
  questItems = {}
  if not (CM.QData and CM.QData:Has()) then return questItems end
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    local id = info and not info.isHeader and info.questID
    local q = id and CM.QData:Quest(id)
    if q and q[8] then
      for _, o in ipairs(q[8]) do
        if o[1] == "i" then questItems[o[2]] = info.title or q[1] end
      end
    end
  end
  return questItems
end
CM:On("QUEST_LOG_UPDATE", function() questItems = nil end)

-- Returns a reason string when the item should be kept, else nil.
function LS:KeepReason(itemID)
  if not itemID or not CM.db then return nil end
  if CM.db.global.keep[itemID] then return "on your keep list" end
  local q = (questItems or buildQuestItems())[itemID]
  if q then return "needed for " .. q end
  return nil
end
function CM:IsKept(itemID) return LS:KeepReason(itemID) ~= nil end

function LS:ToggleKeep(text)
  local id = CM:ItemIDFromLink(text) or tonumber(text)
  if not id then
    local list = {}
    for k in pairs(CM.db.global.keep) do
      list[#list + 1] = select(2, CM.GetItemInfo(k)) or ("item " .. k)
    end
    CM:Print("Keep list (%d): %s", #list, #list > 0 and table.concat(list, ", ") or "empty. Shift-click an item into /wga keep to add it.")
    return
  end
  if CM.db.global.keep[id] then
    CM.db.global.keep[id] = nil
    CM:Print("Removed %s from your keep list.", text)
  else
    CM.db.global.keep[id] = true
    CM:Print("Keeping %s: WGA will never sell or drop it.", text)
  end
end

-- Values ---------------------------------------------------------------------------------------------
-- What one unit is worth to you: the better of selling on the AH (after the cut) or to a vendor.
local function unitValue(id)
  local net, v = CM.PriceDB:NetAH(id), CM.PriceDB:Vendor(id)
  if net and v then return math.max(net, v) end
  return net or v
end
LS.UnitValue = unitValue

local function freeSlots()
  local free = 0
  for bag = 0, CM.Bags.Last do
    local n = C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots(bag)
    free = free + (n or 0)
  end
  return free
end

-- Cheapest bag stack that is safe to drop: priced, not kept, not a quest item, green quality or lower.
function LS:Cheapest()
  local best
  CM:ForEachBagItem(function(bag, slot, info)
    local id = info.itemID
    if info.isLocked or info.hasNoValue or id == HEARTHSTONE or (info.quality or 0) > 2 then return end
    if self:KeepReason(id) then return end
    local qi = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    if qi and (qi.isQuestItem or qi.questID) then return end
    local u = unitValue(id)
    if not u then return end
    local total = u * (info.stackCount or 1)
    if not best or total < best.value then
      best = { bag = bag, slot = slot, value = total, link = info.hyperlink, count = info.stackCount or 1, id = id }
    end
  end)
  return best
end

-- Most valuable loot slot still on the corpse.
local function bestLoot()
  local best
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    local id = CM:ItemIDFromLink(link)
    if id then
      local _, _, qty, _, _, locked, isQuestItem = GetLootSlotInfo(slot)
      if not locked then
        local u = unitValue(id) or 0
        local kept = LS:KeepReason(id) or (isQuestItem and "quest item")
        local total = u * (qty or 1)
        -- kept and quest items always win: you want them regardless of price
        local score = kept and math.huge or total
        if not best or score > best.score then
          best = { slot = slot, link = link, value = total, score = score, qty = qty or 1, kept = kept, id = id }
        end
      end
    end
  end
  return best
end

-- Prompt ---------------------------------------------------------------------------------------------
function LS:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionLootSwap", UIParent)
  f:SetSize(320, 132)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetPoint("TOP", UIParent, "TOP", 0, -260)
  f:EnableMouse(true)
  T:Skin(f, "panel", "accent")
  local stripe = f:CreateTexture(nil, "ARTWORK")
  stripe:SetHeight(3); stripe:SetPoint("TOPLEFT", 1, -1); stripe:SetPoint("TOPRIGHT", -1, -1)
  T:Gradient(stripe)
  f.title = T:Text(f, 14, "heading")
  f.title:SetPoint("TOPLEFT", 12, -12)
  f.title:SetText("Bags full")
  f.drop = T:Text(f, 12, "text")
  f.drop:SetPoint("TOPLEFT", 12, -36); f.drop:SetPoint("RIGHT", -12, 0)
  f.drop:SetWordWrap(false)
  f.get = T:Text(f, 12, "text")
  f.get:SetPoint("TOPLEFT", 12, -56); f.get:SetPoint("RIGHT", -12, 0)
  f.get:SetWordWrap(false)
  f.note = T:Text(f, 10, "muted")
  f.note:SetPoint("TOPLEFT", 12, -76); f.note:SetPoint("RIGHT", -12, 0)

  f.swap = T:Button(f, "Swap", 12, function() LS:DoSwap() end)
  f.swap.primary = true
  f.swap:SetSize(120, 24)
  f.swap:SetPoint("BOTTOMLEFT", 12, 10)
  f.swap.text:ClearAllPoints(); f.swap.text:SetPoint("CENTER")
  T:PaintButton(f.swap)
  f.cancel = T:Button(f, "Not now", 12, function() f:Hide() end)
  f.cancel:SetSize(90, 24)
  f.cancel:SetPoint("LEFT", f.swap, "RIGHT", 8, 0)
  f.cancel.text:ClearAllPoints(); f.cancel.text:SetPoint("CENTER")
  T:Skin(f.cancel, "panel", "border")
  f.keep = T:Button(f, "Keep it", 12, function()
    if f.offer then LS:ToggleKeep(f.offer.drop.link) end
    LS:Check(true)
  end)
  f.keep:SetSize(80, 24)
  f.keep:SetPoint("LEFT", f.cancel, "RIGHT", 8, 0)
  f.keep.text:ClearAllPoints(); f.keep.text:SetPoint("CENTER")
  T:Skin(f.keep, "panel", "border")
  f:Hide()
  self.frame = f
end

function LS:Check(force)
  if not CM.db or CM.db.settings.lootSwap == false then return end
  if not (LootFrame and LootFrame:IsShown()) and GetNumLootItems() == 0 then return end
  if not force and freeSlots() > 0 then return end
  local loot = bestLoot()
  local drop = loot and self:Cheapest()
  self:Build()
  local f = self.frame
  if not loot or not drop or (not loot.kept and loot.value <= drop.value) then f:Hide() return end
  f.offer = { loot = loot, drop = drop }
  f.drop:SetText(string.format("Drop  %s%s  (%s)", drop.link or "?", drop.count > 1 and (" x" .. drop.count) or "",
    T:Recolor(CM:Money(drop.value, true))))
  f.get:SetText(string.format("Loot  %s%s  (%s)", loot.link, loot.qty > 1 and (" x" .. loot.qty) or "",
    loot.kept and loot.kept or T:Recolor(CM:Money(loot.value, true))))
  f.note:SetText("Dropping destroys the item. Values use AH after the cut or vendor, whichever is higher.")
  f:ClearAllPoints()
  if LootFrame and LootFrame:IsShown() then f:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 8, 0) else f:SetPoint("TOP", UIParent, "TOP", 0, -260) end
  f:Show()
end

function LS:DoSwap()
  local f = self.frame
  local o = f.offer
  f:Hide()
  if not o then return end
  -- re-check that the bag slot still holds the same item
  local info = C_Container.GetContainerItemInfo(o.drop.bag, o.drop.slot)
  if not info or info.itemID ~= o.drop.id then CM:Print("Your bags changed; try again.") return end
  ClearCursor()
  C_Container.PickupContainerItem(o.drop.bag, o.drop.slot)
  if not CursorHasItem() then return end
  DeleteCursorItem()
  CM:Print("Dropped %s for %s.", o.drop.link or "?", o.loot.link)
  C_Timer.After(0.3, function()
    if GetNumLootItems() >= o.loot.slot and GetLootSlotLink(o.loot.slot) == o.loot.link then LootSlot(o.loot.slot) end
  end)
end

CM:On("LOOT_OPENED", function() C_Timer.After(0.4, function() LS:Check() end) end)
CM:On("LOOT_SLOT_CLEARED", function() if LS.frame and LS.frame:IsShown() then LS:Check() end end)
CM:On("LOOT_CLOSED", function() if LS.frame then LS.frame:Hide() end end)
CM:On("UI_ERROR_MESSAGE", function(_, _, msg)
  if msg and (msg == ERR_INV_FULL or msg == INVENTORY_FULL) then LS:Check(true) end
end)

-- Tooltip line for kept items
function LS:OnLogin()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
      local why = data and data.id and LS:KeepReason(data.id)
      if why then tooltip:AddLine("|cffffd100WGA|r keeping this: " .. why, 0.5, 0.85, 1) end
    end)
  end
end
