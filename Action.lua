Shalamayne_State = {
  inCombat = false,
  overpowerUntil = 0,
  lastCastSpell = nil,
  lastCastAt = 0,
  lastErrorAt = 0,
  -- Swing timer variables
  mainhandSwingTime = 0,
  mainhandSwingDuration = 2.0,
  offhandSwingTime = 0,
  offhandSwingDuration = 2.0,
  sunderOnceByGuid = {},
  knownSpells = {},
}

-- Reset combat-related states when leaving combat
function Shalamayne_State.ResetCombat()
  Shalamayne_State.overpowerUntil = 0
  Shalamayne_State.lastCastSpell = nil
  Shalamayne_State.lastCastAt = 0
  Shalamayne_State.lastErrorAt = 0
  Shalamayne_State.mainhandSwingTime = 0
  Shalamayne_State.offhandSwingTime = 0
  Shalamayne_State.sunderOnceByGuid = {}
  Shalamayne_State.knownSpells = {}
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

local function DebugHit(reason, spellName, now)
  if not (Shalamayne_Settings and Shalamayne_Settings.debug) then return end
  if not (Shalamayne_DebugUI and Shalamayne_DebugUI.PushLine) then return end
  local stanceNow = Shalamayne_Conditions.GetStance()
  local rageNow = Shalamayne_Conditions.PlayerRage()
  local hpPctNow = Shalamayne_Conditions.TargetExists() and Shalamayne_Conditions.TargetHealthPct() or 0
  local hpAbsNow = Shalamayne_Conditions.TargetExists() and Shalamayne_Conditions.TargetHealth() or 0
  local enemyCountNow = Shalamayne_Conditions.EnemiesInRange()
  local opRem = 0
  if now and Shalamayne_State.overpowerUntil and Shalamayne_State.overpowerUntil > now then
    opRem = Shalamayne_State.overpowerUntil - now
  end
  local targetName = (UnitExists("target") and UnitName("target")) or "-"
  local spellText = spellName or "-"
  Shalamayne_DebugUI.PushLine(string.format("ARMS|%s|%s|stance=%d rage=%d hp=%d(%.1f%%) enemies=%d op=%.1fs target=%s",
    reason or "-", spellText, stanceNow, rageNow, hpAbsNow, hpPctNow, enemyCountNow, opRem, targetName))
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

Shalamayne_Rotation_Arms = {}
Shalamayne_Rotation_Fury = {}

function Shalamayne_Action.Decide(L, now, spec)
  now = now or GetTime()
  spec = spec or (Shalamayne_Settings and Shalamayne_Settings.spec)
  if spec == L.SPEC_FURY_KEY then
    Shalamayne_Rotation_Fury.Decide(L, now)
  else
    Shalamayne_Rotation_Arms.Decide(L, now)
  end
end

