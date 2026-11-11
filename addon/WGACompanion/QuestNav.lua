-- WGA Companion: quest navigation (Questie/Zygor-style) without a bundled quest database.
--
--  * Quest arrow: when no guide step is active, the arrow points at your super-tracked quest
--    (click a quest in the objective tracker), or the closest one. Positions come from the
--    game's own quest map data (C_QuestLog.GetQuestsOnMap / GetNextWaypoint), then from
--    spots WGA has learned. Left-click the arrow to cycle to the next quest.
--  * Quest mob marks: a "!" over the nameplate of any mob you still need for a quest, read
--    from the game's own unit tooltip quest lines.
--  * Learned spots: wherever you see a quest mob, or an objective counts up, WGA remembers the
--    spot (account-wide). Those spots show as dots on the world map while the objective is open.
local _, CM = ...
local N = CM:NewModule("QuestNav")
local QL = C_QuestLog
local LT = Enum and Enum.TooltipDataLineType

local MAX_SPOTS = 40     -- per objective
local NEAR = 0.012       -- spots closer than this (map fraction) are merged
local MAX_PINS = 400

local function S(v) return CM:Safe(v) end

local function here()
  local m = C_Map.GetBestMapForUnit("player")
  local p = m and C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local x, y = p:GetXY()
  return m, x, y
end

local function spots() return CM.db.global.spots end

function N:OnInit()
  CM.db.global.spots = CM.db.global.spots or {}
end

-- Learned spots ------------------------------------------------------------------------
-- spots[questID][objectiveIndex] = { {mapID, x, y, seen}, ... }  (x, y as 0-1 fractions)
function N:AddSpot(questID, idx, m, x, y)
  if not questID or not idx then return end
  if not m then m, x, y = here() end
  if not m then return end
  local q = spots()[questID] or {}
  spots()[questID] = q
  local list = q[idx] or {}
  q[idx] = list
  for _, s in ipairs(list) do
    if s[1] == m and math.abs(s[2] - x) < NEAR and math.abs(s[3] - y) < NEAR then
      s[4] = (s[4] or 1) + 1
      return
    end
  end
  if #list >= MAX_SPOTS then table.remove(list, 1) end
  table.insert(list, { m, math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000, 1 })
  self.mapDirty = true
end

-- Objective progress: when a counter goes up, the thing you need is near you.
local lastCount = {} -- [questID] = { [idx] = numFulfilled }
local function scanProgress()
  if not CM.db then return end
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    local id = info and not info.isHeader and info.questID
    if id then
      local objs = QL.GetQuestObjectives(id)
      local prev = lastCount[id]
      local now = {}
      for idx, o in ipairs(objs or {}) do
        local n = S(o.numFulfilled) or 0
        now[idx] = n
        if prev and prev[idx] and n > prev[idx] and CM.loggedIn then N:AddSpot(id, idx) end
      end
      lastCount[id] = now
    end
  end
end

-- Quest log lookups -----------------------------------------------------------------------
local byTitle = {} -- quest title -> questID, for matching unit tooltip lines
local function rebuildTitles()
  wipe(byTitle)
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    if info and not info.isHeader and info.questID and info.title then byTitle[info.title] = info.questID end
  end
end

local function norm(s) return (s or ""):gsub("%d+%s*/%s*%d+", ""):gsub("[%p%s]", ""):lower() end

local function objectiveIndex(questID, text)
  local want = norm(text)
  if want == "" then return nil end
  for idx, o in ipairs(QL.GetQuestObjectives(questID) or {}) do
    local have = norm(o.text)
    if have ~= "" and (have == want or have:find(want, 1, true) or want:find(have, 1, true)) then return idx end
  end
end

-- Reads the game's own quest lines from a unit's tooltip.
-- Returns a list of { quest = id, idx = objective, text = line } still needed.
function N:UnitNeeds(unit)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit and LT and LT.QuestObjective) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
  if not ok or not data or not data.lines then return nil end
  local out, quest
  for _, line in ipairs(data.lines) do
    local t, text = S(line.type), S(line.leftText)
    if t == LT.QuestTitle and text then
      quest = byTitle[text]
    elseif t == LT.QuestObjective and text and not S(line.completed) then
      out = out or {}
      table.insert(out, { quest = quest, idx = quest and objectiveIndex(quest, text), text = text })
    end
  end
  return out
