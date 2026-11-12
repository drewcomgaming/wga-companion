-- WGA Companion: the Guides page. One place to find every guide: Home (suggested for you and your
-- route with progress bars), Current, Recent and Favorites along the top, categories down the left,
-- a search box, and a detail pane with art, progress and what to do next.
local _, CM = ...
local B = CM:NewModule("Browser")
local T = CM.Theme
local I = "Interface\\Icons\\"

local VIEWS = { "Home", "Current", "Recent", "Favorites" }
local CATS = {
  { key = "Leveling", text = "Leveling zones", icon = I .. "INV_Misc_Map_01" },
  { key = "Dungeons", icon = I .. "INV_Misc_Head_Dragon_01" },
  { key = "Raids", icon = I .. "INV_Misc_Head_Dragon_Black" },
  { key = "Professions", icon = I .. "Trade_BlackSmithing" },
  { key = "Gold", text = "Gold making", icon = I .. "INV_Misc_Coin_01" },
  { key = "Tips", text = "Leveling tips", icon = I .. "INV_Misc_Book_11" },
  { key = "Mine", text = "My guides", icon = I .. "INV_Scroll_03" },
}
local ST = { view = "Home", cat = nil, sel = nil, query = "" }
B.state = ST

local function charDB()
  local c = WGACompanionCharDB
  c.recentGuides = c.recentGuides or {}
  return c
end
local function favs()
  local g = CM.db.global
  g.favGuides = g.favGuides or {}
  return g.favGuides
end
local function side() return UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance" end
local function lvl() return UnitLevel("player") or 1 end
local function range(s) local lo, hi = (s or ""):match("(%d+)%D+(%d+)"); return tonumber(lo), tonumber(hi) end

-- Items --------------------------------------------------------------------------------------------
-- { key, kind, name, lo, hi, icon, data }
local function zoneItem(z)
  return { key = "zone:" .. z[1], kind = "zone", name = z[1], lo = z[2], hi = z[3], cont = z[4],
    icon = side() == "Horde" and I .. "INV_BannerPVP_01" or I .. "INV_BannerPVP_02" }
end

