-- WGA Companion: the guide window. A small themed window, separate from the hub, that walks you
-- through quests one step at a time: who to talk to, what to kill or loot, where, and how far.
-- Shows either the Smart Guide (built live from your quests) or a loaded step guide.
local _, CM = ...
local GW = CM:NewModule("GuideWindow")
local T = CM.Theme

local W = 340
local UPCOMING = 5
local A = "Interface\\AddOns\\WGACompanion\\Icons\\"

local KIND = {
  accept = { icon = "Interface\\GossipFrame\\AvailableQuestIcon", color = "warn", talk = "Talk to" },
  turnin = { icon = "Interface\\GossipFrame\\ActiveQuestIcon", color = "good", talk = "Talk to" },
  kill = { icon = A .. "slay_mono", color = "bad", talk = "Kill" },
  loot = { icon = A .. "loot_mono", color = "accent", talk = "Loot from" },
  use = { icon = A .. "object_mono", color = "accent2", talk = "Use" },
  complete = { icon = A .. "slay_mono", color = "accent", talk = "Near" },
  ["goto"] = { icon = A .. "node", color = "accent", talk = "" },
  level = { icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight", color = "heading", talk = "" },
  collect = { icon = "Interface\\Icons\\INV_Misc_Bag_08", color = "heading", talk = "" },
  note = { icon = "Interface\\Icons\\INV_Misc_Note_01", color = "muted", talk = "" },
}
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
local OPEN = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t"

local function charDB()
  WGACompanionCharDB.guide = WGACompanionCharDB.guide or {}
  return WGACompanionCharDB.guide
end

function GW:Mode()
  local g = charDB()
  if g.mode == "guide" and CM.Guides:Current() then return "guide" end
  return "smart"
end

local TRAVEL_ICON = {
  run = "Interface\\Icons\\Ability_Rogue_Sprint",
  fly = "Interface\\Icons\\Ability_Mount_Gryphon_01",
  hearth = "Interface\\Icons\\INV_Misc_Rune_01",
  hearthfly = "Interface\\Icons\\INV_Misc_Rune_01",
  portal = "Interface\\Icons\\Spell_Arcane_PortalStormWind",
}

local function where(s)
  if not s.m or not s.x then return "Location unknown yet" end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(s.m)
  local txt = string.format("%s  %.1f, %.1f", info and info.name or "", s.x * 100, s.y * 100)
  local d = CM.Arrow and CM.Arrow:Compute({ m = s.m, x = s.x, y = s.y })
  if d then txt = txt .. string.format("   ·   %d yd", d) end
  return txt
end

-- Static guide steps in the same shape as Smart Guide steps.
local function fromGuide()
  local G = CM.Guides
  local guide = G:Current()
  if not guide then return {} end
  local p = G:Progress()
  local out = {}
  for i = p.step, math.min(#guide.steps, p.step + UPCOMING) do
    local st = guide.steps[i]
    local kind = st.t
    if kind == "complete" and st.quest and CM.QData:Has() then
      local ents = CM.QData:ObjectiveEntities(st.quest, 1)
      kind = ents and ents[1] and ({ slay = "kill", loot = "loot", object = "use" })[ents[1][3]] or "complete"
    end
    local s = { kind = kind, title = G:StepTitle(st), npc = st.npc, m = st.m, guideIndex = i,
      x = st.x and st.x / 100, y = st.y and st.y / 100, quest = st.quest, tip = st.tip }
    if st.t == "complete" and st.quest then
      s.objectives = {}
      for _, o in ipairs(C_QuestLog.GetQuestObjectives(st.quest) or {}) do
        if o.text and o.text ~= "" then s.objectives[#s.objectives + 1] = { text = o.text, done = CM:Safe(o.finished) } end
      end
    end
    s.npcID = s.npc and CM.Visuals:NpcID(s.npc)
    out[#out + 1] = s
  end
  return out, string.format("%s   ·   step %d/%d", guide.name, math.min(p.step, #guide.steps), #guide.steps)
end

-- Frame --------------------------------------------------------------------------------------------
local function iconButton(parent, label, tip, onClick)
  local b = T:Button(parent, label, 12, onClick)
  b:SetSize(22, 22)
  b.text:ClearAllPoints(); b.text:SetPoint("CENTER")
  b:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end)
  b:HookScript("OnLeave", GameTooltip_Hide)
  return b
end

function GW:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionGuideWindow", UIParent)
  f:SetSize(W, 300)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  local pos = charDB().pos
  if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -300, 140) end
  T:Skin(f, "bg", "border")

  -- header
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(30)
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() f:StartMoving() end)
  head:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint()
    charDB().pos = { point, x, y }
  end)
  T:Skin(head, "sidebar")
  local logo = head:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(A .. "logo"); logo:SetSize(20, 20); logo:SetPoint("LEFT", 6, 0)
  f.title = T:Text(head, 13, "heading")
  f.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
  f.close = iconButton(head, "x", "Hide (/wga guide to show)", function() GW:Hide() end)
  f.close:SetPoint("RIGHT", -4, 0)
  f.min = iconButton(head, "-", "Show only the current step", function()
    charDB().compact = not charDB().compact; GW:Refresh()
  end)
  f.min:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.mode = iconButton(head, "S", "Switch between the Smart Guide and a loaded step guide", function()
    local g = charDB()
    if GW:Mode() == "smart" then
      if CM.Guides:Current() then g.mode = "guide" else
        local s = CM.Guides:Suggest()
        if s then CM.Guides:Load(s); g.mode = "guide" else CM:Print("No step guides installed yet; the Smart Guide builds your route from your quests.") end
      end
    else
      g.mode = "smart"
    end
    GW.focusQuest = nil
    GW:Refresh()
  end)
  f.mode:SetPoint("RIGHT", f.min, "LEFT", -2, 0)
  f.style = iconButton(head, "E", "", function()
    CM.SmartGuide:SetStyle(CM.SmartGuide:Style() == "efficient" and "completionist" or "efficient")
  end)
  f.style:SetPoint("RIGHT", f.mode, "LEFT", -2, 0)
  f.style:SetScript("OnEnter", function(self)
    local SG = CM.SmartGuide
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if SG:Style() == "efficient" then
      GameTooltip:AddLine("Efficient levelling")
      GameTooltip:AddLine("Only quests worth the time: near your level, no battleground,", 1, 1, 1)
      GameTooltip:AddLine("repeatable or hand-in-only quests. Click for Completionist.", 1, 1, 1)
      local sk = SG.skipped or {}
      if #sk > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Skipped nearby (%d):", #sk))
        for i = 1, math.min(#sk, 12) do
          GameTooltip:AddDoubleLine(sk[i].title or "?", sk[i].why, 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
        end
        if #sk > 12 then GameTooltip:AddLine(string.format("...and %d more", #sk - 12), 0.6, 0.6, 0.6) end
      end
    else
      GameTooltip:AddLine("Completionist")
      GameTooltip:AddLine("Every quest you can pick up, grey ones included.", 1, 1, 1)
      GameTooltip:AddLine("Click for Efficient levelling.", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  local line = head:CreateTexture(nil, "OVERLAY")
  line:SetHeight(2); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  T:Gradient(line)

  -- level / xp strip
  f.sub = T:Text(f, 11, "muted")
  f.sub:SetPoint("TOPLEFT", 10, -36)
  f.sub:SetPoint("RIGHT", -10, 0)
  f.sub:SetWordWrap(false)
  f.xp = CreateFrame("Frame", nil, f)
  f.xp:SetHeight(4)
  f.xp:SetPoint("TOPLEFT", 10, -52); f.xp:SetPoint("TOPRIGHT", -10, -52)
  f.xp.bg = f.xp:CreateTexture(nil, "BACKGROUND"); f.xp.bg:SetAllPoints(); f.xp.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  f.xp.fill = f.xp:CreateTexture(nil, "ARTWORK"); f.xp.fill:SetPoint("TOPLEFT"); f.xp.fill:SetPoint("BOTTOMLEFT")
  f.xp.fill:SetTexture("Interface\\Buttons\\WHITE8x8")

  -- current step card
  local card = CreateFrame("Button", nil, f)
  card:SetPoint("TOPLEFT", 8, -62); card:SetPoint("TOPRIGHT", -8, -62)
  card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  T:Skin(card, "panel", "accent")
  card.portrait = CreateFrame("Frame", nil, card)
  card.portrait:SetSize(64, 64); card.portrait:SetPoint("TOPLEFT", 8, -8)
  T:Skin(card.portrait, "bg", "border")
  card.model = CreateFrame("PlayerModel", nil, card.portrait)
  card.model:SetPoint("TOPLEFT", 1, -1); card.model:SetPoint("BOTTOMRIGHT", -1, 1)
  card.kindIcon = card.portrait:CreateTexture(nil, "ARTWORK")
  card.kindIcon:SetSize(36, 36); card.kindIcon:SetPoint("CENTER")
  card.badge = card:CreateTexture(nil, "OVERLAY")
  card.badge:SetSize(20, 20); card.badge:SetPoint("BOTTOMRIGHT", card.portrait, "BOTTOMRIGHT", 6, -6)
  card.verb = T:Text(card, 11, "warn")
  card.verb:SetPoint("TOPLEFT", card.portrait, "TOPRIGHT", 10, 0)
  card.title = T:Text(card, 14, "heading")
  card.title:SetPoint("TOPLEFT", card.verb, "BOTTOMLEFT", 0, -2)
  card.title:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.who = T:Text(card, 12, "text")
  card.who:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
  card.who:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.who:SetWordWrap(false)
  card.where = T:Text(card, 11, "muted")
  card.where:SetPoint("TOPLEFT", card.who, "BOTTOMLEFT", 0, -3)
  card.where:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.where:SetWordWrap(false)
  card.objs = T:Text(card, 12, "text")
  card.objs:SetPoint("TOPLEFT", card.portrait, "BOTTOMLEFT", 2, -10)
  card.objs:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.objs:SetSpacing(3)
  card:SetScript("OnClick", function(_, button)
    local s = GW.current
    if not s then return end
    if button == "RightButton" or s.kind == "note" or s.kind == "goto" then
      if s.guideIndex then CM.Guides:Skip(1) end
    elseif s.quest and IsShiftKeyDown() and QuestMapFrame_OpenToQuestDetails then
      QuestMapFrame_OpenToQuestDetails(s.quest)
    end
    GW:Refresh()
  end)
  card:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Current step")
    GameTooltip:AddLine("The arrow points here.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: open the quest", 1, 1, 1)
    if GW.current and GW.current.guideIndex then GameTooltip:AddLine("Right-click: mark done and move on", 1, 1, 1) end
    GameTooltip:Show()
  end)
  card:SetScript("OnLeave", GameTooltip_Hide)
  f.card = card

  -- upcoming steps
  f.nextLabel = T:Text(f, 10, "muted")
  f.nextLabel:SetText("COMING UP")
  f.rows = {}
  for i = 1, UPCOMING do
    local r = T:Button(f, "", 12)
    r:SetSize(W - 16, 22)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 6, 0)
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", 28, 0); r.text:SetPoint("RIGHT", -60, 0)
    r.text:SetWordWrap(false)
    r.dist = T:Text(r, 11, "muted")
    r.dist:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(self)
      if not self.step then return end
      GW.focusQuest = self.step.quest
      GW.focusKind = self.step.kind
      GW:Refresh()
    end)
    r:HookScript("OnEnter", function(self)
      if not self.step then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(self.step.title)
      if self.step.npc then GameTooltip:AddLine((KIND[self.step.kind] and KIND[self.step.kind].talk or "") .. " " .. self.step.npc, 1, 1, 1) end
      GameTooltip:AddLine("Click: make this the current step", 0.6, 0.8, 1)
      GameTooltip:Show()
    end)
    r:HookScript("OnLeave", GameTooltip_Hide)
    f.rows[i] = r
  end

  -- footer for step guides
  f.prev = T:Button(f, "< Back", 11, function() GW:Back() end)
  f.prev:SetSize(70, 20); f.prev.text:ClearAllPoints(); f.prev.text:SetPoint("CENTER")
  T:Skin(f.prev, "panel", "border")
  f.skip = T:Button(f, "Skip >", 11, function() GW:Skip() end)
  f.skip:SetSize(70, 20); f.skip.text:ClearAllPoints(); f.skip.text:SetPoint("CENTER")
  T:Skin(f.skip, "panel", "border")

  T:OnChange(function() if f:IsShown() then GW:Refresh() end end)
  f:Hide()
  self.frame = f
end

-- Render -------------------------------------------------------------------------------------------
local function setIcon(tex, kind)
  local k = KIND[kind] or KIND.complete
  tex:SetTexture(k.icon)
  if k.icon:find("_mono") or k.icon:find("node") then
    local c = T:Get()[k.color] or T:Get().accent
    tex:SetVertexColor(c[1], c[2], c[3], 1)
  else
    tex:SetVertexColor(1, 1, 1, 1)
  end
end

-- Smart Guide skips: a list of step keys you skipped, newest last. Back brings the last one back.
local function stepKey(s) return s and ((s.kind or "") .. ":" .. tostring(s.quest or s.title or "")) end
local function skipped()
  local g = charDB()
  g.smartSkipped = g.smartSkipped or {}
  return g.smartSkipped
end

function GW:Skip()
  if self:Mode() == "guide" then CM.Guides:Skip(1) return self:Refresh() end
  local key = stepKey(self.current)
  if not key then return end
  local list = skipped()
  list[#list + 1] = key
  while #list > 40 do table.remove(list, 1) end
  self.focusQuest = nil
  self:Refresh()
end

function GW:Back()
  if self:Mode() == "guide" then CM.Guides:Skip(-1) return self:Refresh() end
  local list = skipped()
  local key = table.remove(list)
  if not key then CM:Print("Nothing skipped to go back to.") return end
  local kind, quest = key:match("^(.-):(.*)$")
  self.focusQuest, self.focusKind = tonumber(quest), kind
  self:Refresh()
end

function GW:Steps()
  if self:Mode() == "guide" then return fromGuide() end
  local route = CM.SmartGuide:Route()
  local skip = {}
  for _, k in ipairs(skipped()) do skip[k] = true end
  if next(skip) then
    local kept = {}
    for _, s in ipairs(route) do if not skip[stepKey(s)] then kept[#kept + 1] = s end end
    route = kept
  end
  local accepts, open, ready = 0, 0, 0
  for _, s in ipairs(route) do
    if s.kind == "accept" then accepts = accepts + 1 elseif s.kind == "turnin" then ready = ready + 1 else open = open + 1 end
  end
  local style = CM.SmartGuide:Style() == "efficient" and "Efficient" or "Completionist"
  return route, string.format("%s   ·   %d to turn in, %d open, %d new", style, ready, open, accepts)
end

function GW:Refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end
  local p = T:Get()
  local steps, subtitle = self:Steps()
  local mode = self:Mode()
  f.title:SetText(mode == "smart" and "WGA Smart Guide" or "WGA Guide")
  f.mode.text:SetText(mode == "smart" and "G" or "S")
  f.style:SetShown(mode == "smart")
  f.style.text:SetText(CM.SmartGuide:Style() == "efficient" and "E" or "C")
  local level, frac = CM.SmartGuide:Summary()
  f.sub:SetText(string.format("Level %d  (%d%%)   ·   %s", level, math.floor(frac * 100), subtitle or ""))
  f.xp.bg:SetVertexColor(p.bar[1], p.bar[2], p.bar[3], 1)
  f.xp.fill:SetVertexColor(p.accent[1], p.accent[2], p.accent[3], 1)
  f.xp.fill:SetWidth(math.max(1, (W - 20) * frac))

  -- keep the step you picked on top while it still exists
  if self.focusQuest and mode == "smart" then
    for i, s in ipairs(steps) do
      if s.quest == self.focusQuest and (not self.focusKind or s.kind == self.focusKind) then
        table.remove(steps, i); table.insert(steps, 1, s); break
      end
    end
  end

  local cur = steps[1]
  self.current = cur
  if CM.Companion then CM.Companion:OnStep(cur) end
  local card = f.card
  local y
  if not cur then
    card.model:Hide(); card.kindIcon:Show(); setIcon(card.kindIcon, "note"); card.badge:Hide()
    card.verb:SetText("ALL CAUGHT UP")
    card.title:SetText(mode == "smart" and "No quests nearby" or "Guide complete")
    card.who:SetText(mode == "smart" and "Check the Leveling page in the hub for where to go next." or "Pick another guide in the hub.")
    card.where:SetText("")
    card.objs:SetText("")
    if CM.Arrow then CM.Arrow:SetTarget(nil) end
  else
    local k = KIND[cur.kind] or KIND.complete
    local verbColor = p[k.color] or p.accent
    card.verb:SetText(((cur.verb or (cur.kind and cur.kind:gsub("^%l", string.upper)) or "")):upper()
      .. (cur.level and cur.level > 0 and string.format("   ·   level %d", cur.level) or "")
      .. (cur.dungeon and "   ·   dungeon" or "") .. (cur.later and "   ·   low value" or ""))
    card.verb:SetTextColor(verbColor[1], verbColor[2], verbColor[3])
    card.title:SetText(cur.title or "")
    card.who:SetText(cur.npc and ((k.talk ~= "" and (k.talk .. " ") or "") .. "|cffffffff" .. cur.npc .. "|r") or (cur.tip or ""))
    card.where:SetText(where(cur))
    local ok = cur.npcID and pcall(card.model.SetCreature, card.model, cur.npcID)
    if ok then
      card.model:Show(); card.kindIcon:Hide()
      pcall(card.model.SetPortraitZoom, card.model, 0.75)
      card.badge:Show(); setIcon(card.badge, cur.kind)
    else
      card.model:Hide(); card.badge:Hide()
      card.kindIcon:Show(); setIcon(card.kindIcon, cur.kind)
    end
    local lines = {}
    local tr = cur.travel
    if tr and tr.text then
      local icon = TRAVEL_ICON[tr.kind] or TRAVEL_ICON.run
      lines[#lines + 1] = string.format("|T%s:14:14|t  |cff66ccff%s|r", icon, tr.text)
    end
    for _, o in ipairs(cur.objectives or {}) do
      lines[#lines + 1] = (o.done and CHECK or OPEN) .. "  " .. (o.done and ("|cff808080" .. o.text .. "|r") or o.text)
    end
    if cur.kind == "turnin" then lines[#lines + 1] = CHECK .. "  All objectives done" end
    card.objs:SetText(T:Recolor(table.concat(lines, "\n")))
    if CM.Arrow then
      local via = cur.travel and cur.travel.via
      if via then CM.Arrow:SetTarget(via.m, via.x, via.y, "Travel: " .. (cur.travel.text or ""))
      elseif cur.m and cur.x then CM.Arrow:SetTarget(cur.m, cur.x, cur.y, (cur.verb and (cur.verb .. ": ") or "") .. (cur.title or "")) else CM.Arrow:SetTarget(nil) end
    end
  end
  local objH = (cur and (#(cur.objectives or {}) > 0 or cur.kind == "turnin" or (cur.travel and cur.travel.text)))
    and (card.objs:GetStringHeight() + 12) or 0
  local cardH = 80 + objH
  card:SetHeight(cardH)
  y = -62 - cardH - 8

  local compact = charDB().compact
  local shown = 0
  f.nextLabel:ClearAllPoints()
  f.nextLabel:SetPoint("TOPLEFT", 12, y)
  f.nextLabel:SetShown(not compact and #steps > 1)
  if not compact and #steps > 1 then y = y - 16 end
  for i, r in ipairs(f.rows) do
    local s = steps[i + 1]
    if s and not compact then
      r.step = s
      setIcon(r.icon, s.kind)
      r.text:SetText(T:Recolor(string.format("%s%s", s.verb and ("|cff808080" .. s.verb .. "|r  ") or "", s.title or "")))
      local d = s.m and CM.Arrow and CM.Arrow:Compute({ m = s.m, x = s.x, y = s.y })
      r.dist:SetText(d and string.format("%d yd", d) or "")
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 8, y)
      r:Show()
      y = y - 23
      shown = shown + 1
    else
      r.step = nil
      r:Hide()
    end
  end
  local guideMode = true   -- Back / Skip in both modes
  f.prev:SetShown(guideMode); f.skip:SetShown(guideMode)
  if mode == "smart" then f.prev:SetAlpha(#skipped() > 0 and 1 or 0.4) else f.prev:SetAlpha(1) end
  if guideMode then
    f.prev:ClearAllPoints(); f.prev:SetPoint("TOPLEFT", 8, y - 4)
    f.skip:ClearAllPoints(); f.skip:SetPoint("TOPRIGHT", -8, y - 4)
    y = y - 28
  end
  f:SetHeight(-y + 8)
end

function GW:Show()
  self:Build()
  charDB().hidden = false
  self.frame:Show()
  self:Refresh()
end

function GW:Hide()
  charDB().hidden = true
  if self.frame then self.frame:Hide() end
  if CM.Arrow then CM.Arrow:SetTarget(nil) end
end

function GW:Toggle()
  self:Build()
  if self.frame:IsShown() then self:Hide() else self:Show() end
end

-- Updates: quest events right away (throttled), position every 2 seconds for distances and routing.
local pending
local function queue()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; GW:Refresh() end)
end
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED" }) do
  CM:On(e, queue)
end
CM:On("QUEST_TURNED_IN", function(_, id)
  if id and id == GW.focusQuest then GW.focusQuest = nil end
  -- a quest that's done can't be skipped any more
  local list = skipped()
  for i = #list, 1, -1 do if list[i]:match(":(.*)$") == tostring(id) then table.remove(list, i) end end
end)

function GW:OnLogin()
  if CM.db.settings.guideWindow == false then return end
  if not charDB().hidden then C_Timer.After(3, function() GW:Show() end) end
  C_Timer.NewTicker(2, function() if GW.frame and GW.frame:IsShown() then GW:Refresh() end end)
end