end

-- Nameplate marks ---------------------------------------------------------------------------
local marks = {} -- unit token -> frame

local function markFor(unit)
  local f = marks[unit]
  if not f then
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(22, 22)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f.tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    marks[unit] = f
  end
  return f
end

local function updatePlate(unit)
  local f = marks[unit]
  if CM.db.settings.questPlates == false then if f then f:Hide() end return end
  local needs = N:UnitNeeds(unit)
  if not needs then if f then f:Hide() end return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then if f then f:Hide() end return end
  f = markFor(unit)
  f:ClearAllPoints()
  if not pcall(f.SetPoint, f, "BOTTOM", plate, "TOP", 0, -4) then f:Hide() return end
  f:Show()
  for _, n in ipairs(needs) do if n.quest and n.idx then N:AddSpot(n.quest, n.idx) end end
end

local function refreshPlates()
  for unit, f in pairs(marks) do f:Hide() end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then updatePlate(unit) end
  end
end

CM:On("NAME_PLATE_UNIT_ADDED", function(_, unit) if CM.db then updatePlate(unit) end end)
CM:On("NAME_PLATE_UNIT_REMOVED", function(_, unit) if marks[unit] then marks[unit]:Hide() end end)

-- Targets and mouseovers teach spots too (works with nameplates turned off).
local function learnFrom(unit)
  if not CM.db or not UnitExists(unit) or UnitIsPlayer(unit) then return end
  for _, n in ipairs(N:UnitNeeds(unit) or {}) do if n.quest and n.idx then N:AddSpot(n.quest, n.idx) end end
end
CM:On("PLAYER_TARGET_CHANGED", function() learnFrom("target") end)
CM:On("UPDATE_MOUSEOVER_UNIT", function() learnFrom("mouseover") end)

-- Quest arrow ----------------------------------------------------------------------------------
local function questTitle(id)
  local t = QL.GetTitleForQuestID(id) or ("Quest " .. id)
  return "|cffffd100" .. t .. "|r"
end

local function nextObjective(id)
  for idx, o in ipairs(QL.GetQuestObjectives(id) or {}) do
    if not o.finished and o.text and o.text ~= "" then return idx, o.text end
  end
end

local function readyForTurnIn(id)
  return QL.ReadyForTurnIn and QL.ReadyForTurnIn(id) or QL.IsComplete(id)
end

-- Distance (map fraction, rough) from the player to the nearest learned spot on this map.
local function nearestSpot(id, onlyIdx)
  local pm, px, py = here()
  if not pm then return nil end
  local best, bd
  local objs = QL.GetQuestObjectives(id) or {}
  for idx, list in pairs(spots()[id] or {}) do
    if (not onlyIdx or idx == onlyIdx) and not (objs[idx] and objs[idx].finished) then
      for _, s in ipairs(list) do
        if s[1] == pm then
          local d = (s[2] - px) ^ 2 + (s[3] - py) ^ 2
          if not bd or d < bd then best, bd = s, d end
        end
      end
    end
  end
  return best, bd
end

-- Where to go for a quest: m, x, y (0-1), sourceLabel
function N:Location(id)
  local pm, px, py = here()
  local QD = CM.QData
  if readyForTurnIn(id) then
    if QD:Has() then
      local m, x, y, who = QD:Nearest(QD:Finishers(id), pm, px, py)
      if m then return m, x, y, "quest database", who end
    end
    local q = CM.QuestDB and CM.QuestDB:Get(id)
    if q and q.t then return q.t[1], q.t[2] / 100, q.t[3] / 100, "turn in" end
  else
    local idx = nextObjective(id)
    if QD:Has() and idx then
      local m, x, y, who = QD:Nearest(QD:ObjectiveEntities(id, idx), pm, px, py)
      if m then return m, x, y, "quest database", who end
    end
    local s = nearestSpot(id, idx) or nearestSpot(id)
    if s then return s[1], s[2], s[3], "learned spot" end
  end
  if pm and QL.GetQuestsOnMap then
    for _, info in ipairs(QL.GetQuestsOnMap(pm) or {}) do
      if info.questID == id and info.x and info.y then return pm, info.x, info.y, "quest map" end
    end
  end
  if QL.GetNextWaypoint then
    local m, x, y = QL.GetNextWaypoint(id)
    if m and x and y then return m, x, y, "waypoint" end
  end
