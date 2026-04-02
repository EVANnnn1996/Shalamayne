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
  if not Shalamayne then Shalamayne = {} end
  if Shalamayne.enabled == nil then Shalamayne.enabled = true end
  if Shalamayne.spec == nil then Shalamayne.spec = L.SPEC_ARMS_KEY end
  if Shalamayne.debug == nil then Shalamayne.debug = false end
  if Shalamayne.showMinimap == nil then Shalamayne.showMinimap = true end
  if Shalamayne.minimapAngle == nil then Shalamayne.minimapAngle = 220 end

  if Shalamayne.heroicStrikeRage == nil then Shalamayne.heroicStrikeRage = 50 end
  if Shalamayne.aoeEnemies == nil then Shalamayne.aoeEnemies = 2 end
  if Shalamayne.sunderArmorHp == nil then Shalamayne.sunderArmorHp = 1000 end
  if Shalamayne.finisherExecuteHp == nil then Shalamayne.finisherExecuteHp = 50000 end
  if Shalamayne.slamSwingThreshold == nil then Shalamayne.slamSwingThreshold = 0.5 end
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
  Shalamayne.enabled = not Shalamayne.enabled
  Print((Shalamayne.enabled and L.STATUS_ENABLED) or L.STATUS_DISABLED)
end

-- Set the current specialization (Arms or Fury)
local function SetSpec(specKey)
  if specKey == L.SPEC_ARMS_KEY or specKey == L.SPEC_FURY_KEY then
    Shalamayne.spec = specKey
  end
end

-- Get a human-readable label for the current spec
local function SpecLabel()
  if Shalamayne.spec == L.SPEC_FURY_KEY then return L.SPEC_FURY end
  return L.SPEC_ARMS
end

-- Execute a single rotation cycle and take action
local function DecideAndAct(specOverride)
  if Shalamayne.disabled then
    PrintError(table.concat(Shalamayne.disabledErrors or { "disabled" }, " "))
    return
  end

  local now = GetTime()
  local spec = specOverride or Shalamayne.spec

  if spec == L.SPEC_FURY_KEY then
    Shalamayne.DecideFury(L, now)
  else
    Shalamayne.DecideArms(L, now)
  end
end

SLASH_SHALAMAYNE1 = "/shala"
SLASH_SHALAMAYNE2 = "/shalamayne"
SlashCmdList["SHALAMAYNE"] = function(msg)
  msg = msg or ""
  local _, _, cmd, rest = string.find(msg, "^(%S+)%s*(.*)$")

  if cmd == nil or cmd == "" then
    if Shalamayne.disabled then
      PrintError(table.concat(Shalamayne.disabledErrors or { "disabled" }, " "))
      return
    end
    Shalamayne.ShowConfig(L)
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
    Shalamayne.debug = not Shalamayne.debug
    if Shalamayne.debug then
      Shalamayne.ShowDebug(L)
      Print(L.STATUS_DEBUG .. ": on")
    else
      Shalamayne.HideDebug()
      Print(L.STATUS_DEBUG .. ": off")
    end
    return
  end
  if cmd == "config" then
    if Shalamayne.disabled then
      PrintError(table.concat(Shalamayne.disabledErrors or { "disabled" }, " "))
      return
    end
    Shalamayne.ShowConfig(L)
    return
  end
  if cmd == "minimap" then
    if not Shalamayne then Shalamayne = {} end
    Shalamayne.showMinimap = not Shalamayne.showMinimap
    if Shalamayne and Shalamayne.Refresh then
      Shalamayne.Refresh(L)
    end
    Print("Minimap: " .. tostring(Shalamayne.showMinimap))
    return
  end
  if cmd == "status" then
    Print(L.STATUS_SPEC .. ": " .. SpecLabel())
    Print(L.STATUS_ENABLED .. ": " .. tostring(Shalamayne.enabled))
    Print(L.STATUS_DEBUG .. ": " .. tostring(Shalamayne.debug))
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
frame:RegisterEvent("PLAYER_ENTER_COMBAT")
frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("UNIT_CASTEVENT")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

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
      local _, guid = UnitExists("target")
      Shalamayne.overpowerUntil = GetTime() + window
      Shalamayne.overpowerTargetGuid = guid
      if Shalamayne.debug then
        Shalamayne.PushLine("Overpower proc: " .. msg)
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
    Shalamayne.Scan()
    if Shalamayne and Shalamayne.RefreshWarriorState then
      Shalamayne.RefreshWarriorState(L)
    end

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

    if Shalamayne.debug then
      Shalamayne.ShowDebug(L)
    end

    Shalamayne.Refresh(L)

    Print(L.LOADED_OK)
    Print(L.CMD_HELP)
    return
  end

  if Shalamayne.disabled then return end

  if event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_REGEN_DISABLED" then
    Shalamayne.inCombat = true
    Shalamayne.Scan()
    return
  end

  if event == "PLAYER_LEAVE_COMBAT" or event == "PLAYER_REGEN_ENABLED" then
    Shalamayne.inCombat = false
    Shalamayne.ResetCombat()
    return
  end

  if event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
    if Shalamayne then
      Shalamayne.Scan()
    end
    if Shalamayne and Shalamayne.RefreshWarriorState then
      Shalamayne.RefreshWarriorState(L)
    end
    return
  end

  if event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
    if Shalamayne and Shalamayne.RefreshWarriorState then
      Shalamayne.RefreshWarriorState(L)
    end
    return
  end


  if event == "CHAT_MSG_COMBAT_SELF_MISSES" then
    local msg = arg1 or ""
    OnCombatLog(L, msg)
    return
  end

  if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    local msg = arg1 or ""
    if string.find(msg, "你的破甲") or string.find(msg, "by Sunder Armor") then
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
          if Shalamayne.sunderOnceByGuid then
            Shalamayne.sunderOnceByGuid[guid] = GetTime()
          end
        end
      end
    end
    return
  end

  if event == "UNIT_CASTEVENT" then
    if arg1 == "player" and arg2 == "START" and arg4 then
      if arg4 == L.SPELL_OVERPOWER then
        Shalamayne.overpowerUntil = 0
        Shalamayne.overpowerTargetGuid = nil
      elseif arg4 == 11597 then
        local _, guid = UnitExists("target")
        Shalamayne.sunderOnceByGuid[guid] = GetTime()
      end
    end
    return
  end
end)
