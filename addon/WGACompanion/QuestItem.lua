-- WGA Companion: quest item button. When the step you're on needs you to use a quest item ("use the
-- torch on the tent"), a button with that item appears next to the arrow. Click it, or press the key
-- you bind to "Use quest item" under Key Bindings > AddOns > WGA Companion.
-- Using an item needs a secure button: it is only changed, shown or hidden out of combat.
local _, CM = ...
local QI = CM:NewModule("QuestItem")

BINDING_HEADER_WGACOMPANION = "WGA Companion"
_G["BINDING_NAME_CLICK WGACompanionQuestItemButton:LeftButton"] = "Use quest item"
BINDING_NAME_WGACOMPANION_NEXTSTEP = "Skip to the next guide step"
BINDING_NAME_WGACOMPANION_GUIDE = "Show or hide the guide window"
BINDING_NAME_WGACOMPANION_HUB = "Open the WGA hub"
function WGACompanion_NextStep() if CM.GuideWindow then CM.GuideWindow:Skip() end end
function WGACompanion_ToggleGuide() if CM.Guides then CM.Guides:Toggle() end end
function WGACompanion_ToggleHub() if CM.UI then CM.UI:Toggle() end end

local SIZE = 42
local function S() return CM.db.settings end

-- The usable item for a quest in your log: link, icon, log index
local function itemFor(id)
  local QL = C_QuestLog
  local idx = id and QL.GetLogIndexForQuestID and QL.GetLogIndexForQuestID(id)
  if not idx or not GetQuestLogSpecialItemInfo then return nil end
  local link, icon, _, showWhenComplete = GetQuestLogSpecialItemInfo(idx)
  if not link then return nil end
  if QL.IsComplete(id) and not showWhenComplete then return nil end
  return link, icon, idx
end

-- Current step first, then the next guide steps, then anything else in your log
function QI:Pick()
  local GW = CM.GuideWindow
  local cur = GW and GW.current
  local tried = {}
  local function try(id)
    if not id or tried[id] then return nil end
    tried[id] = true
    local link, icon, idx = itemFor(id)
    if link then return { link = link, icon = icon, idx = idx, quest = id } end
  end
  if cur and cur.kind ~= "accept" then
    local r = try(cur.quest)
    if r then return r end
  end
  for i, s in ipairs(GW and GW.steps or {}) do
    if i > 6 then break end
    if s.kind ~= "accept" then
      local r = try(s.quest)
      if r then return r end
    end
  end
  return nil
end

function QI:Build()
  if self.button or InCombatLockdown() then return end
  local b = CreateFrame("Button", "WGACompanionQuestItemButton", UIParent, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type1", "item")   -- left click only; right-drag moves it
  b:SetMovable(true)
  b:SetClampedToScreen(true)
  b:RegisterForDrag("RightButton")
  b:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    S().itemButtonPos = { x, y }
  end)
  local T = CM.Theme
  if T and T.Skin then T:Skin(b, "bg", "accent") end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b.icon)
  b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
  b.key:SetPoint("TOPRIGHT", -3, -3)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(b.icon)
  b.hl:SetColorTexture(1, 1, 1, 0.15)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.link then GameTooltip:SetHyperlink(self.link) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to use it for: " .. (self.questTitle or "your quest"), 0.4, 0.85, 1, true)
    GameTooltip:AddLine("Right-drag to move. Bind a key: Key Bindings > AddOns > WGA Companion.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:Hide()
  self.button = b
end

local function place(b)
  b:ClearAllPoints()
  local pos = S().itemButtonPos
  if pos and pos[1] then b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2]) return end
  -- next to the arrow, on its left
  local f = CM.Arrow and CM.Arrow.frame
  local x, y = f and f:IsShown() and f:GetCenter()
  if x and y then
    local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", (x - f:GetWidth() / 2) * scale - 10, y * scale)
  else
    b:SetPoint("TOP", UIParent, "TOP", -140, -120)
  end
end

function QI:Update()
  if InCombatLockdown() then self.pending = true return end
  self:Build()
  local b = self.button
  if not b then return end
  local pick = S().questItemButton ~= false and self:Pick()
  if not pick then b:Hide(); b.link = nil return end
  if b.link ~= pick.link or not b:IsShown() then
    b:SetAttribute("item", pick.link)
    b.link = pick.link
    place(b)
  end
  b.icon:SetTexture(pick.icon or 134400)
  b.idx = pick.idx
  b.questTitle = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(pick.quest)
  local key = GetBindingKey and GetBindingKey("CLICK WGACompanionQuestItemButton:LeftButton")
  b.key:SetText(key and GetBindingText and GetBindingText(key, true) or key or "")
  b:Show()
  self:Cooldown()
end

function QI:Cooldown()
  local b = self.button
  if not (b and b:IsShown() and b.idx and GetQuestLogSpecialItemCooldown) then return end
  local start, dur, enable = GetQuestLogSpecialItemCooldown(b.idx)
  if start and dur and dur > 0 and enable ~= 0 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
end

local queued
local function soon()
  if queued then return end
  queued = true
  C_Timer.After(0.3, function() queued = nil; QI:Update() end)
end

CM:On("QUEST_LOG_UPDATE", soon)
CM:On("UPDATE_BINDINGS", soon)
CM:On("BAG_UPDATE_COOLDOWN", function() QI:Cooldown() end)
CM:On("PLAYER_REGEN_ENABLED", function() if QI.pending then QI.pending = nil; QI:Update() end end)

function QI:OnLogin()
  if CM.GuideWindow and CM.GuideWindow.Refresh then hooksecurefunc(CM.GuideWindow, "Refresh", soon) end
  soon()
end

function QI:ResetPosition()
  S().itemButtonPos = nil
  if self.button and not InCombatLockdown() then place(self.button) end
end
