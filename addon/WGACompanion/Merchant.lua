-- WGA Companion: vendor price learning, vendor->AH flip finder, junk selling, bag advice
local _, CM = ...
local M = CM:NewModule("Merchant")

M.flips = {}

local function merchantInfo(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local t = C_MerchantFrame.GetItemInfo(i)
    if t then return t.name, t.price, t.stackCount or t.quantity, t.numAvailable, t.hasExtendedCost end
  elseif GetMerchantItemInfo then
    local name, _, price, quantity, numAvailable, _, _, extendedCost = GetMerchantItemInfo(i)
    return name, price, quantity, numAvailable, extendedCost
  end
end

local function scanMerchant()
  local DB = CM.PriceDB
  local flips = {}
  for i = 1, GetMerchantNumItems() do
    local name, price, quantity, numAvailable, extendedCost = merchantInfo(i)
    local link = GetMerchantItemLink(i)
    local id = CM:ItemIDFromLink(link)
    if id and price and price > 0 and not extendedCost then
      local unit = price / math.max(quantity or 1, 1)
      CM.db.global.vendorBuy[id] = unit
      local net = DB:NetAH(id)
      if net and net - unit >= CM.db.settings.flipMinProfit then
        table.insert(flips, {
          link = link, name = name, cost = unit, net = net, profit = net - unit,
          limited = numAvailable and numAvailable > 0 and numAvailable or nil,
          vendor = UnitName("npc"), zone = GetZoneText(),
        })
      end
    end
  end
  table.sort(flips, function(a, b) return a.profit > b.profit end)
  M.flips = flips
  if #flips > 0 then
    CM:Print("|cff40ff40%d flip(s) at this vendor|r (buy here, sell on AH):", #flips)
    for i = 1, math.min(#flips, 5) do
      local f = flips[i]
      CM:Print("  %s  buy %s -> AH %s  = %s profit%s", f.link, CM:Money(f.cost, true), CM:Money(f.net, true),
        CM:Money(f.profit, true), f.limited and string.format(" |cffff8040(limited: %d)|r", f.limited) or "")
    end
  end
  -- Remember flips across sessions so the Flips tab can list known opportunities.
  local saved = CM:Realm().flips or {}
  for _, f in ipairs(flips) do saved[f.link] = { cost = f.cost, vendor = f.vendor, zone = f.zone, limited = f.limited } end
  CM:Realm().flips = saved
end

local function sellJunk()
  if not CM.db.settings.autoSellJunk then return end
  local total, n, slots = 0, 0, {}
  CM:ForEachBagItem(function(bag, slot, info)
    if info.quality == 0 and not info.hasNoValue and not info.isLocked then
      local sell = CM:SellPrice(info.itemID)
      if sell and sell > 0 then
        total = total + sell * (info.stackCount or 1)
        n = n + 1
        table.insert(slots, { bag, slot })
      end
    end
  end)
  if n == 0 then return end
  if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and (not C_MerchantFrame.IsSellAllJunkEnabled or C_MerchantFrame.IsSellAllJunkEnabled()) then
    C_MerchantFrame.SellAllJunkItems()
  else
    for _, s in ipairs(slots) do CM.Bags.Use(s[1], s[2]) end
  end
  CM:Print("Sold %d grey item(s) for %s.", n, CM:Money(total))
end

CM:On("MERCHANT_SHOW", function()
  sellJunk()
  C_Timer.After(0.3, scanMerchant) -- give item info a moment to load
end)

function M:BagReport()
  local DB = CM.PriceDB
  local ah, ahTotal, vendTotal = {}, 0, 0
  CM:ForEachBagItem(function(bag, slot, info)
    local id, count = info.itemID, info.stackCount or 1
    local net, v = DB:NetAH(id), DB:Vendor(id)
    if net and (not v or net > v * 1.2) then
      table.insert(ah, { link = info.hyperlink, val = net * count })
      ahTotal = ahTotal + net * count
    elseif v then
      vendTotal = vendTotal + v * count
    end
  end)
  table.sort(ah, function(a, b) return a.val > b.val end)
  CM:Print("Bags: |cff40ff40%s|r worth auctioning, %s better vendored.", CM:Money(ahTotal, true), CM:Money(vendTotal, true))
  for i = 1, math.min(#ah, 10) do CM:Print("  AH: %s  ~%s", ah[i].link, CM:Money(ah[i].val, true)) end
end

function M:Lines()
  local lines = { "|cffffd100Vendor -> Auction flips|r", "",
    "Visit vendors after a scan; any item the vendor sells for less than its AH value",
    "(after the 5% cut, minimum profit " .. CM:Money(CM.db.settings.flipMinProfit, true) .. ") is listed here.", "" }
  local saved = CM:Realm().flips or {}
  local list = {}
  for link, f in pairs(saved) do
    local id = CM:ItemIDFromLink(link)
    local net = CM.PriceDB:NetAH(id)
    if net then table.insert(list, { link = link, f = f, profit = net - f.cost, net = net }) end
  end
  table.sort(list, function(a, b) return a.profit > b.profit end)
  if #list == 0 then table.insert(lines, "|cff808080No flips found yet.|r") end
  for _, e in ipairs(list) do
    if e.profit > 0 then
      table.insert(lines, string.format("%s  buy %s  AH %s  |cff40ff40+%s|r  - %s, %s%s", e.link,
        CM:Money(e.f.cost, true), CM:Money(e.net, true), CM:Money(e.profit, true),
        e.f.vendor or "?", e.f.zone or "?", e.f.limited and " |cffff8040(limited stock)|r" or ""))
    end
  end
  return lines
end