-- Arms (2H) rotation.
-- Decide performs the action directly (casts/switches stance) and returns nothing.
function Shalamayne_Rotation_Arms.Decide(L, now)
  now = now or GetTime()

  local rage = Shalamayne_Conditions.PlayerRage()
  local stance = Shalamayne_Conditions.GetStance()
  local inMelee = Shalamayne_Conditions.InMeleeRange(L)
  local hpPct = Shalamayne_Conditions.TargetHealthPct()
  local hpAbs = Shalamayne_Conditions.TargetHealth()
  local enemyCount = Shalamayne_Conditions.EnemiesInRange()
  local aoeEnemies = (Shalamayne_Settings and Shalamayne_Settings.aoeEnemies) or 2
  local sunderHp = (Shalamayne_Settings and Shalamayne_Settings.sunderArmorHp) or 1000

  -- Auto-target a valid melee enemy if current target is invalid
  if not Shalamayne_Conditions.TargetExists() then
    if not Shalamayne_Conditions.AutoTargetMelee() then
      DebugHit("no_target", nil, now)
      return
    end
  end

  AutoAttack()

  -- Ensure default stance is Berserker Stance (3)
  local hasOp = Shalamayne_Conditions.HasOverpowerWindow(now)
  local sweepKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_SWEEPING_STRIKES] or false
  local sweepReady = sweepKnown and Shalamayne_Conditions.IsSpellReady(L.SPELL_SWEEPING_STRIKES, now)
  local sweepCond = enemyCount >= aoeEnemies and sweepKnown and sweepReady


  DebugCheck("stance!=3", stance ~= 3, "stance=" .. tostring(stance))
  DebugCheck("hasOp", hasOp)
  DebugCheck("sweepCond", sweepCond, "enemies=" .. tostring(enemyCount) .. " aoe=" .. tostring(aoeEnemies) .. " known=" .. tostring(sweepKnown) .. " ready=" .. tostring(sweepReady))

  if stance ~= 3 and not (hasOp or sweepCond or msCond) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE, now)
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  local finisherExecOk = inMelee and enemyCount == 1 and hpAbs > 0 and hpAbs < 50000 and Shalamayne_Conditions.CanUseSpell(L.SPELL_EXECUTE, now)
  DebugCheck("finisher_execute", finisherExecOk, "inMelee=" .. tostring(inMelee) .. " enemies=" .. tostring(enemyCount) .. " hp=" .. tostring(hpAbs) .. " ready=" .. tostring(Shalamayne_Conditions.CanUseSpell(L.SPELL_EXECUTE, now)))
  if finisherExecOk then
    DebugHit("finisher_execute", L.SPELL_EXECUTE, now)
    if SpellStopCasting then SpellStopCasting() end
    if stance ~= 3 then
      QueueOrCast(L.SPELL_BERSERKER_STANCE)
      return
    end
    QueueOrCast(L.SPELL_EXECUTE)
    return
  end

  -- Execute when target is sub-20%.
  local execOk = inMelee and hpPct > 0 and hpPct < 20 and Shalamayne_Conditions.CanUseSpell(L.SPELL_EXECUTE, now)
  DebugCheck("execute", execOk, "inMelee=" .. tostring(inMelee) .. " hpPct=" .. string.format("%.1f", hpPct))
  if execOk then
    DebugHit("execute", L.SPELL_EXECUTE, now)
    if stance ~= 3 then
      QueueOrCast(L.SPELL_BERSERKER_STANCE)
      return
    end
    QueueOrCast(L.SPELL_EXECUTE)
    return
  end

  -- Sunder Armor once per target per combat:
  -- in melee, target HP above threshold, target sunder stacks < 5, and not already successfully sunders this target.
  local sunderStacks = Shalamayne_Conditions.TargetSunderArmorStacks()
  local sunderReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_SUNDER_ARMOR, now)
  local _, sunderGuid = UnitExists("target")
  local sunderOnce = (sunderGuid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[sunderGuid]) and true or false
  local sunderOk = inMelee and hpAbs > sunderHp and sunderStacks < 5 and sunderReady and (not sunderOnce)
  DebugCheck("sunder", sunderOk, "inMelee=" .. tostring(inMelee) .. " hp=" .. tostring(hpAbs) .. " thresh=" .. tostring(sunderHp) .. " stacks=" .. tostring(sunderStacks) .. " ready=" .. tostring(sunderReady) .. " once=" .. tostring(sunderOnce))
  if sunderOk then
    DebugHit("sunder_armor", L.SPELL_SUNDER_ARMOR, now)
    if stance ~= 3 then
      QueueOrCast(L.SPELL_BERSERKER_STANCE)
      return
    end
    QueueOrCast(L.SPELL_SUNDER_ARMOR)
    return
  end

  -- Overpower: requires Battle Stance.
  local opKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_OVERPOWER] or false
  local opReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_OVERPOWER, now)
  local opRageGate = (stance ~= 3) or (rage < 40)
  local opOk = inMelee and hasOp and opKnown and opRageGate
  DebugCheck("overpower", opOk, "inMelee=" .. tostring(inMelee) .. " hasOp=" .. tostring(hasOp) .. " known=" .. tostring(opKnown) .. " ready=" .. tostring(opReady) .. " stance=" .. tostring(stance) .. " rageGate=" .. tostring(opRageGate) .. " rage=" .. tostring(rage))
  if opOk then
    if stance ~= 1 then
      DebugHit("stance_battle_for_overpower", L.SPELL_BATTLE_STANCE, now)
      QueueOrCast(L.SPELL_BATTLE_STANCE)
      return
    end
    if opReady then
      DebugHit("overpower", L.SPELL_OVERPOWER, now)
      QueueOrCast(L.SPELL_OVERPOWER)
      return
    end
  end

  -- AoE toggle: Sweeping Strikes in Battle Stance.
  local sweepRageGate = (stance ~= 3) or (rage < 50)
  DebugCheck("sweepingBlock", sweepCond and sweepRageGate, "rage=" .. tostring(rage) .. " stance=" .. tostring(stance) .. " rageGate=" .. tostring(sweepRageGate))
  if enemyCount >= aoeEnemies and sweepKnown and sweepRageGate then
    if stance ~= 1 then
      DebugHit("stance_battle_for_sweeping", L.SPELL_BATTLE_STANCE, now)
      QueueOrCast(L.SPELL_BATTLE_STANCE)
      return
    end
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_SWEEPING_STRIKES, now) then
      DebugHit("sweeping", L.SPELL_SWEEPING_STRIKES, now)
      QueueOrCast(L.SPELL_SWEEPING_STRIKES)
      return
    end
  end

  local msKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_MORTAL_STRIKE] or false
  local msReady = msKnown and Shalamayne_Conditions.IsSpellReady(L.SPELL_MORTAL_STRIKE, now)
  local msCond = msKnown and msReady
  DebugCheck("mortalStrikeBlock", msCond, "rage=" .. tostring(rage) .. " stance=" .. tostring(stance))

  local wwKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_WHIRLWIND] or false
  local wwReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_WHIRLWIND, now)
  local wwOk = enemyCount >= aoeEnemies and wwKnown
  DebugCheck("whirlwindBlock", wwOk, "rage=" .. tostring(rage) .. " stance=" .. tostring(stance) .. " ready=" .. tostring(wwReady))

  local function TryWhirlwind()
    if enemyCount >= aoeEnemies and wwKnown and rage >= 25 and Shalamayne_Conditions.CanUseSpell(L.SPELL_WHIRLWIND, now) then
      if stance ~= 3 and rage < 50 then
        DebugHit("stance_berseker_for_ww", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return true
      end
      if stance == 3 then
        DebugHit("whirlwind", L.SPELL_WHIRLWIND, now)
        QueueOrCast(L.SPELL_WHIRLWIND)
        return true
      end
    end
    return false
  end

  local function TryMortalStrike()
    if not msKnown then return false end
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_MORTAL_STRIKE, now) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE, now)
      QueueOrCast(L.SPELL_MORTAL_STRIKE)
      return true
    end
    return false
  end

  if enemyCount > 1 then
    if TryWhirlwind() then return end
    if TryMortalStrike() then return end
  else
    if TryMortalStrike() then return end
    if TryWhirlwind() then return end
  end

  local execKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_EXECUTE] or false
  local msCd = msKnown and (not Shalamayne_Conditions.IsSpellReady(L.SPELL_MORTAL_STRIKE, now))
  local wwCd = wwKnown and (not Shalamayne_Conditions.IsSpellReady(L.SPELL_WHIRLWIND, now))
  if enemyCount > 1 and execKnown and msCd and wwCd and rage >= 15 and MPScanNearbyEnemiesCount then
    local _, _, nearList = MPScanNearbyEnemiesCount(4.0)
    if nearList then
      local bestGuid = nil
      local bestArmor = nil
      for guid in pairs(nearList) do
        local exists = UnitExists(guid)
        if exists and UnitCanAttack("player", guid) and not UnitIsDead(guid) then
          local hpMax = UnitHealthMax(guid) or 0
          if hpMax > 0 then
            local hpPct2 = (UnitHealth(guid) or 0) / hpMax
            if hpPct2 > 0 and hpPct2 < 0.2 then
              local armorBase, armorEff = UnitArmor(guid)
              local armor = armorEff or armorBase
              if armor then
                if bestArmor == nil or armor < bestArmor then
                  bestArmor = armor
                  bestGuid = guid
                end
              end
            end
          end
        end
      end

      if bestGuid then
        DebugHit("execute_other_low_armor", L.SPELL_EXECUTE, now)
        local spellId = GetSpellIdForName and GetSpellIdForName(L.SPELL_EXECUTE)
        if spellId and CastSpellNoQueue then
          pcall(CastSpellNoQueue, spellId, 0, bestGuid)
        elseif QueueSpellByName then
          pcall(QueueSpellByName, L.SPELL_EXECUTE, bestGuid)
        elseif CastSpellByName then
          pcall(CastSpellByName, L.SPELL_EXECUTE, bestGuid)
        end
        return
      end
    end
  end

  -- Bloodrage as a low-rage stabilizer.
  local brKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_BLOODRAGE] or false
  local brReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODRAGE, now)
  local brOk = brKnown and rage < 10 and brReady
  DebugCheck("bloodrage", brOk, "rage=" .. tostring(rage) .. " known=" .. tostring(brKnown) .. " ready=" .. tostring(brReady))
  if brKnown then
    if rage < 10 and Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODRAGE, now) then
      DebugHit("bloodrage", L.SPELL_BLOODRAGE, now)
      QueueOrCast(L.SPELL_BLOODRAGE)
      return
    end
  end

  -- Heroic Strike as a rage dump.
  local hsRage = (Shalamayne_Settings and Shalamayne_Settings.heroicStrikeRage) or 50
  local hsKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_HEROIC_STRIKE] or false
  local hsReady = Shalamayne_Conditions.CanUseSpell(L.SPELL_HEROIC_STRIKE, now)
  local hsOk = inMelee and rage >= hsRage and hsKnown and hsReady
  DebugCheck("heroic_strike", hsOk, "rage=" .. tostring(rage) .. " req=" .. tostring(hsRage) .. " inMelee=" .. tostring(inMelee) .. " known=" .. tostring(hsKnown) .. " ready=" .. tostring(hsReady))
  if inMelee and rage >= hsRage and hsKnown then
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_HEROIC_STRIKE, now) then
      DebugHit("heroic_strike", L.SPELL_HEROIC_STRIKE, now)
      if stance ~= 3 then
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      QueueOrCast(L.SPELL_HEROIC_STRIKE)
      return
    end
  end

  DebugHit("no_action", nil, now)
  return
