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
  local function DebugHit(reason, spellName)
    if not (Shalamayne_Settings and Shalamayne_Settings.debug) then return end
    if not (Shalamayne_DebugUI and Shalamayne_DebugUI.PushLine) then return end
    local stance = Shalamayne_Conditions.GetStance()
    local rage = Shalamayne_Conditions.PlayerRage()
    local hpPct = Shalamayne_Conditions.TargetExists() and Shalamayne_Conditions.TargetHealthPct() or 0
    local hpAbs = Shalamayne_Conditions.TargetExists() and Shalamayne_Conditions.TargetHealth() or 0
    local enemyCount = Shalamayne_Conditions.EnemiesInRange()
    local opRem = 0
    if Shalamayne_State.overpowerUntil and Shalamayne_State.overpowerUntil > now then
      opRem = Shalamayne_State.overpowerUntil - now
    end
    local targetName = (UnitExists("target") and UnitName("target")) or "-"
    local spellText = spellName or "-"
    Shalamayne_DebugUI.PushLine(string.format("ARMS|%s|%s|stance=%d rage=%d hp=%d(%.1f%%) enemies=%d op=%.1fs target=%s",
      reason or "-", spellText, stance, rage, hpAbs, hpPct, enemyCount, opRem, targetName))
  end

  local function DebugCheck(tag, ok, details)
    if not (Shalamayne_Settings and Shalamayne_Settings.debug) then return end
    if not (Shalamayne_DebugUI and Shalamayne_DebugUI.PushLine) then return end
    local status = ok and "OK" or "NO"
    local msg = "ARMS? " .. tag .. "=" .. status
    if details and details ~= "" then
      msg = msg .. " | " .. details
    end
    Shalamayne_DebugUI.PushLine(msg)
  end

  if not Shalamayne_State.inCombat then
    DebugHit("not_in_combat")
    return nil, "not_in_combat"
  end

  -- Auto-target a valid melee enemy if current target is invalid
  if not Shalamayne_Conditions.TargetExists() then
    if not Shalamayne_Conditions.AutoTargetMelee() then
      DebugHit("no_target")
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
  local hasOp = Shalamayne_Conditions.HasOverpowerWindow(now)
  local sweepKnown = Shalamayne_Conditions.IsSpellKnown(L.SPELL_SWEEPING_STRIKES)
  local sweepReady = Shalamayne_Conditions.IsSpellReady(L.SPELL_SWEEPING_STRIKES, now)
  local sweepCond = enemyCount >= aoeEnemies and Shalamayne_Settings.useSweeping and sweepKnown and sweepReady
  local msKnown = Shalamayne_Conditions.IsSpellKnown(L.SPELL_MORTAL_STRIKE)
  local msReady = Shalamayne_Conditions.IsSpellReady(L.SPELL_MORTAL_STRIKE, now)
  local msCond = Shalamayne_Settings.useMortalStrike and msKnown and msReady

  DebugCheck("stance!=3", stance ~= 3, "stance=" .. tostring(stance))
  DebugCheck("hasOp", hasOp)
  DebugCheck("sweepCond", sweepCond, "enemies=" .. tostring(enemyCount) .. " aoe=" .. tostring(aoeEnemies) .. " known=" .. tostring(sweepKnown) .. " ready=" .. tostring(sweepReady))
  DebugCheck("msCond", msCond, "known=" .. tostring(msKnown) .. " ready=" .. tostring(msReady))

  if stance ~= 3 and not (hasOp or sweepCond or msCond) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE)
    return SpellAction(L.SPELL_BERSERKER_STANCE, 3), "stance_berseker_default"
  end

  -- Execute when target is sub-20%.
  local execOk = inMelee and hpPct > 0 and hpPct < 20 and Shalamayne_Conditions.CanUseSpell(L.SPELL_EXECUTE, now)
  DebugCheck("execute", execOk, "inMelee=" .. tostring(inMelee) .. " hpPct=" .. string.format("%.1f", hpPct))
  if execOk then
    DebugHit("execute", L.SPELL_EXECUTE)
    return SpellAction(L.SPELL_EXECUTE, 3), "execute"
  end

  -- Sunder Armor if target HP is above threshold and missing Sunder debuff
  local sunderMissing = not Shalamayne_Conditions.TargetHasDebuff(L.SPELL_SUNDER_ARMOR)
  local sunderReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_SUNDER_ARMOR, now)
  local sunderOk = inMelee and hpAbs > sunderHp and sunderMissing and sunderReady
  DebugCheck("sunder", sunderOk, "inMelee=" .. tostring(inMelee) .. " hp=" .. tostring(hpAbs) .. " thresh=" .. tostring(sunderHp) .. " missing=" .. tostring(sunderMissing) .. " ready=" .. tostring(sunderReady))
  if sunderOk then
    DebugHit("sunder_armor", L.SPELL_SUNDER_ARMOR)
    return SpellAction(L.SPELL_SUNDER_ARMOR, 3), "sunder_armor"
  end

  -- Overpower: requires Battle Stance.
  local opKnown = Shalamayne_Conditions.IsSpellKnown(L.SPELL_OVERPOWER)
  local opReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_OVERPOWER, now)
  local opOk = inMelee and hasOp and opKnown
  DebugCheck("overpower", opOk, "inMelee=" .. tostring(inMelee) .. " hasOp=" .. tostring(hasOp) .. " known=" .. tostring(opKnown) .. " ready=" .. tostring(opReady) .. " stance=" .. tostring(stance))
  if opOk then
    if stance ~= 1 then
      DebugHit("stance_battle_for_overpower", L.SPELL_BATTLE_STANCE)
      return SpellAction(L.SPELL_BATTLE_STANCE, 1), "stance_battle_for_overpower"
    end
    if opReady then
      DebugHit("overpower", L.SPELL_OVERPOWER)
      return SpellAction(L.SPELL_OVERPOWER, 1), "overpower"
    end
  end

  -- AoE toggle: Sweeping Strikes in Battle Stance.
  DebugCheck("sweepingBlock", sweepCond, "rage=" .. tostring(rage) .. " stance=" .. tostring(stance))
  if enemyCount >= aoeEnemies and Shalamayne_Settings and Shalamayne_Settings.useSweeping and Shalamayne_Conditions.IsSpellKnown(L.SPELL_SWEEPING_STRIKES) then
    if stance ~= 1 then
      DebugHit("stance_battle_for_sweeping", L.SPELL_BATTLE_STANCE)
      return SpellAction(L.SPELL_BATTLE_STANCE, 1), "stance_battle_for_sweeping"
    end
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_SWEEPING_STRIKES, now) then
      DebugHit("sweeping", L.SPELL_SWEEPING_STRIKES)
      return SpellAction(L.SPELL_SWEEPING_STRIKES, 1), "sweeping"
    end
  end

  -- Mortal Strike in Battle Stance.
  DebugCheck("mortalStrikeBlock", msCond, "rage=" .. tostring(rage) .. " stance=" .. tostring(stance))
  if Shalamayne_Settings and Shalamayne_Settings.useMortalStrike and Shalamayne_Conditions.IsSpellKnown(L.SPELL_MORTAL_STRIKE) then
    if stance ~= 1 then
      DebugHit("stance_battle_for_ms", L.SPELL_BATTLE_STANCE)
      return SpellAction(L.SPELL_BATTLE_STANCE, 1), "stance_battle_for_ms"
    end
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_MORTAL_STRIKE, now) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE)
      return SpellAction(L.SPELL_MORTAL_STRIKE, 1), "mortal_strike"
    end
  end

  -- AoE toggle: Whirlwind in Berserker Stance.
  local wwKnown = Shalamayne_Conditions.IsSpellKnown(L.SPELL_WHIRLWIND)
  local wwReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_WHIRLWIND, now)
  local wwOk = enemyCount >= aoeEnemies and Shalamayne_Settings and Shalamayne_Settings.useWhirlwind and wwKnown
  DebugCheck("whirlwindBlock", wwOk, "rage=" .. tostring(rage) .. " stance=" .. tostring(stance) .. " ready=" .. tostring(wwReady))
  if enemyCount >= aoeEnemies and Shalamayne_Settings and Shalamayne_Settings.useWhirlwind and Shalamayne_Conditions.IsSpellKnown(L.SPELL_WHIRLWIND) then
    if stance ~= 3 then
      DebugHit("stance_berseker_for_ww", L.SPELL_BERSERKER_STANCE)
      return SpellAction(L.SPELL_BERSERKER_STANCE, 3), "stance_berseker_for_ww"
    end
    if rage >= 25 and Shalamayne_Conditions.CanUseSpell(L.SPELL_WHIRLWIND, now) then
      DebugHit("whirlwind", L.SPELL_WHIRLWIND)
      return SpellAction(L.SPELL_WHIRLWIND, 3), "whirlwind"
    end
  end

  -- Bloodrage as a low-rage stabilizer.
  local brKnown = Shalamayne_Conditions.IsSpellKnown(L.SPELL_BLOODRAGE)
  local brReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODRAGE, now)
  local brOk = Shalamayne_Settings and Shalamayne_Settings.useBloodrage and brKnown and rage < 10 and brReady
  DebugCheck("bloodrage", brOk, "rage=" .. tostring(rage) .. " known=" .. tostring(brKnown) .. " ready=" .. tostring(brReady))
  if Shalamayne_Settings and Shalamayne_Settings.useBloodrage and Shalamayne_Conditions.IsSpellKnown(L.SPELL_BLOODRAGE) then
    if rage < 10 and Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODRAGE, now) then
      DebugHit("bloodrage", L.SPELL_BLOODRAGE)
      return SpellAction(L.SPELL_BLOODRAGE, stance), "bloodrage"
    end
  end

  -- Heroic Strike as a rage dump.
  local hsRage = (Shalamayne_Settings and Shalamayne_Settings.heroicStrikeRage) or 50
  local hsKnown = Shalamayne_Conditions.IsSpellKnown(L.SPELL_HEROIC_STRIKE)
  local hsReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_HEROIC_STRIKE, now)
  local hsOk = inMelee and Shalamayne_Settings and Shalamayne_Settings.useHeroicStrike and rage >= hsRage and hsKnown and hsReady
  DebugCheck("heroic_strike", hsOk, "rage=" .. tostring(rage) .. " req=" .. tostring(hsRage) .. " inMelee=" .. tostring(inMelee) .. " known=" .. tostring(hsKnown) .. " ready=" .. tostring(hsReady))
  if inMelee and Shalamayne_Settings and Shalamayne_Settings.useHeroicStrike and rage >= hsRage and Shalamayne_Conditions.IsSpellKnown(L.SPELL_HEROIC_STRIKE) then
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_HEROIC_STRIKE, now) then
      DebugHit("heroic_strike", L.SPELL_HEROIC_STRIKE)
      return SpellAction(L.SPELL_HEROIC_STRIKE, 3), "heroic_strike"
    end
  end

  DebugHit("no_action")
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
