Shalamayne_State = {
  inCombat = false,
  overpowerUntil = 0,
  lastDecision = nil,
  lastDecisionAt = 0,
  lastCastSpell = nil,
  lastCastAt = 0,
  lastErrorAt = 0,
  -- Swing timer variables
  mainhandSwingTime = 0,
  mainhandSwingDuration = 2.0,
  offhandSwingTime = 0,
  offhandSwingDuration = 2.0,
}

-- Reset combat-related states when leaving combat
function Shalamayne_State.ResetCombat()
  Shalamayne_State.overpowerUntil = 0
  Shalamayne_State.lastDecision = nil
  Shalamayne_State.lastDecisionAt = 0
  Shalamayne_State.lastCastSpell = nil
  Shalamayne_State.lastCastAt = 0
  Shalamayne_State.lastErrorAt = 0
  Shalamayne_State.mainhandSwingTime = 0
  Shalamayne_State.offhandSwingTime = 0
end

Shalamayne_Action = {}

-- QueueSpellByName (Nampower) provides reliable spell queuing.
-- If it's not available, fall back to CastSpellByName.
local function QueueOrCast(spellName)
  if QueueSpellByName then
    QueueSpellByName(spellName)
    return
  end
  CastSpellByName(spellName)
end

-- Ensure auto-attack is running (optional setting).
-- We intentionally keep this simple and only call AttackTarget when we have a valid hostile target.
function Shalamayne_Action.EnsureAutoAttack()
  if not Shalamayne_Conditions.TargetExists() then return end
  AttackTarget()
end

-- Switch stance during combat when required.
-- 1=Battle, 2=Defensive, 3=Berserker.
function Shalamayne_Action.SwitchStance(requiredStance, L)
  local stance = Shalamayne_Conditions.GetStance()
  if stance == requiredStance then return false end
  if requiredStance == 1 then
    QueueOrCast(L.SPELL_BATTLE_STANCE)
    return true
  elseif requiredStance == 2 then
    QueueOrCast(L.SPELL_DEFENSIVE_STANCE)
    return true
  elseif requiredStance == 3 then
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return true
  end
  return false
end

-- Cast (or queue) the requested spell.
function Shalamayne_Action.CastSpell(spellName)
  QueueOrCast(spellName)
end

Shalamayne_Rotation_Arms = {}

-- Helper to format an action table
local function SpellAction(spellName, requiredStance)
  return { type = "spell", spell = spellName, stance = requiredStance }
end

