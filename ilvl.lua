local ADDON = ...
ilvlDB = ilvlDB or {}

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("INSPECT_READY")

-- Cache: guid -> number (score) or nil (unknown)
local cache = {}

-- Throttle inspect attempts to avoid spamming
local lastInspectAt = 0
local INSPECT_COOLDOWN = 1.0

-- Keep track of who we are currently inspecting
local inspectingGuid = nil

local function Now()
  return GetTime()
end

local function GetGuid(unit)
  if not UnitExists(unit) then return nil end
  return UnitGUID(unit)
end

local function ComputeSelfScore()
  -- Example score: average equipped item level rounded
  local avg, equipped = GetAverageItemLevel()
  if equipped and equipped > 0 then
    return math.floor(equipped + 0.5)
  end
  if avg and avg > 0 then
    return math.floor(avg + 0.5)
  end
  return nil
end

local function ComputeInspectScore(unit)
  -- Uses inspected unit data (must be valid after INSPECT_READY)
  -- Note: Some API variants differ by version; this is the common approach.
  local avg = C_PaperDollInfo.GetInspectItemLevel(unit)
  if avg and avg > 0 then
    return math.floor(avg + 0.5)
  end
  return nil
end

local function CanInspect(unit)
  if not UnitIsPlayer(unit) then return false end
  if UnitIsUnit(unit, "player") then return false end
  if not CanInspect(unit) then return false end -- global API CanInspect(unit)
  return true
end

local function RequestInspect(unit)
  if InCombatLockdown() then return end
  if not CanInspect(unit) then return end

  local t = Now()
  if (t - lastInspectAt) < INSPECT_COOLDOWN then return end
  lastInspectAt = t

  inspectingGuid = GetGuid(unit)
  if not inspectingGuid then return end

  NotifyInspect(unit)
end

-- ---- Frame attachment (Blizzard party/raid frames) ----

local function EnsureLabel(frame)
  if frame.GSF_Label then return frame.GSF_Label end

  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
  label:SetJustifyH("RIGHT")
  label:SetText("??")

  frame.GSF_Label = label
  return label
end

local function SetFrameText(frame, text)
  local label = EnsureLabel(frame)
  label:SetText(text)
end

local function ScoreTextForUnit(unit)
  local guid = GetGuid(unit)
  if not guid then return "??" end

  -- Self
  if UnitIsUnit(unit, "player") then
    local s = ComputeSelfScore()
    if s then
      cache[guid] = s
      return tostring(s)
    end
    return "??"
  end

  local s = cache[guid]
  if s then
    return tostring(s)
  end

  -- Unknown -> request inspect and show ??
  RequestInspect(unit)
  return "??"
end

local function TryUpdateBlizzardPartyFrames()
  if not PartyFrame or not PartyFrame.MemberFramePool then return end

  for memberFrame in PartyFrame.MemberFramePool:EnumerateActive() do
    local unit = memberFrame.unit
    if unit then
      SetFrameText(memberFrame, ScoreTextForUnit(unit))
    end
  end
end

local function TryUpdateBlizzardRaidFrames()
  -- Uses CompactUnitFrame based raid frames
  if not CompactRaidFrameContainer or not CompactRaidFrameContainer.memberFramePool then return end

  for frame in CompactRaidFrameContainer.memberFramePool:EnumerateActive() do
    local unit = frame.unit
    if unit then
      SetFrameText(frame, ScoreTextForUnit(unit))
    end
  end
end

local function UpdateAll()
  TryUpdateBlizzardPartyFrames()
  TryUpdateBlizzardRaidFrames()
end

-- ---- Events ----

f:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    -- Hook updates when compact frames refresh
    hooksecurefunc("CompactUnitFrame_UpdateAll", function()
      -- CompactUnitFrame_UpdateAll is called a lot; keep it lightweight
      UpdateAll()
    end)
    UpdateAll()

  elseif event == "GROUP_ROSTER_UPDATE" then
    UpdateAll()

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    -- Update self score in cache
    local guid = UnitGUID("player")
    if guid then
      cache[guid] = ComputeSelfScore()
    end
    UpdateAll()

  elseif event == "INSPECT_READY" then
    local guid = ...
    if not guid or guid ~= inspectingGuid then
      -- Still update; other inspect results could arrive
    end

    -- Find which unit matches this guid (party/raid iterate)
    local function handleUnit(unit)
      if UnitGUID(unit) == guid then
        local score = ComputeInspectScore(unit)
        if score then
          cache[guid] = score
        end
      end
    end

    if IsInRaid() then
      for i = 1, GetNumGroupMembers() do
        handleUnit("raid"..i)
      end
    elseif IsInGroup() then
      for i = 1, GetNumSubgroupMembers() do
        handleUnit("party"..i)
      end
    end

    inspectingGuid = nil
    ClearInspectPlayer()
    UpdateAll()
  end
end)