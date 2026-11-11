-- WGA Companion: per-realm price database built from auction scans
local _, CM = ...
local DB = CM:NewModule("PriceDB")

local HISTORY_DAYS = 14
local AH_CUT = 0.05 -- auction house cut on a sale

local function today() return math.floor(time() / 86400) end

-- record = { m = latest min unit buyout, q = quantity seen, t = timestamp, h = { {day, min}, ... } }
function DB:Commit(itemID, minUnit, qty, name)
  if not itemID or not minUnit or minUnit <= 0 then return end
  local prices = CM:Realm().prices
  local rec = prices[itemID]
  if not rec then rec = { h = {} }; prices[itemID] = rec end
  rec.m, rec.q, rec.t = minUnit, qty, time()
  local d = today()
  local last = rec.h[#rec.h]
  if last and last[1] == d then
    last[2] = math.min(last[2], minUnit)
  else
    table.insert(rec.h, { d, minUnit })
    while #rec.h > HISTORY_DAYS do table.remove(rec.h, 1) end
  end
  if name then CM.db.global.itemNames[itemID] = name end
end

-- Region prices from the WGACompanion_Data addon (built hourly from the Battle.net API) ----
local houseCache, parsed = nil, {}

local function houses()
  return WGACompanionData and WGACompanionData.houses or nil
end

-- Pick the auction house that matches this character: the saved choice, else one whose
-- name mentions the player's faction (and realm/ruleset name if several), else the largest.
function DB:House()
  if houseCache ~= nil then return houseCache or nil end
  local hs = houses()
  if not hs then houseCache = false; return nil end
  local forced = CM.db and CM.db.settings.house
  if forced and hs[forced] then houseCache = hs[forced]; return houseCache end
  local faction = (UnitFactionGroup("player") or ""):lower()
  local realm = (GetRealmName() or ""):lower()
  local best, bestScore, bestSize = nil, -1, -1
  for id, h in pairs(hs) do
    local name, size = (h.name or ""):lower(), 0
    for _ in pairs(h.items or {}) do size = size + 1 end
    local score = (faction ~= "" and name:find(faction, 1, true) and 2 or 0) + (realm ~= "" and name:find(realm, 1, true) and 1 or 0)
    if score > bestScore or (score == bestScore and size > bestSize) then best, bestScore, bestSize = h, score, size end
  end
  houseCache = best or false
  return best
end

function DB:ResetHouse() houseCache = nil; parsed = {} end

-- returns min, market, quantity (copper per unit) from region data
function DB:Region(itemID)
  local h = itemID and self:House()
  local raw = h and h.items and h.items[itemID]
  if not raw then return nil end
  local p = parsed[itemID]
  if not p then
    local mn, mk, q = raw:match("^(%d+),(%d+),(%d+)$")
    p = { tonumber(mn), tonumber(mk), tonumber(q) }
    parsed[itemID] = p
  end
  return p[1], p[2], p[3]
end

function DB:RegionAge()
  return WGACompanionData and WGACompanionData.generated or nil
end

function DB:ListHouses()
  local hs = houses()
  if not hs then CM:Print("No region data installed. Download WGACompanion_Data and put it in your AddOns folder."); return end
  local cur = self:House()
  CM:Print("Region auction houses (data from %s). Pick with /wga house <id>:", CM:Age(self:RegionAge()))
  for id, h in pairs(hs) do
    local n = 0
    for _ in pairs(h.items or {}) do n = n + 1 end
    CM:Print("  %s%d|r  %s  (%d items)", h == cur and "|cff40ff40> " or "  ", id, h.name ~= "" and h.name or "?", n)
  end
end

function DB:SetHouse(id)
  id = tonumber(id)
  if not id or not (houses() and houses()[id]) then CM:Print("Unknown house id. /wga house lists them."); return end
  CM.db.settings.house = id
  self:ResetHouse()
  CM:Print("Using auction house %d for region prices.", id)
end

function DB:Get(itemID)
  return itemID and CM:Realm().prices[itemID]
end

-- Market value: median of daily minimum buyouts over the stored history.
-- It smooths out one-off cheap or overpriced listings.
local FRESH = 2 * 86400 -- own scans newer than this beat region data

function DB:Market(itemID)
  local rec = self:Get(itemID)
  if not rec or not rec.h or #rec.h == 0 or (time() - (rec.t or 0) > FRESH and self:Region(itemID)) then
    local _, mk = self:Region(itemID)
    return mk
  end
  local vals = {}
  for i, e in ipairs(rec.h) do vals[i] = e[2] end
  table.sort(vals)
  local n = #vals
  if n % 2 == 1 then return vals[(n + 1) / 2] end
  return math.floor((vals[n / 2] + vals[n / 2 + 1]) / 2)
end

function DB:Min(itemID)
  local rec = self:Get(itemID)
  if rec and rec.m and (time() - (rec.t or 0) <= FRESH or not self:Region(itemID)) then return rec.m end
  return (self:Region(itemID))
end

function DB:Vendor(itemID)
  if not itemID then return nil end
  local sell = CM:SellPrice(itemID)
  return (sell and sell > 0) and sell or nil
end

function DB:VendorBuy(itemID)
  return itemID and CM.db.global.vendorBuy[itemID]
end

-- What you would actually pocket selling one unit on the AH after the cut.
function DB:NetAH(itemID)
  local v = self:Market(itemID) or self:Min(itemID)
  return v and math.floor(v * (1 - AH_CUT))
end

-- Cheapest known way to acquire one unit (vendor if it is sold by one, else AH).
function DB:AcquireCost(itemID)
  local vb = self:VendorBuy(itemID)
  local ah = self:Min(itemID) or self:Market(itemID)
  if vb and ah then return math.min(vb, ah), (vb <= ah) and "vendor" or "AH" end
  if vb then return vb, "vendor" end
  if ah then return ah, "AH" end
  return nil
end

function DB:FindByName(query)
  query = query:lower()
  local out = {}
  for id, name in pairs(CM.db.global.itemNames) do
    if name:lower():find(query, 1, true) and self:Get(id) then
      table.insert(out, id)
    end
  end
  table.sort(out, function(a, b) return (self:Market(a) or 0) > (self:Market(b) or 0) end)
  return out
end

function DB:PrintPrice(text)
  local id = CM:ItemIDFromLink(text)
  local ids = id and { id } or self:FindByName(text)
  if #ids == 0 then
    CM:Print("No price data for '%s'. Run /wga scan at the auction house first.", text)
    return
  end
  for i = 1, math.min(#ids, 8) do
    local iid = ids[i]
    local rec = self:Get(iid)
    local name = CM.db.global.itemNames[iid] or CM.GetItemInfo(iid) or ("item " .. iid)
    CM:Print("%s  min %s  market %s  vendor %s  (%s, %d listed)", name,
      CM:Money(rec and rec.m), CM:Money(self:Market(iid)), CM:Money(self:Vendor(iid)),
      CM:Age(rec and rec.t), rec and rec.q or 0)
  end
end
