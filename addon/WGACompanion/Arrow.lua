-- WGA Companion: waypoint arrow + built-in map pin.
-- Positions are converted to world yards so the arrow works across zone borders
-- on the same continent.
local _, CM = ...
local A = CM:NewModule("Arrow")

local ARRIVE_YARDS = 10
local target, temp -- { m, x, y, title }  temp = { ..., expires }

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
  f:SetSize(56, 56)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.tex:SetTexture("Interface\\Buttons\\UI-MicroStream-Green") -- points down; rotated below
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOP", f, "BOTTOM", 0, -2)
  f.title:SetWidth(240)
  f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -1)
  f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then A:SetTarget(nil); temp = nil; f:Hide() end end)
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

function A:Active()
  if temp and GetTime() > temp.expires then temp = nil end
  return temp or target
end

function A:Tick()
  local f, t = self.frame, self:Active()
  if not t then f:Hide(); return end
  f.title:SetText(t.title or "")
  local dist, bearing = self:Compute(t)
  if not dist then
    f.dist:SetText("|cff808080" .. tostring(bearing) .. "|r")
    f.tex:SetAlpha(0.3)
    return
  end
  f.tex:SetAlpha(1)
  f.dist:SetText(string.format("%d yd", dist))
  local facing = CM:Safe(GetPlayerFacing())
  if facing then
    local rel = bearing + facing           -- clockwise angle from where you face
    f.tex:SetRotation(math.pi - rel)        -- texture points down, SetRotation is counter-clockwise
    -- colour: green ahead, yellow to the side, red behind
    local off = math.abs(((rel + math.pi) % (2 * math.pi)) - math.pi)
    f.tex:SetTexture(off < 0.5 and "Interface\\Buttons\\UI-MicroStream-Green"
      or (off < 1.8 and "Interface\\Buttons\\UI-MicroStream-Yellow" or "Interface\\Buttons\\UI-MicroStream-Red"))
  end
  if dist < ARRIVE_YARDS then
    if t == temp then temp = nil
    elseif CM.Guides then CM.Guides:OnArrive() end
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

function A:Toggle()
  self:Build()
  CM.db.settings.arrow = CM.db.settings.arrow == false
  CM:Print("Arrow %s.", CM.db.settings.arrow and "on" or "off")
  self.frame:SetShown(CM.db.settings.arrow and self:Active() ~= nil)
end