end

-- Quests in the log, closest first
function N:Candidates()
  local list = {}
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    if info and not info.isHeader and not info.isHidden and info.questID then
      local m, x, y = self:Location(info.questID)
      if m then
        local d = QL.GetDistanceSqToQuest and S(QL.GetDistanceSqToQuest(info.questID))
        if not d then
          local dist = CM.Arrow and CM.Arrow:Compute({ m = m, x = x, y = y })
          d = dist and dist * dist or math.huge
        end
        table.insert(list, { id = info.questID, d = d })
      end
    end
  end
  table.sort(list, function(a, b) return a.d < b.d end)
  return list
end

function N:Pick()
  local st = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
  if st and st ~= 0 and QL.IsOnQuest(st) and self:Location(st) then return st end
  local c = self:Candidates()[1]
  return c and c.id
end

function N:UpdateArrow()
  if not CM.db or not CM.Arrow then return end
  if CM.db.settings.questArrow == false then CM.Arrow:SetAuto(nil) return end
  local id = self:Pick()
  if not id then CM.Arrow:SetAuto(nil) return end
  local m, x, y, _, who = self:Location(id)
  local title = questTitle(id)
  if readyForTurnIn(id) then
    title = title .. "\n|cff40ff40Turn in" .. (who and (" to " .. who) or "") .. "|r"
  else
    local _, text = nextObjective(id)
    if text then title = title .. "\n" .. text end
    if who and not (text and text:lower():find(who:lower(), 1, true)) then title = title .. "\n|cffaaaaaa" .. who .. "|r" end
  end
  CM.Arrow:SetAuto(m, x, y, title)
  self.current = id
end

-- Left-click on the arrow: super-track the next closest quest.
function N:Next()
  local list = self:Candidates()
  if #list == 0 then return end
  local pos = 0
  for i, c in ipairs(list) do if c.id == self.current then pos = i end end
  local nxt = list[pos % #list + 1].id
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, nxt) end
  self.current = nxt
  self:UpdateArrow()
  CM:Print("Arrow: %s", questTitle(nxt))
end

-- World map dots ---------------------------------------------------------------------------------
local pins = {}

local function newPin(canvas)
  local p = CreateFrame("Frame", nil, canvas)
  p.glow = p:CreateTexture(nil, "BACKGROUND")
  p.glow:SetPoint("CENTER")
  p.glow:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\ring")
  p.tex = p:CreateTexture(nil, "OVERLAY")
  p.tex:SetAllPoints()
  p:EnableMouse(true)
  p:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.title or "")
    if self.text then GameTooltip:AddLine(self.text, 1, 1, 1, true) end
    if (self.count or 1) > 1 then GameTooltip:AddLine(self.count .. " spawns around here", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Click to point the arrow here", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and self.m and CM.Arrow then
      CM.Arrow:Point(self.m, self.x, self.y, (self.title or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), 600)
    end
  end)
  table.insert(pins, p)
  return p
end

-- Converts a spot to fractions on another map (e.g. zone spot onto the continent map).
local function onMap(sm, x, y, mapID)
  if sm == mapID then return x, y end
  if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos) then return nil end
  local cont, w = C_Map.GetWorldPosFromMapPos(sm, CreateVector2D(x, y))
  if not cont or not w then return nil end
  local _, pos = C_Map.GetMapPosFromWorldPos(cont, w, mapID)
  if not pos then return nil end
  return pos.x, pos.y
end

