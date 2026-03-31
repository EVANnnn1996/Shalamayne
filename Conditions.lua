Shalamayne_Spellbook = {
  slotByName = {},
  lastScanAt = 0,
}

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

local Shalamayne_NP = {
  spellIdCache = {},
}

local function GetSpellIdFromName(spellName)
  if not spellName then return nil end
  local cache = Shalamayne_NP.spellIdCache
  if cache[spellName] then
    return cache[spellName]
  end
  if GetSpellIdForName then
    local spellId = GetSpellIdForName(spellName)
    if spellId and spellId > 0 then
      cache[spellName] = spellId
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
  local slot = Shalamayne_Spellbook.GetSlot(spellName)
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
    slot = Shalamayne_Spellbook.GetSlot(spellName)
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

local function IsSpellUsableWrapper(spellId, spellName)
  if not IsSpellUsable then
    return nil
  end
  local ok, usable, oom
  if spellId and spellId > 0 then
    ok, usable, oom = pcall(IsSpellUsable, spellId)
    if ok then return usable, oom end
  end
  ok, usable, oom = pcall(IsSpellUsable, spellName)
  if ok then return usable, oom end
  return nil
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

-- Wipe all keys from a table
local function Wipe(t)
  for k in pairs(t) do t[k] = nil end
end

-- Scan the spellbook and cache the spell name to slot index mappings
function Shalamayne_Spellbook.Scan()
  local cache = Shalamayne_Spellbook.slotByName
  Wipe(cache)

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

  Shalamayne_Spellbook.lastScanAt = GetTime()
end

-- Retrieve the spellbook slot index for a given spell name
function Shalamayne_Spellbook.GetSlot(spellName)
  return Shalamayne_Spellbook.slotByName[spellName]
end


Shalamayne_EnemyScanner = {
  lastScanAt = 0,
  lastCount = 1,
  cacheSeconds = 0.35,
  rangeYards = 8.0,
  maxIterations = 40,
}

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
function Shalamayne_EnemyScanner.CountEnemiesInMelee()
  local now = GetTime()
  if (now - Shalamayne_EnemyScanner.lastScanAt) < Shalamayne_EnemyScanner.cacheSeconds then
    return Shalamayne_EnemyScanner.lastCount
  end

  local function ScanGuidsInRange(rangeYards)
    if not Shalamayne_EnemyScanner.knownEnemyGuids then
      Shalamayne_EnemyScanner.knownEnemyGuids = {}
    end
    local knownEnemyGuids = Shalamayne_EnemyScanner.knownEnemyGuids
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

  local _, count = ScanGuidsInRange(Shalamayne_EnemyScanner.rangeYards)

  local originalGuid = GetTargetGuid()
  local seen = {}
  local count2 = 0

  local ok = pcall(UnitXP, "target", "nearestEnemy")
  if not ok or not UnitExists("target") then
    Shalamayne_EnemyScanner.lastScanAt = now
    Shalamayne_EnemyScanner.lastCount = 1
    RestoreTarget(originalGuid)
    return 1
  end

  local firstGuid = GetTargetGuid()

  for i = 1, Shalamayne_EnemyScanner.maxIterations do
    local currentGuid = GetTargetGuid()
    if not currentGuid then break end

    if i > 1 and firstGuid and currentGuid == firstGuid then
      break
    end

    if not seen[currentGuid] then
      seen[currentGuid] = true
      local okDist, dist = pcall(UnitXP, "distanceBetween", "player", "target")
      if okDist and dist and dist <= Shalamayne_EnemyScanner.rangeYards then
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
  Shalamayne_EnemyScanner.lastScanAt = now
  Shalamayne_EnemyScanner.lastCount = count
  return count
end

function Shalamayne_EnemyScanner.GetEnemyGuidsInRange(rangeYards)
  rangeYards = rangeYards or Shalamayne_EnemyScanner.rangeYards
  if not Shalamayne_EnemyScanner.knownEnemyGuids then
    Shalamayne_EnemyScanner.knownEnemyGuids = {}
  end
  local knownEnemyGuids = Shalamayne_EnemyScanner.knownEnemyGuids
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


