-- WGA Companion: rare, treasure and watched NPC alerts
-- Sources: minimap vignettes (rares and treasures the game marks), nameplates,
-- mouseover and target. Values the client marks secret (in combat) are skipped safely.
local _, CM = ...
local R = CM:NewModule("RareFinder")
local seen = {}         -- [guid] = time of last alert
local COOLDOWN = 300    -- seconds before the same mob alerts again
R.log = {}              -- recent sightings for the UI

local function position()
  local mapID = C_Map.GetBestMapForUnit("player")
  local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
  if pos then return string.format("%.1f, %.1f", pos.x * 100, pos.y * 100) end
  return "?"
end

local function alert(key, name, tag, where, extra, mapID, x, y, level)
  if CM.db.settings.rareIgnore and CM.db.settings.rareIgnore[name:lower()] then return end
  local now = GetTime()
  if seen[key] and now - seen[key] < COOLDOWN then return end
  seen[key] = now
  local known = CM.Data.Rares and CM.Data.Rares[name]
  local msg = string.format("%s: %s%s at %s", tag, name, extra or "", where)

  RaidNotice_AddMessage(RaidWarningFrame, "|cffff8000" .. msg .. "|r", ChatTypeInfo["RAID_WARNING"])
  CM:Print("|cffff8000%s|r", msg)
  if known and known.note then CM:Print("  |cffbbbbbb%s|r", known.note) end
  if CM.db.settings.rareSound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
  if FlashClientIcon then FlashClientIcon() end

  if mapID and x and CM.Arrow and CM.db.settings.rareArrow ~= false then CM.Arrow:Point(mapID, x, y, name, 90) end
  if CM.RareButton then
    CM.RareButton:Remember(key, name)
    CM.RareButton:Show({ name = name, tag = tag, where = where, npcID = CM.RareButton.NpcID(key), mapID = mapID, x = x, y = y, level = level })
  end
  table.insert(R.log, 1, { name = name, tag = tag, where = where, at = date("%H:%M"), npc = CM.RareButton and CM.RareButton.NpcID(key) })
  while #R.log > 30 do table.remove(R.log) end
end


local function check(unit)
  if not CM.db or not CM.db.settings.rareAlerts then return end
  local S = function(v) return CM:Safe(v) end
  if not S(UnitExists(unit)) or S(UnitIsPlayer(unit)) ~= false or S(UnitIsDead(unit)) then return end
  local guid, name, class = S(UnitGUID(unit)), S(UnitName(unit)), S(UnitClassification(unit))
  if not guid or not name then return end
  local known = CM.Data.Rares and CM.Data.Rares[name]
  local watched = CM.db.settings.watchList[name:lower()]
  if not (class == "rare" or class == "rareelite" or known or watched) then return end
  local level = S(UnitLevel(unit))
  local tag = class == "rareelite" and "Rare Elite" or (class == "rare" and "Rare" or "Watched")
  local lvl = (not level or level == -1) and "??" or level
  alert(guid, name, tag, GetZoneText() .. " " .. position(), string.format(" (lvl %s)", lvl), nil, nil, nil, lvl)
end

-- Vignettes: the modern client marks rares and treasures on the minimap.
local function checkVignette(vguid)
  if not CM.db or not CM.db.settings.rareAlerts or not C_VignetteInfo then return end
  local info = C_VignetteInfo.GetVignetteInfo(vguid)
  if not info or not info.name then return end
  local atlas = (info.atlasName or ""):lower()
  local tag = atlas:find("loot") and "Treasure" or ((atlas:find("kill") or atlas:find("elite")) and "Rare" or "Point of interest")
  if tag == "Treasure" and CM.db.settings.treasureAlerts == false then return end
  local mapID = C_Map.GetBestMapForUnit("player")
  local pos = mapID and C_VignetteInfo.GetVignettePosition(vguid, mapID)
  local where = GetZoneText()
  local x, y
  if pos then x, y = pos.x, pos.y; where = string.format("%s %.1f, %.1f", where, x * 100, y * 100) end
  alert(info.objectGUID or vguid, info.name, tag, where, nil, mapID, x, y)
end

CM:On("VIGNETTE_MINIMAP_UPDATED", function(_, vguid, onMinimap) if onMinimap then checkVignette(vguid) end end)
CM:On("VIGNETTES_UPDATED", function()
  if not C_VignetteInfo then return end
  for _, g in ipairs(C_VignetteInfo.GetVignettes() or {}) do
    local info = C_VignetteInfo.GetVignetteInfo(g)
    if info and info.onMinimap then checkVignette(g) end
  end
end)
CM:On("NAME_PLATE_UNIT_ADDED", function(_, unit) check(unit) end)
CM:On("UPDATE_MOUSEOVER_UNIT", function() check("mouseover") end)
CM:On("PLAYER_TARGET_CHANGED", function() check("target") end)

function R:Lines()
  local lines = { "|cffffd100Rare & unique finder|r", "",
    "Alerts (card with model, loot and a Target button, sound, arrow) when a rare, treasure or watched NPC appears on",
    "your minimap, a nameplate, under your mouse or as your target.",
    "Add your own: /wga watch <npc name>.   Toggle: /wga rares (currently " ..
      (CM.db.settings.rareAlerts and "|cff40ff40on|r" or "|cffff4040off|r") .. ")", "",
    "|cffffd100Recent sightings|r" }
  if #R.log == 0 then table.insert(lines, "|cff808080None this session.|r") end
  for _, e in ipairs(R.log) do
    table.insert(lines, string.format("[%s] |cffff8000%s|r (%s) - %s", e.at, e.name, e.tag, e.where))
  end
  local ign = {}
  for n in pairs(CM.db.settings.rareIgnore or {}) do table.insert(ign, n) end
  table.sort(ign)
  table.insert(lines, "")
  table.insert(lines, "|cffffd100Ignored|r (shift + right-click an alert card to add; /wga rares unignore <name>): " ..
    (#ign > 0 and table.concat(ign, ", ") or "|cff808080none|r"))
  local learned = 0
  for _ in pairs(CM.db.global.rareLoot or {}) do learned = learned + 1 end
  table.insert(lines, string.format("Loot learned for %d rare(s). It shows on the alert card.", learned))
  local watch = {}
  for n in pairs(CM.db.settings.watchList) do table.insert(watch, n) end
  table.sort(watch)
  table.insert(lines, "")
  table.insert(lines, "|cffffd100Your watch list|r: " .. (#watch > 0 and table.concat(watch, ", ") or "|cff808080empty|r"))
  table.insert(lines, "")
  table.insert(lines, "|cffffd100Notable rares by zone|r")
  local byZone, zones = {}, {}
  for n, info in pairs(CM.Data.Rares or {}) do
    if not byZone[info.zone] then byZone[info.zone] = {}; table.insert(zones, info.zone) end
    table.insert(byZone[info.zone], n .. (info.note and (" |cffbbbbbb- " .. info.note .. "|r") or ""))
  end
  table.sort(zones)
  for _, z in ipairs(zones) do
    table.sort(byZone[z])
    table.insert(lines, "|cffffffff" .. z .. "|r")
    for _, s in ipairs(byZone[z]) do table.insert(lines, "   " .. s) end
  end
  return lines
end
