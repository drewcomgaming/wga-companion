-- WGA Companion: core namespace, events, saved variables, helpers and slash commands
local ADDON, CM = ...
_G.WGACompanion = CM

CM.version = "0.16.1"
CM.modules = {}
CM.Data = CM.Data or {}

local defaults = {
  global = {
    vendorBuy = {},      -- [itemID] = copper per unit, learned at merchants
    itemNames = {},      -- [itemID] = name, for market search
    spots = {},          -- [questID][objective] = learned quest objective spots
    rareLoot = {},       -- [rare name][itemID] = times seen dropping
    keep = {},           -- [itemID] = true, never sold or dropped
    shopping = { cur = 1, lists = { { name = "Shopping", items = {} } } },
  },
  realms = {},           -- [realm-faction] = { prices = {}, lastScan = 0, recipes = {} }
  settings = {
    tooltip = true,
    rareAlerts = true,
    rareSound = true,
    autoSellJunk = true,
    flipMinProfit = 5000, -- 50s minimum profit for a vendor flip to be listed
    watchList = {},       -- [lower name] = true, extra NPC names to alert on
    questArrow = true,    -- arrow points at your tracked/closest quest when no guide is loaded
    questPins = true,     -- quest objective and turn-in spots on the world map
    minimapButton = true, -- WGA button on the minimap edge
    minimapAngle = 215,   -- its position around the minimap, in degrees
    questMinimap = true,  -- the same quest icons on the minimap
    questAvailable = true, -- "!" on the world map for quests you can pick up
    questPlates = true,   -- "!" over mobs you still need
    theme = "dark",       -- dark | light | hcdark | hclight
    uiScale = 1, fontScale = 1, trackerScale = 1,
    tracker = true,          -- WGA quest tracker
    hideBlizzTracker = true, -- hide the default objective tracker while ours is on
    trackerAlpha = 0.85,
    trackerCollapsed = {},   -- [zone] = true
    trackerFolded = {},      -- [questID] = true
    rareIgnore = {},         -- [lower name] = true, never alert
    rareButton = true,       -- alert card with model, loot and Target button
    lootSwap = true,         -- offer to swap out the cheapest bag item when bags are full
    shopping = true,         -- shopping list panel at the auction house
    rareHideDone = false,    -- hide rares you have killed and collected everything from
    autoQuest = true,        -- accept the guide's quests and hand in finished ones when you talk to NPCs
    autoReward = true,       -- pick the quest reward: a real upgrade, else the most valuable
    upgradeIlvl = 5,         -- item levels better than what you wear to count as a real upgrade
    guideEfficient = true,   -- Smart Guide: only quests worth the time (false = completionist)
    guideDungeons = true,    -- Smart Guide: suggest dungeon quests
    companion = true,        -- talking companion above the guide window
    companionVoiceOn = false, -- read the companion's lines aloud (game text-to-speech)
    companionName = "Whirl",
  },
}

local function copyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      copyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- Event dispatch -------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function CM:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end

-- Registering an event the client does not know throws on the modern client.
local _RegisterEvent = frame.RegisterEvent
frame.RegisterEvent = function(self, ev)
  local ok = pcall(_RegisterEvent, self, ev)
  if not ok then CM.unknownEvents = (CM.unknownEvents or 0) + 1 end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then geterrorhandler()(err) end
  end
end)

-- Helpers ----------------------------------------------------------------------
function CM:Print(msg, ...)
  if select("#", ...) > 0 then msg = string.format(msg, ...) end
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100WGA Companion|r: " .. tostring(msg))
end

function CM:Money(copper, short)
  if not copper then return "|cff808080--|r" end
  copper = math.floor(copper + 0.5)
  local neg = copper < 0
  if neg then copper = -copper end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out
  if g > 0 then
    out = string.format("|cffffd700%dg|r", g)
    if not short or g < 100 then out = out .. string.format(" |cffc7c7cf%ds|r", s) end
    if not short then out = out .. string.format(" |cffeda55f%dc|r", c) end
  elseif s > 0 then
    out = string.format("|cffc7c7cf%ds|r", s)
    if not short or s < 10 then out = out .. string.format(" |cffeda55f%dc|r", c) end
  else
    out = string.format("|cffeda55f%dc|r", c)
  end
  return (neg and "|cffff4040-|r" or "") .. out
end

function CM:ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("item:(%d+)")
  return id and tonumber(id)
end

function CM:Age(ts)
  if not ts or ts == 0 then return "never" end
  local d = time() - ts
  if d < 3600 then return string.format("%dm ago", math.floor(d / 60)) end
  if d < 86400 then return string.format("%dh ago", math.floor(d / 3600)) end
  return string.format("%dd ago", math.floor(d / 86400))
end