Shalamayne_Conditions = {}

local BOOKTYPE_SPELL = BOOKTYPE_SPELL or "spell"

-- Rage is represented as mana for Warriors in 1.12.
function Shalamayne_Conditions.PlayerRage()
  return UnitMana("player") or 0
end

-- Automatically target a nearby valid enemy in melee range (UnitXP)
function Shalamayne_Conditions.AutoTargetMelee()
  local ok = pcall(UnitXP, "target", "nearestEnemy")
  if not ok or not UnitExists("target") then return false end

  local firstGuid = GetTargetGuid()

  for i = 1, Shalamayne_EnemyScanner.maxIterations do
    local currentGuid = GetTargetGuid()
    if not currentGuid then break end

    if i > 1 and firstGuid and currentGuid == firstGuid then
      break
    end

    local okDist, dist = pcall(UnitXP, "distanceBetween", "player", "target")
    local inRange = (okDist and dist and dist <= Shalamayne_EnemyScanner.rangeYards)

    -- If target is valid and in range, stop scanning and keep this target
    if inRange and Shalamayne_Conditions.TargetExists() then
      return true
    end

    local okNext = pcall(UnitXP, "target", "nextEnemyConsideringDistance")
    if not okNext then
      okNext = pcall(UnitXP, "target", "nextEnemyInCycle")
    end
    if not okNext then
      break
    end
  end

  ClearTarget()
  return false
end

-- Returns true when we have a live hostile target.
function Shalamayne_Conditions.TargetExists()
  if not UnitExists("target") then return false end
  if UnitIsDeadOrGhost("target") then return false end
  if not UnitCanAttack("player", "target") then return false end
  return true
end

-- Target health percentage (0..100).
function Shalamayne_Conditions.TargetHealthPct()
  local hp = UnitHealth("target") or 0
  local maxHp = UnitHealthMax("target") or 0
  if maxHp <= 0 then return 0 end
  return (hp / maxHp) * 100
end

-- Target absolute health value.
function Shalamayne_Conditions.TargetHealth()
  return UnitHealth("target") or 0
end

-- Distance between player and target, in yards (UnitXP).
function Shalamayne_Conditions.DistanceToTarget()
  if not Shalamayne_Conditions.TargetExists() then return nil end
  local ok, dist = pcall(UnitXP, "distanceBetween", "player", "target")
  if ok then return dist end
  return nil
end

-- Returns true when the target is in melee range.
-- We prefer UnitXP distance; as a secondary signal we can use IsSpellInRange with a melee ability.
function Shalamayne_Conditions.InMeleeRange(L)
  if not Shalamayne_Conditions.TargetExists() then return false end
  local dist = Shalamayne_Conditions.DistanceToTarget()
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
function Shalamayne_Conditions.GetStance()
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
function Shalamayne_Conditions.HasOverpowerWindow(now)
  now = now or GetTime()
  return Shalamayne_State.overpowerUntil and Shalamayne_State.overpowerUntil > now
end

-- Get mainhand swing timer remaining. Returns 0 if weapon is ready to swing.
function Shalamayne_Conditions.MainhandSwingRemaining(now)
  now = now or GetTime()
  local elapsed = now - (Shalamayne_State.mainhandSwingTime or 0)
  local duration = Shalamayne_State.mainhandSwingDuration or 2.0
  if elapsed >= duration then return 0 end
  return duration - elapsed
end

-- Get offhand swing timer remaining. Returns 0 if weapon is ready to swing.
function Shalamayne_Conditions.OffhandSwingRemaining(now)
  now = now or GetTime()
  local elapsed = now - (Shalamayne_State.offhandSwingTime or 0)
  local duration = Shalamayne_State.offhandSwingDuration or 2.0
  if elapsed >= duration then return 0 end
  return duration - elapsed
end