local ADDON_ICONS = "Interface\\AddOns\\WGACompanion\\Icons\\"
-- texture, tint (r, g, b), size in screen pixels
local STYLE = {
  slay    = { ADDON_ICONS .. "slay_mono", 1, 0.35, 0.3, 13 },
  loot    = { ADDON_ICONS .. "loot_mono", 1, 0.82, 0.2, 13 },
  object  = { ADDON_ICONS .. "object_mono", 0.4, 0.78, 1, 13 },
  learned = { ADDON_ICONS .. "node", 0.4, 1, 0.4, 10 },
  avail   = { "Interface\\GossipFrame\\AvailableQuestIcon", 1, 1, 1, 17 },
  turnin  = { "Interface\\GossipFrame\\ActiveQuestIcon", 1, 1, 1, 17 },
}
N.STYLE = STYLE

local function styleIcon(p, kind, size)
  local st = STYLE[kind] or STYLE.slay
  p:SetSize(st[5] * size, st[5] * size)
  p.tex:SetTexture(st[1])
  p.tex:SetVertexColor(st[2], st[3], st[4])
  p.glow:Hide()
end

-- Everything worth showing on one map: emit(x, y, kind, title, text), x/y as 0-1 fractions.
function N:Collect(mapID, emit)
  local QD = CM.QData
  -- quests in the log: objectives still open, or where to turn in
  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    local id = info and not info.isHeader and info.questID
    if id then
      if readyForTurnIn(id) then
        for _, e in ipairs(QD:Has() and QD:Finishers(id) or {}) do
          local sp = QD:Spawns(e[1], e[2])
          local list = sp and sp[mapID]
          for k = 1, list and #list or 0, 2 do emit(list[k], list[k + 1], "turnin", questTitle(id), "Turn in: " .. (QD:Name(e[1], e[2]) or "?")) end
        end
      else
        for idx, o in ipairs(QL.GetQuestObjectives(id) or {}) do
          if not o.finished then
            for _, e in ipairs(QD:Has() and QD:ObjectiveEntities(id, idx) or {}) do
              local sp = QD:Spawns(e[1], e[2])
              local list = sp and sp[mapID]
              for k = 1, list and #list or 0, 2 do
                emit(list[k], list[k + 1], e[3] or "slay", questTitle(id), (QD:Name(e[1], e[2]) or "") .. "\n" .. (o.text or ""))
              end
            end
            for _, s in ipairs((spots()[id] or {})[idx] or {}) do
              local x, y = onMap(s[1], s[2], s[3], mapID)
              if x then emit(x, y, "learned", questTitle(id), (o.text or "") .. "\n|cff808080Learned spot|r") end
            end
          end
        end
      end
    end
  end
  -- quests you can pick up
  if QD:Has() and CM.db.settings.questAvailable ~= false then
    for _, id in ipairs(QD:Available()) do
      for _, e in ipairs(QD:Starters(id)) do
        local sp = QD:Spawns(e[1], e[2])
        local list = sp and sp[mapID]
        for k = 1, list and #list or 0, 2 do
          emit(list[k], list[k + 1], "avail", string.format("|cffffd100%s|r (%d)", QD:Title(id) or "?", QD:Level(id) or 0),
            "Quest giver: " .. (QD:Name(e[1], e[2]) or "?"))
        end
      end
    end
  end
end

