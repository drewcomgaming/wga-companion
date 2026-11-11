-- WGA Companion: auction house scanner for the modern (C_AuctionHouse) auction house.
-- Full scan uses C_AuctionHouse.ReplicateItems (allowed about once per 15 minutes).
-- Every browse or commodity search you do by hand is also recorded.
local _, CM = ...
local S = CM:NewModule("Scanner")
local AH = C_AuctionHouse

local state = { active = false }

local function finish(acc, full)
  local n = 0
  for itemID, e in pairs(acc) do
    CM.PriceDB:Commit(itemID, math.floor(e.min), e.qty, e.name or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)))
    n = n + 1
  end
  if full then CM:Realm().lastScan = time() end
  return n
end

local function add(acc, itemID, unit, qty, name)
  if not itemID or not unit or unit <= 0 then return end
  local e = acc[itemID]
  if not e then acc[itemID] = { min = unit, qty = qty or 0, name = name }
  else
    if unit < e.min then e.min = unit end
    e.qty = e.qty + (qty or 0)
    e.name = e.name or name
  end
end

function S:Start()
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    CM:Print("Open the auction house first, then run /wga scan.")
    return
  end
  if state.active then CM:Print("A scan is already running."); return end
  local last = CM:Realm().lastScan or 0
  if time() - last < 15 * 60 then
    CM:Print("Full scans are limited to once every 15 minutes (next in %d min). Browsing still records prices.",
      math.ceil((15 * 60 - (time() - last)) / 60))
    return
  end
  state = { active = true }
  CM:Print("Starting full auction scan. The game may pause for a few seconds.")
  AH.ReplicateItems()
end

-- Replicate results: process in slices so the client stays responsive.
CM:On("REPLICATE_ITEM_LIST_UPDATE", function()
  if not state.active or state.processing then return end
  state.processing = true
  local total = AH.GetNumReplicateItems()
  CM:Print("Processing %d auctions...", total)
  local acc, i = {}, 0
  local function step()
    local last = math.min(i + 999, total - 1)
    for idx = i, last do
      local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(idx)
      if itemID and buyout and buyout > 0 and count and count > 0 then add(acc, itemID, buyout / count, count, name) end
    end
    i = last + 1
    if i < total then C_Timer.After(0, step) else
      local n = finish(acc, true)
      state.active = false
      CM:Print("Scan complete: %d items priced.", n)
      if CM.UI and CM.UI.Refresh then CM.UI:Refresh() end
    end
  end
  step()
end)

-- Passive capture from normal browsing ------------------------------------------------
local function captureBrowse()
  local results = AH.GetBrowseResults and AH.GetBrowseResults()
  if not results then return end
  local acc = {}
  for _, r in ipairs(results) do
    local id = r.itemKey and r.itemKey.itemID
    -- only plain items (no item level / suffix variants) map cleanly to one price
    if id and r.minPrice and (not r.itemKey.itemSuffix or r.itemKey.itemSuffix == 0) then
      add(acc, id, r.minPrice, r.totalQuantity)
    end
  end
  finish(acc, false)
end
CM:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", captureBrowse)
CM:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", captureBrowse)

CM:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
  if not itemID then return end
  local first = AH.GetCommoditySearchResultInfo(itemID, 1)
  if first and first.unitPrice then
    CM.PriceDB:Commit(itemID, first.unitPrice, AH.GetCommoditySearchResultsQuantity(itemID))
  end
end)

CM:On("AUCTION_HOUSE_CLOSED", function() state.active = false; state.processing = false end)

CM:On("AUCTION_HOUSE_SHOW", function()
  if S.button or not AuctionHouseFrame then return end
  local b = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
  b:SetSize(90, 22)
  b:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -1)
  b:SetText("WGA Scan")
  b:SetScript("OnClick", function() S:Start() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("WGA Companion full scan")
    GameTooltip:AddLine("Last full scan: " .. CM:Age(CM:Realm().lastScan), 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  S.button = b
end)