-- Spell known check via cached spellbook slot.
function Shalamayne_Conditions.IsSpellKnown(spellName)
  local slot = GetSpellSlotInfo(spellName)
  if slot then return true end
  local sid = GetSpellIdFromName(spellName)
  return sid ~= nil
end

-- Spell cooldown check by spellbook slot.
function Shalamayne_Conditions.IsSpellReady(spellName, now)
  now = now or GetTime()
  if not Shalamayne_Conditions.IsSpellKnown(spellName) then
    return false
  end
  local spellId = GetSpellIdFromName(spellName)
  if IsSpellOnCooldown(spellId, spellName, true) then
    return false
  end
  return true
end

-- Full usability check: cooldown + resource requirements.
function Shalamayne_Conditions.CanUseSpell(spellName, now)
  now = now or GetTime()

  if not Shalamayne_Conditions.IsSpellKnown(spellName) then
    return false
  end

  local spellId = GetSpellIdFromName(spellName)
  if IsSpellOnCooldown(spellId, spellName, true) then
    return false
  end

  local usable, noResource = IsSpellUsableWrapper(spellId, spellName)
  if usable ~= nil then
    if noResource then return false end
    return usable ~= 0
  end

  if spellId and GetSpellRecField then
    local okCost, cost = pcall(GetSpellRecField, spellId, "manaCost")
    if okCost and cost and cost > 0 then
      local power = UnitMana("player") or 0
      if power < cost then
        return false
      end
    end
  end

  return true
end

-- Returns an approximate enemy count for AoE decisions.
-- This implementation uses UnitXP target cycling and restores the original target afterwards.
function Shalamayne_Conditions.EnemiesInRange()
  local settings = Shalamayne_Settings or {}
  if settings.enemyCountOverride and settings.enemyCountOverride > 0 then
    return settings.enemyCountOverride
  end
  local ok, count = pcall(Shalamayne_EnemyScanner.CountEnemiesInMelee)
  if ok and type(count) == "number" then
    return count
  end
  return 1
end

function Shalamayne_Conditions.EnemyGuidsInMelee(rangeYards)
  if Shalamayne_EnemyScanner and Shalamayne_EnemyScanner.GetEnemyGuidsInRange then
    return Shalamayne_EnemyScanner.GetEnemyGuidsInRange(rangeYards)
  end
  return {}
end

-- Checks if the target has a specific debuff by name
function Shalamayne_Conditions.TargetHasDebuff(debuffName)
  if not Shalamayne_Conditions.TargetExists() then return false end
  local searchId = GetSpellIdFromName(debuffName)
  local searchLower = string.lower(StripRank(debuffName))
  local found = FindUnitAuraInfo("target", searchId, searchLower)
  if found ~= nil then
    return found and true or false
  end
  local i = 1
  while true do
    local texture, stacks = UnitDebuff("target", i)
    local name = texture
    if not name then break end
    
    -- In 1.12 UnitDebuff returns the texture path, we do a basic string match
    -- Usually debuffName is the spell name, so this is a simplified fallback
    -- Note: extensions might provide a better UnitDebuff wrapper returning names.
    -- Here we use the texture path as a simple heuristic if it contains the name (lowercased, spaces removed)
    -- A more robust way in 1.12 without extensions is scanning tooltip, but for Sunder Armor,
    -- checking for the known texture "Ability_Warrior_Sunder" is standard.
    
    local textureStr = string.lower(name)
    local searchStr = string.lower(string.gsub(debuffName, "%s+", ""))
    if string.find(textureStr, searchStr) then
      return true
    end
    -- Specifically for Sunder Armor
    if debuffName == "Sunder Armor" or debuffName == "破甲攻击" then
      if string.find(textureStr, "ability_warrior_sunder") then
        return true
      end
    end
    i = i + 1
  end
  return false
end

-- Get Sunder Armor stacks on target (0..5).
-- In 1.12 UnitDebuff returns texture and stack count; we match by texture.
function Shalamayne_Conditions.TargetSunderArmorStacks()
  if not Shalamayne_Conditions.TargetExists() then return 0 end
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
