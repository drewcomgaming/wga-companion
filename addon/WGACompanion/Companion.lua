-- WGA Companion: the companion. A little guide character that sits on the guide window, explains
-- each step in plain words, cheers you on and warns you about things (full bags, a full quest log,
-- rares nearby), and can read it all out loud with the game's own text-to-speech.
-- Everything is worked out inside the game from your quests and the quest database; no internet.
local _, CM = ...
local C = CM:NewModule("Companion")
local T = CM.Theme

local MODELS = {   -- choices for the companion's look: creature IDs, or a unit
  { name = "Faerie dragon", npc = 5278 },
  { name = "Owl", npc = 1995 },
  { name = "Whirlwind", npc = 1792 },
  { name = "Your pet", unit = "pet" },
  { name = "You", unit = "player" },
}
C.MODELS = MODELS

local function S() return CM.db.settings end

-- Words ------------------------------------------------------------------------------------------
local DIRS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
local function direction(bearing)
  if not bearing then return nil end
  local i = math.floor(((bearing % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8 + 1
  return DIRS[i]
end

local function pick(list) return list[math.random(#list)] end

local function distanceWords(step)
  if not (step.m and step.x and CM.Arrow) then return nil end
  local d, b = CM.Arrow:Compute({ m = step.m, x = step.x, y = step.y })
  if not d then return nil end
  if d < 15 then return "right here" end
  local dir = direction(b)
  if d < 1000 then return string.format("about %d yards %s", math.floor(d / 10 + 0.5) * 10, dir) end
  return string.format("a fair run %s, about %.1f thousand yards", dir, d / 1000)
end

local function levelWords(step)
  local lvl, me = step.level, UnitLevel("player") or 1
  if not lvl or lvl <= 0 then return nil end
  if lvl >= me + 3 then return "It's a tough one for your level, so bring a friend or wait a level." end
  if lvl <= me - 6 then return "It's an easy one now, quick experience." end
  return nil
end

local function remaining(step)
  for _, o in ipairs(step.objectives or {}) do
    if not o.done then
      local have, need = o.have, o.need
      if have and need and need > 0 then return need - have, o.text end
      return nil, o.text
    end
  end
end

-- One explanation for a step, in a friendly voice.
function C:Explain(step)
  if not step then
    return pick({ "We're all caught up here. Check the Leveling page for where to head next.",
      "Nothing left nearby. Want to try the next zone up? The Leveling page has ideas." })
  end
  local where = distanceWords(step)
  local title = step.title or "this quest"
  local npc = step.npc or "the quest giver"
  local parts = {}
  if step.kind == "accept" then
    parts[#parts + 1] = pick({ "Let's pick up %s from %s.", "%s is waiting for us. %s has it.", "Next up: grab %s from %s." })
      :format(title, npc)
  elseif step.kind == "turnin" then
    parts[#parts + 1] = pick({ "Nice work, %s is done! Let's hand it in to %s.", "%s is complete. %s will want to hear about it.",
      "All done with %s. Turn it in to %s for your reward." }):format(title, npc)
  elseif (step.kind == "kill" or step.kind == "loot" or step.kind == "use") and not step.npc then
    local _, text = remaining(step)
    parts[#parts + 1] = text and string.format("For %s, we still need: %s.", title, (text:gsub("%s*%d+/%d+", "")))
      or string.format("Let's finish %s.", title)
  elseif step.kind == "kill" then
    local left = remaining(step)
    parts[#parts + 1] = left and string.format("For %s, we need to take down %d more %s.", title, left, npc)
      or string.format("For %s, we need to take down some %s.", title, npc)
  elseif step.kind == "loot" then
    local left, text = remaining(step)
    parts[#parts + 1] = string.format("For %s, %s drop what we need%s.", title, npc,
      left and string.format(", %d more to go", left) or "")
    if text then parts[#parts + 1] = "We're after: " .. text:gsub("%s*%d+/%d+", "") .. "." end
  elseif step.kind == "use" then
    parts[#parts + 1] = string.format("For %s, look for the %s and click it.", title, npc)
  elseif step.kind == "flight" then
    parts[#parts + 1] = pick({ "%s has a flight path we don't have yet. Let's grab it, it'll save us loads of walking later.",
      "Quick stop: let's learn the flight path from %s while we're close." }):format(npc)
  elseif step.kind == "goto" then
    parts[#parts + 1] = string.format("Let's head over: %s.", title)
  else
    parts[#parts + 1] = string.format("Let's work on %s.", title)
  end
  if where then parts[#parts + 1] = (where == "right here") and "It's right here." or ("It's " .. where .. ".") end
  local tr = step.travel
  if tr and tr.kind ~= "run" and tr.text then
    parts[#parts + 1] = (tr.kind == "fly" and "Quickest is to take the flight path: "
      or tr.kind == "hearth" and "Your hearthstone is ready and it's faster: "
      or tr.kind == "portal" and "Here's how we get there: "
      or "Best way there: ") .. tr.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "") .. "."
  end
  if step.phase == "town" and step.kind == "accept" then
    parts[#parts + 1] = "Let's grab everything in town before we head out."
  elseif step.phase == "return" and step.kind == "turnin" then
    parts[#parts + 1] = "Field work's done, time to cash in."
  end
  if step.dungeon then
    parts[#parts + 1] = step.kind == "accept" and "It's a dungeon quest, so grab it before your next run there."
      or "This one is done inside a dungeon, so it's best with a group."
  end
  if step.later then
    parts[#parts + 1] = string.format("Heads up, this one isn't great value (%s). Finish it if it's on the way, or drop it.", step.later)
  end
  local lw = not step.later and levelWords(step)
  if lw then parts[#parts + 1] = lw end
  local out = table.concat(parts, " "):gsub("^%l", string.upper):gsub("([%.!?] )(%l)", function(a, b) return a .. b:upper() end)
  return out
end

-- Voice ------------------------------------------------------------------------------------------
local function voiceID()
  local id
  if C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then
    local ok, v = pcall(C_TTSSettings.GetVoiceOptionID, Enum.TtsVoiceType.Standard)
    if ok then id = v end
  end
  if not id and C_VoiceChat and C_VoiceChat.GetTtsVoices then
    local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
    local choice = S().companionVoice or 1
    local v = ok and voices and (voices[choice] or voices[1])
    id = v and v.voiceID
  end
  if S().companionVoice and C_VoiceChat and C_VoiceChat.GetTtsVoices then
    local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
    local v = ok and voices and voices[S().companionVoice]
    if v then id = v.voiceID end
  end
  return id or 0
end

function C:Say(text)
  if S().companionVoiceOn ~= true or not (C_VoiceChat and C_VoiceChat.SpeakText) or not text then return end
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  pcall(C_VoiceChat.StopSpeakingText)
  local rate = S().companionRate or 0
  local dest = Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback or 1
  -- the call's shape changed between client versions; try the newer one first
  if not pcall(C_VoiceChat.SpeakText, voiceID(), plain, rate, 100, false) then
    pcall(C_VoiceChat.SpeakText, voiceID(), plain, dest, rate, 100)
  end
end

function C:VoiceNames()
  local out = {}
  if C_VoiceChat and C_VoiceChat.GetTtsVoices then
    local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
    for i, v in ipairs(ok and voices or {}) do out[i] = v.name end
  end
  return out
end

-- The voice picked in the game's own Options > Accessibility > Text to Speech
function C:SettingsVoice()
  if not (C_TTSSettings and Enum and Enum.TtsVoiceType) then return nil end
  local okN, name = pcall(C_TTSSettings.GetVoiceOptionName, Enum.TtsVoiceType.Standard)
  local okI, id = pcall(C_TTSSettings.GetVoiceOptionID, Enum.TtsVoiceType.Standard)
  return okN and name or nil, okI and id or nil
end

hooksecurefunc(CM.GuideWindow, "Hide", function() if C.frame then C.frame:Hide() end end)

-- Ask the game to (re)load the voice list; it fills in a moment later
CM:On("VOICE_CHAT_TTS_VOICES_UPDATE", function() C.voicesLoaded = true end)

-- Frame -------------------------------------------------------------------------------------------
local function charDB()
  WGACompanionCharDB.companion = WGACompanionCharDB.companion or {}
  return WGACompanionCharDB.companion
end

-- Its own window. Sits just above the guide window until you drag it somewhere else.
function C:Place()
  local f, gw = self.frame, CM.GuideWindow and CM.GuideWindow.frame
  if not f then return end
  f:ClearAllPoints()
  local pos = charDB().pos
  if pos then
    f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
  elseif gw then
    f:SetPoint("BOTTOMLEFT", gw, "TOPLEFT", 0, 8)
  else
    f:SetPoint("CENTER")
  end
end

function C:Build(anchor)
  if self.frame then return end
  local f = CreateFrame("Frame", "WGACompanionBuddy", UIParent)
  f:SetSize(340, 80)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint()
    charDB().pos = { point, x, y }
  end)
  f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and IsShiftKeyDown() then charDB().pos = nil; C:Place() end
  end)
  T:Skin(f, "bg", "border")
  f.portrait = CreateFrame("Frame", nil, f)
  f.portrait:SetSize(64, 64)
  f.portrait:SetPoint("TOPLEFT", 8, -8)
  T:Skin(f.portrait, "panel", "accent")
  f.model = CreateFrame("PlayerModel", nil, f.portrait)
  f.model:SetPoint("TOPLEFT", 1, -1); f.model:SetPoint("BOTTOMRIGHT", -1, 1)
  f.portrait:EnableMouse(true)
  f.portrait:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then C:CycleModel() else C:Speak(true) end
  end)
  f.portrait:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(S().companionName or "Whirl")
    GameTooltip:AddLine("Click: say that again", 1, 1, 1)
    GameTooltip:AddLine("Right-click: change my look", 1, 1, 1)
    GameTooltip:AddLine("Drag the window to move it; Shift + right-click it to put it back", 1, 1, 1)
    GameTooltip:Show()
  end)
  f.portrait:SetScript("OnLeave", GameTooltip_Hide)

  f.bubble = CreateFrame("Frame", nil, f)
  f.bubble:SetPoint("TOPLEFT", f.portrait, "TOPRIGHT", 8, 2)
  f.bubble:SetPoint("BOTTOMRIGHT", -6, 6)
  f.name = T:Text(f.bubble, 11, "heading")
  f.name:SetPoint("TOPLEFT", 8, -6)
  f.voice = T:Button(f.bubble, "", 11, function()
    S().companionVoiceOn = not (S().companionVoiceOn == true)
    if not S().companionVoiceOn then pcall(C_VoiceChat.StopSpeakingText) end
    C:Paint()
    if S().companionVoiceOn then C:Speak(true) end
  end)
  f.voice:SetSize(70, 16); f.voice:SetPoint("TOPRIGHT", -4, -4)
  f.voice.text:ClearAllPoints(); f.voice.text:SetPoint("RIGHT", -4, 0)
  f.text = T:Text(f.bubble, 12, "text")
  f.text:SetPoint("TOPLEFT", 8, -22); f.text:SetPoint("TOPRIGHT", -8, -22)
  f.text:SetJustifyV("TOP")
  f.text:SetWordWrap(true)
  T:OnChange(function() C:Paint() end)
  self.frame = f
  self:ApplyModel()
  self:Paint()
end

function C:Paint()
  local f = self.frame
  if not f then return end
  f.name:SetText(S().companionName or "Whirl")
  f.voice.text:SetText(S().companionVoiceOn and "Voice: on" or "Voice: off")
end

function C:ApplyModel()
  local f = self.frame
  if not f then return end
  local choice = MODELS[S().companionModel or 1] or MODELS[1]
  local ok
  if choice.unit then
    ok = UnitExists(choice.unit) and pcall(f.model.SetUnit, f.model, choice.unit)
  else
    ok = pcall(f.model.SetCreature, f.model, choice.npc)
  end
  if not ok then pcall(f.model.SetCreature, f.model, MODELS[1].npc) end
  pcall(f.model.SetPortraitZoom, f.model, 0.6)
  f.model:SetFacing(0.3)
end

function C:CycleModel()
  S().companionModel = (S().companionModel or 1) % #MODELS + 1
  self:ApplyModel()
  CM:Print("Companion look: %s", MODELS[S().companionModel].name)
end

-- Talking ---------------------------------------------------------------------------------------------
-- Called by the guide window each refresh with the current step; speaks when the step changes.
function C:OnStep(step)
  if S().companion == false then if self.frame then self.frame:Hide() end return end
  local gw = CM.GuideWindow.frame
  if not gw then return end
  if not self.frame then self:Build(gw); self:Place() end
  self.frame:SetShown(gw:IsShown())
  local key = step and table.concat({ step.kind or "", step.quest or "", step.npc or "", step.guideIndex or "" }, ":") or "none"
  self.step = step
  if key ~= self.lastKey then
    self.lastKey = key
    self:Speak(true)
  end
end

function C:Speak(aloud, text)
  local f = self.frame
  if not f then return end
  text = text or self:Explain(self.step)
  self.lastText = text
  f.text:SetText(text)
  self:Fit()
  C_Timer.After(0, function() self:Fit() end)   -- again once the text has been laid out
  if aloud then self:Say(text) end
end

-- Grow the bubble (upwards) so the whole line fits.
function C:Fit()
  local f = self.frame
  if not f then return end
  local h = (f.text:GetStringHeight() or 0) + 40
  f:SetHeight(math.max(80, math.min(h, 320)))
end

-- A one-off remark that interrupts the step explanation for a moment.
function C:Remark(text)
  if S().companion == false or not self.frame or not self.frame:IsVisible() then return end
  self:Speak(true, text)
  C_Timer.After(12, function()
    if self.lastText == text then self:Speak(false) end
  end)
end

local function freeSlots()
  local free = 0
  for bag = 0, CM.Bags.Last do
    free = free + ((C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots(bag)) or 0)
  end
  return free
end

CM:On("PLAYER_LEVEL_UP", function(_, level)
  C:Remark(pick({ "Level %d! You're getting stronger. Don't forget to visit your trainer.",
    "Ding, level %d! New skills might be waiting at your trainer." }):format(level or (UnitLevel("player") or 0)))
end)
CM:On("QUEST_TURNED_IN", function()
  C_Timer.After(0.5, function() C:Remark(pick({ "Quest done. Nice!", "Another one handed in. Good job.", "That's one more off the list!" })) end)
end)
local bagWarned = -1000
CM:On("BAG_UPDATE_DELAYED", function()
  local free = freeSlots()
  if free <= 2 and GetTime() - bagWarned > 300 then
    bagWarned = GetTime()
    C:Remark(free == 0 and "Your bags are full! Sell or drop something so we don't miss loot."
      or "Your bags are almost full. A vendor trip soon would help.")
  end
end)
CM:On("QUEST_ACCEPTED", function()
  local n = select(2, C_QuestLog.GetNumQuestLogEntries())
  local max = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 25
  if n and n >= max - 1 then C:Remark("Your quest log is nearly full. Let's finish a few before taking more.") end
end)

function C:OnRare(name)
  self:Remark(string.format("Look out, %s is nearby! It's a rare, and it might drop something good.", name))
end

-- /wga companion [on|off|voice|name <name>|look|voices|voice <n>|rate <-10..10>|say]
function C:Command(rest)
  local cmd, arg = rest:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  local s = S()
  if cmd == "" or cmd == "on" or cmd == "off" then
    if cmd == "" then s.companion = s.companion == false else s.companion = cmd == "on" end
    self.lastKey = nil
    if s.companion == false and self.frame then self.frame:Hide() end
    CM.GuideWindow:Refresh()
    CM:Print("Companion %s.", s.companion ~= false and "on" or "off")
  elseif cmd == "voice" and arg ~= "" and tonumber(arg) then
    s.companionVoice = tonumber(arg) > 0 and tonumber(arg) or nil
    if not s.companionVoice then CM:Print("Companion follows the game's Text to Speech voice.") self:Speak(true) return end
    CM:Print("Companion voice %d: %s", s.companionVoice, self:VoiceNames()[s.companionVoice] or "?")
    self:Speak(true)
  elseif cmd == "voice" or cmd == "talk" then
    s.companionVoiceOn = not (s.companionVoiceOn == true)
    if not s.companionVoiceOn then pcall(C_VoiceChat.StopSpeakingText) end
    self:Paint()
    CM:Print("Companion voice %s.", s.companionVoiceOn and "on" or "off")
    if s.companionVoiceOn then self:Speak(true) end
  elseif cmd == "voices" then
    local names = self:VoiceNames()
    for i, n in ipairs(names) do CM:Print("  %d. %s", i, n) end
    local sname = self:SettingsVoice()
    if #names == 0 then
      CM:Print("The game hasn't given addons a voice list. Pick your voice in Options > Accessibility > Text to Speech instead; the companion uses that voice.")
    end
    CM:Print("Game's Text to Speech voice: %s%s", sname or "unknown",
      s.companionVoice and string.format(" (companion overrides it with voice %d; /wga companion voice 0 to follow the game)", s.companionVoice) or " (companion uses this one)")
  elseif cmd == "rate" then
    s.companionRate = math.max(-10, math.min(10, tonumber(arg) or 0))
    CM:Print("Companion speaking speed %d.", s.companionRate)
  elseif cmd == "name" and arg ~= "" then
    s.companionName = arg:sub(1, 24)
    self:Paint()
    CM:Print("Your companion is now called %s.", s.companionName)
  elseif cmd == "look" then
    self:CycleModel()
  elseif cmd == "say" then
    self:Speak(true)
  elseif CM.Advisor and CM.Advisor:Command(cmd, arg) then
    return
  else
    CM:Print("/wga companion [on|off] | voice | voices | voice <n> | rate <-10..10> | name <name> | look | say")
    CM:Print("Advice: /wga companion advice | build | stats | dungeons | gear | style solo|group | experience new|veteran")
  end
end
