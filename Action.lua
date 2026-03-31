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
  lastUnknownSpell = nil,
  lastUnknownSpellAt = 0,
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
  Shalamayne_State.lastUnknownSpell = nil
  Shalamayne_State.lastUnknownSpellAt = 0
end

Shalamayne_Action = {}

-- QueueSpellByName (Nampower) provides reliable spell queuing.
-- If it's not available, fall back to CastSpellByName.
local function QueueOrCast(spellName)
  if Shalamayne_Conditions and Shalamayne_Conditions.IsSpellKnown then
    if not Shalamayne_Conditions.IsSpellKnown(spellName) then
      if Shalamayne_Settings and Shalamayne_Settings.debug and Shalamayne_DebugUI and Shalamayne_DebugUI.PushLine then
        local now = GetTime()
        if Shalamayne_State.lastUnknownSpell ~= spellName or (now - (Shalamayne_State.lastUnknownSpellAt or 0)) > 1.0 then
          Shalamayne_State.lastUnknownSpell = spellName
          Shalamayne_State.lastUnknownSpellAt = now
          Shalamayne_DebugUI.PushLine("SPELL? not_known=" .. tostring(spellName))
        end
      end
      return
    end
  end
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

  if not Shalamayne_Conditions.TargetExists() then
    Shalamayne_Conditions.AutoTargetMelee()
  end

  local rage = Shalamayne_Conditions.PlayerRage()
  local stance = Shalamayne_Conditions.GetStance()
  local inMelee = Shalamayne_Conditions.InMeleeRange(L)
  local hpPct = Shalamayne_Conditions.TargetHealthPct()
  local hpAbs = Shalamayne_Conditions.TargetHealth()
  local enemyCount = Shalamayne_Conditions.EnemiesInRange()
  local sunderHp = (Shalamayne_Settings and Shalamayne_Settings.sunderArmorHp) or 1000
  local hsRage = (Shalamayne_Settings and Shalamayne_Settings.heroicStrikeRage) or 50
  local finisherHp = (Shalamayne_Settings and Shalamayne_Settings.finisherExecuteHp) or 50000

  if not (PlayerFrame and PlayerFrame.inCombat) then
    AttackTarget()
  end

  local function Cond(spellName, hasCd, minRage, maxRage)
    if hasCd and not Shalamayne_Conditions.IsSpellReady(spellName, now) then return false end
    -- if minRage and rage < minRage then return false end
    -- if maxRage and rage >= maxRage then return false end
    return true
  end

  local hasOp = Shalamayne_Conditions.HasOverpowerWindow(now)
  local opRageGate = (stance ~= 3) or (rage < 40)
  local sweepRageGate = (stance ~= 3) or (rage < 50)
  if stance ~= 3 and not ((hasOp and opRageGate and Cond(L.SPELL_OVERPOWER, true)) or (enemyCount >= 2 and sweepRageGate and Cond(L.SPELL_SWEEPING_STRIKES, true, 30))) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE, now)
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  local function DoAOE()
    if enemyCount >= 2 and Cond(L.SPELL_EXECUTE, true, 15) then
      local guids = Shalamayne_Conditions.EnemyGuidsInMelee(4.0)
      local bestGuid = nil
      local bestArmor = nil
      for guid in pairs(guids) do
        if UnitExists(guid) and UnitCanAttack("player", guid) and not UnitIsDead(guid) then
          local maxHp2 = UnitHealthMax(guid) or 0
          if maxHp2 > 0 then
            local hpPct2 = (UnitHealth(guid) or 0) / maxHp2
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
          return
        end
        if QueueSpellByName then
          pcall(QueueSpellByName, L.SPELL_EXECUTE, bestGuid)
          return
        end
        if CastSpellByName then
          pcall(CastSpellByName, L.SPELL_EXECUTE, bestGuid)
          return
        end
      end
    end
    if enemyCount >= 2 and sweepRageGate and Cond(L.SPELL_SWEEPING_STRIKES, true, 30) then
      if stance ~= 1 then
        DebugHit("stance_for_sweeping", L.SPELL_BATTLE_STANCE, now)
        QueueOrCast(L.SPELL_BATTLE_STANCE)
        return
      end
      DebugHit("sweeping_strikes", L.SPELL_SWEEPING_STRIKES, now)
      QueueOrCast(L.SPELL_SWEEPING_STRIKES)
    end

    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Cond(L.SPELL_SUNDER_ARMOR, true) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if enemyCount >= 2 and Cond(L.SPELL_WHIRLWIND, true, 25) then
      if stance ~= 3 and rage < 50 then
        DebugHit("stance_for_whirlwind", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      if stance == 3 then
        DebugHit("whirlwind", L.SPELL_WHIRLWIND, now)
        QueueOrCast(L.SPELL_WHIRLWIND)
        return
      end
    end

    if inMelee and Cond(L.SPELL_CLEAVE, false, hsRage) then
      if stance == 2 then
        DebugHit("stance_for_cleave", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("cleave", L.SPELL_CLEAVE, now)
      QueueOrCast(L.SPELL_CLEAVE)
      return
    end

    if Cond(L.SPELL_MORTAL_STRIKE, true, 30) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE, now)
      QueueOrCast(L.SPELL_MORTAL_STRIKE)
      return
    end

    if inMelee and Cond(L.SPELL_SLAM, true, 15) then
      DebugHit("slam", L.SPELL_SLAM, now)
      QueueOrCast(L.SPELL_SLAM)
      return
    end

    DebugHit("no_action", nil, now)
  end

  local function DoSingle()
    if inMelee and hpAbs > 0 and hpAbs < finisherHp and Cond(L.SPELL_EXECUTE, true) then
      if SpellStopCasting then
        SpellStopCasting()
      end
      if stance ~= 3 then
        DebugHit("stance_for_execute", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("finisher_execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Cond(L.SPELL_SUNDER_ARMOR, true) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if inMelee and hasOp and opRageGate then
      if stance ~= 1 then
        DebugHit("stance_for_overpower", L.SPELL_BATTLE_STANCE, now)
        QueueOrCast(L.SPELL_BATTLE_STANCE)
        return
      end
      if Cond(L.SPELL_OVERPOWER, true) then
        DebugHit("overpower", L.SPELL_OVERPOWER, now)
        QueueOrCast(L.SPELL_OVERPOWER)
        return
      end
    end

    if Cond(L.SPELL_MORTAL_STRIKE, true, 30) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE, now)
      QueueOrCast(L.SPELL_MORTAL_STRIKE)
      return
    end

    if Cond(L.SPELL_WHIRLWIND, true, 25) then
      if stance ~= 3 and rage < 50 then
        DebugHit("stance_for_whirlwind", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      if stance == 3 then
        DebugHit("whirlwind", L.SPELL_WHIRLWIND, now)
        QueueOrCast(L.SPELL_WHIRLWIND)
        return
      end
    end

    if inMelee and hpPct > 0 and hpPct < 20 and Cond(L.SPELL_EXECUTE, true) then
      DebugHit("execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and rage > 60 and Cond(L.SPELL_HEROIC_STRIKE, false, hsRage) then
      DebugHit("heroic_strike", L.SPELL_HEROIC_STRIKE, now)
      QueueOrCast(L.SPELL_HEROIC_STRIKE)
      return
    end

    if inMelee and Cond(L.SPELL_SLAM, true, 15) then
      DebugHit("slam", L.SPELL_SLAM, now)
      QueueOrCast(L.SPELL_SLAM)
      return
    end

    DebugHit("no_action", nil, now)
  end

  if enemyCount >= 2 then
    DoAOE()
    return
  end

  DoSingle()
  return
end

-- Fury (dual-wield) rotation.
-- Decide performs the action directly (casts/switches stance) and returns nothing.
function Shalamayne_Rotation_Fury.Decide(L, now)
  now = now or GetTime()
  if not Shalamayne_State.inCombat then return end

  if not Shalamayne_Conditions.TargetExists() then
    if not Shalamayne_Conditions.AutoTargetMelee() then
      return
    end
  end

  if not (PlayerFrame and PlayerFrame.inCombat) then
    AttackTarget()
  end

  local rage = Shalamayne_Conditions.PlayerRage()
  local stance = Shalamayne_Conditions.GetStance()
  local inMelee = Shalamayne_Conditions.InMeleeRange(L)
  local hpPct = Shalamayne_Conditions.TargetHealthPct()
  local hpAbs = Shalamayne_Conditions.TargetHealth()
  local enemyCount = Shalamayne_Conditions.EnemiesInRange()
  local sunderHp = (Shalamayne_Settings and Shalamayne_Settings.sunderArmorHp) or 1000
  local hsRage = (Shalamayne_Settings and Shalamayne_Settings.heroicStrikeRage) or 50
  local finisherHp = (Shalamayne_Settings and Shalamayne_Settings.finisherExecuteHp) or 50000
  local function Cond(spellName, hasCd, minRage, maxRage)
    if hasCd and not Shalamayne_Conditions.IsSpellReady(spellName, now) then return false end
    if minRage and rage < minRage then return false end
    if maxRage and rage >= maxRage then return false end
    return Shalamayne_Conditions.CanUseSpell(spellName, now)
  end

  local hasOp = Shalamayne_Conditions.HasOverpowerWindow(now)
  local opRageGate = (stance ~= 3) or (rage < 40)
  if stance ~= 3 and not (hasOp and opRageGate and Cond(L.SPELL_OVERPOWER, true)) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE, now)
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  local function DoAOE()
    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Cond(L.SPELL_SUNDER_ARMOR, true) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if Cond(L.SPELL_WHIRLWIND, true, 25) then
      if stance ~= 3 and rage < 50 then
        DebugHit("stance_for_whirlwind", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      if stance == 3 then
        DebugHit("whirlwind", L.SPELL_WHIRLWIND, now)
        QueueOrCast(L.SPELL_WHIRLWIND)
        return
      end
    end

    if inMelee and Cond(L.SPELL_CLEAVE, false, hsRage) then
      if stance == 2 then
        DebugHit("stance_for_cleave", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("cleave", L.SPELL_CLEAVE, now)
      QueueOrCast(L.SPELL_CLEAVE)
      return
    end

    if Cond(L.SPELL_BLOODTHIRST, true, 30) then
      DebugHit("bloodthirst", L.SPELL_BLOODTHIRST, now)
      QueueOrCast(L.SPELL_BLOODTHIRST)
      return
    end
  end

  local function DoSingle()
    if inMelee and hpAbs > 0 and hpAbs < finisherHp and Cond(L.SPELL_EXECUTE, true) then
      if SpellStopCasting then
        SpellStopCasting()
      end
      DebugHit("finisher_execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Cond(L.SPELL_SUNDER_ARMOR, true) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if inMelee and hasOp and opRageGate then
      if stance ~= 1 then
        DebugHit("stance_for_overpower", L.SPELL_BATTLE_STANCE, now)
        QueueOrCast(L.SPELL_BATTLE_STANCE)
        return
      end
      if Cond(L.SPELL_OVERPOWER, true) then
        DebugHit("overpower", L.SPELL_OVERPOWER, now)
        QueueOrCast(L.SPELL_OVERPOWER)
        return
      end
    end

    if Cond(L.SPELL_BLOODTHIRST, true, 30) then
      DebugHit("bloodthirst", L.SPELL_BLOODTHIRST, now)
      QueueOrCast(L.SPELL_BLOODTHIRST)
      return
    end

    if Cond(L.SPELL_WHIRLWIND, true, 25) then
      if stance ~= 3 and rage < 50 then
        DebugHit("stance_for_whirlwind", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      if stance == 3 then
        DebugHit("whirlwind", L.SPELL_WHIRLWIND, now)
        QueueOrCast(L.SPELL_WHIRLWIND)
        return
      end
    end

    if inMelee and hpPct > 0 and hpPct < 20 and Cond(L.SPELL_EXECUTE, true) then
      if stance ~= 3 then
        DebugHit("stance_for_execute", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and Cond(L.SPELL_HEROIC_STRIKE, false, hsRage) then
      if stance == 2 then
        DebugHit("stance_for_heroic_strike", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("heroic_strike", L.SPELL_HEROIC_STRIKE, now)
      QueueOrCast(L.SPELL_HEROIC_STRIKE)
      return
    end
  end

  if enemyCount >= 2 then
    DoAOE()
    return
  end

  DoSingle()
  return
end