function N:DrawMap()
  for _, p in ipairs(pins) do p:Hide() end
  local wm = WorldMapFrame
  if not CM.db or CM.db.settings.questPins == false or not wm or not wm:IsShown() then return end
  local mapID = wm.GetMapID and wm:GetMapID()
  local canvas = wm.GetCanvas and wm:GetCanvas()
  if not mapID or not canvas then return end
  local w, h = canvas:GetSize()
  -- same size on screen at any zoom, in the small and the maximized map
  local cs = canvas:GetEffectiveScale()
  local unit = (CM.db.settings.pinScale or 1) * (cs > 0 and UIParent:GetEffectiveScale() / cs or 1)
  self.drawnScale = cs
  local n, seen = 0, {}
  self:Collect(mapID, function(x, y, kind, title, text)
    if n >= MAX_PINS or not x or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local key = kind .. math.floor(x * 400) .. ":" .. math.floor(y * 400) -- drop exact overlaps
    if seen[key] then return end
    seen[key] = true
    n = n + 1
    local p = pins[n] or newPin(canvas)
    p:SetParent(canvas)
    styleIcon(p, kind, unit)
    p:SetFrameLevel(canvas:GetFrameLevel() + ((kind == "avail" or kind == "turnin") and 2100 or 2000))
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
    p.title, p.text, p.m, p.x, p.y, p.count = title, text, mapID, x, y, 1
    p:Show()
  end)
  self.mapDirty = false
end

-- Minimap icons -------------------------------------------------------------------------------------
-- Minimap view diameter in yards per zoom level (used when the client has no C_Minimap.GetViewRadius)
local MM_OUTDOOR = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local MM_INDOOR = { 300, 240, 180, 120, 80, 50 }
local mmPins, mmPoints, mmMap = {}, {}, nil

local function mmPin(i)
  local p = mmPins[i]
  if p then return p end
  p = newPin(Minimap)
  table.remove(pins) -- newPin registers world map pins; keep minimap pins separate
  p:SetFrameStrata(Minimap:GetFrameStrata())
  p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  mmPins[i] = p
  return p
end

function N:CollectMinimap()
  wipe(mmPoints)
  mmMap = C_Map.GetBestMapForUnit("player")
  if not mmMap or not CM.db or CM.db.settings.questMinimap == false then return end
  local seen = {}
  self:Collect(mmMap, function(x, y, kind, title, text)
    local key = kind .. math.floor(x * 400) .. ":" .. math.floor(y * 400)
    if seen[key] then return end
    seen[key] = true
    local cont, wp = C_Map.GetWorldPosFromMapPos(mmMap, CreateVector2D(x, y))
    if cont and wp then table.insert(mmPoints, { wp.x, wp.y, cont, kind, title, text, x, y }) end
  end)
end

function N:UpdateMinimap()
  local shown = 0
  if mmMap and #mmPoints > 0 and Minimap:IsVisible() then
    local pm = C_Map.GetBestMapForUnit("player")
    if pm ~= mmMap then self:CollectMinimap() pm = mmMap end
    local pp = pm and C_Map.GetPlayerMapPosition(pm, "player")
    local ax = pp and CM.Arrow.Axes(pm)
    if pp and ax then
      local pc, pw = C_Map.GetWorldPosFromMapPos(pm, pp)
      local radius
      if C_Minimap and C_Minimap.GetViewRadius then radius = C_Minimap.GetViewRadius() end
      if not radius or radius <= 0 then
        local z = (Minimap:GetZoom() or 0) + 1
        radius = ((IsIndoors and IsIndoors()) and MM_INDOOR or MM_OUTDOOR)[z] / 2
      end
      local half = Minimap:GetWidth() / 2
      local ppy = half / radius
      local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
      local facing = rotate and CM:Safe(GetPlayerFacing()) or 0
      local cf, sf = math.cos(facing), math.sin(facing)
      local scale = CM.db.settings.pinScale or 1
      for _, pt in ipairs(mmPoints) do
        if pt[3] == pc then
          local dx, dy = pt[1] - pw.x, pt[2] - pw.y
          local east = dx * ax[1] + dy * ax[2]
          local north = -(dx * ax[3] + dy * ax[4])
          if rotate then east, north = east * cf + north * sf, -east * sf + north * cf end
          local sx, sy = east * ppy, north * ppy
          if sx * sx + sy * sy < (half - 5) ^ 2 then
            shown = shown + 1
            local p = mmPin(shown)
            styleIcon(p, pt[4], scale * 0.9)
            p:ClearAllPoints()
            p:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
            p.title, p.text, p.m, p.x, p.y = pt[5], pt[6], mmMap, pt[7], pt[8]
            p:Show()
          end
        end
      end
    end
  end
  for i = shown + 1, #mmPins do mmPins[i]:Hide() end