function CM:RealmKey()
  return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end

function CM:Realm()
  local key = self:RealmKey()
  local r = self.db.realms[key]
  if not r then
    r = { prices = {}, lastScan = 0, recipes = {} }
    self.db.realms[key] = r
  end
  return r
end

-- API helpers (WoW Forever uses the modern retail API; old globals are gone) ---------
CM.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
CM.GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

function CM:SellPrice(itemID)
  local sell = select(11, CM.GetItemInfo(itemID))
  if sell == nil and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
  return sell
end

-- Secret values: in combat the modern client may hand addons opaque values that
-- error on comparison. Treat them as unknown.
function CM:Safe(v)
  if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
  return v
end

local NUM_BAGS = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
CM.Bags = {
  Last = NUM_BAGS,
  NumSlots = function(bag) return C_Container.GetContainerNumSlots(bag) or 0 end,
  Link = function(bag, slot) return C_Container.GetContainerItemLink(bag, slot) end,
  Info = function(bag, slot) return C_Container.GetContainerItemInfo(bag, slot) end,
  Count = function(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0, info and info.isLocked
  end,
  Use = function(bag, slot) C_Container.UseContainerItem(bag, slot) end,
}

-- Iterate every bag slot holding an item: fn(bag, slot, info)
function CM:ForEachBagItem(fn)
  for bag = 0, CM.Bags.Last do
    for slot = 1, CM.Bags.NumSlots(bag) do
      local info = CM.Bags.Info(bag, slot)
      if info and info.itemID then fn(bag, slot, info) end
    end
  end
end

-- Init -------------------------------------------------------------------------
CM:On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  WGACompanionDB = WGACompanionDB or {}
  WGACompanionCharDB = WGACompanionCharDB or {}
  copyDefaults(defaults, WGACompanionDB)
  CM.db = WGACompanionDB
  for _, m in pairs(CM.modules) do
    if m.OnInit then m:OnInit() end
  end
end)

CM:On("PLAYER_LOGIN", function()
  for _, m in pairs(CM.modules) do
    if m.OnLogin then m:OnLogin() end
  end
  CM:Print("v%s loaded. Type |cff00ff00/wga|r to open, |cff00ff00/wga help|r for commands.", CM.version)
end)

function CM:NewModule(name)
  local m = { name = name }
  self.modules[name] = m
  self[name] = m
  return m
end

