if not Shalamayne then Shalamayne = {} end

Shalamayne.inCombat = false
Shalamayne.isAutoAttacking = false
Shalamayne.overpowerUntil = 0
Shalamayne.overpowerTargetGuid = nil
Shalamayne.sunderOnceByGuid = {}
Shalamayne.queuedHeroicStrike = false
Shalamayne.queuedHeroicStrikeTime = nil
Shalamayne.queuedCleave = false
Shalamayne.queuedCleaveTime = nil

-- Reset combat-related states when leaving combat
function Shalamayne.ResetCombat()
  Shalamayne.inCombat = false
  Shalamayne.isAutoAttacking = false
  Shalamayne.overpowerUntil = 0
  Shalamayne.overpowerTargetGuid = nil
  Shalamayne.sunderOnceByGuid = {}
  Shalamayne.queuedHeroicStrike = false
  Shalamayne.queuedHeroicStrikeTime = nil
  Shalamayne.queuedCleave = false
  Shalamayne.queuedCleaveTime = nil
end

Shalamayne.costSunderArmor = 10
Shalamayne.costWhirlwind = 25
Shalamayne.costHeroicStrike = 15
Shalamayne.costCleave = 15
Shalamayne.costExecute = 15
Shalamayne.costSweepingStrikes = 20

local function StartAttack()
  if not UnitExists("target") or UnitIsDeadOrGhost("target") or not UnitCanAttack("player", "target") then
    return
  end

  if not Shalamayne.isAutoAttacking then
    AttackTarget()
    Shalamayne.isAutoAttacking = true
  end
end

-- QueueSpellByName (Nampower) provides reliable spell queuing.
-- If it's not available, fall back to CastSpellByName.
local function QueueOrCast(spellName)
  print(spellName)
  if QueueSpellByName then
    QueueSpellByName(spellName)
    return
  end
  CastSpellByName(spellName)
end

local function DebugHit(reason, spellName, now)
  if not Shalamayne.debug then return end

  local stanceNow = Shalamayne.GetStance()
  local rageNow = Shalamayne.PlayerRage()
  local hpAbsNow = Shalamayne.TargetHealth()
  local hpPctNow = Shalamayne.TargetHealthPct()
  local enemyCountNow = Shalamayne.GetEnemiesInfoInRange()
  local opRem = 0
  if now and Shalamayne.overpowerUntil and Shalamayne.overpowerUntil > now then
    opRem = Shalamayne.overpowerUntil - now
  end
  local targetName = (UnitExists("target") and UnitName("target")) or "-"
  local spellText = spellName or "-"
  Shalamayne.PushLine(string.format("ARMS|%s|%s|stance=%d rage=%d hp=%d(%.1f%%) enemies=%d op=%.1fs target=%s",
    reason or "-", spellText, stanceNow, rageNow, hpAbsNow, hpPctNow, enemyCountNow, opRem, targetName))
end