end

local function hookMap()
  local wm = WorldMapFrame
  if not wm or N.mapHooked then return end
  N.mapHooked = true
  wm:HookScript("OnShow", function() N:DrawMap() end)
  local elapsed = 0
  wm:HookScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 0.15 then return end
    elapsed = 0
    local canvas = wm.GetCanvas and wm:GetCanvas()
    if canvas and N.drawnScale and math.abs(canvas:GetEffectiveScale() - N.drawnScale) > 0.001 then N:DrawMap() end
  end)
  if wm.OnMapChanged then hooksecurefunc(wm, "OnMapChanged", function() N:DrawMap() end) end
end

CM:On("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then hookMap() end end)

-- Wiring -------------------------------------------------------------------------------------------
local pending
local function refresh()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function()
    pending = false
    rebuildTitles()
    scanProgress()
    N:UpdateArrow()
    refreshPlates()
    if WorldMapFrame and WorldMapFrame:IsShown() then N:DrawMap() end
    N:CollectMinimap()
  end)
end

CM:On("QUEST_LOG_UPDATE", refresh)
CM:On("QUEST_ACCEPTED", refresh)
CM:On("QUEST_REMOVED", refresh)
CM:On("SUPER_TRACKING_CHANGED", refresh)
CM:On("ZONE_CHANGED_NEW_AREA", refresh)

function N:OnLogin()
  hookMap()
  rebuildTitles()
  -- re-pick the closest quest every few seconds as you move
  C_Timer.NewTicker(2, function() N:UpdateArrow() end)
  C_Timer.NewTicker(0.1, function() N:UpdateMinimap() end)
  refresh()
end

-- /wga quest [arrow|pins|marks|why]
function N:Command(arg)
  arg = (arg or ""):lower()
  local s = CM.db.settings
  if arg == "arrow" or arg == "" then
    s.questArrow = s.questArrow == false
    CM:Print("Quest arrow %s.", s.questArrow and "on" or "off")
    self:UpdateArrow()
  elseif arg == "pins" then
    s.questPins = s.questPins == false
    CM:Print("Quest map dots %s.", s.questPins and "on" or "off")
    self:DrawMap()
  elseif arg == "available" or arg == "avail" then
    s.questAvailable = s.questAvailable == false
    CM:Print("Available quests on the map %s.", s.questAvailable and "on" or "off")
    self:DrawMap()
  elseif arg:match("^size") then
    local v = tonumber(arg:match("^size%s+([%d%.]+)"))
    if v and v >= 0.5 and v <= 3 then s.pinScale = v end
    CM:Print("Map icon size: %s (use /wga quest size 0.5 to 3).", tostring(s.pinScale or 1))
    self:DrawMap()
  elseif arg == "minimap" then
    s.questMinimap = s.questMinimap == false
    CM:Print("Quest icons on the minimap %s.", s.questMinimap and "on" or "off")
    self:CollectMinimap()
  elseif arg == "marks" then
    s.questPlates = s.questPlates == false
    CM:Print("Quest mob marks %s.", s.questPlates and "on" or "off")
    refreshPlates()
  elseif arg == "why" then
    local id = self:Pick()
    if not id then CM:Print("No quest with a known location right now.") return end
    local m, x, y, src = self:Location(id)
    CM:Print("%s: %s (map %s, %.1f, %.1f)", questTitle(id), src or "?", tostring(m), (x or 0) * 100, (y or 0) * 100)
    local pm = C_Map.GetBestMapForUnit("player")
    local onmap = 0
    for _ in ipairs(pm and QL.GetQuestsOnMap and QL.GetQuestsOnMap(pm) or {}) do onmap = onmap + 1 end
    local n = 0
    for _, list in pairs(spots()[id] or {}) do n = n + #list end
    CM:Print("  Game quest-map entries on this map: %d. Learned spots for this quest: %d.", onmap, n)
  else
    CM:Print("/wga quest [arrow | pins | minimap | available | marks | size <n> | why]")
  end
end
