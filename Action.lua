Shalamayne_State = {
  inCombat = false,
  overpowerUntil = 0,
  mainhandSwingTime = 0,
  mainhandSwingDuration = 2.0,
  offhandSwingTime = 0,
  offhandSwingDuration = 2.0,
  sunderOnceByGuid = {},
}

-- Reset combat-related states when leaving combat
function Shalamayne_State.ResetCombat()
  Shalamayne_State.overpowerUntil = 0
  Shalamayne_State.mainhandSwingTime = 0
  Shalamayne_State.offhandSwingTime = 0
  Shalamayne_State.sunderOnceByGuid = {}
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

function Shalamayne_Action.DecideArms(L, now)
  now = now or GetTime()

  if not Shalamayne_Conditions.TargetExists() then
    Shalamayne_Conditions.AutoTargetMelee()
  end

  local rage = Shalamayne_Conditions.PlayerRage()
  local stance = Shalamayne_Conditions.GetStance()
  local inMelee = Shalamayne_Conditions.InMeleeRange(L)
  local hpPct = Shalamayne_Conditions.TargetHealthPct()
  local hpAbs = Shalamayne_Conditions.TargetHealth()
  local enemyCount, lowHpEnemies = Shalamayne_Conditions.GetEnemiesInfoInRange()
  local sunderHp = (Shalamayne_Settings and Shalamayne_Settings.sunderArmorHp) or 1000
  local finisherHp = (Shalamayne_Settings and Shalamayne_Settings.finisherExecuteHp) or 50000
  local slamThreshold = (Shalamayne_Settings and Shalamayne_Settings.slamSwingThreshold) or 0.5

  if not (PlayerFrame and PlayerFrame.inCombat) then
    AttackTarget()
  end

  local hasOp = Shalamayne_Conditions.HasOverpowerWindow(now)
  if stance ~= 3 and not ((hasOp and Shalamayne_Conditions.IsSpellReady(L.SPELL_OVERPOWER, now)) or (enemyCount >= 2 and Shalamayne_Conditions.IsSpellReady(L.SPELL_SWEEPING_STRIKES, now))) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE, now)
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  local function DoAOE()
    if enemyCount >= 2 and Shalamayne_Conditions.IsSpellReady(L.SPELL_EXECUTE, now) then
      local mhRem = Shalamayne_Conditions.MainhandSwingRemaining(now)
      if mhRem < 1.5 then
        local bestGuid = next(lowHpEnemies)
        if bestGuid then
          DebugHit("execute_other_target", L.SPELL_EXECUTE, now)
          local selfCast = GetCVar("autoSelfCast")
          if selfCast then
            SetCVar("autoSelfCast", "0")
          end

          local obj, oldTargetGUID = UnitExists("target")
          if bestGuid ~= "target" then
            TargetUnit(bestGuid)
          end

          if UnitIsVisible("target") then
            local spellId = GetSpellIdForName and GetSpellIdForName(L.SPELL_EXECUTE)
            if spellId and CastSpellNoQueue then
              pcall(CastSpellNoQueue, spellId, 0, bestGuid)
            else
              QueueOrCast(L.SPELL_EXECUTE)
            end
          end

          if bestGuid ~= "target" then
            if obj then
              TargetUnit(oldTargetGUID)
            else
              ClearTarget()
            end
          end

          if selfCast then
            SetCVar("autoSelfCast", selfCast)
          end
          return
        end
      end
    end
    if enemyCount >= 2 and Shalamayne_Conditions.IsSpellReady(L.SPELL_SWEEPING_STRIKES, now) then
      local sweepRageGate = (stance ~= 3) or (rage < 50)
      if sweepRageGate then
        if stance ~= 1 then
          DebugHit("stance_for_sweeping", L.SPELL_BATTLE_STANCE, now)
          QueueOrCast(L.SPELL_BATTLE_STANCE)
          return
        end
        DebugHit("sweeping_strikes", L.SPELL_SWEEPING_STRIKES, now)
        QueueOrCast(L.SPELL_SWEEPING_STRIKES)
        return
      end
    end

    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Shalamayne_Conditions.IsSpellReady(L.SPELL_SUNDER_ARMOR, now) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if enemyCount >= 2 and Shalamayne_Conditions.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and Shalamayne_Conditions.IsSpellReady(L.SPELL_CLEAVE, now) and not Shalamayne_Conditions.IsSpellQueued(L.SPELL_CLEAVE) then
      DebugHit("cleave", L.SPELL_CLEAVE, now)
      QueueOrCast(L.SPELL_CLEAVE)
      return
    end

    if Shalamayne_Conditions.IsSpellReady(L.SPELL_MORTAL_STRIKE, now) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE, now)
      QueueOrCast(L.SPELL_MORTAL_STRIKE)
      return
    end

    if inMelee and Shalamayne_Conditions.IsSpellReady(L.SPELL_SLAM, now) then
      local mhRem = Shalamayne_Conditions.MainhandSwingRemaining(now)
      local mhDur = Shalamayne_State.mainhandSwingDuration or 2.0
      if mhDur > 0 and (mhRem / mhDur) >= slamThreshold then
        DebugHit("slam", L.SPELL_SLAM, now)
        QueueOrCast(L.SPELL_SLAM)
        return
      end
    end

    DebugHit("no_action", nil, now)
  end

  local function DoSingle()
    if inMelee and hpPct < 20 and hpAbs > 0 and hpAbs < finisherHp and Shalamayne_Conditions.IsSpellReady(L.SPELL_EXECUTE, now) then
      DebugHit("finisher_execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Shalamayne_Conditions.IsSpellReady(L.SPELL_SUNDER_ARMOR, now) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if inMelee and hasOp then
      if stance ~= 1 and rage < 40 then
        DebugHit("stance_for_overpower", L.SPELL_BATTLE_STANCE, now)
        QueueOrCast(L.SPELL_BATTLE_STANCE)
        return
      end
      if stance == 1 and Shalamayne_Conditions.IsSpellReady(L.SPELL_OVERPOWER, now) then
        DebugHit("overpower", L.SPELL_OVERPOWER, now)
        QueueOrCast(L.SPELL_OVERPOWER)
        return
      end
    end

    if Shalamayne_Conditions.IsSpellReady(L.SPELL_MORTAL_STRIKE, now) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE, now)
      QueueOrCast(L.SPELL_MORTAL_STRIKE)
      return
    end

    if Shalamayne_Conditions.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and hpPct > 0 and hpPct < 20 and Shalamayne_Conditions.IsSpellReady(L.SPELL_EXECUTE, now) then
      DebugHit("execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and rage > 60 and Shalamayne_Conditions.IsSpellReady(L.SPELL_HEROIC_STRIKE, now) and not Shalamayne_Conditions.IsSpellQueued(L.SPELL_HEROIC_STRIKE) then
      DebugHit("heroic_strike", L.SPELL_HEROIC_STRIKE, now)
      QueueOrCast(L.SPELL_HEROIC_STRIKE)
      return
    end

    if inMelee and Shalamayne_Conditions.IsSpellReady(L.SPELL_SLAM, now) then
      local mhRem = Shalamayne_Conditions.MainhandSwingRemaining(now)
      local mhDur = Shalamayne_State.mainhandSwingDuration or 2.0
      if mhDur > 0 and (mhRem / mhDur) >= slamThreshold then
        DebugHit("slam", L.SPELL_SLAM, now)
        QueueOrCast(L.SPELL_SLAM)
        return
      end
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

function Shalamayne_Action.DecideFury(L, now)
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
  local enemyCount, lowHpEnemies = Shalamayne_Conditions.GetEnemiesInfoInRange()
  local sunderHp = (Shalamayne_Settings and Shalamayne_Settings.sunderArmorHp) or 1000
  local finisherHp = (Shalamayne_Settings and Shalamayne_Settings.finisherExecuteHp) or 50000

  local hasOp = Shalamayne_Conditions.HasOverpowerWindow(now)
  if stance ~= 3 and not (hasOp and Shalamayne_Conditions.IsSpellReady(L.SPELL_OVERPOWER, now)) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE, now)
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  local function DoAOE()
    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Shalamayne_Conditions.IsSpellReady(L.SPELL_SUNDER_ARMOR, now) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if Shalamayne_Conditions.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and Shalamayne_Conditions.IsSpellReady(L.SPELL_CLEAVE, now) and not Shalamayne_Conditions.IsSpellQueued(L.SPELL_CLEAVE) then
      if stance == 2 then
        DebugHit("stance_for_cleave", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("cleave", L.SPELL_CLEAVE, now)
      QueueOrCast(L.SPELL_CLEAVE)
      return
    end

    if Shalamayne_Conditions.IsSpellReady(L.SPELL_BLOODTHIRST, now) then
      DebugHit("bloodthirst", L.SPELL_BLOODTHIRST, now)
      QueueOrCast(L.SPELL_BLOODTHIRST)
      return
    end
  end

  local function DoSingle()
    if inMelee and hpAbs > 0 and hpAbs < finisherHp and Shalamayne_Conditions.IsSpellReady(L.SPELL_EXECUTE, now) then
      if SpellStopCasting then
        SpellStopCasting()
      end
      DebugHit("finisher_execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and hpAbs > sunderHp and Shalamayne_Conditions.TargetSunderArmorStacks() < 5 and Shalamayne_Conditions.IsSpellReady(L.SPELL_SUNDER_ARMOR, now) then
      local _, guid = UnitExists("target")
      if not (guid and Shalamayne_State.sunderOnceByGuid and Shalamayne_State.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

    if inMelee and hasOp then
      local opRageGate = (stance ~= 3) or (rage < 40)
      if opRageGate then
        if stance ~= 1 then
          DebugHit("stance_for_overpower", L.SPELL_BATTLE_STANCE, now)
          QueueOrCast(L.SPELL_BATTLE_STANCE)
          return
        end
        if Shalamayne_Conditions.IsSpellReady(L.SPELL_OVERPOWER, now) then
          DebugHit("overpower", L.SPELL_OVERPOWER, now)
          QueueOrCast(L.SPELL_OVERPOWER)
          return
        end
      end
    end

    if Shalamayne_Conditions.IsSpellReady(L.SPELL_BLOODTHIRST, now) then
      DebugHit("bloodthirst", L.SPELL_BLOODTHIRST, now)
      QueueOrCast(L.SPELL_BLOODTHIRST)
      return
    end

    if Shalamayne_Conditions.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and hpPct > 0 and hpPct < 20 and Shalamayne_Conditions.IsSpellReady(L.SPELL_EXECUTE, now) then
      if stance ~= 3 then
        DebugHit("stance_for_execute", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and Shalamayne_Conditions.IsSpellReady(L.SPELL_HEROIC_STRIKE, now) and not Shalamayne_Conditions.IsSpellQueued(L.SPELL_HEROIC_STRIKE) then
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
