Shalamayne_Spellbook = {
  slotByName = {},
  lastScanAt = 0,
}

local BOOKTYPE_SPELL = BOOKTYPE_SPELL or "spell"

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

  local originalGuid = GetTargetGuid()
  local seen = {}
  local count = 0

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
        count = count + 1
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

  if count < 1 then count = 1 end
  Shalamayne_EnemyScanner.lastScanAt = now
  Shalamayne_EnemyScanner.lastCount = count
  return count
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
  local form = GetShapeshiftForm and GetShapeshiftForm() or 0
  return form
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
  return Shalamayne_Spellbook.GetSlot(spellName) ~= nil
end

-- Spell cooldown check by spellbook slot.
function Shalamayne_Conditions.IsSpellReady(spellName, now)
  local slot = Shalamayne_Spellbook.GetSlot(spellName)
  if not slot then return false end
  now = now or GetTime()
  local start, duration, enabled = GetSpellCooldown(slot, BOOKTYPE_SPELL)
  if enabled == 0 then return false end
  if start == 0 or duration == 0 then return true end
  return (start + duration) <= now
end

-- Full usability check: cooldown + resource requirements.
function Shalamayne_Conditions.CanUseSpell(spellName, now)
  if not Shalamayne_Conditions.IsSpellReady(spellName, now) then return false end
  if IsSpellUsable then
    local ok, usable, noResource = pcall(IsSpellUsable, spellName)
    if ok then
      if noResource then return false end
      return usable ~= nil and usable ~= 0
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

-- Checks if the target has a specific debuff by name
function Shalamayne_Conditions.TargetHasDebuff(debuffName)
  if not Shalamayne_Conditions.TargetExists() then return false end
  local i = 1
  while true do
    local name, _, _ = UnitDebuff("target", i)
    if not name then break end
    
    -- In 1.12 UnitDebuff returns the texture path, we do a basic string match
    -- Usually debuffName is the spell name, so this is a simplified fallback
    -- Note: NampowerAPI or SuperCleveRoids might provide a better UnitDebuff wrapper returning names.
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
