-- WGA Companion: shopping lists at the auction house.
-- A panel beside the auction house: several named lists, each item with an optional amount.
-- Click an item to search for it; for stackable goods (commodities) "Buy" gets the cheapest units.
local _, CM = ...
local SH = CM:NewModule("Shopping")
local T = CM.Theme
local AH = C_AuctionHouse

local ROWS, ROW_H, W = 14, 22, 250

local function store() return CM.db.global.shopping end
local function list()
  local s = store()
  if #s.lists == 0 then s.lists[1] = { name = "Shopping", items = {} } end
  s.cur = math.min(math.max(s.cur or 1, 1), #s.lists)
  return s.lists[s.cur]
end

local function idForName(name)
  local lower = name:lower()
  for id, n in pairs(CM.db.global.itemNames) do
    if n:lower() == lower then return id end
  end
end

-- "Linen Cloth/20", "[Linen Cloth] 20" or an item link with an amount after it.
local function parse(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local id = CM:ItemIDFromLink(text)
  local name = text:match("|h%[(.-)%]|h") or text
  local qty = text:match("/%s*(%d+)%s*$") or text:match("|r%s+(%d+)%s*$") or text:match("%]%s+(%d+)%s*$")
  name = name:gsub("/%s*%d+%s*$", ""):gsub("^%[", ""):gsub("%]%s*%d*$", ""):gsub("%s+$", "")
  return { name = name, id = id or idForName(name), qty = tonumber(qty) }
end

-- Searching --------------------------------------------------------------------------------------------
function SH:Search(entry)
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  if not bar then return end
  if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then
    pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
  end
  local box = bar.SearchBox
  if box then box:SetText(entry.name) end
  if bar.StartSearch then bar:StartSearch() end
  self.searched = entry
  self:Refresh()
end

function SH:SearchNext()
  local items = list().items
  if #items == 0 then return end
  local idx = 1
  for i, e in ipairs(items) do if e == self.searched then idx = i % #items + 1 end end
  self:Search(items[idx])
end

-- Buying the cheapest units of a commodity: Start -> price arrives -> Confirm (two clicks).
local function isCommodity(id)
  if not id or not AH.GetItemCommodityStatus then return false end
  local ok, status = pcall(AH.GetItemCommodityStatus, id)
  return ok and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Item
end

function SH:Buy(entry)
  if not entry.id or not isCommodity(entry.id) then
    CM:Print("Buy works for stackable goods. Searching instead; buy from the results.")
    self:Search(entry)
    return
  end
  local qty = entry.qty or 1
  local have = CM.GetItemCount(entry.id, true) or 0
  if entry.qty then qty = math.max(1, entry.qty - have) end
  self.pending = { entry = entry, id = entry.id, qty = qty }
  AH.StartCommoditiesPurchase(entry.id, qty)
  self.frame.status:SetText(string.format("Getting price for %d x %s...", qty, entry.name))
end

CM:On("COMMODITY_PRICE_UPDATED", function(_, unitPrice, totalPrice)
  local p = SH.pending
  if not p or not SH.frame then return end
  p.total, p.unit = totalPrice, unitPrice
  SH.frame.status:SetText(string.format("%d x %s for %s (%s each)", p.qty, p.entry.name,
    T:Recolor(CM:Money(totalPrice, true)), T:Recolor(CM:Money(unitPrice, true))))
  SH.frame.confirm:Show()
end)
CM:On("COMMODITY_PRICE_UNAVAILABLE", function()
  if SH.pending and SH.frame then SH.frame.status:SetText("Not enough on the auction house.") end
  SH.pending = nil
  if SH.frame then SH.frame.confirm:Hide() end
end)
CM:On("COMMODITY_PURCHASE_SUCCEEDED", function()
  local p = SH.pending
  SH.pending = nil
  if not SH.frame then return end
  SH.frame.confirm:Hide()
  if p then
    SH.frame.status:SetText(string.format("Bought %d x %s.", p.qty, p.entry.name))
    if p.unit then CM.PriceDB:Commit(p.id, p.unit, 0) end
  end
  SH:Refresh()
end)
CM:On("COMMODITY_PURCHASE_FAILED", function()
  SH.pending = nil
  if SH.frame then SH.frame.confirm:Hide(); SH.frame.status:SetText("Purchase failed. Prices may have changed.") end
end)

-- Panel ------------------------------------------------------------------------------------------------
local function smallButton(parent, label, w, onClick)
  local b = T:Button(parent, label, 11, onClick)
  b:SetSize(w, 20)
  b.text:ClearAllPoints(); b.text:SetPoint("CENTER")
  T:Skin(b, "panel", "border")
  return b
end

function SH:Build()
  if self.frame or not AuctionHouseFrame then return end
  local f = CreateFrame("Frame", "WGACompanionShopping", AuctionHouseFrame)
  f:SetSize(W, 92 + ROWS * ROW_H + 60)
  f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
  f:EnableMouse(true)
  T:Skin(f, "bg", "border")
  local stripe = f:CreateTexture(nil, "ARTWORK")
  stripe:SetHeight(2); stripe:SetPoint("TOPLEFT", 1, -30); stripe:SetPoint("TOPRIGHT", -1, -30)
  T:Gradient(stripe)
  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\logo")
  logo:SetSize(20, 20); logo:SetPoint("TOPLEFT", 8, -6)
  local title = T:Text(f, 13, "heading")
  title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
  title:SetText("Shopping lists")

  -- list picker: < name >
  f.prev = smallButton(f, "<", 22, function() local s = store(); s.cur = (s.cur - 2) % #s.lists + 1; SH:Refresh() end)
  f.prev:SetPoint("TOPLEFT", 8, -38)
  f.next = smallButton(f, ">", 22, function() local s = store(); s.cur = s.cur % #s.lists + 1; SH:Refresh() end)
  f.next:SetPoint("TOPRIGHT", -8, -38)
  f.listName = T:Text(f, 12, "text")
  f.listName:SetPoint("LEFT", f.prev, "RIGHT", 6, 0)
  f.listName:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
  f.listName:SetJustifyH("CENTER")

  f.new = smallButton(f, "New list", 70, function() SH:Prompt("new") end)
  f.new:SetPoint("TOPLEFT", 8, -62)
  f.ren = smallButton(f, "Rename", 64, function() SH:Prompt("rename") end)
  f.ren:SetPoint("LEFT", f.new, "RIGHT", 4, 0)
  f.del = smallButton(f, "Delete", 60, function()
    local s = store()
    if IsShiftKeyDown() then
      table.remove(s.lists, s.cur); SH:Refresh()
    else
      f.status:SetText("Shift-click Delete to remove this list.")
    end
  end)
  f.del:SetPoint("LEFT", f.ren, "RIGHT", 4, 0)

  -- add box (shift-click item links into it too)
  local box = CreateFrame("EditBox", nil, f)
  box:SetSize(W - 16, 22)
  box:SetPoint("TOPLEFT", 8, -88)
  box:SetAutoFocus(false)
  box:SetTextInsets(6, 6, 0, 0)
  T:Skin(box, "panel", "border")
  box:SetFontObject(ChatFontNormal)
  box.hint = T:Text(box, 11, "muted")
  box.hint:SetPoint("LEFT", 6, 0)
  box.hint:SetText("Add item, e.g. Linen Cloth/20")
  box:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "" and not self:HasFocus()) end)
  box:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
  box:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  box:SetScript("OnEnterPressed", function(self)
    if self.mode then
      local name = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
      if name ~= "" then
        local s = store()
        if self.mode == "new" then table.insert(s.lists, { name = name, items = {} }); s.cur = #s.lists
        else list().name = name end
      end
      self.mode = nil
      self.hint:SetText("Add item, e.g. Linen Cloth/20")
    else
      local e = parse(self:GetText())
      if e then table.insert(list().items, e) end
    end
    self:SetText("")
    SH:Refresh()
  end)
  local function color()
    local c = T:Get().text
    box:SetTextColor(c[1], c[2], c[3])
  end
  color(); T:OnChange(color)
  f.box = box
  if ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      if box:HasFocus() and link then box:Insert(link) end
    end)
  end

  -- rows
  f.rows = {}
  for i = 1, ROWS do
    local r = T:Button(f, "", 12)
    r:SetSize(W - 16, ROW_H - 2)
    r:SetPoint("TOPLEFT", 8, -116 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.text:SetPoint("RIGHT", r, "RIGHT", -96, 0)
    r.text:SetWordWrap(false)
    r.price = T:Text(r, 11, "muted")
    r.price:SetPoint("RIGHT", -44, 0)
    r.buy = smallButton(r, "Buy", 38, function() if r.entry then SH:Buy(r.entry) end end)
    r.buy:SetSize(38, ROW_H - 4)
    r.buy:SetPoint("RIGHT", -2, 0)
    r:SetScript("OnClick", function(self, button)
      if not self.entry then return end
      if button == "RightButton" then
        local items = list().items
        for k, e in ipairs(items) do if e == self.entry then table.remove(items, k) break end end
        SH:Refresh()
      else
        SH:Search(self.entry)
      end
    end)
    r:HookScript("OnEnter", function(self)
      if not self.entry then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.entry.id then GameTooltip:SetItemByID(self.entry.id) else GameTooltip:AddLine(self.entry.name) end
      GameTooltip:AddLine("Click: search   Right-click: remove   Buy: cheapest units (stackable goods)", 0.6, 0.8, 1, true)
      GameTooltip:Show()
    end)
    r:HookScript("OnLeave", GameTooltip_Hide)
    f.rows[i] = r
  end
  f:EnableMouseWheel(true)
  f.offset = 0
  f:SetScript("OnMouseWheel", function(_, d)
    f.offset = math.max(0, math.min(f.offset - d, math.max(0, #list().items - ROWS)))
    SH:Refresh()
  end)

  f.searchNext = smallButton(f, "Search next", 110, function() SH:SearchNext() end)
  f.searchNext.primary = true
  T:PaintButton(f.searchNext)
  f.searchNext:SetPoint("BOTTOMLEFT", 8, 30)
  f.total = T:Text(f, 11, "muted")
  f.total:SetPoint("LEFT", f.searchNext, "RIGHT", 8, 0)
  f.total:SetPoint("RIGHT", -8, 0)
  f.status = T:Text(f, 11, "text")
  f.status:SetPoint("BOTTOMLEFT", 8, 10)
  f.status:SetPoint("RIGHT", -84, 0)
  f.status:SetWordWrap(false)
  f.confirm = smallButton(f, "Confirm", 70, function()
    local p = SH.pending
    if p then AH.ConfirmCommoditiesPurchase(p.id, p.qty) end
    f.confirm:Hide()
  end)
  f.confirm.primary = true
  T:PaintButton(f.confirm)
  f.confirm:SetPoint("BOTTOMRIGHT", -8, 8)
  f.confirm:Hide()
  self.frame = f
end

function SH:Prompt(mode)
  local box = self.frame.box
  box.mode = mode
  box.hint:SetText(mode == "new" and "Name the new list, then Enter" or "New name, then Enter")
  box:SetText(mode == "rename" and list().name or "")
  box:SetFocus()
end

function SH:Refresh()
  local f = self.frame
  if not f then return end
  local s, l = store(), list()
  f.listName:SetText(string.format("%s  (%d/%d)", l.name, s.cur, #s.lists))
  local total, missing = 0, 0
  for i, r in ipairs(f.rows) do
    local e = l.items[i + f.offset]
    r.entry = e
    if e then
      local have = e.id and CM.GetItemCount(e.id, true) or 0
      local label = e.name
      if e.qty then label = string.format("%s  |cff808080%d/%d|r", e.name, math.min(have, e.qty), e.qty) end
      r.text:SetText(T:Recolor(label))
      local price = e.id and (CM.PriceDB:Min(e.id) or CM.PriceDB:Market(e.id))
      r.price:SetText(price and T:Recolor(CM:Money(price, true)) or "")
      r.selected = e == self.searched
      T:PaintButton(r)
      r:Show()
    else
      r:Hide()
    end
  end
  for _, e in ipairs(l.items) do
    local price = e.id and (CM.PriceDB:Min(e.id) or CM.PriceDB:Market(e.id))
    local need = e.qty and math.max(0, e.qty - (e.id and CM.GetItemCount(e.id, true) or 0)) or 1
    if price then total = total + price * need elseif need > 0 then missing = missing + 1 end
  end
  f.total:SetText(T:Recolor(string.format("About %s%s", CM:Money(total, true), missing > 0 and string.format(" (+%d unpriced)", missing) or "")))
end

function SH:Toggle()
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    CM:Print("Open the auction house to use shopping lists.")
    return
  end
  self:Build()
  CM.db.settings.shopping = not self.frame:IsShown()
  self.frame:SetShown(CM.db.settings.shopping)
  self:Refresh()
end

CM:On("AUCTION_HOUSE_SHOW", function()
  if CM.db.settings.shopping == false then if SH.frame then SH.frame:Hide() end return end
  SH:Build()
  if SH.frame then SH.frame:Show(); SH:Refresh() end
end)
CM:On("BAG_UPDATE_DELAYED", function() if SH.frame and SH.frame:IsVisible() then SH:Refresh() end end)
