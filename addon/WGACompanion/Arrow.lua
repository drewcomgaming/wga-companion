-- WGA Companion: waypoint arrow + built-in map pin.
-- Positions are converted to world yards so the arrow works across zone borders
-- on the same continent.
local _, CM = ...
local A = CM:NewModule("Arrow")

local ARRIVE_YARDS = 10
local target, temp, auto -- { m, x, y, title }  temp = { ..., expires }; auto = quest arrow (lowest priority)

local function worldPos(mapID, x, y)
  local cont, w = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
  if not cont or not w then return nil end
  return cont, w.x, w.y
end

-- Unit vectors (in world space) for "east" and "south" on a given map.
local axisCache = {}
local function axes(mapID)
  local a = axisCache[mapID]
  if a then return a end
  local c0, x0, y0 = worldPos(mapID, 0, 0)
  local _, x1, y1 = worldPos(mapID, 1, 0)
  local _, x2, y2 = worldPos(mapID, 0, 1)
  if not c0 or not x1 or not x2 then return nil end
  local ex, ey = x1 - x0, y1 - y0
  local sx, sy = x2 - x0, y2 - y0
  local el, sl = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
  if el == 0 or sl == 0 then return nil end
  a = { ex / el, ey / el, sx / sl, sy / sl }
  axisCache[mapID] = a
  return a
end

A.WorldPos, A.Axes = worldPos, axes

-- Returns distance (yards), clockwise bearing from north (radians), or nil + reason
function A:Compute(t)
  local pm = C_Map.GetBestMapForUnit("player")
  local pp = pm and C_Map.GetPlayerMapPosition(pm, "player")
  if not pp then return nil, "no position here" end
  local px, py = pp:GetXY()
  local pc, wpx, wpy = worldPos(pm, px, py)
  local tc, wtx, wty = worldPos(t.m, t.x, t.y)
  if not pc or not tc then return nil, "unknown map" end
  if pc ~= tc then return nil, "on another continent" end
  local ax = axes(pm)
  if not ax then return nil, "unknown map" end
  local dx, dy = wtx - wpx, wty - wpy
  local east = dx * ax[1] + dy * ax[2]
  local south = dx * ax[3] + dy * ax[4]
  -- axes are unit vectors in world yards, so this is yards
  return math.sqrt(east * east + south * south), math.atan2(east, -south)
end

function A:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionArrow", UIParent)
  f:SetSize(72, 72)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f.ring = f:CreateTexture(nil, "BACKGROUND")
  f.ring:SetAllPoints()
  f.ring:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\ring")
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetSize(50, 50)
  f.tex:SetPoint("CENTER")
  f.tex:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\arrow") -- grey, points up; tinted and rotated below
  f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.dist:SetPoint("TOP", f, "BOTTOM", 0, -3)
  f.dist:SetShadowOffset(1, -1)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.title:SetPoint("TOP", f.dist, "BOTTOM", 0, -3)
  f.title:SetWidth(260)
  f.title:SetSpacing(2)
  f.title:SetShadowOffset(1, -1)
  f:SetScript("OnDragStart", function(self) self.dragging = true; self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); C_Timer.After(0, function() self.dragging = false; A:UpdateHearth() end) end)
  f:SetScript("OnMouseUp", function(self, button)
    if self.dragging then return end
    if button == "RightButton" then A:SetTarget(nil); temp = nil; if not auto then f:Hide() end
    elseif button == "LeftButton" and A:Active() == auto and CM.QuestNav then CM.QuestNav:Next() end
  end)
  local elapsed = 0
  f:SetScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 0.05 then return end
    elapsed = 0
    A:Tick()
  end)
  f:Hide()
  self.frame = f
end

-- Dead and released: the arrow points to your body, whatever else it was doing
local corpse
local function corpseTarget()
  if not (UnitIsGhost and UnitIsGhost("player")) then corpse = nil return nil end
  if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil end
  local m = C_Map.GetBestMapForUnit("player")
  for _ = 1, 4 do
    if not m then break end
    local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, m)
    if ok and pos then
      local x, y = pos:GetXY()
      if x and x > 0 then
        corpse = corpse or {}
        corpse.m, corpse.x, corpse.y, corpse.title = m, x, y, "Your body"
        return corpse
      end
    end
    local info = C_Map.GetMapInfo(m)
    m = info and info.parentMapID
  end
  return corpse   -- keep the last known spot (e.g. after you zone while running back)
end

-- City gates, learned as you walk in and out of the capitals. When you and the target are on
-- different sides of a city wall, the arrow takes you to the nearest gate first.
local CITY = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
A.CITY = CITY
local function zoneOf(m)
  local SG = CM.SmartGuide
  return SG and SG.ZoneOf and SG.ZoneOf(m) or m
end
local function gates()
  CM.db.global.gates = CM.db.global.gates or {}
  return CM.db.global.gates