-- Slash commands -----------------------------------------------------------------
SLASH_WGACOMPANION1 = "/wga"
SLASH_WGACOMPANION2 = "/wgacompanion"
SlashCmdList.WGACOMPANION = function(input)
  local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    CM.UI:Toggle()
  elseif cmd == "scan" then
    CM.Scanner:Start()
  elseif cmd == "price" and rest ~= "" then
    CM.PriceDB:PrintPrice(rest)
  elseif cmd == "house" then
    if rest ~= "" then CM.PriceDB:SetHouse(rest) else CM.PriceDB:ListHouses() end
  elseif cmd == "bags" then
    CM.Merchant:BagReport()
  elseif cmd == "watch" and rest ~= "" then
    CM.db.settings.watchList[rest:lower()] = true
    CM:Print("Now watching for '%s'.", rest)
  elseif cmd == "unwatch" and rest ~= "" then
    CM.db.settings.watchList[rest:lower()] = nil
    CM:Print("Stopped watching '%s'.", rest)
  elseif cmd == "rares" and rest:match("^unignore ") then
    CM.db.settings.rareIgnore[rest:match("^unignore%s+(.+)$"):lower()] = nil
    CM:Print("Alerts back on for %s.", rest:match("^unignore%s+(.+)$"))
  elseif cmd == "rares" and rest:match("^ignore ") then
    CM.db.settings.rareIgnore[rest:match("^ignore%s+(.+)$"):lower()] = true
    CM:Print("Ignoring %s.", rest:match("^ignore%s+(.+)$"))
  elseif cmd == "rares" and rest == "test" then
    CM.RareButton:Test()
  elseif cmd == "rares" then
    CM.db.settings.rareAlerts = not CM.db.settings.rareAlerts
    CM:Print("Rare alerts %s.", CM.db.settings.rareAlerts and "on" or "off")
  elseif cmd == "tooltip" then
    CM.db.settings.tooltip = not CM.db.settings.tooltip
    CM:Print("Tooltip prices %s.", CM.db.settings.tooltip and "on" or "off")
  elseif cmd == "junk" then
    CM.db.settings.autoSellJunk = not CM.db.settings.autoSellJunk
    CM:Print("Auto-sell grey items %s.", CM.db.settings.autoSellJunk and "on" or "off")
  elseif cmd == "companion" or cmd == "buddy" then
    CM.Companion:Command(rest or "")
  elseif cmd == "auto" then
    local st = CM.db.settings
    if rest == "rewards" then
      st.autoReward = st.autoReward == false
      CM:Print("Auto reward pick %s.", st.autoReward and "on" or "off")
    elseif rest:match("^upgrade %d+$") then
      st.upgradeIlvl = tonumber(rest:match("%d+"))
      CM:Print("A reward counts as an upgrade at %d+ item levels over what you wear.", st.upgradeIlvl)
    else
      st.autoQuest = st.autoQuest == false
      CM:Print("Auto accept and turn in %s. Hold Shift while talking to an NPC to skip it once.", st.autoQuest and "on" or "off")
    end
  elseif cmd == "guide" and (rest == "efficient" or rest == "fast") then
    CM.SmartGuide:SetStyle("efficient")
  elseif cmd == "guide" and (rest == "all" or rest == "completionist") then
    CM.SmartGuide:SetStyle("completionist")
  elseif cmd == "guide" and rest == "smart" then
    WGACompanionCharDB.guide.mode = "smart"
    CM.GuideWindow:Show()
  elseif cmd == "guide" then
    if rest ~= "" then CM.Guides:Load(rest) else CM.Guides:Toggle() end
  elseif cmd == "guides" then
    CM.Guides:PrintList()
  elseif cmd == "reset" then
    CM.Guides:Reset()
  elseif cmd == "minimap" or cmd == "button" then
    CM.MinimapButton:SetShown(not (CM.db.settings.minimapButton ~= false))
  elseif cmd == "keep" then
    CM.LootSwap:ToggleKeep(rest)
  elseif cmd == "shop" or cmd == "shopping" then
    CM.Shopping:Toggle()
  elseif cmd == "theme" then
    if rest ~= "" then CM.Theme:Set(rest:lower()) else CM.Theme:Cycle() end
  elseif cmd == "tracker" then
    CM.db.settings.tracker = not (CM.db.settings.tracker ~= false)
    CM.Tracker:Update()
  elseif cmd == "settings" or cmd == "options" then
    CM.UI:Show("Settings")
  elseif cmd == "arrow" then
    if rest == "reset" then CM.Arrow:ResetPosition() else CM.Arrow:Toggle() end
  elseif cmd == "quest" or cmd == "q" then
    CM.QuestNav:Command(rest)
  elseif cmd == "record" then
    CM.Recorder:Command(rest)
  elseif cmd == "dungeon" or cmd == "prof" or cmd == "gold" or cmd == "level" then
    CM.UI:Show(({ level = "Leveling", dungeon = "Dungeons", prof = "Professions", gold = "Gold" })[cmd])
  else
    CM:Print("Commands:")
    CM:Print("  /wga  - open the window")
    CM:Print("  /wga minimap  - show or hide the minimap button")
    CM:Print("  /wga settings  - themes, sizes and feature toggles")
    CM:Print("  /wga theme [dark|light|hcdark|hclight]  - switch theme")
    CM:Print("  /wga tracker  - show or hide the WGA quest tracker")
    CM:Print("  /wga scan  - scan the auction house (AH window must be open)")
    CM:Print("  /wga price <item name or link>  - show stored prices")
    CM:Print("  /wga house [id]  - list or pick the region auction house (0 = automatic)")
    CM:Print("  /wga bags  - what to vendor vs. auction in your bags")
    CM:Print("  /wga watch|unwatch <npc name>  - custom rare/NPC alerts")
    CM:Print("  /wga rares | tooltip | junk  - toggle features")
    CM:Print("  /wga rares test | ignore <name> | unignore <name>  - rare alert card and filters")
    CM:Print("  /wga keep [item link]  - toggle an item on your keep list, or list it")
    CM:Print("  /wga shop  - show the shopping list panel (at the auction house)")
    CM:Print("  /wga guide [name]  - show/hide the guide window (Smart Guide or a step guide), or load one")
    CM:Print("  /wga guide smart  - switch the guide window to the Smart Guide")
    CM:Print("  /wga auto | auto rewards | auto upgrade <n>  - auto accept/turn in, reward picking (hold Shift to skip)")
    CM:Print("  /wga guide efficient | all  - Smart Guide picks only quests worth the time, or every quest")
    CM:Print("  /wga companion [on|off|voice|voices|voice <n>|rate <n>|name <name>|look|say]  - your talking guide buddy")
    CM:Print("  /wga guides | reset | arrow  - list guides, restart guide, toggle arrow")
    CM:Print("  /wga quest [arrow|pins|minimap|available|marks|size|why]  - quest arrow, map icons and mob marks")
    CM:Print("  /wga record start|stop|export  - record your own route as a guide")
    CM:Print("  /wga level | dungeon | prof | gold  - reference pages")
  end
end