-- Arms (2H) rotation.
-- Returns an action table or nil, plus a short debug reason key.
-- Stance switching is allowed ONLY in combat.
function Shalamayne_Rotation_Arms.Decide(L, now)
  now = now or GetTime()
  if not Shalamayne_State.inCombat then return nil, "not_in_combat" end

  -- Auto-target a valid melee enemy if current target is invalid
  if not Shalamayne_Conditions.TargetExists() then
    if not Shalamayne_Conditions.AutoTargetMelee() then
      return nil, "no_target"
    end
  end

  local rage = Shalamayne_Conditions.PlayerRage()
  local stance = Shalamayne_Conditions.GetStance()
  local inMelee = Shalamayne_Conditions.InMeleeRange(L)
  local hpPct = Shalamayne_Conditions.TargetHealthPct()
  local hpAbs = Shalamayne_Conditions.TargetHealth()
  local enemyCount = Shalamayne_Conditions.EnemiesInRange()
  local aoeEnemies = (Shalamayne_Settings and Shalamayne_Settings.aoeEnemies) or 2
  local sunderHp = (Shalamayne_Settings and Shalamayne_Settings.sunderArmorHp) or 1000

  Shalamayne_Action.EnsureAutoAttack()

  -- Ensure default stance is Berserker Stance (3)
  if stance ~= 3 and not (Shalamayne_Conditions.HasOverpowerWindow(now) or
    (enemyCount >= aoeEnemies and Shalamayne_Settings.useSweeping and Shalamayne_Conditions.IsSpellKnown(L.SPELL_SWEEPING_STRIKES) and Shalamayne_Conditions.IsSpellReady(L.SPELL_SWEEPING_STRIKES, now)) or
    (Shalamayne_Settings.useMortalStrike and Shalamayne_Conditions.IsSpellKnown(L.SPELL_MORTAL_STRIKE) and Shalamayne_Conditions.IsSpellReady(L.SPELL_MORTAL_STRIKE, now))) then
    return SpellAction(L.SPELL_BERSERKER_STANCE, 3), "stance_berseker_default"
  end

  -- Execute when target is sub-20%.
  if inMelee and hpPct > 0 and hpPct < 20 and Shalamayne_Conditions.CanUseSpell(L.SPELL_EXECUTE, now) then
    return SpellAction(L.SPELL_EXECUTE, 3), "execute"
  end

  -- Sunder Armor if target HP is above threshold and missing Sunder debuff
  if inMelee and hpAbs > sunderHp and not Shalamayne_Conditions.TargetHasDebuff(L.SPELL_SUNDER_ARMOR) then
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_SUNDER_ARMOR, now) then
      return SpellAction(L.SPELL_SUNDER_ARMOR, 3), "sunder_armor"
    end
  end

  -- Overpower: requires Battle Stance.
  if inMelee and Shalamayne_Conditions.HasOverpowerWindow(now) and Shalamayne_Conditions.IsSpellKnown(L.SPELL_OVERPOWER) then
    if stance ~= 1 then
      return SpellAction(L.SPELL_BATTLE_STANCE, 1), "stance_battle_for_overpower"
    end
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_OVERPOWER, now) then
      return SpellAction(L.SPELL_OVERPOWER, 1), "overpower"
    end
  end

  -- AoE toggle: Sweeping Strikes in Battle Stance.
  if enemyCount >= aoeEnemies and Shalamayne_Settings and Shalamayne_Settings.useSweeping and Shalamayne_Conditions.IsSpellKnown(L.SPELL_SWEEPING_STRIKES) then
    if stance ~= 1 then
      return SpellAction(L.SPELL_BATTLE_STANCE, 1), "stance_battle_for_sweeping"
    end
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_SWEEPING_STRIKES, now) then
      return SpellAction(L.SPELL_SWEEPING_STRIKES, 1), "sweeping"
    end
  end

  -- Mortal Strike in Battle Stance.
  if Shalamayne_Settings and Shalamayne_Settings.useMortalStrike and Shalamayne_Conditions.IsSpellKnown(L.SPELL_MORTAL_STRIKE) then
    if stance ~= 1 then
      return SpellAction(L.SPELL_BATTLE_STANCE, 1), "stance_battle_for_ms"
    end
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_MORTAL_STRIKE, now) then
      return SpellAction(L.SPELL_MORTAL_STRIKE, 1), "mortal_strike"
    end
  end

  -- AoE toggle: Whirlwind in Berserker Stance.
  if enemyCount >= aoeEnemies and Shalamayne_Settings and Shalamayne_Settings.useWhirlwind and Shalamayne_Conditions.IsSpellKnown(L.SPELL_WHIRLWIND) then
    if stance ~= 3 then
      return SpellAction(L.SPELL_BERSERKER_STANCE, 3), "stance_berseker_for_ww"
    end
    if rage >= 25 and Shalamayne_Conditions.CanUseSpell(L.SPELL_WHIRLWIND, now) then
      return SpellAction(L.SPELL_WHIRLWIND, 3), "whirlwind"
    end
  end

  -- Bloodrage as a low-rage stabilizer.
  if Shalamayne_Settings and Shalamayne_Settings.useBloodrage and Shalamayne_Conditions.IsSpellKnown(L.SPELL_BLOODRAGE) then
    if rage < 10 and Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODRAGE, now) then
      return SpellAction(L.SPELL_BLOODRAGE, stance), "bloodrage"
    end
  end

  -- Heroic Strike as a rage dump.
  local hsRage = (Shalamayne_Settings and Shalamayne_Settings.heroicStrikeRage) or 50
  if inMelee and Shalamayne_Settings and Shalamayne_Settings.useHeroicStrike and rage >= hsRage and Shalamayne_Conditions.IsSpellKnown(L.SPELL_HEROIC_STRIKE) then
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_HEROIC_STRIKE, now) then
      return SpellAction(L.SPELL_HEROIC_STRIKE, 3), "heroic_strike"
    end
  end

  return nil, "no_action"