local function zones()
  local out = {}
  for _, z in ipairs(CM.SmartGuide:AllZones(side())) do out[#out + 1] = zoneItem(z) end
  return out
end

local function dungeons()
  local out = {}
  local mine = side()
  for _, d in ipairs(CM.Data.Dungeons or {}) do
    local lo, hi = range(d.levels)
    if lo and hi and lo < 60 and not d.raid and (not d.faction or d.faction:find(mine, 1, true)) then
      local name = d.name:gsub("^NEW:%s*", "")
      out[#out + 1] = { key = "dungeon:" .. name, kind = "dungeon", name = name, lo = lo, hi = hi, data = d,
        icon = I .. "INV_Misc_Head_Dragon_01", new = name ~= d.name }
    end
  end
  table.sort(out, function(a, b) if a.lo ~= b.lo then return a.lo < b.lo end return a.name < b.name end)
  return out
end

local function raids()
  local out, seen = {}, {}
  local ok, list = pcall(CM.Journal.Instances, CM.Journal, true)
  for _, inst in ipairs(ok and list or {}) do
    if not seen[inst.name] then
      seen[inst.name] = true
      out[#out + 1] = { key = "raid:" .. inst.name, kind = "raid", name = inst.name, lo = 60, hi = 60, inst = inst,
        icon = I .. "INV_Misc_Head_Dragon_Black" }
    end
  end
  -- raids our own notes know about that the journal doesn't show yet
  for _, d in ipairs(CM.Data.Dungeons or {}) do
    if d.name:find("^RAIDS") then
      for _, line in ipairs(d.bosses or {}) do
        local name, rest = line:match("^(.-)%s*%(%d+%)%s*%-%s*(.*)$")
        if name and not seen[name] then
          seen[name] = true
          out[#out + 1] = { key = "raid:" .. name, kind = "raid", name = name, lo = 60, hi = 60, note = rest, data = d,
            icon = I .. "INV_Misc_Head_Dragon_Black" }
        end
      end
    end
  end
  return out
end

local function docs(list, kind, tab)
  local out = {}
  for _, e in ipairs(list or {}) do
    local name = e.title or e.name
    out[#out + 1] = { key = kind .. ":" .. name, kind = kind, name = name, data = e, icon = CM.Visuals:Icon(tab, e) }
  end
  return out
end

local function myGuides()
  local out = {}
  for _, g in ipairs(CM.Guides and CM.Guides.list or {}) do
    local lo, hi = range(g.levels)
    out[#out + 1] = { key = "guide:" .. g.name, kind = "guide", name = g.name, lo = lo, hi = hi, data = g,
      icon = I .. "INV_Scroll_03" }
  end
  return out
end

local function category(key)
  if key == "Leveling" then return zones() end
  if key == "Dungeons" then return dungeons() end
  if key == "Raids" then return raids() end
  if key == "Professions" then return docs(CM.Data.Professions, "prof", "Professions") end
  if key == "Gold" then return docs(CM.Data.GoldTips, "gold", "Gold") end
  if key == "Tips" then return docs(CM.Data.Leveling, "tip", "Leveling") end
  if key == "Mine" then return myGuides() end
  return {}
end

local function trainerItem()
  local Tr = CM.Trainer
  if not Tr then return nil end
  local n = #Tr:Available()
  if n == 0 and Tr:HasData() then return nil end
  return { key = "trainer", kind = "trainer", name = n > 0 and string.format("New skills at your trainer (%d)", n)
    or "Your class trainer", icon = I .. "INV_Misc_Book_09" }
end

-- every item by key, for Recent / Favorites / search
local function index()
  local all, order = {}, {}
  for _, c in ipairs(CATS) do
    for _, it in ipairs(category(c.key)) do
      if not all[it.key] then all[it.key] = it; order[#order + 1] = it end
    end
  end
  local tr = trainerItem()
  if tr then all[tr.key] = tr; order[#order + 1] = tr end
  return all, order
end

local function header(text) return { header = text } end

-- What the list shows right now
function B:Items()
  local all, order = index()
  local q = (ST.query or ""):lower()
  if q ~= "" then
    local out = { header("RESULTS FOR \"" .. ST.query:upper() .. "\"") }
    for _, it in ipairs(order) do if it.name:lower():find(q, 1, true) then out[#out + 1] = it end end
    if #out == 1 then out[2] = header("Nothing found") end
    return out, all
  end
  if ST.cat then
    local c
    for _, x in ipairs(CATS) do if x.key == ST.cat then c = x end end
    local out = { header(((c and c.text) or ST.cat):upper()) }
    for _, it in ipairs(category(ST.cat)) do out[#out + 1] = it end
    return out, all
  end
  local SG = CM.SmartGuide
  local out = {}
  if ST.view == "Home" then
    out[1] = header("SUGGESTED FOR YOU")
    local rec = SG:RecommendedZone()
    if rec and all["zone:" .. rec] then out[#out + 1] = all["zone:" .. rec] end
    local tr = all.trainer
    if tr and tr.name:find("%(") then out[#out + 1] = tr end
    for _, d in ipairs(dungeons()) do
      if lvl() >= d.lo - 1 and lvl() <= d.hi then out[#out + 1] = d end
    end
    local roster = SG:FollowingRoster() and SG:Roster()
    out[#out + 1] = header(roster and #roster > 0 and "YOUR ROUTE" or "THE STANDARD PATH")
    if roster and #roster > 0 then
      for _, name in ipairs(roster) do
        out[#out + 1] = all["zone:" .. name] or zoneItem({ name, SG.ZoneRange(name) })
      end
    else
      for _, z in ipairs(SG:Path()) do out[#out + 1] = all["zone:" .. z[1]] or zoneItem(z) end
    end
  elseif ST.view == "Current" then
    out[1] = header("WHAT YOU'RE DOING NOW")
    local _, lockName = SG:LockedZone()
    if lockName and all["zone:" .. lockName] then out[#out + 1] = all["zone:" .. lockName] end
    local m = C_Map.GetBestMapForUnit("player")
    local z = m and SG.ZoneOf(m)
    local info = z and C_Map.GetMapInfo(z)
    if info and info.name ~= lockName and all["zone:" .. info.name] then out[#out + 1] = all["zone:" .. info.name] end
    local g = CM.Guides and CM.Guides:Current()
    if g and all["guide:" .. g.name] then out[#out + 1] = all["guide:" .. g.name] end
    if all.trainer then out[#out + 1] = all.trainer end
    if #out == 1 then out[2] = header("Nothing yet: pick a zone and press Quest here") end
  elseif ST.view == "Recent" then
    out[1] = header("RECENTLY OPENED")
    for _, k in ipairs(charDB().recentGuides) do if all[k] then out[#out + 1] = all[k] end end
    if #out == 1 then out[2] = header("Guides you open show up here") end
  elseif ST.view == "Favorites" then
    out[1] = header("FAVORITES")
    for _, it in ipairs(order) do if favs()[it.key] then out[#out + 1] = it end end
    if #out == 1 then out[2] = header("Star a guide to keep it here") end
  end
  return out, all
end

-- Progress for an item: done, total
function B:Progress(it)
  local P = CM.Progress
  if not P then return 0, 0 end
  if it.kind == "zone" then return P:Zone(it.name) end
  if it.kind == "dungeon" then return P:Dungeon(it.name) end
  if it.kind == "guide" and CM.Guides then
    local cur = CM.Guides:Current()
    if cur and cur.name == it.name then return math.max(0, CM.Guides:Progress().step - 1), #it.data.steps end
    return 0, #(it.data.steps or {})
  end
  return 0, 0
end

local function remember(key)
  local r = charDB().recentGuides
  for i = #r, 1, -1 do if r[i] == key then table.remove(r, i) end end
  table.insert(r, 1, key)
  while #r > 15 do table.remove(r) end
end

-- Page ---------------------------------------------------------------------------------------------
local function small(parent, label, w, onClick)
  local b = T:Button(parent, label, 11, onClick)
  b:SetSize(w, 22)
  b.text:ClearAllPoints(); b.text:SetPoint("CENTER")
  T:Skin(b, "panel", "border")
  return b
end

local function scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  sf.child = child
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
  end)
  return sf
end

local CAT_W, LIST_W, ROW_H = 128, 340, 26

function B:Build(body)
  local page = CreateFrame("Frame", nil, body)
  page:SetPoint("TOPLEFT", 12, -12)
  page:SetPoint("BOTTOMRIGHT", -12, 12)
  page:Hide()
  self.page = page

  -- top: views and search
  page.views = {}
  local x = 0
  for _, v in ipairs(VIEWS) do
    local b = T:Button(page, v, 13, function() ST.view, ST.cat, ST.query = v, nil, ""; page.search:SetText(""); B:Fill() end)
    b:SetSize(86, 26)
    b:SetPoint("TOPLEFT", x, 0)
    b.text:ClearAllPoints(); b.text:SetPoint("CENTER")
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetPoint("BOTTOMRIGHT"); b.bar:SetHeight(2)
    b.view = v
    page.views[#page.views + 1] = b
    x = x + 90
  end
  local search = CreateFrame("EditBox", nil, page)
  search:SetSize(220, 26)
  search:SetPoint("TOPRIGHT", 0, 0)
  search:SetAutoFocus(false)
  search:SetTextInsets(10, 10, 0, 0)
  T:Skin(search, "panel", "border")
  local sfs = T:Text(search, 13, "text")
  search:SetFontObject(GameFontHighlight)
  search:SetFont(sfs:GetFont())
  local ph = T:Text(search, 12, "muted")
  ph:SetPoint("LEFT", 10, 0)
  ph:SetText("Search guides...")
  search:SetScript("OnTextChanged", function(s, user)
    ph:SetShown(s:GetText() == "")
    if user then ST.query = s:GetText(); B:Fill() end
  end)
  search:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
  search:SetScript("OnEscapePressed", function(s) s:SetText(""); ST.query = ""; s:ClearFocus(); B:Fill() end)
  local function searchColor() local c = T:Get().text; search:SetTextColor(c[1], c[2], c[3]) end
  searchColor(); T:OnChange(searchColor)
  page.search = search

  -- left: categories
  local cats = CreateFrame("Frame", nil, page)
  cats:SetPoint("TOPLEFT", 0, -34); cats:SetPoint("BOTTOMLEFT")
  cats:SetWidth(CAT_W)
  T:Skin(cats, "panel", "border")
  page.cats = {}
  for i, c in ipairs(CATS) do
    local b = T:Button(cats, c.text or c.key, 12, function() ST.cat, ST.query = c.key, ""; page.search:SetText(""); B:Fill() end)
    b:SetSize(CAT_W - 2, 28)
    b:SetPoint("TOPLEFT", 1, -4 - (i - 1) * 29)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 8, 0)
    b.icon:SetTexture(c.icon); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 32, 0)
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
    b.cat = c.key
    page.cats[#page.cats + 1] = b
  end
  local trainer = small(cats, "Trainer skills", CAT_W - 16, function() if CM.Trainer then CM.Trainer:Show() end end)
  trainer:SetPoint("BOTTOMLEFT", 8, 8)

  -- middle: list
  local lp = CreateFrame("Frame", nil, page)
  lp:SetPoint("TOPLEFT", cats, "TOPRIGHT", 8, 0); lp:SetPoint("BOTTOMLEFT", cats, "BOTTOMRIGHT", 8, 0)
  lp:SetWidth(LIST_W)
  T:Skin(lp, "panel", "border")
  local list = scroll(lp)
  list:SetPoint("TOPLEFT", 4, -4); list:SetPoint("BOTTOMRIGHT", -4, 4)
  list.child:SetWidth(LIST_W - 8)
  list.rows = {}
  page.list = list
  page.hint = T:Text(page, 10, "muted")

  -- right: detail
  local dp = CreateFrame("Frame", nil, page)
  dp:SetPoint("TOPLEFT", lp, "TOPRIGHT", 8, 0); dp:SetPoint("BOTTOMRIGHT")
  T:Skin(dp, "panel", "border")
  page.detail = dp
  dp.banner = CM.Visuals:BuildBanner(dp)
  dp.banner:SetPoint("TOPLEFT", 1, -1); dp.banner:SetPoint("TOPRIGHT", -1, -1)
  dp.banner:SetHeight(84)
  dp.banner.iconFrame:SetSize(46, 46)
  T:Font(dp.banner.title, 15, "heading")
  dp.banner.sub:SetWordWrap(true)
  dp.prog = T:Text(dp, 11, "muted")
  dp.prog:SetPoint("TOPLEFT", dp.banner, "BOTTOMLEFT", 10, -10)
  dp.bar = T:Bar(dp, 6)
  dp.bar:SetPoint("TOPLEFT", dp.prog, "BOTTOMLEFT", 0, -5)
  dp.bar:SetPoint("RIGHT", -10, 0)
  local body2 = scroll(dp)
  body2:SetPoint("TOPLEFT", dp.bar, "BOTTOMLEFT", 0, -10)
  body2:SetPoint("BOTTOMRIGHT", -8, 70)
  dp.text = T:Text(body2.child, 12, "text")
  dp.text:SetPoint("TOPLEFT")
  dp.text:SetJustifyV("TOP")
  dp.text:SetSpacing(3)
  dp.scroll = body2
  dp.primary = T:Button(dp, "", 13, nil)
  dp.primary.primary = true
  dp.primary:SetHeight(28)
  dp.primary:SetPoint("BOTTOMLEFT", 10, 38); dp.primary:SetPoint("BOTTOMRIGHT", -10, 38)
  dp.primary.text:ClearAllPoints(); dp.primary.text:SetPoint("CENTER")
  T:PaintButton(dp.primary)
  dp.second = small(dp, "", 116, nil)
  dp.second:SetPoint("BOTTOMLEFT", 10, 10)
  dp.star = small(dp, "", 80, nil)
  dp.star:SetPoint("BOTTOMRIGHT", -10, 10)
  return page
end

local STAR_ON = "|TInterface\\COMMON\\FavoritesIcon:14|t"
local STAR_OFF = "|TInterface\\COMMON\\FavoritesIcon:14:14:0:0:32:32:0:32:0:32:90:90:90|t"

local function row(list, i)
  local r = list.rows[i]
  if r then return r end
  local w = LIST_W - 14
  r = T:Button(list.child, "", 13, nil)
  r:SetSize(w, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 1))
  r.lv = T:Text(r, 12, "muted")
  r.lv:SetPoint("LEFT", 6, 0); r.lv:SetWidth(44)
  r.text:ClearAllPoints(); r.text:SetPoint("LEFT", 52, 0); r.text:SetWidth(132); r.text:SetWordWrap(false)
  r.prog = T:Text(r, 10, "muted")
  r.prog:SetPoint("RIGHT", -90, 0); r.prog:SetJustifyH("RIGHT")
  r.bar = T:Bar(r, 5)
  r.bar:SetSize(60, 5); r.bar:SetPoint("RIGHT", -24, 0)
  r.star = CreateFrame("Button", nil, r)
  r.star:SetSize(18, 18); r.star:SetPoint("RIGHT", -3, 0)
  r.star.text = T:Text(r.star, 12, "muted")
  r.star.text:SetPoint("CENTER")
  r.head = T:Text(r, 11, "heading")
  r.head:SetPoint("BOTTOMLEFT", 4, 3)
  r.line = r:CreateTexture(nil, "ARTWORK")
  r.line:SetHeight(1)
  r.line:SetPoint("LEFT", r.head, "RIGHT", 8, 0); r.line:SetPoint("RIGHT", -4, 0)
  r.line:SetTexture("Interface\\Buttons\\WHITE8x8")
  list.rows[i] = r
  return r
end

function B:Fill()
  local page = self.page
  if not page or not page:IsShown() then return end
  local items, all = self:Items()
  for _, b in ipairs(page.views) do
    b.selected = not ST.cat and (ST.query or "") == "" and ST.view == b.view
    T:PaintButton(b)
  end
  for _, b in ipairs(page.cats) do b.selected = ST.cat == b.cat and (ST.query or "") == ""; T:PaintButton(b) end
  local p = T:Get()
  local list = page.list
  for _, r in ipairs(list.rows) do r:Hide() end
  local first
  for i, it in ipairs(items) do
    local r = row(list, i)
    local isHead = it.header ~= nil
    r.head:SetShown(isHead); r.line:SetShown(isHead)
    r.lv:SetShown(not isHead); r.text:SetShown(not isHead); r.star:SetShown(not isHead)
    r:EnableMouse(not isHead)
    if isHead then
      r.head:SetText(it.header)
      r.line:SetVertexColor(p.border[1], p.border[2], p.border[3], 1)
      r.prog:Hide(); r.bar:Hide()
      r.selected = false
    else
      first = first or it
      r.lv:SetText(it.lo and (it.lo == it.hi and tostring(it.lo) or string.format("%d-%d", it.lo, it.hi)) or "")
      local col = ""
      if it.lo and it.hi then
        if lvl() > it.hi then col = "|cff808080" elseif lvl() < it.lo - 1 then col = "|cffff8040" end
      end
      r.text:SetText(col .. it.name .. (col ~= "" and "|r" or ""))
      local done, total = self:Progress(it)
      local frac = total > 0 and done / total or 0
      r.prog:SetText(total > 0 and string.format("%d/%d", done, total) or ""); r.prog:SetShown(total > 0)
      r.bar:SetShown(total > 0); r.bar:SetValue(frac)
      r.star.text:SetText(favs()[it.key] and STAR_ON or STAR_OFF)
      r.star:SetAlpha(favs()[it.key] and 1 or 0.45)
      r.star:SetScript("OnClick", function() favs()[it.key] = not favs()[it.key] or nil; B:Fill() end)
      r.selected = ST.sel == it.key
      r:SetScript("OnClick", function() ST.sel = it.key; remember(it.key); B:Fill() end)
    end
    T:PaintButton(r)
    r:Show()
  end
  list.child:SetHeight(math.max(10, #items * (ROW_H + 1)))
  if not (ST.sel and all[ST.sel]) then ST.sel = first and first.key end
  self:Detail(ST.sel and all[ST.sel])
end

-- Detail pane ----------------------------------------------------------------------------------------
local function lines(t) return table.concat(t, "\n") end

function B:Detail(it)
  local dp = self.page.detail
  local SG, V = CM.SmartGuide, CM.Visuals
  dp.primary:Hide(); dp.second:Hide(); dp.star:Hide()
  dp.bar:Hide(); dp.prog:SetText("")
  if not it then
    dp.banner:Set(I .. "INV_Misc_Book_09", "Guides", "Pick a guide on the left", nil)
    dp.text:SetText("")
    return
  end
  local out, sub, map = {}, "", nil
  local primary, second
  if it.kind == "zone" then
    sub = string.format("Levels %d-%d   ·   %s", it.lo or 1, it.hi or 60, it.cont or "")
    map = V:MapID(it.name)
    local level = lvl()
    local now = 0
    for _, z in ipairs(SG:ZoneChoices()) do if z.name == it.name then now = z.count end end
    if level < (it.lo or 1) - 1 then out[#out + 1] = string.format("|cffff8040You're a bit low for this zone (level %d).|r", level)
    elseif level > (it.hi or 60) then out[#out + 1] = "|cff808080You've outlevelled this zone; quests here give little XP.|r"
    else out[#out + 1] = string.format("|cff66ff66A good fit for your level (%d).|r", level) end
    out[#out + 1] = string.format("%d quests you can pick up here right now.", now)
    if SG:RecommendedZone() == it.name then out[#out + 1] = "|cffffd100This is the best zone for you now.|r" end
    local inRoute = false
    for _, n in ipairs(SG:Roster()) do if n == it.name then inRoute = true end end
    out[#out + 1] = ""
    out[#out + 1] = "Quest here sends the Smart Guide and arrow to this zone's quests. Add it to your route to string zones together on the Leveling guide page."
    primary = { "Quest here", function()
      local id = V:MapID(it.name)
      if id then SG:LockZone(id); CM:Print("Smart Guide: questing in %s.", it.name) end
      if CM.GuideWindow then CM.GuideWindow:Show() end
      B:Fill()
    end }
    second = { inRoute and "In your route" or "Add to my route", function() SG:RosterAdd(it.name); B:Fill() end }
  elseif it.kind == "dungeon" then
    local d = it.data
    sub = string.format("Level %s   ·   %s", d.levels or "?", d.zone or "")
    map = V:MapID(it.name)
    if it.new then out[#out + 1] = "|cff66ccffNew in WoW Forever.|r" end
    out[#out + 1] = "|cffffd100Bosses|r"
    for _, b in ipairs(d.bosses or {}) do out[#out + 1] = "  " .. b end
    if d.tips then
      out[#out + 1] = ""; out[#out + 1] = "|cffffd100Tips|r"
      for _, t in ipairs(d.tips) do out[#out + 1] = "  " .. t end
    end
    primary = { "Open in the dungeon journal", function() B:OpenJournal(it.name, false) end }
    if CM.QData:Has() and CM.QData:DungeonEntrance(it.name) then
      second = { "Arrow to entrance", function()
        local m, x, y = CM.QData:DungeonEntrance(it.name)
        CM.Arrow:Point(m, x, y, it.name .. " entrance", 900)
      end }
    end
  elseif it.kind == "raid" then
    sub = "Raid   ·   level 60"
    if it.note then out[#out + 1] = it.note end
    local d = it.data
    for _, t in ipairs(d and d.tips or {}) do out[#out + 1] = "  " .. t end
    if it.inst then primary = { "Open in the dungeon journal", function() B:OpenJournal(it.name, true) end } end
  elseif it.kind == "prof" or it.kind == "gold" or it.kind == "tip" then
    sub = ({ prof = "Profession guide", gold = "Gold making", tip = "Leveling tips" })[it.kind]
    for _, l in ipairs(it.data.lines or {}) do out[#out + 1] = l end
    if it.kind == "prof" then primary = { "See crafting profits", function() CM.UI:Show("Crafting") end } end
    if it.kind == "gold" then primary = { "Open auction prices", function() CM.UI:Show("Market") end } end
  elseif it.kind == "guide" then
    local g = it.data
    sub = string.format("%s   ·   levels %s   ·   %d steps", g.faction or "Both factions", g.levels or "?", #g.steps)
    for i, st in ipairs(g.steps) do
      if i > 60 then out[#out + 1] = "..."; break end
      out[#out + 1] = string.format("|cff808080%d.|r %s", i, CM.Guides:StepTitle(st))
    end
    primary = { "Load this guide", function() CM.Guides:Load(g.name); B:Fill() end }
  elseif it.kind == "trainer" then
    local Tr = CM.Trainer
    sub = "Spells you can learn now"
    local list = Tr:Available()
    if not Tr:HasData() then
      out[#out + 1] = "Visit your class trainer once and I'll remember what they teach and what it costs."
    end
    local total = 0
    for _, g in ipairs(list) do
      total = total + g.cost
      local ranks = g.lo and (g.lo == g.hi and (" rank " .. g.lo) or string.format(" ranks %d-%d", g.lo, g.hi)) or ""
      out[#out + 1] = string.format("%s%s   %s", g.name, ranks, CM:Money(g.cost))
    end
    if #list > 0 then out[#out + 1] = ""; out[#out + 1] = "Total: " .. CM:Money(total) end
    primary = { "Arrow to my trainer", function() Tr:ArrowToTrainer() end }
    second = { "Trainer card", function() Tr:Show() end }
  end
  dp.banner:Set(it.icon, it.name, sub, map or CM.UI.PageMap and CM.UI.PageMap(it.kind == "prof" and "Professions" or it.kind == "gold" and "Gold" or "Guides"))
  local done, total = self:Progress(it)
  if total > 0 then
    dp.prog:SetText(string.format("Progress:  %s", CM.Progress:Label(done, total)))
    dp.bar:SetValue(done / total); dp.bar:Show()
  end
  local w = dp.scroll:GetWidth()
  if not w or w <= 0 then w = 220 end
  dp.text:SetWidth(w - 6)
  dp.scroll.child:SetWidth(w)
  dp.text:SetText(T:Recolor(lines(out)))
  dp.scroll.child:SetHeight(dp.text:GetStringHeight() + 10)
  dp.scroll:SetVerticalScroll(0)
  if primary then
    dp.primary.text:SetText(primary[1]); dp.primary:SetScript("OnClick", primary[2]); dp.primary:Show()
  end
  if second then
    dp.second.text:SetText(second[1]); dp.second:SetScript("OnClick", second[2]); dp.second:Show()
  end
  local fav = favs()[it.key]
  dp.star.text:SetText(fav and (STAR_ON .. " Favorite") or "Favorite")
  dp.star:SetScript("OnClick", function() favs()[it.key] = not fav or nil; B:Fill() end)
  dp.star:Show()
end

-- Jump to the journal page for a dungeon or raid
function B:OpenJournal(name, raid)
  local J = CM.Journal
  CM.UI:Show("Dungeons")
  C_Timer.After(0.05, function()
    J.raids = raid and true or false
    if J.page and J.page.kind then J.page.kind.text:SetText(raid and "Raids" or "Dungeons") end
    local want = name:lower():gsub("^the ", "")
    for _, inst in ipairs(J:Instances(raid)) do
      if inst.name:lower():gsub("^the ", "") == want then J:Open(inst) return end
    end
    J:Open(nil)
  end)
end

-- keep progress bars honest as you hand quests in
CM:On("QUEST_TURNED_IN", function()
  C_Timer.After(1, function() if B.page and B.page:IsShown() then B:Fill() end end)
end)
