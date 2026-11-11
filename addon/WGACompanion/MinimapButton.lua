-- WGA Companion: minimap button. Drag it around the minimap edge; left-click opens the hub,
-- right-click opens a quick menu. Also registers in the addon compartment when the client has one.
local _, CM = ...
local MB = CM:NewModule("MinimapButton")

local ICON = "Interface\\AddOns\\WGACompanion\\Icons\\logo"

local function place(b)
  local angle = math.rad(CM.db.settings.minimapAngle or 215)
  local r = Minimap:GetWidth() / 2 + 10
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function onOff(v) return v == false and "|cffff6060off|r" or "|cff40ff40on|r" end

-- Quick menu -------------------------------------------------------------------------------------------
local ITEMS = {
  { "Open WGA hub", function() CM.UI:Toggle() end },
  { "Step guide", function() CM.Guides:Toggle() end },
  { "Leveling", function() CM.UI:Show("Leveling") end },
  { "Dungeons", function() CM.UI:Show("Dungeons") end },
  { "Professions", function() CM.UI:Show("Professions") end },
  { "Gold making", function() CM.UI:Show("Gold") end },
  "-",
  { function() return "Quest arrow: " .. onOff(CM.db.settings.questArrow) end, function() CM.QuestNav:Command("arrow") end },
  { function() return "Map quest icons: " .. onOff(CM.db.settings.questPins) end, function() CM.QuestNav:Command("pins") end },
  { function() return "Minimap quest icons: " .. onOff(CM.db.settings.questMinimap) end, function() CM.QuestNav:Command("minimap") end },
  { function() return "Quests to pick up: " .. onOff(CM.db.settings.questAvailable) end, function() CM.QuestNav:Command("available") end },
  { function() return "Mob marks: " .. onOff(CM.db.settings.questPlates) end, function() CM.QuestNav:Command("marks") end },
  "-",
  { "Scan auction house", function() CM.Scanner:Start() end },
  { "What to sell in my bags", function() CM.Merchant:BagReport() end },
  { function() return "Rare alerts: " .. onOff(CM.db.settings.rareAlerts) end, function() SlashCmdList.WGACOMPANION("rares") end },
  "-",
  { "Hide this button", function() MB:SetShown(false) end },
}

function MB:BuildMenu()
  if self.menu then return end
  local m = CreateFrame("Frame", "WGACompanionMinimapMenu", UIParent, "BackdropTemplate")
  m:SetFrameStrata("DIALOG")
  m:SetClampedToScreen(true)
  if m.SetBackdrop then
    m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    m:SetBackdropColor(0.05, 0.07, 0.12, 0.95)
    m:SetBackdropBorderColor(0.4, 0.75, 1, 0.9)
  end
  local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("WGA Companion")
  m.rows = {}
  local y, width = -26, 210
  for _, item in ipairs(ITEMS) do
    if item == "-" then
      local line = m:CreateTexture(nil, "ARTWORK")
      line:SetColorTexture(1, 1, 1, 0.12)
      line:SetSize(width - 16, 1)
      line:SetPoint("TOPLEFT", 8, y - 4)
      y = y - 9
    else
      local b = CreateFrame("Button", nil, m)
      b:SetSize(width - 12, 18)
      b:SetPoint("TOPLEFT", 6, y)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 6, 0)
      b.item = item
      b:SetScript("OnClick", function(self) m:Hide(); self.item[2]() end)
      table.insert(m.rows, b)
      y = y - 18
    end
  end
  m:SetSize(width, -y + 8)
  m:Hide()
  -- close when clicking anywhere else
  m:RegisterEvent("GLOBAL_MOUSE_DOWN")
  m:SetScript("OnEvent", function(self)
    if self:IsShown() and not self:IsMouseOver() and not (MB.button and MB.button:IsMouseOver()) then self:Hide() end
  end)
  self.menu = m
end

function MB:ToggleMenu(anchor)
  self:BuildMenu()
  local m = self.menu
  if m:IsShown() then m:Hide() return end
  for _, b in ipairs(m.rows) do
    local label = b.item[1]
    b.text:SetText(type(label) == "function" and label() or label)
  end
  m:ClearAllPoints()
  m:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 4, 4)
  m:Show()
end

-- Button --------------------------------------------------------------------------------------------------
function MB:Build()
  if self.button then return end
  local b = CreateFrame("Button", "WGACompanionMinimapButton", Minimap)
  b:SetSize(40, 40)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(32, 32)
  bg:SetPoint("CENTER")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(30, 30)
  icon:SetPoint("CENTER")
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(68, 68)
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then MB:ToggleMenu(self) else CM.UI:Toggle() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      CM.db.settings.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      place(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffffd100WGA Companion|r  v" .. CM.version)
    GameTooltip:AddLine("Left-click: open the hub", 1, 1, 1)
    GameTooltip:AddLine("Right-click: quick menu", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.button = b
  place(b)
end

function MB:SetShown(show)
  CM.db.settings.minimapButton = show
  self:Build()
  self.button:SetShown(show)
  if not show then CM:Print("Minimap button hidden. Type |cff00ff00/wga minimap|r to bring it back.") end
end

function MB:OnLogin()
  self:Build()
  self.button:SetShown(CM.db.settings.minimapButton ~= false)
end

-- Addon compartment (the addon list button by the minimap on newer clients)
function WGACompanion_OnCompartmentClick(_, button)
  if button == "RightButton" and MB.button then MB:ToggleMenu(MB.button) else CM.UI:Toggle() end
end
