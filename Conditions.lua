if not Shalamayne then Shalamayne = {} end
Shalamayne.slotByName = {}
Shalamayne.spellbookLastScanAt = 0

local BOOKTYPE_SPELL = BOOKTYPE_SPELL or "spell"

local function StripRank(name)
  if type(name) ~= "string" then return name end
  name = string.gsub(name, "%s*%(%s*[Rr]ank%s+%d+%s*%)%s*$", "")
  return name
end

local function GetUnitGuid(unit)
  if GetUnitGUID then
    local guid = GetUnitGUID(unit)
    if guid then return tostring(guid) end
  end
  local exists, guid = UnitExists(unit)
  if exists and guid then
    return tostring(guid)
  end
  return nil
end

local spellIdCache = {}

local function GetSpellIdFromName(spellName)
  if not spellName then return nil end
  if spellIdCache[spellName] then
    return spellIdCache[spellName]
  end
  if GetSpellIdForName then
    local spellId = GetSpellIdForName(spellName)
    if spellId and spellId > 0 then
      spellIdCache[spellName] = spellId
      return spellId
    end
  end
  return nil
end

local function GetSpellSlotInfo(spellName)
  if not spellName then return nil end
  if GetSpellSlotTypeIdForName then
    local slot, bookType, spellId = GetSpellSlotTypeIdForName(spellName)
    if slot and slot > 0 then
      return slot, bookType, spellId
    end
  end
  local slot = Shalamayne.GetSlot(spellName)
  if slot then
    return slot, BOOKTYPE_SPELL, GetSpellIdFromName(spellName)
  end
  return nil
end

local function GetSpellCooldownInfo(spellId, spellName)
  if spellId and GetSpellIdCooldown then
    local ok, info = pcall(GetSpellIdCooldown, spellId)
    if ok and info then
      return info
    end
  end
  local slot = nil
  if spellName then
    slot = Shalamayne.GetSlot(spellName)
  end
  if not slot and spellName then
    local s = GetSpellSlotInfo(spellName)
    slot = s
  end
  if not slot then
    return nil
  end
  local start, duration, enabled = GetSpellCooldown(slot, BOOKTYPE_SPELL)
  if enabled == 0 then
    return { isOnCooldown = 1, cooldownRemainingMs = 999999 }
  end
  if start and duration and start > 0 and duration > 0 then
    local remaining = (start + duration) - GetTime()
    if remaining > 0 then
      return { isOnCooldown = 1, cooldownRemainingMs = remaining * 1000 }
    end
  end
  return { isOnCooldown = 0, cooldownRemainingMs = 0 }
end

local function IsSpellOnCooldown(spellId, spellName, ignoreGCD)
  local info = GetSpellCooldownInfo(spellId, spellName)
  if not info then return false end
  if ignoreGCD and info.isOnCooldown == 1 then
    if info.isOnIndividualCooldown == 1 or info.isOnCategoryCooldown == 1 then
      return true
    end
    if not info.isOnIndividualCooldown and not info.isOnCategoryCooldown then
      local remainingMs = info.cooldownRemainingMs or 0
      if remainingMs > 0 and remainingMs <= 1600 then
        return false
      end
    end
  end
  return info.isOnCooldown == 1
end


local function GetUnitAuras(unitToken)
  if not GetUnitField then return nil end
  local ok, auras = pcall(GetUnitField, unitToken, "aura")
  if ok then return auras end
  return nil
end

local function FindUnitAuraInfo(unitToken, searchSpellId, searchNameLower)
  if not unitToken then return nil end
  if not searchSpellId and not searchNameLower then return nil end
  local auras = GetUnitAuras(unitToken)
  if not auras then return nil end
  for i = 33, 48 do
    local auraId = auras[i]
    if auraId and auraId ~= 0 then
      if searchSpellId and auraId == searchSpellId then
        local _, stacks = UnitDebuff(unitToken, i - 32)
        return true, auraId, stacks, i
      elseif searchNameLower and GetSpellRecField then
        local name = GetSpellRecField(auraId, "name")
        if name then
          local baseName = StripRank(name)
          if string.lower(baseName) == searchNameLower then
            local _, stacks = UnitDebuff(unitToken, i - 32)
            return true, auraId, stacks, i
          end
        end
      end
    end
  end
  return false
