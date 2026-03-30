Shalamayne = Shalamayne or {}

local L = Shalamayne_GetL()

-- Print a standard message to the chat frame
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cFF4477FFShalamayne|r: " .. msg)
end

-- Print an error message to the chat frame
local function PrintError(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cFF4477FFShalamayne|r: |cFFFF3030" .. msg .. "|r")
end

-- Initialize default settings if they are missing
local function EnsureDefaults()
  if not Shalamayne_Settings then Shalamayne_Settings = {} end
  if Shalamayne_Settings.enabled == nil then Shalamayne_Settings.enabled = true end
  if Shalamayne_Settings.spec == nil then Shalamayne_Settings.spec = L.SPEC_ARMS_KEY end
  if Shalamayne_Settings.debug == nil then Shalamayne_Settings.debug = false end
  if Shalamayne_Settings.showMinimap == nil then Shalamayne_Settings.showMinimap = true end
  if Shalamayne_Settings.minimapAngle == nil then Shalamayne_Settings.minimapAngle = 220 end

  if Shalamayne_Settings.heroicStrikeRage == nil then Shalamayne_Settings.heroicStrikeRage = 50 end
  if Shalamayne_Settings.aoeEnemies == nil then Shalamayne_Settings.aoeEnemies = 2 end
  if Shalamayne_Settings.sunderArmorHp == nil then Shalamayne_Settings.sunderArmorHp = 1000 end
end

-- Compare version numbers
local function CompareVersion(major, minor, patch, reqMajor, reqMinor, reqPatch)
  if major ~= reqMajor then return major > reqMajor end
  if minor ~= reqMinor then return minor > reqMinor end
  return patch >= reqPatch
end

-- Parse version numbers from a string (e.g. "1.5.0")
local function ParseVersionFromString(s)
  if type(s) ~= "string" then return nil end
  local _, _, a, b, c = string.find(s, "(%d+)%.(%d+)%.?(%d*)")
  if not a or not b then return nil end
  a, b = tonumber(a) or 0, tonumber(b) or 0
  c = tonumber(c) or 0
  return a, b, c
end

-- Check if all required dependencies and their versions are met
local function CheckRequirements(L)
  local ok = true
  local errors = {}
  local caps = {}

  caps.hasSuperwow = SUPERWOW_STRING ~= nil
  caps.superwowVersion = SUPERWOW_VERSION
  caps.superwowString = SUPERWOW_STRING

  if not caps.hasSuperwow then
    ok = false
    table.insert(errors, L.REQ_SUPERWOW_MISSING)
  else
    local major, minor, patch = ParseVersionFromString(caps.superwowVersion) or ParseVersionFromString(caps.superwowString)
    local reqMajor, reqMinor, reqPatch = 1, 5, 0
    if not major or not CompareVersion(major, minor, patch, reqMajor, reqMinor, reqPatch) then
      ok = false
      table.insert(errors, L.REQ_SUPERWOW_BADVER)
    end
  end

  caps.hasNampower = (type(GetNampowerVersion) == "function") and (IsSpellInRange ~= nil)
  caps.nampowerMajor, caps.nampowerMinor, caps.nampowerPatch = 0, 0, 0
  if not caps.hasNampower then
    ok = false
    table.insert(errors, L.REQ_NAMPOWER_MISSING)
  else
    local major, minor, patch = GetNampowerVersion()
    major, minor, patch = major or 0, minor or 0, patch or 0
    caps.nampowerMajor, caps.nampowerMinor, caps.nampowerPatch = major, minor, patch
    local reqMajor, reqMinor, reqPatch = 3, 0, 0
    if not CompareVersion(major, minor, patch, reqMajor, reqMinor, reqPatch) then
      ok = false
      table.insert(errors, string.format(L.REQ_NAMPOWER_BADVER, reqMajor, reqMinor, reqPatch, major, minor, patch))
    end
  end

  caps.hasUnitXP = pcall(UnitXP, "nop", "nop")
  caps.unitxpCompileTime = nil
  caps.unitxpHasBehind = false
  caps.unitxpHasDistance = false
  caps.unitxpHasVersion = false
  if not caps.hasUnitXP then
    ok = false
    table.insert(errors, L.REQ_UNITXP_MISSING)
  else
    caps.unitxpHasBehind = pcall(UnitXP, "behind", "player", "target")
    caps.unitxpHasDistance = pcall(UnitXP, "distanceBetween", "player", "target")
    caps.unitxpHasVersion = pcall(UnitXP, "version", "coffTimeDateStamp")
    if caps.unitxpHasVersion then
      caps.unitxpCompileTime = UnitXP("version", "coffTimeDateStamp")
    end
    if not (caps.unitxpHasBehind and caps.unitxpHasDistance and caps.unitxpHasVersion) then
      ok = false
      table.insert(errors, L.REQ_UNITXP_BADVER)
    end
  end

  return ok, errors, caps
end

Shalamayne.disabled = false
Shalamayne.disabledErrors = nil
Shalamayne.caps = nil

-- Toggle the enabled state of the addon
function Shalamayne_ToggleEnabled()
  if Shalamayne.disabled then
    PrintError(table.concat(Shalamayne.disabledErrors or { "disabled" }, " "))
    return
  end
  Shalamayne_Settings.enabled = not Shalamayne_Settings.enabled
  Print((Shalamayne_Settings.enabled and L.STATUS_ENABLED) or L.STATUS_DISABLED)
end

-- Set the current specialization (Arms or Fury)
local function SetSpec(specKey)
  if specKey == L.SPEC_ARMS_KEY or specKey == L.SPEC_FURY_KEY then
    Shalamayne_Settings.spec = specKey
  end
end

-- Get a human-readable label for the current spec
local function SpecLabel()
  if Shalamayne_Settings.spec == L.SPEC_FURY_KEY then return L.SPEC_FURY end
  return L.SPEC_ARMS
end

-- Execute a single rotation cycle and take action
local function DecideAndAct(specOverride)
  if Shalamayne.disabled then
    PrintError(table.concat(Shalamayne.disabledErrors or { "disabled" }, " "))
    return
  end

  local now = GetTime()
  local spec = specOverride or Shalamayne_Settings.spec

  Shalamayne_Action.Decide(L, now, spec)
end

SLASH_SHALAMAYNE1 = "/shala"
SLASH_SHALAMAYNE2 = "/shalamayne"
SlashCmdList["SHALAMAYNE"] = function(msg)
  msg = msg or ""
  local _, _, cmd, rest = string.find(msg, "^(%S+)%s*(.*)$")

  if cmd == nil or cmd == "" then
    DecideAndAct(nil)
    return
  end

  cmd = string.lower(cmd)

  if cmd == "arms" then
    DecideAndAct(L.SPEC_ARMS_KEY)
    return
  end
  if cmd == "fury" then
    DecideAndAct(L.SPEC_FURY_KEY)
    return
  end
  if cmd == "spec" then
    rest = string.lower(rest or "")
    if rest == "arms" then SetSpec(L.SPEC_ARMS_KEY) end
    if rest == "fury" then SetSpec(L.SPEC_FURY_KEY) end
    Print(L.STATUS_SPEC .. ": " .. SpecLabel())
    return
  end
  if cmd == "toggle" then
    Shalamayne_ToggleEnabled()
    return
  end
  if cmd == "debug" then
    if Shalamayne.disabled then
      PrintError(table.concat(Shalamayne.disabledErrors or { "disabled" }, " "))
      return
    end
    Shalamayne_Settings.debug = not Shalamayne_Settings.debug
    if Shalamayne_Settings.debug then
      Shalamayne_DebugUI.Show(L)
      Print(L.STATUS_DEBUG .. ": on")
    else
      Shalamayne_DebugUI.Hide()
      Print(L.STATUS_DEBUG .. ": off")
    end
    return
  end
  if cmd == "config" then
    if Shalamayne.disabled then
      PrintError(table.concat(Shalamayne.disabledErrors or { "disabled" }, " "))
      return
    end
    Shalamayne_ConfigUI.Show(L)
    return
  end
  if cmd == "minimap" then
    if not Shalamayne_Settings then Shalamayne_Settings = {} end
    if Shalamayne_Settings.showMinimap == nil then
      Shalamayne_Settings.showMinimap = false
    else
      Shalamayne_Settings.showMinimap = not Shalamayne_Settings.showMinimap
    end
    if Shalamayne_Minimap and Shalamayne_Minimap.Refresh then
      Shalamayne_Minimap.Refresh(L)
    end
    Print("Minimap: " .. tostring(Shalamayne_Settings.showMinimap))
    return
  end
  if cmd == "status" then
    Print(L.STATUS_SPEC .. ": " .. SpecLabel())
    Print(L.STATUS_ENABLED .. ": " .. tostring(Shalamayne_Settings.enabled))
    Print(L.STATUS_DEBUG .. ": " .. tostring(Shalamayne_Settings.debug))
    if Shalamayne.caps then
      local u = Shalamayne.caps.unitxpCompileTime
      local ud = u and date("%Y-%m-%d", u) or "?"
      Print(L.STATUS_REQUIREMENTS .. ": superwow=" .. tostring(Shalamayne.caps.hasSuperwow) .. " nampower=" ..
        string.format("%d.%d.%d", Shalamayne.caps.nampowerMajor or 0, Shalamayne.caps.nampowerMinor or 0, Shalamayne.caps.nampowerPatch or 0) ..
        " unitxp=" .. tostring(ud))
    end
    return
  end

  Print(L.CMD_HELP)
end

local frame = CreateFrame("Frame", "Shalamayne_Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("RAW_COMBATLOG")
frame:RegisterEvent("UNIT_CASTEVENT")
frame:RegisterEvent("AUTO_ATTACK_SELF")
frame:RegisterEvent("SPELL_GO_SELF")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
frame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
frame:RegisterEvent("BUFF_ADDED_SELF")
frame:RegisterEvent("BUFF_REMOVED_SELF")

local Swing = {}
Swing.HITINFO_LEFTSWING = 4
Swing.HITINFO_NOACTION = 65536

Swing.hsSpellIDs = {[78]=true, [284]=true, [285]=true, [1608]=true, [11564]=true, [11565]=true, [11566]=true, [11567]=true, [25286]=true}
Swing.cleaveSpellIDs = {[845]=true, [7369]=true, [11608]=true, [11609]=true, [20569]=true}
Swing.slamSpellIDs = {[1464]=true, [8820]=true, [11604]=true, [11605]=true, [25241]=true}

function Swing.UpdateDurations(keepProgress)
  local now = GetTime()
  local speedMH, speedOH = UnitAttackSpeed("player")

  if speedMH and speedMH > 0 then
    if keepProgress and Shalamayne_State.mainhandSwingDuration and Shalamayne_State.mainhandSwingDuration > 0 then
      local old = Shalamayne_State.mainhandSwingDuration
      local elapsed = now - (Shalamayne_State.mainhandSwingTime or now)
      local pct = elapsed / old
      if pct < 0 then pct = 0 end
      if pct > 1 then pct = 1 end
      Shalamayne_State.mainhandSwingDuration = speedMH
      Shalamayne_State.mainhandSwingTime = now - (pct * speedMH)
    else
      Shalamayne_State.mainhandSwingDuration = speedMH
    end
  end

  if speedOH and speedOH > 0 then
    if keepProgress and Shalamayne_State.offhandSwingDuration and Shalamayne_State.offhandSwingDuration > 0 then
      local old = Shalamayne_State.offhandSwingDuration
      local elapsed = now - (Shalamayne_State.offhandSwingTime or now)
      local pct = elapsed / old
      if pct < 0 then pct = 0 end
      if pct > 1 then pct = 1 end
      Shalamayne_State.offhandSwingDuration = speedOH
      Shalamayne_State.offhandSwingTime = now - (pct * speedOH)
    else
      Shalamayne_State.offhandSwingDuration = speedOH
    end
  end
end

function Swing.ApplyParryHaste()
  local now = GetTime()

  local function ReduceTimer(swingTimeKey, durationKey)
    local swingTime = Shalamayne_State[swingTimeKey] or 0
    local duration = Shalamayne_State[durationKey] or 0
    if duration <= 0 then return end

    local elapsed = now - swingTime
    local remaining = duration - elapsed
    if remaining <= 0 then return end

    local minimum = duration * 0.20
    local reduct = duration * 0.40
    local newRemaining = remaining - reduct
    if newRemaining < minimum then
      newRemaining = minimum
    end

    Shalamayne_State[swingTimeKey] = now - (duration - newRemaining)
  end

  local mhRem = Shalamayne_Conditions and Shalamayne_Conditions.MainhandSwingRemaining and Shalamayne_Conditions.MainhandSwingRemaining(now) or 0
  local ohRem = Shalamayne_Conditions and Shalamayne_Conditions.OffhandSwingRemaining and Shalamayne_Conditions.OffhandSwingRemaining(now) or 0

  if ohRem > 0 and (mhRem == 0 or ohRem < mhRem) then
    ReduceTimer("offhandSwingTime", "offhandSwingDuration")
  else
    ReduceTimer("mainhandSwingTime", "mainhandSwingDuration")
  end
end

function Swing.IsParryHasteMessage(msg)
  if not msg then return false end
  if string.find(msg, " attacks%. You parry%.") then return true end
  if string.find(msg, " was parried%.") then return true end
  if string.find(msg, "攻击%. 你招架了") then return true end
  if string.find(msg, "被招架") then return true end
  return false
end

-- Handle combat log events (e.g., detecting dodges for Overpower)
local function OnCombatLog(L, msg)
  if not msg or msg == "" then return end

  local locale = (type(Shalamayne_GetLocale) == "function" and Shalamayne_GetLocale()) or "enUS"
  if locale == "enUS" then
    if not string.find(msg, "^Your") then
      return
    end
  end

  local patterns = L.COMBATLOG_ENEMY_DODGE_PATTERNS
  if not patterns then return end
  for _, p in ipairs(patterns) do
    if string.find(msg, p) then
      local window = 4.0
      Shalamayne_State.overpowerUntil = GetTime() + window
      if Shalamayne_Settings.debug then
        Shalamayne_DebugUI.PushLine("Overpower proc: " .. msg)
      end
      return
    end
  end
end

-- Main event handler
frame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 ~= "Shalamayne" then return end

    EnsureDefaults()
    Shalamayne_Spellbook.Scan()

    local ok, errors, caps = CheckRequirements(L)
    Shalamayne.caps = caps
    if not ok then
      Shalamayne.disabled = true
      Shalamayne.disabledErrors = errors
      for _, e in ipairs(errors) do
        PrintError(e)
      end
      Print(L.LOADED_DISABLED)
      Print(L.CMD_HELP)
      return
    end

    Shalamayne.disabled = false
    Shalamayne.disabledErrors = nil


    if SetCVar then
      SetCVar("NP_EnableAutoAttackEvents", "1")
      SetCVar("NP_EnableSpellGoEvents", "1")
    end

    Swing.UpdateDurations(false)
    if Shalamayne_Settings.debug then
      Shalamayne_DebugUI.Show(L)
    end


    Shalamayne_Minimap.Refresh(L)

    Print(L.LOADED_OK)
    Print(L.CMD_HELP)
    return
  end

  if Shalamayne.disabled then return end

  if event == "PLAYER_REGEN_DISABLED" then
    Shalamayne_State.inCombat = true
    Shalamayne_Spellbook.Scan()
    Shalamayne_State.knownSpells = {}
    Shalamayne_State.knownSpells[L.SPELL_OVERPOWER] = Shalamayne_Spellbook.GetSlot(L.SPELL_OVERPOWER) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_MORTAL_STRIKE] = Shalamayne_Spellbook.GetSlot(L.SPELL_MORTAL_STRIKE) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_SWEEPING_STRIKES] = Shalamayne_Spellbook.GetSlot(L.SPELL_SWEEPING_STRIKES) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_WHIRLWIND] = Shalamayne_Spellbook.GetSlot(L.SPELL_WHIRLWIND) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_BLOODRAGE] = Shalamayne_Spellbook.GetSlot(L.SPELL_BLOODRAGE) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_HEROIC_STRIKE] = Shalamayne_Spellbook.GetSlot(L.SPELL_HEROIC_STRIKE) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_EXECUTE] = Shalamayne_Spellbook.GetSlot(L.SPELL_EXECUTE) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_SUNDER_ARMOR] = Shalamayne_Spellbook.GetSlot(L.SPELL_SUNDER_ARMOR) ~= nil
    Shalamayne_State.knownSpells[L.SPELL_BLOODTHIRST] = Shalamayne_Spellbook.GetSlot(L.SPELL_BLOODTHIRST) ~= nil
    if not Shalamayne_State.mainhandSwingTime or Shalamayne_State.mainhandSwingTime == 0 then
      Shalamayne_State.mainhandSwingTime = GetTime()
      Swing.UpdateDurations(false)
    end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    Shalamayne_State.inCombat = false
    Shalamayne_State.ResetCombat()
    return
  end

  if event == "SPELLS_CHANGED" then
    Shalamayne_Spellbook.Scan()
    return
  end

  if event == "RAW_COMBATLOG" then
    OnCombatLog(L, arg1)
    return
  end

  if event == "AUTO_ATTACK_SELF" then
    -- SuperWoW's AUTO_ATTACK_SELF event passes the hitInfo bitfield in arg4.
    local hitInfo = arg4
    if not hitInfo then return end

    if math.mod(math.floor(hitInfo / Swing.HITINFO_NOACTION), 2) ~= 0 then
      return
    end

    local offhand = math.mod(math.floor(hitInfo / Swing.HITINFO_LEFTSWING), 2) ~= 0
    local speedMH, speedOH = UnitAttackSpeed("player")
    local now = GetTime()

    if offhand then
      Shalamayne_State.offhandSwingTime = now
      Shalamayne_State.offhandSwingDuration = speedOH or 2.0
    else
      Shalamayne_State.mainhandSwingTime = now
      Shalamayne_State.mainhandSwingDuration = speedMH or 2.0
    end
    return
  end

  if event == "SPELL_GO_SELF" then
    local spellId = arg2
    if not spellId then return end
    if Swing.hsSpellIDs[spellId] or Swing.cleaveSpellIDs[spellId] or Swing.slamSpellIDs[spellId] then
      local speedMH, _ = UnitAttackSpeed("player")
      Shalamayne_State.mainhandSwingTime = GetTime()
      Shalamayne_State.mainhandSwingDuration = speedMH or 2.0
    end
    return
  end

  if event == "UNIT_INVENTORY_CHANGED" then
    if arg1 == "player" then
      Swing.UpdateDurations(true)
    end
    return
  end

  if event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" or event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" or event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
    if Swing.IsParryHasteMessage(arg1) then
      Swing.ApplyParryHaste()
    end
    return
  end

  if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    local msg = arg1 or ""
    if string.find(msg, "你的破甲") or string.find(msg, "Your Sunder Armor") then
      local guid = nil
      local s, e = string.find(msg, "0x" .. string.rep("%x", 16))
      if s then
        guid = string.sub(msg, s, e)
      else
        _, guid = UnitExists("target")
      end
      if guid then
        if string.find(msg, "招架") or string.find(msg, "躲闪") or string.find(msg, "格挡") or string.find(msg, "没有击中") or string.find(msg, "免疫") or string.find(msg, "抵抗") or string.find(msg, "parried") or string.find(msg, "dodged") or string.find(msg, "blocked") or string.find(msg, "miss") or string.find(msg, "immune") or string.find(msg, "resist") then
        else
          if Shalamayne_State.sunderOnceByGuid then
            Shalamayne_State.sunderOnceByGuid[guid] = GetTime()
          end
        end
      end
    end
    return
  end

  if event == "BUFF_ADDED_SELF" or event == "BUFF_REMOVED_SELF" then
    local spellId = arg3
    if not spellId then return end
    local okName, name = pcall(GetSpellNameAndRankForId, spellId)
    if not okName or not name then return end
    if name == "Flurry" or name == "乱舞" then
      Swing.UpdateDurations(true)
    end
    return
  end

  if event == "UNIT_CASTEVENT" then
    if arg1 == "player" and arg2 == "START" and arg4 then
      Shalamayne_State.lastCastSpell = arg4
      Shalamayne_State.lastCastAt = GetTime()
      if arg4 == L.SPELL_OVERPOWER then
        Shalamayne_State.overpowerUntil = 0
      end
    end
    return
  end
end)