end
local function dist2(c1, x1, y1, c2, x2, y2)
  if not c1 or c1 ~= c2 then return nil end
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

-- Ticker: notice when you walk (not teleport) across a city border and remember where
local last
function A:LearnGate()
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if not p or (UnitOnTaxi and UnitOnTaxi("player")) or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then last = nil return end
  local x, y = p:GetXY()
  local c, wx, wy = worldPos(m, x, y)
  local z = zoneOf(m)
  if last and last.z ~= z and (CITY[z] or CITY[last.z]) then
    local d = dist2(c, wx, wy, last.c, last.wx, last.wy)
    if d and d < 60 then                      -- walked across, not a hearth or portal
      local city = CITY[z] and z or last.z
      local list = gates()[city] or {}
      gates()[city] = list
      local dup
      for _, g in ipairs(list) do
        local gc, gx, gy = worldPos(g[1], g[2], g[3])
        local dd = dist2(c, wx, wy, gc, gx, gy)
        if dd and dd < 50 then dup = true break end
      end
      if not dup and #list < 12 then list[#list + 1] = { m, x, y } end
    end
  end
  last = { z = z, c = c, wx = wx, wy = wy }
end

-- Where the arrow should actually point for target t: t itself, or a city gate on the way
function A:Via(t)
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if not p or not t or not t.m then return t end
  local pz, tz = zoneOf(m), zoneOf(t.m)
  if pz == tz then return t end
  local city = (CITY[pz] and pz) or (CITY[tz] and tz)
  local list = city and gates()[city]
  if not list or #list == 0 then return t end
  local x, y = p:GetXY()
  local pc, px, py = worldPos(m, x, y)
  local tc, tx, ty = worldPos(t.m, t.x, t.y)
  if not pc or pc ~= tc then return t end
  local best, bd
  for _, g in ipairs(list) do
    local gc, gx, gy = worldPos(g[1], g[2], g[3])
    local a, b = dist2(pc, px, py, gc, gx, gy), dist2(gc, gx, gy, tc, tx, ty)
    if a and b and (not bd or a + b < bd) then best, bd = g, a + b end
  end
  if not best then return t end
  local gc, gx, gy = worldPos(best[1], best[2], best[3])
  if dist2(pc, px, py, gc, gx, gy) < 15 then return t end   -- at the gate: go on
  return { m = best[1], x = best[2], y = best[3], title = (t.title or "") .. "\n|cff9d9d9d(via the city gate)|r", via = t }
end

function A:Active()
  local c = corpseTarget()
  if c then return c end
  if temp and GetTime() > temp.expires then temp = nil end
  return temp or target or auto
end

function A:Tick()
  local f, goal = self.frame, self:Active()
  if not goal then f:Hide(); return end
  local t = goal == corpse and goal or self:Via(goal)
  f.title:SetText(t.title or "")
  local dist, bearing = self:Compute(t)
  if not dist then
    f.dist:SetText("|cff808080" .. tostring(bearing) .. "|r")
    f.tex:SetAlpha(0.3)
    return
  end
  f.tex:SetAlpha(1)
  f.dist:SetText(dist < ARRIVE_YARDS and "|cff40ff40You're here|r" or string.format("%d yd", dist))
  local facing = CM:Safe(GetPlayerFacing())
  if facing then
    local rel = bearing + facing           -- clockwise angle from where you face
    f.tex:SetRotation(-rel)                 -- texture points up, SetRotation is counter-clockwise
    -- colour fades green (ahead) -> yellow (side) -> red (behind)
    local off = math.abs(((rel + math.pi) % (2 * math.pi)) - math.pi) / math.pi -- 0 ahead, 1 behind
    if off < 0.5 then f.tex:SetVertexColor(0.2 + off * 1.6, 1, 0.2)
    else f.tex:SetVertexColor(1, 1 - (off - 0.5) * 1.6, 0.15) end
  end
  if dist < ARRIVE_YARDS then
    if t == temp then temp = nil
    elseif t == target and CM.Guides then CM.Guides:OnArrive() end
  end
end

local function setMapPin(t)
  if not C_Map.SetUserWaypoint or not UiMapPoint then return end
  if not t then if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end return end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(t.m) then return end
  local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(t.m, t.x, t.y))
  return ok
end

-- Guide target (persistent). x, y are 0-1 map fractions.
function A:SetTarget(m, x, y, title)
  self:Build()
  if not m then
    if target then setMapPin(nil) end
    target = nil
  else
    target = { m = m, x = x, y = y, title = title }
    setMapPin(target)
  end
  if CM.db and CM.db.settings.arrow == false then self.frame:Hide() return end
  self.frame:SetShown(self:Active() ~= nil)
end

