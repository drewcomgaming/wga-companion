-- WGA Companion: price lines on item tooltips (modern TooltipDataProcessor)
local _, CM = ...
local T = CM:NewModule("Tooltip")

local function stackCount(tooltip)
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  if owner and owner.GetBagID and owner.GetID then
    local ok, bag = pcall(owner.GetBagID, owner)
    if ok and bag then
      local count = CM.Bags.Count(bag, owner:GetID())
      if count and count > 1 then return count end
    end
  end
  if owner and type(owner.count) == "number" and owner.count > 1 then return owner.count end
  return 1
end

local function addLines(tooltip, id)
  if not CM.db or not CM.db.settings.tooltip or not id then return end
  local DB = CM.PriceDB
  local rec = DB:Get(id)
  local market, vendor, vbuy = DB:Market(id), DB:Vendor(id), DB:VendorBuy(id)
  local rMin, rMarket, rQty = DB:Region(id)
  if not rec and not vbuy and not rMarket then return end
  local n = stackCount(tooltip)
  local function line(label, v)
    if not v then return end
    local right = CM:Money(v, true)
    if n > 1 then right = right .. string.format(" |cff808080(x%d: %s)|r", n, CM:Money(v * n, true)) end
    tooltip:AddDoubleLine("|cffffd100WGA|r " .. label, right, 0.8, 0.8, 0.8, 1, 1, 1)
  end
  if rec then
    line("AH min", rec.m)
    line("AH market", market)
    tooltip:AddDoubleLine("|cffffd100WGA|r seen", string.format("%s, %d listed", CM:Age(rec.t), rec.q or 0), 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
  end
  if rMarket then
    line("region market", rMarket)
    tooltip:AddDoubleLine("|cffffd100WGA|r region", string.format("min %s, %d listed, %s", CM:Money(rMin, true), rQty or 0, CM:Age(DB:RegionAge())), 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
  end
  if vbuy then line("vendor buy", vbuy) end
  local net = DB:NetAH(id)
  if net and vendor then
    if net > vendor * 1.2 then
      tooltip:AddLine("|cffffd100WGA|r |cff40ff40Auction it|r (" .. CM:Money(net - vendor, true) .. " more than vendor after cut)")
    elseif vendor >= net then
      tooltip:AddLine("|cffffd100WGA|r |cffffa040Vendor it|r (AH pays no more after the 5% cut)")
    end
  end
end

function T:OnLogin()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
      local id = data and data.id
      if not id and tooltip.GetItem then id = CM:ItemIDFromLink(select(2, tooltip:GetItem())) end
      addLines(tooltip, id)
    end)
  else
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tt)
      addLines(tt, CM:ItemIDFromLink(select(2, tt:GetItem())))
    end)
  end
end
