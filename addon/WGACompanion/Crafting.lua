-- WGA Companion: crafting profit for the open profession window (C_TradeSkillUI)
local _, CM = ...
local Cr = CM:NewModule("Crafting")
local TS = C_TradeSkillUI

Cr.results = {}
Cr.profession = nil

-- relativeDifficulty: 0 optimal (orange), 1 medium (yellow), 2 easy (green), 3 trivial (grey)
local DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

local function analyze()
  if not (TS and TS.GetAllRecipeIDs) then return end
  local ids = TS.GetAllRecipeIDs()
  if not ids or #ids == 0 then return end
  local DB = CM.PriceDB
  local out = {}
  for _, recipeID in ipairs(ids) do
    local info = TS.GetRecipeInfo(recipeID)
    if info and info.learned then
      local schem = TS.GetRecipeSchematic(recipeID, false)
      local itemID = schem and schem.outputItemID
      local made = schem and (((schem.quantityMin or 1) + (schem.quantityMax or schem.quantityMin or 1)) / 2) or 1
      local cost, missing = 0, 0
      for _, slot in ipairs(schem and schem.reagentSlotSchematics or {}) do
        if slot.required ~= false and slot.reagents and slot.reagents[1] then
          local rID = slot.reagents[1].itemID
          local unit = rID and DB:AcquireCost(rID)
          if unit then cost = cost + unit * (slot.quantityRequired or 1) else missing = missing + 1 end
        end
      end
      local unitValue = itemID and DB:NetAH(itemID)
      local value = unitValue and unitValue * made
      table.insert(out, {
        name = info.name, itemID = itemID, skillType = DIFF[info.relativeDifficulty] or "trivial",
        cost = cost, value = value, missing = missing,
        profit = value and missing == 0 and (value - cost) or nil,
      })
    end
  end
  table.sort(out, function(a, b)
    if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
    return (a.profit or -1e12) > (b.profit or -1e12)
  end)
  local base = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
  Cr.results = out
  Cr.profession = base and base.professionName or "Profession"
  CM:Realm().recipes[Cr.profession] = out
end

local pending
local function schedule()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    analyze()
    if CM.UI and CM.UI.Refresh then CM.UI:Refresh() end
  end)
end

CM:On("TRADE_SKILL_SHOW", function()
  schedule()
  local parent = ProfessionsFrame or TradeSkillFrame
  if not Cr.button and parent then
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(80, 20)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -2)
    b:SetText("WGA Profit")
    b:SetScript("OnClick", function() CM.UI:Show("Crafting") end)
    Cr.button = b
  end
end)
CM:On("TRADE_SKILL_LIST_UPDATE", schedule)
CM:On("TRADE_SKILL_DATA_SOURCE_CHANGED", schedule)

function Cr:Lines()
  local results, prof = Cr.results, Cr.profession
  if #results == 0 then
    for p, r in pairs(CM:Realm().recipes) do prof, results = p, r; break end
  end
  if not results or #results == 0 then
    return { "Open a profession window to analyze its recipes.", "",
      "Profit uses the cheapest known source for each reagent (vendor price learned at merchants, else AH)",
      "and the AH market value of the result minus the 5% cut. Run /wga scan at the auction house first." }
  end
  local lines = { string.format("|cffffd100%s|r  (%d recipes)", prof or "Profession", #results), "" }
  local colors = { optimal = "ff8040", medium = "ffff00", easy = "40bf40", trivial = "808080" }
  for _, r in ipairs(results) do
    local nameStr = string.format("|cff%s%s|r", colors[r.skillType] or "ffffff", r.name or "?")
    if r.profit then
      table.insert(lines, string.format("%s  cost %s  sells %s  profit %s%s", nameStr,
        CM:Money(r.cost, true), CM:Money(r.value, true), r.profit >= 0 and "|cff40ff40+|r" or "", CM:Money(r.profit, true)))
    elseif r.missing > 0 then
      table.insert(lines, string.format("%s  |cff808080%d reagent price(s) unknown|r", nameStr, r.missing))
    else
      table.insert(lines, string.format("%s  cost %s  |cff808080no AH data for result|r", nameStr, CM:Money(r.cost, true)))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "|cff808080Recipe colour = skill-up chance (orange always, yellow usually, green rarely, grey never).|r")
  return lines
end