end

Shalamayne_Rotation_Fury = {}

local function SpellAction(spellName, requiredStance)
  return { type = "spell", spell = spellName, stance = requiredStance }
end

-- Fury (dual-wield) rotation.
-- Uses Berserker Stance as the default combat stance.
function Shalamayne_Rotation_Fury.Decide(L, now)
  now = now or GetTime()
  if not Shalamayne_State.inCombat then return nil, "not_in_combat" end

  -- Auto-target a valid melee enemy if current target is invalid
  if not Shalamayne_Conditions.TargetExists() then
    if not Shalamayne_Conditions.AutoTargetMelee() then
      return nil, "no_target"
    end
  end

  local rage = Shalamayne_Conditions.PlayerRage()
  local stance = Shalamayne_Conditions.GetStance()
  local inMelee = Shalamayne_Conditions.InMeleeRange(L)
  local hpPct = Shalamayne_Conditions.TargetHealthPct()
  local hpAbs = Shalamayne_Conditions.TargetHealth()
  local enemyCount = Shalamayne_Conditions.EnemiesInRange()
  local aoeEnemies = (Shalamayne_Settings and Shalamayne_Settings.aoeEnemies) or 2
  local sunderHp = (Shalamayne_Settings and Shalamayne_Settings.sunderArmorHp) or 1000

  Shalamayne_Action.EnsureAutoAttack()

  if stance ~= 3 then
    return SpellAction(L.SPELL_BERSERKER_STANCE, 3), "stance_berseker"
  end

  -- Execute when target is sub-20%.
  if inMelee and hpPct > 0 and hpPct < 20 and Shalamayne_Conditions.CanUseSpell(L.SPELL_EXECUTE, now) then
    return SpellAction(L.SPELL_EXECUTE, 3), "execute"
  end

  -- Sunder Armor if target HP is above threshold and missing Sunder debuff
  if inMelee and hpAbs > sunderHp and not Shalamayne_Conditions.TargetHasDebuff(L.SPELL_SUNDER_ARMOR) then
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_SUNDER_ARMOR, now) then
      return SpellAction(L.SPELL_SUNDER_ARMOR, 3), "sunder_armor"
    end
  end

  -- Bloodthirst on cooldown.
  if Shalamayne_Settings and Shalamayne_Settings.useBloodthirst and Shalamayne_Conditions.IsSpellKnown(L.SPELL_BLOODTHIRST) then
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODTHIRST, now) then
      return SpellAction(L.SPELL_BLOODTHIRST, 3), "bloodthirst"
    end
  end

  -- Whirlwind for AoE.
  if enemyCount >= aoeEnemies and Shalamayne_Settings and Shalamayne_Settings.useWhirlwind and Shalamayne_Conditions.IsSpellKnown(L.SPELL_WHIRLWIND) then
    if rage >= 25 and Shalamayne_Conditions.CanUseSpell(L.SPELL_WHIRLWIND, now) then
      return SpellAction(L.SPELL_WHIRLWIND, 3), "whirlwind"
    end
  end

  -- Bloodrage as a low-rage stabilizer.
  if Shalamayne_Settings and Shalamayne_Settings.useBloodrage and Shalamayne_Conditions.IsSpellKnown(L.SPELL_BLOODRAGE) then
    if rage < 10 and Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODRAGE, now) then
      return SpellAction(L.SPELL_BLOODRAGE, 3), "bloodrage"
    end
  end

  -- Heroic Strike as a rage dump.
  local hsRage = (Shalamayne_Settings and Shalamayne_Settings.heroicStrikeRage) or 50
  if inMelee and Shalamayne_Settings and Shalamayne_Settings.useHeroicStrike and rage >= hsRage and Shalamayne_Conditions.IsSpellKnown(L.SPELL_HEROIC_STRIKE) then
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_HEROIC_STRIKE, now) then
      return SpellAction(L.SPELL_HEROIC_STRIKE, 3), "heroic_strike"
    end
  end

  return nil, "no_action"
end
