local addonName = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("INSPECT_READY")

local text
local pendingGUID

-- Only count real gear slots (exclude shirt/tabard).
local ILVL_SLOTS = {
  INVSLOT_HEAD,
  INVSLOT_NECK,
  INVSLOT_SHOULDER,
  INVSLOT_CHEST,
  INVSLOT_WAIST,
  INVSLOT_LEGS,
  INVSLOT_FEET,
  INVSLOT_WRIST,
  INVSLOT_HAND,
  INVSLOT_FINGER1,
  INVSLOT_FINGER2,
  INVSLOT_TRINKET1,
  INVSLOT_TRINKET2,
  INVSLOT_BACK,
  INVSLOT_MAINHAND,
  INVSLOT_OFFHAND,
}

local function EnsureText()
  if text or not InspectFrame then return end

  text = InspectFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  -- Above the titlebar
  text:SetPoint("TOP", InspectFrame, "TOP", 0, 14)
  text:SetText("")
end

-- Why this works:
-- - INSPECT_READY populates links for GetInventoryItemLink("target", slot)
-- - We read each equipped item, get its effective item level, and average them.
-- - We exclude INVSLOT_SHIRT and INVSLOT_TABARD by never iterating them.
local function GetInspectAvgEquippedIlvl(unit)
  local total, count = 0, 0

  for i = 1, #ILVL_SLOTS do
    local slotId = ILVL_SLOTS[i]
    local link = GetInventoryItemLink(unit, slotId)
    if link then
      -- Returns the "effective" iLvl for the item link (handles upgrades/scaling).
      local ilvl = GetDetailedItemLevelInfo(link)
      if ilvl and ilvl > 0 then
        total = total + ilvl
        count = count + 1
      end
    end
  end

  if count == 0 then return nil end
  return total / count
end

local function SetTextForUnit(unit)
  if not text then return end
  if not unit or not UnitExists(unit) then
    text:SetText("")
    return
  end

  local ilvl = GetInspectAvgEquippedIlvl(unit)
  if ilvl then
    text:SetFormattedText("iLvl: %.1f", ilvl)
  else
    text:SetText("iLvl: ...")
  end
end

local function RequestInspect(unit)
  if not unit or not UnitExists(unit) then return end
  if not CanInspect(unit, false) then return end

  pendingGUID = UnitGUID(unit)
  text:SetText("iLvl: ...")
  NotifyInspect(unit)
end

local function HookInspectFrame()
  if not InspectFrame or InspectFrame.__InspectAvgIlvlHooked then return end
  InspectFrame.__InspectAvgIlvlHooked = true

  EnsureText()

  InspectFrame:HookScript("OnShow", function()
    EnsureText()
    RequestInspect(InspectFrame.unit or "target")
  end)

  InspectFrame:HookScript("OnHide", function()
    if text then text:SetText("") end
    pendingGUID = nil
    ClearInspectPlayer()
  end)
end

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    HookInspectFrame()
    return
  end

  if event == "INSPECT_READY" then
    if pendingGUID and arg1 and arg1 ~= pendingGUID then return end
    EnsureText()
    SetTextForUnit(InspectFrame and (InspectFrame.unit or "target") or "target")
  end
end)
