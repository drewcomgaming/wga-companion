-- WGA Companion: quest automation, Zygor style. When you talk to a quest giver it picks the
-- quest the guide wants, accepts it, hands in finished quests and chooses your reward:
-- a real upgrade if one is on offer, otherwise the reward worth the most gold.
-- Hold Shift while talking to an NPC to do it all by hand.
local _, CM = ...
local Rw = CM:NewModule("Rewards")

local function S() return CM.db.settings end
local function paused() return IsShiftKeyDown and IsShiftKeyDown() end
local function autoQuest() return S().autoQuest ~= false and not paused() end
local function autoReward() return S().autoReward ~= false and not paused() end

-- Value -------------------------------------------------------------------------------------------
local function valueOf(link)
  local id = CM:ItemIDFromLink(link)
  if not id then return 0 end
  local net = CM.PriceDB:NetAH(id) or 0
  local vendor = CM.PriceDB:Vendor(id) or 0
  return math.max(net, vendor), net > vendor and "AH" or "vendor"
end

-- Upgrades ----------------------------------------------------------------------------------------
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
  INVTYPE_THROWN = { 18 },
}

-- Armor you should wear (classID 4 subclass: 1 cloth, 2 leather, 3 mail, 4 plate), by level
local ARMOR = {
  WARRIOR = function(l) return l >= 40 and 4 or 3 end, PALADIN = function(l) return l >= 40 and 4 or 3 end,
  HUNTER = function(l) return l >= 40 and 3 or 2 end, SHAMAN = function(l) return l >= 40 and 3 or 2 end,
  ROGUE = function() return 2 end, DRUID = function() return 2 end,
  PRIEST = function() return 1 end, MAGE = function() return 1 end, WARLOCK = function() return 1 end,
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
-- Weapons each class can use (classID 2 subclasses)
local WEAPONS = {
  WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
  HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
  PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
  WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 6, 10, 13, 15 },
}
-- Stats each class wants; an item with main stats but none of these is not for you
local WANTS = {
  WARRIOR = { STRENGTH = true, AGILITY = true }, PALADIN = { STRENGTH = true, INTELLECT = true },
  HUNTER = { AGILITY = true, INTELLECT = true }, ROGUE = { AGILITY = true },
  PRIEST = { INTELLECT = true, SPIRIT = true }, SHAMAN = { INTELLECT = true, STRENGTH = true, AGILITY = true },
  MAGE = { INTELLECT = true, SPIRIT = true }, WARLOCK = { INTELLECT = true, SPIRIT = true },
  DRUID = { INTELLECT = true, AGILITY = true, STRENGTH = true },
}
local MAIN = { STRENGTH = true, AGILITY = true, INTELLECT = true, SPIRIT = true }

local function contains(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end end

local function ilvl(link)
  if not link then return 0 end
  local ok, v = pcall(C_Item.GetDetailedItemLevelInfo, link)
  return (ok and v) or 0
end

-- Why this item suits you, or nil
local function suits(link, class, level)
  local _, _, _, equipLoc, _, classID, subID = C_Item.GetItemInfoInstant(link)
  if not equipLoc or not SLOTS[equipLoc] then return nil end
  if classID == 4 then
    if equipLoc == "INVTYPE_SHIELD" then if not SHIELD[class] then return nil end
    elseif subID and subID >= 1 and subID <= 4 and equipLoc ~= "INVTYPE_CLOAK" then
      local best = ARMOR[class] and ARMOR[class](level)
      if best and subID ~= best then return nil end
    end
  elseif classID == 2 then
    if not contains(WEAPONS[class], subID) then return nil end
  end
  local ok, stats = pcall(C_Item.GetItemStats, link)
  if ok and stats then
    local hasMain, hasMine = false, false
    for k in pairs(stats) do
      local stat = k:match("^ITEM_MOD_(%u+)_SHORT$")
      if stat and MAIN[stat] then
        hasMain = true
        if WANTS[class] and WANTS[class][stat] then hasMine = true end
      end
    end
    if hasMain and not hasMine then return nil end
  end
  return SLOTS[equipLoc]
end

-- How much better than what you wear: item levels gained (or a big number for an empty slot)
local function upgradeBy(link, class, level)
  local slots = suits(link, class, level)
  if not slots then return nil end
  local new = ilvl(link)
  local worst
  for _, slot in ipairs(slots) do
    local cur = GetInventoryItemLink("player", slot)
    local l = cur and ilvl(cur) or 0
    if not worst or l < worst then worst = l end
  end
  if (worst or 0) == 0 then return 99, "empty slot" end
  return new - worst, string.format("item level %d vs your %d", new, worst)
end
Rw.UpgradeBy = upgradeBy

-- Pick a reward: returns index, reason
function Rw:Choose()
  local n = GetNumQuestChoices() or 0
  if n <= 1 then return n == 1 and 1 or nil end
  local _, class = UnitClass("player")
  local level = UnitLevel("player") or 1
  local need = S().upgradeIlvl or 5
  local bestUp, bestUpBy, upWhy
  local best, bestVal, bestSrc = nil, -1, nil
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    local _, _, count, _, usable = GetQuestItemInfo("choice", i)
    if link then
      if usable ~= false then
        local by, why = upgradeBy(link, class, level)
        if by and by >= need and (not bestUpBy or by > bestUpBy) then bestUp, bestUpBy, upWhy = i, by, why end
      end
      local v, src = valueOf(link)
      v = v * (count or 1)
      if v > bestVal then best, bestVal, bestSrc = i, v, src end
    end
  end
  if bestUp then return bestUp, "upgrade (" .. upWhy .. ")" end
  if best and bestVal > 0 then return best, string.format("worth the most, %s via %s", CM:Money(bestVal, true), bestSrc) end
  return nil
end

-- Which quests to handle ---------------------------------------------------------------------------
-- Only the guide's current step, plus other guide steps at that same NPC (so a quest giver with
-- three hand-ins gets them all done in one visit). Every other NPC is left alone.
local function guideWants(id)
  if not id or id == 0 then return false end
  local GW = CM.GuideWindow
  local cur = GW and GW.current
  if not cur then return false end
  if cur.quest == id then return true end
  local npc = UnitName and UnitName("npc")
  if not npc or not cur.npc or npc ~= cur.npc then return false end
  local ok, steps = pcall(GW.Steps, GW)
  for _, s in ipairs(ok and steps or {}) do
    if s.quest == id and s.npc == npc and (s.kind == "accept" or s.kind == "turnin") then return true end
  end
  return false
