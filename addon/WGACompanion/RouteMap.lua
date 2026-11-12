-- WGA Companion: the Smart Guide's route drawn on the world map. A dotted line runs from you through
-- the next steps in order, with a numbered marker on each stop (hover for what to do there).
local _, CM = ...
local RM = CM:NewModule("RouteMap")

local MAX_STEPS = 12
local DOT_GAP = 9       -- screen pixels between dots
local MAX_DOTS = 700
local COLORS = {
  accept = { 1, 0.82, 0.2 }, turnin = { 0.35, 1, 0.45 }, flight = { 0.55, 0.75, 1 },
  default = { 0.30, 0.80, 1 },
}

local layer, dots, marks = nil, {}, {}

local function S() return CM.db and CM.db.settings or {} end

-- A spot on another map (zone spot onto the continent map and back)
local function onMap(sm, x, y, mapID)
  if sm == mapID then return x, y end
  if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos) then return nil end
  local cont, w = C_Map.GetWorldPosFromMapPos(sm, CreateVector2D(x, y))
  if not cont or not w then return nil end
  local _, pos = C_Map.GetMapPosFromWorldPos(cont, w, mapID)
  if not pos then return nil end
  return pos.x, pos.y
end

local function inside(x, y) return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 end

local function dot(i)
  local d = dots[i]
  if not d then
    d = layer:CreateTexture(nil, "OVERLAY")
    d:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\node")
    dots[i] = d
  end
  return d
end

local function mark(i)
  local m = marks[i]
  if m then return m end
  m = CreateFrame("Frame", nil, layer)
  m.ring = m:CreateTexture(nil, "ARTWORK")
  m.ring:SetAllPoints()
  m.ring:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\node")
  m.num = m:CreateFontString(nil, "OVERLAY")
  m.num:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  m.num:SetPoint("CENTER", 0, 0)
  m:EnableMouse(true)
  m:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(string.format("Step %d", self.index or 0))
    if self.title then GameTooltip:AddLine(self.title, 1, 1, 1, true) end
    GameTooltip:AddLine("Click to point the arrow here", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  m:SetScript("OnLeave", function() GameTooltip:Hide() end)
  m:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and self.m and CM.Arrow then
      CM.Arrow:Point(self.m, self.x, self.y, (self.title or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), 600)
    end
  end)
  marks[i] = m
  return m
end

local function steps()
  local GW = CM.GuideWindow
  if not GW then return {} end
  if GW.steps and GW.frame and GW.frame:IsShown() then return GW.steps end
  -- guide window closed: work the route out ourselves, at most every few seconds
  local now = GetTime()
  if not RM.cache or now - RM.cacheAt > 5 then
    local ok, list = pcall(GW.Steps, GW)
    RM.cache, RM.cacheAt = ok and list or {}, now
  end
  return RM.cache
end

local function stepTitle(s)
  local t = s.title or (s.quest and CM.QData and CM.QData:Title(s.quest)) or ""
  local verb = ({ accept = "Accept", turnin = "Turn in", flight = "Get the flight path" })[s.kind or ""]
  return verb and (verb .. ": " .. t) or t
end

function RM:Draw()
  for _, d in ipairs(dots) do d:Hide() end
  for _, m in ipairs(marks) do m:Hide() end
  local wm = WorldMapFrame
  if S().routeLine == false or not wm or not wm:IsShown() then return end
  local mapID = wm.GetMapID and wm:GetMapID()
  local canvas = wm.GetCanvas and wm:GetCanvas()
  if not mapID or not canvas then return end
  if not layer then
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
  end
  layer:SetParent(canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(canvas:GetFrameLevel() + 1900)
  layer:Show()
  local w, h = canvas:GetSize()
  local cs = canvas:GetEffectiveScale()
  local unit = cs > 0 and UIParent:GetEffectiveScale() / cs or 1
  self.drawnScale = cs

  -- the points: you, then the next steps that show on this map
  local pts = {}
  local pp = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
  if pp then
    local x, y = pp:GetXY()
    if inside(x, y) then pts[1] = { x = x, y = y, me = true } end
  end
  local n = 0
  for _, s in ipairs(steps()) do
    if n >= MAX_STEPS then break end
    if s.m and s.x and s.y then
      n = n + 1
      local x, y = onMap(s.m, s.x, s.y, mapID)
      if inside(x, y) then
        pts[#pts + 1] = { x = x, y = y, step = s, index = n }
      else
        pts[#pts + 1] = { gap = true }  -- off this map: break the line here
      end
    end
  end

  local nd = 0
  local prev
  for _, p in ipairs(pts) do
    if p.gap then prev = nil
    else
      if prev and nd < MAX_DOTS then
        local x1, y1, x2, y2 = prev.x * w, prev.y * h, p.x * w, p.y * h
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local gap = DOT_GAP * unit
        local c = COLORS[p.step and p.step.kind or ""] or COLORS.default
        for k = 1, math.floor(len / gap) - 1 do
          if nd >= MAX_DOTS then break end
          nd = nd + 1
          local d = dot(nd)
          local t = k * gap / len
          d:SetSize(4 * unit, 4 * unit)
          d:SetVertexColor(c[1], c[2], c[3], 0.9)
          d:ClearAllPoints()
          d:SetPoint("CENTER", layer, "TOPLEFT", x1 + (x2 - x1) * t, -(y1 + (y2 - y1) * t))
          d:Show()
        end
      end
      prev = p
    end
  end

  local mi = 0
  for _, p in ipairs(pts) do
    if p.step then
      mi = mi + 1
      local m = mark(mi)
      local c = COLORS[p.step.kind or ""] or COLORS.default
      m:SetSize(16 * unit, 16 * unit)
      m.ring:SetVertexColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 0.95)
      m.num:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(7, math.floor(9 * unit + 0.5)), "OUTLINE")
      m.num:SetTextColor(c[1], c[2], c[3])
      m.num:SetText(p.index)
      m:ClearAllPoints()
      m:SetPoint("CENTER", layer, "TOPLEFT", p.x * w, -p.y * h)
      m:SetFrameLevel(layer:GetFrameLevel() + 2)
      m.index, m.title = p.index, stepTitle(p.step)
      m.m, m.x, m.y = p.step.m, p.step.x, p.step.y
      m:Show()
    end
  end
end

-- redraw soon (route changed), not on every refresh
function RM:Dirty()
  if self.pending then return end
  self.pending = true
  C_Timer.After(0.2, function()
    RM.pending = nil
    if WorldMapFrame and WorldMapFrame:IsShown() then RM:Draw() end
  end)
end

local function hook()
  local wm = WorldMapFrame
  if not wm or RM.hooked then return end
  RM.hooked = true
  wm:HookScript("OnShow", function() RM:Draw() end)
  if wm.OnMapChanged then hooksecurefunc(wm, "OnMapChanged", function() RM:Draw() end) end
  local elapsed = 0
  wm:HookScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 1 then return end   -- you move: keep the first leg fresh
    elapsed = 0
    RM:Draw()
  end)
end

CM:On("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then hook() end end)
function RM:OnLogin() hook() end