function Shalamayne.DecideArms(L, now)
  now = now or GetTime()

  if not Shalamayne.TargetExists() then
    Shalamayne.AutoTargetMelee()
  end

  local rage = Shalamayne.PlayerRage()
  local stance = Shalamayne.GetStance()
  local inMelee = Shalamayne.InMeleeRange(L)
  local hpPct = Shalamayne.TargetHealthPct()
  local hpAbs = Shalamayne.TargetHealth()
  local enemyCount, lowHpEnemies = Shalamayne.GetEnemiesInfoInRange()
  local sunderHp = Shalamayne.sunderArmorHp or 1000
  local finisherHp = Shalamayne.finisherExecuteHp or 50000
  local slamThreshold = Shalamayne.slamSwingThreshold or 0.5
  local hasOp = Shalamayne.HasOverpowerWindow(now)

  StartAttack()

  if Shalamayne.inCombat and not Shalamayne.PlayerHasBuff("ability_warrior_battleshout") and rage >= 10 then
    QueueOrCast(L.SPELL_BATTLE_SHOUT)
    return
  end

  if stance ~= 3 and rage < 50 and not ((hasOp and Shalamayne.IsSpellReady(L.SPELL_OVERPOWER, now)) or (enemyCount >= 2 and Shalamayne.IsSpellReady(L.SPELL_SWEEPING_STRIKES, now))) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE, now)
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  if inMelee and rage >= Shalamayne.costSunderArmor and hpAbs > sunderHp and Shalamayne.TargetHasDebuff("ability_warrior_sunder", L.SPELL_SUNDER_ARMOR) < 5 then
    local guid = Shalamayne.GetTargetGuid()
    if not (guid and Shalamayne.sunderOnceByGuid and Shalamayne.sunderOnceByGuid[guid]) then
      DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
      QueueOrCast(L.SPELL_SUNDER_ARMOR)
      return
    end
  end

  local function DoAOE()
    if range >= Shalamayne.costSweepingStrikes and Shalamayne.IsSpellReady(L.SPELL_SWEEPING_STRIKES, now) then
      if stance ~= 1 and rage < 50 then
        DebugHit("stance_for_sweeping", L.SPELL_BATTLE_STANCE, now)
        QueueOrCast(L.SPELL_BATTLE_STANCE)
      end
      DebugHit("sweeping_strikes", L.SPELL_SWEEPING_STRIKES, now)
      QueueOrCast(L.SPELL_SWEEPING_STRIKES)
      return
    end

    if Shalamayne.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and rage >= 20 and Shalamayne.IsSpellReady(L.SPELL_MORTAL_STRIKE, now) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE, now)
      QueueOrCast(L.SPELL_MORTAL_STRIKE)
      return
    end

    if Shalamayne.IsSpellReady(L.SPELL_EXECUTE, now) then
      if st_timer < 1.5 then
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

    if rage >= 50 and Shalamayne.IsSpellReady(L.SPELL_CLEAVE, now) and not Shalamayne.IsSpellQueued(L.SPELL_CLEAVE) then
      DebugHit("cleave", L.SPELL_CLEAVE, now)
      QueueOrCast(L.SPELL_CLEAVE)
      return
    end

    if inMelee and Shalamayne.IsSpellReady(L.SPELL_SLAM, now) then
      local mhRem = Shalamayne.MainhandSwingRemaining()
      if mhRem >= slamThreshold then
        DebugHit("slam", L.SPELL_SLAM, now)
        QueueOrCast(L.SPELL_SLAM)
        return
      end
    end

    DebugHit("no_action", nil, now)
  end

  local function DoSingle()
    if inMelee and rage >= Shalamayne.costExecute and hpPct <= 20 and hpAbs <= finisherHp then
      DebugHit("finisher_execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and hasOp then
      if stance ~= 1 and rage < 40 then
        DebugHit("stance_for_overpower", L.SPELL_BATTLE_STANCE, now)
        QueueOrCast(L.SPELL_BATTLE_STANCE)
        return
      end
      if stance == 1 and Shalamayne.IsSpellReady(L.SPELL_OVERPOWER, now) then
        DebugHit("overpower", L.SPELL_OVERPOWER, now)
        QueueOrCast(L.SPELL_OVERPOWER)
        return
      end
    end

    if Shalamayne.IsSpellReady(L.SPELL_MORTAL_STRIKE, now) then
      DebugHit("mortal_strike", L.SPELL_MORTAL_STRIKE, now)
      QueueOrCast(L.SPELL_MORTAL_STRIKE)
      return
    end

    if Shalamayne.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and hpPct > 0 and hpPct < 20 and Shalamayne.IsSpellReady(L.SPELL_EXECUTE, now) then
      DebugHit("execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and rage > 60 and Shalamayne.IsSpellReady(L.SPELL_HEROIC_STRIKE, now) and not Shalamayne.IsSpellQueued(L.SPELL_HEROIC_STRIKE) then
      DebugHit("heroic_strike", L.SPELL_HEROIC_STRIKE, now)
      QueueOrCast(L.SPELL_HEROIC_STRIKE)
      return
    end

    if inMelee and Shalamayne.IsSpellReady(L.SPELL_SLAM, now) then
      local mhRem = Shalamayne.MainhandSwingRemaining()
      if mhRem >= slamThreshold then
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

function Shalamayne.DecideFury(L, now)
  now = now or GetTime()
  if not Shalamayne.inCombat then return end

  if not Shalamayne.TargetExists() then
    if not Shalamayne.AutoTargetMelee() then
      return
    end
  end

  StartAttack()

  local rage = Shalamayne.PlayerRage()
  local stance = Shalamayne.GetStance()
  local inMelee = Shalamayne.InMeleeRange(L)
  local hpPct = Shalamayne.TargetHealthPct()
  local hpAbs = Shalamayne.TargetHealth()
  local enemyCount, lowHpEnemies = Shalamayne.GetEnemiesInfoInRange()
  local sunderHp = Shalamayne.sunderArmorHp or 1000
  local finisherHp = Shalamayne.finisherExecuteHp or 50000

  if not Shalamayne.PlayerHasBuff("ability_warrior_battleshout") and rage >= 10 then
    DebugHit("battle_shout", L.SPELL_BATTLE_SHOUT, now)
    QueueOrCast(L.SPELL_BATTLE_SHOUT)
    return
  end

  local hasOp = Shalamayne.HasOverpowerWindow(now)
  if stance ~= 3 and not (hasOp and Shalamayne.IsSpellReady(L.SPELL_OVERPOWER, now)) then
    DebugHit("stance_berseker_default", L.SPELL_BERSERKER_STANCE, now)
    QueueOrCast(L.SPELL_BERSERKER_STANCE)
    return
  end

  if inMelee and hpAbs > sunderHp and Shalamayne.TargetHasDebuff("ability_warrior_sunder", L.SPELL_SUNDER_ARMOR) < 5 and Shalamayne.IsSpellReady(L.SPELL_SUNDER_ARMOR, now) then
      local guid = Shalamayne.GetTargetGuid()
      if not (guid and Shalamayne.sunderOnceByGuid and Shalamayne.sunderOnceByGuid[guid]) then
        DebugHit("sunder_once", L.SPELL_SUNDER_ARMOR, now)
        QueueOrCast(L.SPELL_SUNDER_ARMOR)
        return
      end
    end

  local function DoAOE()
    if Shalamayne.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and Shalamayne.IsSpellReady(L.SPELL_CLEAVE, now) and not Shalamayne.IsSpellQueued(L.SPELL_CLEAVE) then
      if stance == 2 then
        DebugHit("stance_for_cleave", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("cleave", L.SPELL_CLEAVE, now)
      QueueOrCast(L.SPELL_CLEAVE)
      return
    end

    if Shalamayne.IsSpellReady(L.SPELL_BLOODTHIRST, now) then
      DebugHit("bloodthirst", L.SPELL_BLOODTHIRST, now)
      QueueOrCast(L.SPELL_BLOODTHIRST)
      return
    end
  end

  local function DoSingle()
    if inMelee and hpAbs > 0 and hpAbs < finisherHp and Shalamayne.IsSpellReady(L.SPELL_EXECUTE, now) then
      if SpellStopCasting then
        SpellStopCasting()
      end
      DebugHit("finisher_execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and hasOp then
      local opRageGate = (stance ~= 3) or (rage < 40)
      if opRageGate then
        if stance ~= 1 then
          DebugHit("stance_for_overpower", L.SPELL_BATTLE_STANCE, now)
          QueueOrCast(L.SPELL_BATTLE_STANCE)
          return
        end
        if Shalamayne.IsSpellReady(L.SPELL_OVERPOWER, now) then
          DebugHit("overpower", L.SPELL_OVERPOWER, now)
          QueueOrCast(L.SPELL_OVERPOWER)
          return
        end
      end
    end

    if Shalamayne.IsSpellReady(L.SPELL_BLOODTHIRST, now) then
      DebugHit("bloodthirst", L.SPELL_BLOODTHIRST, now)
      QueueOrCast(L.SPELL_BLOODTHIRST)
      return
    end

    if Shalamayne.IsSpellReady(L.SPELL_WHIRLWIND, now) then
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

    if inMelee and hpPct > 0 and hpPct < 20 and Shalamayne.IsSpellReady(L.SPELL_EXECUTE, now) then
      if stance ~= 3 then
        DebugHit("stance_for_execute", L.SPELL_BERSERKER_STANCE, now)
        QueueOrCast(L.SPELL_BERSERKER_STANCE)
        return
      end
      DebugHit("execute", L.SPELL_EXECUTE, now)
      QueueOrCast(L.SPELL_EXECUTE)
      return
    end

    if inMelee and Shalamayne.IsSpellReady(L.SPELL_HEROIC_STRIKE, now) and not Shalamayne.IsSpellQueued(L.SPELL_HEROIC_STRIKE) then
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
