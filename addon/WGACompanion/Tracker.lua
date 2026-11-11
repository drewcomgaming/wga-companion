-- WGA Companion: quest tracker in WGA style. Lists your quests by zone with objective progress bars,
-- distance to the next objective, and which quest the arrow is following.
--   click a quest: point the arrow at it    shift-click: open it in the quest log
--   right-click a quest: fold its objectives    click a zone: fold the zone
local _, CM = ...
local TR = CM:NewModule("Tracker")
local T = CM.Theme
local QL = C_QuestLog

local WIDTH = 270
local WHITE = "Interface\\Buttons\\WHITE8x8"
local rows, used = {}, 0

local function S() return CM.db.settings end

local function getRow(parent)
  used = used + 1
  local r = rows[used]
  if not r then
    r = CreateFrame("Button", nil, parent)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.left = T:Text(r, 12, "text")
    r.left:SetPoint("TOPLEFT", 0, 0)
    r.left:SetWordWrap(true)
    r.right = T:Text(r, 11, "muted")
    r.right:SetPoint("TOPRIGHT", 0, 0)
    r.right:SetJustifyH("RIGHT")
    r.barBg = r:CreateTexture(nil, "ARTWORK")
    r.barBg:SetTexture(WHITE)
    r.barBg:SetHeight(2)
    r.bar = r:CreateTexture(nil, "OVERLAY")
    r.bar:SetTexture(WHITE)
    r.bar:SetHeight(2)
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\arrow")
    r.mark:SetSize(11, 11)
    r.mark:SetRotation(-math.pi / 2) -- points right
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetTexture(WHITE)
    r.hl:Hide()
    r:SetScript("OnEnter", function(self)
      if not self.questID and not self.zone then return end
      local p = T:Get()
      self.hl:SetVertexColor(p.hover[1], p.hover[2], p.hover[3], p.hover[4]); self.hl:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide() end)
    r:SetScript("OnClick", function(self, button) TR:OnRowClick(self, button) end)
    rows[used] = r
  end
  r:SetParent(parent)
  r:ClearAllPoints()
  r.questID, r.zone = nil, nil
  r.right:SetText("")
  r.barBg:Hide(); r.bar:Hide(); r.mark:Hide()
  r:Show()
  return r
end

function TR:OnRowClick(r, button)
  if r.zone then
    local c = S().trackerCollapsed
    c[r.zone] = not c[r.zone] or nil
    self:Update()
  elseif r.questID then
    local id = r.questID
    if button == "RightButton" then
      local c = S().trackerFolded
      c[id] = not c[id] or nil
      self:Update()
    elseif IsShiftKeyDown() and QuestMapFrame_OpenToQuestDetails then
      pcall(QuestMapFrame_OpenToQuestDetails, id)
    else
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, id) end
      CM.QuestNav.current = id
      CM.QuestNav:UpdateArrow()
      self:Update()
    end
  end
end