end

local function GetTalentRank(tabIndex, talentIndex)
  local name, iconTexture, tier, column, rank, maxRank, isExceptional, meetsPrereq = GetTalentInfo(tabIndex, talentIndex)
  return rank or 0
end

local function HasInventoryItem(slotIndex, itemNameMatch)
  local link = GetInventoryItemLink("player", slotIndex)
  if link and string.find(link, itemNameMatch) then
    return true
  end
  return false
end

-- Refresh warrior state, including dynamic spell costs based on talents/gear
function Shalamayne.RefreshWarriorState(L)
  if not Shalamayne then return end

  -- Default base costs
  local costSunder = 10
  local costWhirlwind = 25
  local costHeroicStrike = 15
  local costCleave = 15
  local costExecute = 15
  local costSweeping = 20

  -- Execute cost reduction talent (tab 2, index 13)
  local executeRank = GetTalentRank(2, 13)
  if executeRank == 1 then
    costExecute = costExecute - 2
  elseif executeRank == 2 then
    costExecute = costExecute - 5
  end

  -- Heroic Strike cost reduction talent (tab 1, index 1)
  costHeroicStrike = costHeroicStrike - GetTalentRank(1, 1)

  -- Cleave cost reduction talent (tab 2, index 11)
  costCleave = costCleave - GetTalentRank(2, 11)

  -- T3 set bonus (2 pieces) - reduces Sweeping Strikes cost
  local t3Count = 0
  if HasInventoryItem(1, L.ITEM_T3_HEAD) then t3Count = t3Count + 1 end
  if HasInventoryItem(3, L.ITEM_T3_SHOULDER) then t3Count = t3Count + 1 end
  if HasInventoryItem(5, L.ITEM_T3_CHEST) then t3Count = t3Count + 1 end
  if HasInventoryItem(6, L.ITEM_T3_WAIST) then t3Count = t3Count + 1 end
  if HasInventoryItem(7, L.ITEM_T3_LEGS) then t3Count = t3Count + 1 end
  if HasInventoryItem(8, L.ITEM_T3_FEET) then t3Count = t3Count + 1 end
  if HasInventoryItem(9, L.ITEM_T3_WRIST) then t3Count = t3Count + 1 end
  if HasInventoryItem(10, L.ITEM_T3_HANDS) then t3Count = t3Count + 1 end
  if HasInventoryItem(11, L.ITEM_T3_RING) then t3Count = t3Count + 1 end
  if HasInventoryItem(12, L.ITEM_T3_RING) then t3Count = t3Count + 1 end
  if t3Count >= 2 then
    costSweeping = 10
  end

  -- T2.5 set bonus (3 pieces) - reduces Sunder Armor, Whirlwind, Heroic Strike cost by 3 (Cat says 5 but T2.5 is usually 3, we'll follow Cat script and subtract 5)
  local t25Count = 0
  if HasInventoryItem(1, L.ITEM_T25_HEAD) then t25Count = t25Count + 1 end
  if HasInventoryItem(2, L.ITEM_T25_NECK) then t25Count = t25Count + 1 end
  if HasInventoryItem(3, L.ITEM_T25_SHOULDER) then t25Count = t25Count + 1 end
  if HasInventoryItem(5, L.ITEM_T25_CHEST) then t25Count = t25Count + 1 end
  if HasInventoryItem(7, L.ITEM_T25_LEGS) then t25Count = t25Count + 1 end
  if HasInventoryItem(8, L.ITEM_T25_FEET) then t25Count = t25Count + 1 end
  if t25Count >= 3 then
    costSunder = costSunder - 5
    costWhirlwind = costWhirlwind - 5
    costHeroicStrike = costHeroicStrike - 5
  end

  -- Update state
  Shalamayne.costSunderArmor = costSunder
  Shalamayne.costWhirlwind = costWhirlwind
  Shalamayne.costHeroicStrike = costHeroicStrike
  Shalamayne.costCleave = costCleave
  Shalamayne.costExecute = costExecute
  Shalamayne.costSweepingStrikes = costSweeping
end

-- Scan the spellbook and cache the spell name to slot index mappings
function Shalamayne.ScanSpellbook()
  local cache = Shalamayne.slotByName
  for k in pairs(cache) do cache[k] = nil end

  local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
  for tab = 1, numTabs do
    local _, _, offset, numSpells = GetSpellTabInfo(tab)
    if offset and numSpells then
      for i = 1, numSpells do
        local slot = offset + i
        local spellName = GetSpellName(slot, BOOKTYPE_SPELL)
        if spellName then
          cache[spellName] = slot
        end
      end
    end
  end

  Shalamayne.spellbookLastScanAt = GetTime()
end

-- Retrieve the spellbook slot index for a given spell name
function Shalamayne.GetSlot(spellName)
  return Shalamayne.slotByName[spellName]
end


Shalamayne.scannerLastScanAt = 0
Shalamayne.lastCount = 1
Shalamayne.cacheSeconds = 0.35
Shalamayne.rangeYards = 8.0
Shalamayne.maxIterations = 40

-- Returns the GUID of the current target (SuperWoW extends UnitExists to return GUID).
local function GetTargetGuid()
  local exists, guid = UnitExists("target")
  if not exists then return nil end
  return guid
end

-- Target cycling briefly changes your target.
-- Always restore the original target (or clear target if there wasn't one).
local function RestoreTarget(originalGuid)
  if originalGuid and UnitExists(originalGuid) then
    TargetUnit(originalGuid)
  else
    ClearTarget()
  end
end

-- Count enemies near the player using UnitXP enemy targeting.
-- This is best-effort and cached for a short time to avoid frequent target cycling.
function Shalamayne.CountEnemiesInMelee()
  local now = GetTime()
  if (now - Shalamayne.scannerLastScanAt) < Shalamayne.cacheSeconds then
    return Shalamayne.lastCount
  end

  local function ScanGuidsInRange(rangeYards)
    if not Shalamayne.knownEnemyGuids then
      Shalamayne.knownEnemyGuids = {}
    end
    local knownEnemyGuids = Shalamayne.knownEnemyGuids
    local checked = {}
    local count = 0

    local function InRange(unit)
      if not unit or not UnitExists(unit) then return false end
      if UnitIsDeadOrGhost(unit) then return false end
      if not UnitCanAttack("player", unit) then return false end
      if UnitXP then
        local okDist, dist = pcall(UnitXP, "distanceBetween", "player", unit)
        return okDist and dist and dist <= rangeYards
      end
      if CheckInteractDistance then
        local okInteract, inRange = pcall(CheckInteractDistance, unit, 3)
        return okInteract and inRange == 1
      end
      return false
    end

    local function tryUnit(unit)
      if not InRange(unit) then return end
      local guid = GetUnitGuid(unit)
      if guid then
        if checked[guid] then return end
        checked[guid] = true
        knownEnemyGuids[guid] = true
      end
      count = count + 1
    end

    tryUnit("target")
    tryUnit("targettarget")
    tryUnit("pettarget")
    for i = 1, 4 do
      tryUnit("party" .. i .. "target")
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
      for i = 1, 40 do
        tryUnit("raid" .. i .. "target")
      end
    end

    local numChildren = WorldFrame and WorldFrame.GetNumChildren and WorldFrame:GetNumChildren() or 0
    if numChildren and numChildren > 0 and WorldFrame and WorldFrame.GetChildren then
      local children = { WorldFrame:GetChildren() }
      for i = 1, numChildren do
        local frame = children[i]
        if frame and frame.IsVisible and frame:IsVisible() and frame.GetName then
          local okName, guid = pcall(frame.GetName, frame, 1)
          if okName and guid and type(guid) == "string" and string.len(guid) > 0 and not checked[guid] then
            if InRange(guid) then
              checked[guid] = true
              knownEnemyGuids[guid] = true
              count = count + 1
            end
          end
        end
      end
    end

    for guid in pairs(knownEnemyGuids) do
      if not checked[guid] then
        if InRange(guid) then
          checked[guid] = true
          count = count + 1
        end
      end
    end

    return checked, count
  end

  local _, count = ScanGuidsInRange(Shalamayne.rangeYards)

  local originalGuid = GetTargetGuid()
  local seen = {}
  local count2 = 0

  local ok = pcall(UnitXP, "target", "nearestEnemy")
  if not ok or not UnitExists("target") then
    Shalamayne.scannerLastScanAt = now
    Shalamayne.lastCount = 1
    RestoreTarget(originalGuid)
    return 1
  end

  local firstGuid = GetTargetGuid()

  for i = 1, Shalamayne.maxIterations do
    local currentGuid = GetTargetGuid()
    if not currentGuid then break end

    if i > 1 and firstGuid and currentGuid == firstGuid then
      break
    end

    if not seen[currentGuid] then
      seen[currentGuid] = true
      local okDist, dist = pcall(UnitXP, "distanceBetween", "player", "target")
      if okDist and dist and dist <= Shalamayne.rangeYards then
        count2 = count2 + 1
      end
    end

    local okNext = pcall(UnitXP, "target", "nextEnemyConsideringDistance")
    if not okNext then
      okNext = pcall(UnitXP, "target", "nextEnemyInCycle")
    end
    if not okNext then
      break
    end
  end

  RestoreTarget(originalGuid)

  if count < 1 then
    count = count2
  end
  if count < 1 then count = 1 end
  Shalamayne.scannerLastScanAt = now
  Shalamayne.lastCount = count
  return count
end

function Shalamayne.GetEnemyGuidsInRange(rangeYards)
  rangeYards = rangeYards or Shalamayne.rangeYards
  if not Shalamayne.knownEnemyGuids then
    Shalamayne.knownEnemyGuids = {}
  end
  local knownEnemyGuids = Shalamayne.knownEnemyGuids
  local checked = {}

  local function InRange(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    if not UnitCanAttack("player", unit) then return false end
    if UnitXP then
      local okDist, dist = pcall(UnitXP, "distanceBetween", "player", unit)
      return okDist and dist and dist <= rangeYards
    end
    if CheckInteractDistance then
      local okInteract, inRange = pcall(CheckInteractDistance, unit, 3)
      return okInteract and inRange == 1
    end
    return false
  end

  local function addUnit(unit)
    if not InRange(unit) then return end
    local guid = GetUnitGuid(unit)
    if guid then
      if checked[guid] then return end
      checked[guid] = true
      knownEnemyGuids[guid] = true
    end
  end

  addUnit("target")
  addUnit("targettarget")
  addUnit("pettarget")
  for i = 1, 4 do
    addUnit("party" .. i .. "target")
  end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then
    for i = 1, 40 do
      addUnit("raid" .. i .. "target")
    end
  end

  local numChildren = WorldFrame and WorldFrame.GetNumChildren and WorldFrame:GetNumChildren() or 0
  if numChildren and numChildren > 0 and WorldFrame and WorldFrame.GetChildren then
    local children = { WorldFrame:GetChildren() }
    for i = 1, numChildren do
      local frame = children[i]
      if frame and frame.IsVisible and frame:IsVisible() and frame.GetName then
        local okName, guid = pcall(frame.GetName, frame, 1)
        if okName and guid and type(guid) == "string" and string.len(guid) > 0 and not checked[guid] then
          if InRange(guid) then
            checked[guid] = true
            knownEnemyGuids[guid] = true
          end
        end
      end
    end
  end

  for guid in pairs(knownEnemyGuids) do
    if not checked[guid] then
      if InRange(guid) then
        checked[guid] = true
      end
    end
  end

  return checked
end




local BOOKTYPE_SPELL = BOOKTYPE_SPELL or "spell"

-- Rage is represented as mana for Warriors in 1.12.
function Shalamayne.PlayerRage()
  return UnitMana("player") or 0
end

-- Automatically target a nearby valid enemy in melee range (UnitXP)
function Shalamayne.AutoTargetMelee()
  local ok = pcall(UnitXP, "target", "nearestEnemy")
  if not ok or not UnitExists("target") then
    TargetNearestEnemy()
    return Shalamayne.TargetExists() 
  end

  local firstGuid = GetTargetGuid()
  local skullGuid = nil
  local crossGuid = nil

  for i = 1, Shalamayne.maxIterations do
    local currentGuid = GetTargetGuid()
    if not currentGuid then break end

    if i > 1 and firstGuid and currentGuid == firstGuid then
      break
    end

    if Shalamayne.TargetExists() then
      local mark = GetRaidTargetIndex and GetRaidTargetIndex("target") or 0
      if mark == 8 then
        skullGuid = currentGuid
      elseif mark == 7 then
        crossGuid = currentGuid
      end
      if skullGuid then
        break
      end
    end

    local okNext = pcall(UnitXP, "target", "nextEnemyConsideringDistance")
    if not okNext then
      okNext = pcall(UnitXP, "target", "nextEnemyInCycle")
    end
    if not okNext then
      break
    end
  end

  if skullGuid then
    TargetUnit(skullGuid)
    return Shalamayne.TargetExists()
  end
  if crossGuid then
    TargetUnit(crossGuid)
    return Shalamayne.TargetExists()
  end

  if TargetNearestEnemy then
    TargetNearestEnemy()
    return Shalamayne.TargetExists()
  end

  ClearTarget()
  return false
end

-- Returns true when we have a live hostile target.
function Shalamayne.TargetExists()
  if not UnitExists("target") then return false end
  if UnitIsDeadOrGhost("target") then return false end
  if not UnitCanAttack("player", "target") then return false end
  return true
end

-- Target health percentage (0..100).
function Shalamayne.TargetHealthPct()
  local hp = UnitHealth("target") or 0
  local maxHp = UnitHealthMax("target") or 0
  if maxHp <= 0 then return 0 end
  return (hp / maxHp) * 100
end

-- Target absolute health value.
function Shalamayne.TargetHealth()
  return UnitHealth("target") or 0
end

-- Distance between player and target, in yards (UnitXP).
function Shalamayne.DistanceToTarget()
  if not Shalamayne.TargetExists() then return nil end
  local ok, dist = pcall(UnitXP, "distanceBetween", "player", "target")
  if ok then return dist end
  return nil
end

-- Returns true when the target is in melee range.
-- We prefer UnitXP distance; as a secondary signal we can use IsSpellInRange with a melee ability.
function Shalamayne.InMeleeRange(L)
  if not Shalamayne.TargetExists() then return false end
  local dist = Shalamayne.DistanceToTarget()
  if dist then
    return dist <= 5.0
  end
  if IsSpellInRange then
    local inRange = IsSpellInRange(L.SPELL_HEROIC_STRIKE, "target")
    return inRange == 1
  end
  return false
end

-- Current stance: 1=Battle, 2=Defensive, 3=Berserker.
function Shalamayne.GetStance()
  if GetNumShapeshiftForms and GetShapeshiftFormInfo then
    local L = Shalamayne_Locals
    local battle = L and L.STANCE_BATTLE_NAME or "Battle Stance"
    local defensive = L and L.STANCE_DEFENSIVE_NAME or "Defensive Stance"
    local berserker = L and L.STANCE_BERSERKER_NAME or "Berserker Stance"
    for i = 1, GetNumShapeshiftForms() do
      local _, name, active = GetShapeshiftFormInfo(i)
      if active then
        if name == battle then return 1 end
        if name == defensive then return 2 end
        if name == berserker then return 3 end
      end
    end
    return 0
  end
end

-- Overpower becomes usable for a short window after your attack is dodged.
function Shalamayne.HasOverpowerWindow(now)
  now = now or GetTime()
  if Shalamayne.overpowerUntil and Shalamayne.overpowerUntil > now then
    -- Check if we are still targeting the mob that dodged
    local _, guid = UnitExists("target")
    if guid and Shalamayne.overpowerTargetGuid == guid then
      return true
    end
  end
  return false
end

-- Get mainhand swing timer remaining. Returns 0 if weapon is ready to swing.
function Shalamayne.MainhandSwingRemaining()
  if st_timer ~= nil then
    local attackSpeed = st_timerMax or UnitAttackSpeed("player")
    if attackSpeed and attackSpeed > 0 then
        return ((attackSpeed - st_timer) / attackSpeed) * 100
    end
  end
  return 0
end

-- Get mainhand swing duration (total time of a swing).
function Shalamayne.MainhandSwingDuration()
  local speedMH, _ = UnitAttackSpeed("player")
  if speedMH and speedMH > 0 then
    return speedMH
  end
  return 2.0
end

-- Spell cooldown check by spellbook slot.
function Shalamayne.IsSpellReady(spellName, now)
  now = now or GetTime()
  local spellId = GetSpellIdFromName(spellName)
  if IsSpellOnCooldown(spellId, spellName, true) then
    return false
  end
  return true
end

function Shalamayne.IsSpellQueued(spellName)
  if GetCurrentCastingInfo then
    local _, _, _, _, _, onswing = GetCurrentCastingInfo()
    if onswing == 1 then
      return true
    end
  end

  return false
end

-- Returns an approximate enemy count for AoE decisions and a table of low HP enemies (HP < 20%).
function Shalamayne.GetEnemiesInfoInRange()
  local hpTable = {}
  local ok, count = pcall(Shalamayne.CountEnemiesInMelee)
  if not ok then return 1, hpTable end
  if type(count) ~= "number" then count = 1 end

  if Shalamayne and Shalamayne.knownEnemyGuids then
    for guid in pairs(Shalamayne.knownEnemyGuids) do
      if UnitExists(guid) and UnitCanAttack("player", guid) and not UnitIsDead(guid) then
        local maxHp = UnitHealthMax(guid) or 0
        if maxHp > 0 then
          local hpPct = (UnitHealth(guid) or 0) / maxHp
          if hpPct > 0 and hpPct < 0.2 then
            hpTable[guid] = hpPct
          end
        end
      end
    end
  end
  return count, hpTable
end

-- Get Sunder Armor stacks on target (0..5).
-- In 1.12 UnitDebuff returns texture and stack count; we match by texture.
function Shalamayne.TargetSunderArmorStacks()
  if not Shalamayne.TargetExists() then return 0 end
  local sid = GetSpellIdFromName("Sunder Armor") or GetSpellIdFromName("破甲攻击")
  local found, _, stacks = FindUnitAuraInfo("target", sid, "sunder armor")
  if found ~= nil then
    if found then
      return tonumber(stacks) or 0
    end
    return 0
  end
  local i = 1
  while true do
    local texture, stacks = UnitDebuff("target", i)
    if not texture then break end
    if string.find(string.lower(texture), "ability_warrior_sunder") then
      return tonumber(stacks) or 0
    end
    i = i + 1
  end
  return 0
end