end
Rw.Wants = guideWants

-- The next part of a chain you just handed in, offered by the same NPC: the guide hasn't had time
-- to add it to the route yet, but it obviously wants it (unless efficient mode thinks it's poor value).
local lastTurnIn
CM:On("QUEST_TURNED_IN", function(_, id)
  lastTurnIn = { id = id, npc = UnitName and UnitName("npc"), t = GetTime() }
end)
local function followUp(id)
  local QD = CM.QData
  if not (id and lastTurnIn and QD and QD:Has()) then return false end
  if GetTime() - lastTurnIn.t > 60 then return false end
  local npc = UnitName and UnitName("npc")
  if lastTurnIn.npc and npc and npc ~= lastTurnIn.npc then return false end
  local prev, q = QD:Quest(lastTurnIn.id), QD:Quest(id)
  local chained = prev and prev[12] == id
  for _, p in ipairs(q and q[9] or {}) do if p == lastTurnIn.id then chained = true end end
  for _, p in ipairs(q and q[10] or {}) do if p == lastTurnIn.id then chained = true end end
  if not chained then return false end
  local SG = CM.SmartGuide
  if SG and SG:Style() == "efficient" and QD:NotWorthIt(id, UnitLevel("player") or 1) then return false end
  return true
end
Rw.FollowUp = followUp
local function wanted(id) return guideWants(id) or followUp(id) end

local function skip(repeatable, frequency)
  return repeatable or (frequency and frequency > 0)
end

local function remark(text)
  if CM.Companion then CM.Companion:Remark(text) end
end

-- Gossip (NPCs with chat options)
CM:On("GOSSIP_SHOW", function()
  if not autoQuest() or not C_GossipInfo then return end
  for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
    if q.isComplete and q.questID and guideWants(q.questID) then C_GossipInfo.SelectActiveQuest(q.questID) return end
  end
  for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
    if q.questID and not skip(q.repeatable, q.frequency) and wanted(q.questID) then
      C_GossipInfo.SelectAvailableQuest(q.questID) return
    end
  end
end)

-- Quest greeting (NPCs with only a quest list)
CM:On("QUEST_GREETING", function()
  if not autoQuest() then return end
  for i = 1, (GetNumActiveQuests() or 0) do
    local _, complete = GetActiveTitle(i)
    if complete and guideWants(GetActiveQuestID and GetActiveQuestID(i)) then SelectActiveQuest(i) return end
  end
  for i = 1, (GetNumAvailableQuests() or 0) do
    local _, frequency, repeatable, _, id = GetAvailableQuestInfo(i)
    if not skip(repeatable, frequency) and wanted(id) then SelectAvailableQuest(i) return end
  end
end)

CM:On("QUEST_DETAIL", function()
  if not autoQuest() then return end
  local id = GetQuestID()
  if QuestGetAutoAccept and QuestGetAutoAccept() then
    AcknowledgeAutoAcceptQuest()   -- the game already accepted it
  elseif wanted(id) then
    AcceptQuest()
  else
    -- the guide may not have caught up with a turn-in a moment ago: look again shortly
    C_Timer.After(0.6, function()
      if CM.GuideWindow and CM.GuideWindow.Refresh then pcall(CM.GuideWindow.Refresh, CM.GuideWindow) end
      if autoQuest() and GetQuestID() == id and QuestFrame and QuestFrame:IsShown() and wanted(id) then AcceptQuest() end
    end)
  end
end)

CM:On("QUEST_PROGRESS", function()
  if autoQuest() and IsQuestCompletable() and guideWants(GetQuestID()) then CompleteQuest() end
end)

-- Rewards
CM:On("QUEST_COMPLETE", function()
  if not guideWants(GetQuestID()) then return end
  local n = GetNumQuestChoices() or 0
  local pick, why = Rw:Choose()
  if n <= 1 then
    if autoQuest() then GetQuestReward(n == 1 and 1 or 0) end
    return
  end
  if not pick then return end
  local link = GetQuestItemLink("choice", pick) or "?"
  if autoReward() then
    CM:Print("Took %s: %s.", link, why)
    if why:find("^upgrade") then remark("I picked " .. (GetQuestItemInfo("choice", pick) or "the upgrade") .. " for you, it's an upgrade. Equip it!") end
    GetQuestReward(pick)
    return
  end
  CM:Print("Best reward: %s (%s).", link, why)
  local btn = QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons and QuestInfoRewardsFrame.RewardButtons[pick]
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