end

-- Fury (dual-wield) rotation.
-- Decide performs the action directly (casts/switches stance) and returns nothing.
function Shalamayne_Rotation_Fury.Decide(L, now)
  now = now or GetTime()
  if not Shalamayne_State.inCombat then
    return
  end

  if not Shalamayne_Conditions.TargetExists() then
    if not Shalamayne_Conditions.AutoTargetMelee() then
      return
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

  AutoAttack()

  if stance ~= 3 then
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  if inMelee and hpPct > 0 and hpPct < 20 and Shalamayne_Conditions.CanUseSpell(L.SPELL_EXECUTE, now) then
    QueueOrCast(L.SPELL_EXECUTE)
    return
  end

  local sunderStacks = Shalamayne_Conditions.TargetSunderArmorStacks()
  if inMelee and hpAbs > sunderHp and sunderStacks < 5 then
    local _, sunderGuid = UnitExists("target")
    local sunderOnce = (sunderGuid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[sunderGuid]) and true or false
    if (not sunderOnce) and Shalamayne_Conditions.CanUseSpell(L.SPELL_SUNDER_ARMOR, now) then
      QueueOrCast(L.SPELL_SUNDER_ARMOR)
      return
    end
  end

  local btKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_BLOODTHIRST] or false
  if btKnown then
    if rage >= 30 and Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODTHIRST, now) then
      QueueOrCast(L.SPELL_BLOODTHIRST)
      return
    end
  end

  local wwKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_WHIRLWIND] or false
  if enemyCount >= aoeEnemies and wwKnown then
    if rage >= 25 and Shalamayne_Conditions.CanUseSpell(L.SPELL_WHIRLWIND, now) then
      QueueOrCast(L.SPELL_WHIRLWIND)
      return
    end
  end

  local brKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_BLOODRAGE] or false
  if brKnown then
    if rage < 10 and Shalamayne_Conditions.CanUseSpell(L.SPELL_BLOODRAGE, now) then
      QueueOrCast(L.SPELL_BLOODRAGE)
      return
    end
  end

  local hsRage = (Shalamayne_Settings and Shalamayne_Settings.heroicStrikeRage) or 50
  local hsKnown = Shalamayne_State.knownSpells and Shalamayne_State.knownSpells[L.SPELL_HEROIC_STRIKE] or false
  if inMelee and rage >= hsRage and hsKnown then
    if Shalamayne_Conditions.CanUseSpell(L.SPELL_HEROIC_STRIKE, now) then
      QueueOrCast(L.SPELL_HEROIC_STRIKE)
      return
    end
  end

  return
end