-- Temporary target (e.g. a rare), returns to the guide target after `seconds`.
function A:Point(m, x, y, title, seconds)
  self:Build()
  temp = { m = m, x = x, y = y, title = "|cffff8000" .. (title or "") .. "|r", expires = GetTime() + (seconds or 60) }
  if CM.db.settings.arrow ~= false then self.frame:Show() end
end

function A:ClearTemp()
  temp = nil
  if self.frame and not self:Active() then self.frame:Hide() end
end

function A:Toggle()
  self:Build()
  CM.db.settings.arrow = CM.db.settings.arrow == false
  CM:Print("Arrow %s.", CM.db.settings.arrow and "on" or "off")
  self.frame:SetShown(CM.db.settings.arrow and self:Active() ~= nil)
end

-- Quest arrow target from QuestNav; shown only when there is no guide or temporary target.
function A:SetAuto(m, x, y, title)
  self:Build()
  if m then
    if not auto then auto = {} end
    auto.m, auto.x, auto.y, auto.title = m, x, y, title
  else
    auto = nil
  end
  if CM.db and CM.db.settings.arrow == false then self.frame:Hide() return end
  self.frame:SetShown(self:Active() ~= nil)
end

function A:ResetPosition()
  self:Build()
  self.frame:ClearAllPoints()
  self.frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  self.frame:SetShown(self:Active() ~= nil)
  CM:Print("Arrow moved back to the top of the screen.")
end

-- Death: show the arrow to your body as soon as you release, and go back to normal when alive
local function deathUpdate()
  A:Build()
  if CM.db and CM.db.settings.arrow == false then return end
  A.frame:SetShown(A:Active() ~= nil)
end
for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CORPSE_POSITION_UPDATE" }) do
  CM:On(e, function() C_Timer.After(0.5, deathUpdate) end)
end

function A:OnLogin()
  C_Timer.NewTicker(1, function() A:LearnGate() end)
  A:BuildHearth()
  if CM.GuideWindow and CM.GuideWindow.Hide then hooksecurefunc(CM.GuideWindow, "Hide", function() A:UpdateHearth() end) end
  if UnitIsGhost and UnitIsGhost("player") then C_Timer.After(2, deathUpdate) end
end

-- Hearth button under the arrow -------------------------------------------------------------------
-- When the guide says hearthing saves time, a click on this button uses your hearthstone. Using an
-- item needs a secure button; it can only be shown, hidden or moved out of combat, and it sits on
-- UIParent (placed under the arrow) so the arrow itself stays free to change in combat.
function A:BuildHearth()
  if self.hearth or InCombatLockdown() then return end
  local b = CreateFrame("Button", "WGACompanionHearthButton", UIParent, "SecureActionButtonTemplate")
  b:SetSize(190, 26)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  local T = CM.Theme
  if T and T.Skin then T:Skin(b, "panel", "accent") end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 4, 0)
  b.icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.text:SetPoint("RIGHT", -6, 0)
  b.text:SetJustifyH("LEFT")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Use your Hearthstone")
    if self.tip then GameTooltip:AddLine(self.tip, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:Hide()
  self.hearth = b
end

function A:UpdateHearth()
  if InCombatLockdown() then self.hearthPending = true return end
  self:BuildHearth()
  local b = self.hearth
  if not b then return end
  local GW = CM.GuideWindow
  local tr = GW and GW.current and GW.current.travel
  local want = tr and (tr.kind == "hearth" or tr.kind == "hearthfly") and self.frame and self.frame:IsShown()
    and GW.frame and GW.frame:IsShown()
    and CM.db.settings.hearthButton ~= false
  if not want then b:Hide() return end
  local SG = CM.SmartGuide
  local id = SG and SG.HearthItem and SG:HearthItem() or 6948
  b:SetAttribute("item", "item:" .. id)
  local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if icon then b.icon:SetTexture(icon) end
  local label = (tr.text or "Hearth"):gsub(", saves", "  |cff66ff66saves")
  b.text:SetText(label .. "|r")
  b.tip = tr.text
  -- place it under the arrow's title, in screen coordinates
  local f = self.frame
  local x, y = f:GetCenter()
  local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local titleH = (f.title and f.title:GetStringHeight() or 12) + (f.dist and f.dist:GetStringHeight() or 16) + 12
  b:ClearAllPoints()
  if x and y then
    b:SetPoint("TOP", UIParent, "BOTTOMLEFT", x * scale, (y - f:GetHeight() / 2 - titleH) * scale)
  else
    b:SetPoint("TOP", UIParent, "TOP", 0, -260)
  end
  b:Show()
end

CM:On("PLAYER_REGEN_ENABLED", function()
  if A.hearthPending then A.hearthPending = nil; A:UpdateHearth() end
end)
CM:On("PLAYER_REGEN_DISABLED", function()
  if A.hearth and A.hearth:IsShown() then A.hearthPending = true end
end)