function TR:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionTracker", UIParent)
  f:SetWidth(WIDTH)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  local pos = S().trackerPos
  if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -70, -250) end
  T:Skin(f, "bg", "border")

  local head = CreateFrame("Button", nil, f)
  head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT")
  head:SetHeight(26)
  head:RegisterForDrag("LeftButton")
  head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  head:SetScript("OnDragStart", function() if not S().trackerLocked then f:StartMoving() end end)
  head:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint(1)
    S().trackerPos = { point, x, y }
  end)
  head:SetScript("OnClick", function(_, button)
    if button == "RightButton" then CM.UI:Show("Settings") end
  end)
  local logo = head:CreateTexture(nil, "ARTWORK")
  logo:SetTexture("Interface\\AddOns\\WGACompanion\\Icons\\logo")
  logo:SetSize(18, 18)
  logo:SetPoint("LEFT", 6, 0)
  f.title = T:Text(head, 13, "heading")
  f.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
  f.title:SetText("Quests")
  f.count = T:Text(head, 11, "muted")
  f.count:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
  local fold = T:Button(head, "-", 14, function()
    S().trackerMin = not S().trackerMin or nil
    TR:Update()
  end)
  fold:SetSize(22, 22)
  fold:SetPoint("RIGHT", -2, 0)
  fold.text:ClearAllPoints(); fold.text:SetPoint("CENTER")
  f.fold = fold
  local line = head:CreateTexture(nil, "ARTWORK")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  T:Gradient(line)
  head:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("WGA quest tracker")
    GameTooltip:AddLine("Drag to move. Right-click for settings.", 1, 1, 1)
    GameTooltip:AddLine("Click a quest to point the arrow at it,", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("shift-click to open it, right-click to fold it.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  head:SetScript("OnLeave", function() GameTooltip:Hide() end)

  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 8, -32)
  f.body:SetPoint("TOPRIGHT", -8, -32)
  f.body:SetHeight(10)
  self.frame = f
  self:ApplyScale()
  T:OnChange(function() TR:Update() end)
end

function TR:ApplyScale()
  if self.frame then self.frame:SetScale(S().trackerScale or 1) end
end

local function yardsTo(id)
  local m, x, y = CM.QuestNav:Location(id)
  if not m or not CM.Arrow then return nil end
  local d = CM.Arrow:Compute({ m = m, x = x, y = y })
  return d
end

local function fmtYards(d)
  if not d then return "" end
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", d)
end

function TR:Update()
  if not CM.db then return end
  if S().tracker == false then
    if self.frame then self.frame:Hide() end
    self:ApplyBlizzard()
    return
  end
  self:Build()
  self:ApplyBlizzard()
  local f, p = self.frame, T:Get()
  T:Skin(f, "bg", "border")
  f.wgaBg:SetAlpha(S().trackerAlpha or 0.85)
  for i = 1, used do rows[i]:Hide() end
  used = 0

  local total, shown = 0, 0
  local y, maxH = 0, S().trackerMaxHeight or 560
  local inner = WIDTH - 16
  local zone
  local collapsed, folded = S().trackerCollapsed, S().trackerFolded
  local current = CM.QuestNav.current
  local overflow = 0

  for i = 1, QL.GetNumQuestLogEntries() do
    local info = QL.GetInfo(i)
    if info and info.isHeader then
      zone = info.title
    elseif info and info.questID and not info.isHidden then
      total = total + 1
      if not S().trackerMin then
        if y > maxH then
          overflow = overflow + 1
        else
          if zone and zone ~= self.lastZone then
            local r = getRow(f.body)
            r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y)
            r.zone = zone
            T:Font(r.left, 10, "muted")
            r.left:SetWidth(inner)
            r.left:SetText((collapsed[zone] and "+  " or "") .. zone:upper())
            r:SetHeight(16)
            y = y + (shown > 0 and 20 or 16)
            if shown > 0 then r:SetPoint("TOPLEFT", 0, -(y - 16)); r:SetPoint("TOPRIGHT", 0, -(y - 16)) end
            self.lastZone = zone
          end
          if not collapsed[zone or ""] then
            shown = shown + 1
            local id = info.questID
            local ready = QL.ReadyForTurnIn and QL.ReadyForTurnIn(id) or QL.IsComplete(id)
            -- quest title row
            local r = getRow(f.body)
            r.questID = id
            r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y)
            local indent = 0
            if id == current then
              r.mark:SetPoint("LEFT", -1, 0)
              r.mark:SetVertexColor(p.accent[1], p.accent[2], p.accent[3], 1)
              r.mark:Show()
              indent = 12
            end
            r.left:ClearAllPoints()
            r.left:SetPoint("TOPLEFT", indent, 0)
            r.left:SetWidth(inner - indent - 52)
            T:Font(r.left, 12, ready and "good" or "heading")
            local level = info.level or (QL.GetQuestDifficultyLevel and QL.GetQuestDifficultyLevel(id))
            local title = info.title or QL.GetTitleForQuestID(id) or ("Quest " .. id)
            if level and T:Key() == "dark" and GetQuestDifficultyColor and not ready then
              local c = GetQuestDifficultyColor(level)
              if c then r.left:SetTextColor(c.r, c.g, c.b) end
            end
            r.left:SetText(level and string.format("[%d] %s", level, title) or title)
            T:Font(r.right, 10, "muted")
            r.right:SetText(fmtYards(yardsTo(id)))
            local h = math.max(16, r.left:GetStringHeight() + 2)
            r:SetHeight(h)
            y = y + h + 2
            -- objectives
            if not folded[id] then
              if ready then
                local o = getRow(f.body)
                o:SetPoint("TOPLEFT", 10, -y); o:SetPoint("TOPRIGHT", 0, -y)
                o.left:ClearAllPoints(); o.left:SetPoint("TOPLEFT", 0, 0)
                T:Font(o.left, 11, "good")
                o.left:SetWidth(inner - 10)
                local _, _, _, _, who = CM.QuestNav:Location(id)
                o.left:SetText("Ready to turn in" .. (who and (" to " .. who) or ""))
                o:SetHeight(o.left:GetStringHeight() + 2)
                y = y + o:GetHeight() + 2
              else
                for _, ob in ipairs(QL.GetQuestObjectives(id) or {}) do
                  if ob.text and ob.text ~= "" then
                    local o = getRow(f.body)
                    o:SetPoint("TOPLEFT", 10, -y); o:SetPoint("TOPRIGHT", 0, -y)
                    o.left:ClearAllPoints(); o.left:SetPoint("TOPLEFT", 0, 0)
                    local need, have = ob.numRequired or 0, ob.numFulfilled or 0
                    local label = ob.text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
                    T:Font(o.left, 11, ob.finished and "good" or "text")
                    o.left:SetWidth(inner - 54)
                    o.left:SetText(label)
                    T:Font(o.right, 11, ob.finished and "good" or "muted")
                    o.right:SetText(need > 1 and string.format("%d/%d", have, need) or (ob.finished and "done" or ""))
                    local h = o.left:GetStringHeight() + 2
                    if need > 1 then
                      o.barBg:ClearAllPoints()
                      o.barBg:SetPoint("TOPLEFT", 0, -(h + 1)); o.barBg:SetPoint("TOPRIGHT", 0, -(h + 1))
                      o.barBg:SetVertexColor(p.bar[1], p.bar[2], p.bar[3], 1)
                      o.barBg:Show()
                      local frac = math.min(1, have / need)
                      o.bar:ClearAllPoints()
                      o.bar:SetPoint("TOPLEFT", o.barBg, "TOPLEFT")
                      o.bar:SetWidth(math.max(1, (inner - 10) * frac))
                      local c = ob.finished and p.good or p.accent
                      o.bar:SetVertexColor(c[1], c[2], c[3], 1)
                      o.bar:SetShown(frac > 0)
                      h = h + 4
                    end
                    o:SetHeight(h)
                    y = y + h + 2
                  end
                end
              end
            end
            y = y + 4
          end
        end
      end
    end
  end
  self.lastZone = nil
  if overflow > 0 then
    local r = getRow(f.body)
    r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y)
    T:Font(r.left, 11, "muted")
    r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", 0, 0)
    r.left:SetText(string.format("+ %d more quests", overflow))
    r:SetHeight(14)
    y = y + 16
  end
  local maxQuests = QL.GetMaxNumQuestsCanAccept and QL.GetMaxNumQuestsCanAccept() or 25
  f.count:SetText(string.format("%d/%d", total, maxQuests))
  f.fold.text:SetText(S().trackerMin and "+" or "-")
  f.body:SetHeight(math.max(1, y))
  f:SetHeight(S().trackerMin and 26 or (32 + y + 6))
  f:SetShown(total > 0 or S().trackerMin)
end

-- Blizzard's own tracker: hidden while ours is on (setting), restored when it's off.
local blizzHooked
function TR:ApplyBlizzard()
  local otf = ObjectiveTrackerFrame
  if not otf then return end
  local hide = S().tracker ~= false and S().hideBlizzTracker ~= false
  if hide and not blizzHooked then
    blizzHooked = true
    hooksecurefunc(otf, "Show", function(self)
      if S().tracker ~= false and S().hideBlizzTracker ~= false then self:Hide() end
    end)
  end
  if hide then otf:Hide() elseif not otf:IsShown() then otf:Show() end
end

local pending
local function queue()
  if pending then return end
  pending = true
  C_Timer.After(0.25, function() pending = false; TR:Update() end)
end
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
  CM:On(e, queue)
end

function TR:OnLogin()
  local s = S()
  s.trackerCollapsed = s.trackerCollapsed or {}
  s.trackerFolded = s.trackerFolded or {}
  queue()
  C_Timer.NewTicker(1.5, function() if TR.frame and TR.frame:IsShown() and not S().trackerMin then TR:Update() end end)
end
