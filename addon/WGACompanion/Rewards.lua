-- WGA Companion: quest reward advisor. Marks the reward choice worth the most gold
-- (AH value after cut, or vendor price, whichever is higher).
local _, CM = ...
local Rw = CM:NewModule("Rewards")

local function valueOf(link)
  local id = CM:ItemIDFromLink(link)
  if not id then return 0 end
  local net = CM.PriceDB:NetAH(id) or 0
  local vendor = CM.PriceDB:Vendor(id) or 0
  return math.max(net, vendor), net > vendor and "AH" or "vendor"
end

CM:On("QUEST_COMPLETE", function()
  local n = GetNumQuestChoices()
  if not n or n < 2 then return end
  local best, bestVal, bestSrc = nil, -1, nil
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    local _, _, count = GetQuestItemInfo("choice", i)
    local v, src = valueOf(link)
    v = v * (count or 1)
    if v > bestVal then best, bestVal, bestSrc = i, v, src end
  end
  if not best or bestVal <= 0 then return end
  CM:Print("Most valuable reward: %s (%s via %s). Pick an upgrade instead if you can use one.",
    GetQuestItemLink("choice", best) or "?", CM:Money(bestVal, true), bestSrc)
  local btn = QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons and QuestInfoRewardsFrame.RewardButtons[best]
  if btn then
    if not Rw.mark then
      Rw.mark = CreateFrame("Frame", nil, UIParent)
      Rw.mark:SetSize(18, 18)
      Rw.mark.tex = Rw.mark:CreateTexture(nil, "OVERLAY")
      Rw.mark.tex:SetAllPoints()
      Rw.mark.tex:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    end
    Rw.mark:SetParent(btn)
    Rw.mark:ClearAllPoints()
    Rw.mark:SetPoint("TOPLEFT", btn, "TOPLEFT", -4, 4)
    Rw.mark:SetFrameLevel(btn:GetFrameLevel() + 5)
    Rw.mark:Show()
  end
end)
CM:On("QUEST_FINISHED", function() if Rw.mark then Rw.mark:Hide() end end)
