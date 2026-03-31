Shalamayne_Localization = {
  enUS = {
    ADDON_TITLE = "Shalamayne",
    LOADED_OK = "Loaded.",
    LOADED_DISABLED = "Loaded (disabled - missing requirements).",
    CMD_HELP = "Commands: /shala (run) | /shala arms | /shala fury | /shala toggle | /shala debug | /shala config | /shala minimap | /shala status",
    STATUS_ENABLED = "Enabled",
    STATUS_DISABLED = "Disabled",
    STATUS_SPEC = "Spec",
    STATUS_DEBUG = "Debug",
    STATUS_REQUIREMENTS = "Requirements",
    SPEC_ARMS = "Arms (2H)",
    SPEC_FURY = "Fury (DW)",
    SPEC_ARMS_KEY = "arms",
    SPEC_FURY_KEY = "fury",

    REQ_SUPERWOW_MISSING = "SuperWoW is required.",
    REQ_SUPERWOW_BADVER = "SuperWoW version is not supported (need 1.5+).",
    REQ_NAMPOWER_MISSING = "Nampower is required.",
    REQ_NAMPOWER_BADVER = "Nampower version is not supported (need %d.%d.%d+; you have %d.%d.%d).",
    REQ_UNITXP_MISSING = "UnitXP_SP3 is required.",
    REQ_UNITXP_BADVER = "UnitXP is missing required features (behind/distanceBetween/version).",

    UI_CONFIG_TITLE = "Shalamayne Config",
    UI_DEBUG_TITLE = "Shalamayne Debug",
    UI_CLOSE = "Close",
    UI_ENABLED = "Enabled",
    UI_SPEC = "Spec",
    UI_ARMS = "Arms",
    UI_FURY = "Fury",
    UI_SHOW_DEBUG = "Show debug",
    UI_HS_RAGE = "Heroic Strike rage >=",
    UI_AOE_ENEMIES = "AoE enemies >=",
    UI_SUNDER_HP = "Sunder Armor HP >",
    UI_FINISHER_EXECUTE_HP = "Finisher Execute HP <",

    SPELL_BATTLE_STANCE = "Battle Stance",
    SPELL_DEFENSIVE_STANCE = "Defensive Stance",
    SPELL_BERSERKER_STANCE = "Berserker Stance",
    STANCE_BATTLE_NAME = "Battle Stance",
    STANCE_DEFENSIVE_NAME = "Defensive Stance",
    STANCE_BERSERKER_NAME = "Berserker Stance",
    SPELL_OVERPOWER = "Overpower",
    SPELL_MORTAL_STRIKE = "Mortal Strike",
    SPELL_EXECUTE = "Execute",
    SPELL_SWEEPING_STRIKES = "Sweeping Strikes",
    SPELL_WHIRLWIND = "Whirlwind",
    SPELL_BLOODTHIRST = "Bloodthirst",
    SPELL_BLOODRAGE = "Bloodrage",
    SPELL_CLEAVE = "Cleave",
    SPELL_HEROIC_STRIKE = "Heroic Strike",
    SPELL_SUNDER_ARMOR = "Sunder Armor",
    SPELL_SLAM = "Slam",

    COMBATLOG_ENEMY_DODGE_PATTERNS = {
      "was dodged by",
    },
  },
  zhCN = {
    ADDON_TITLE = "乌龟服战士一键输出",
    LOADED_OK = "加载完成。",
    LOADED_DISABLED = "加载完成（已禁用：缺少依赖）。",
    CMD_HELP = "命令：/shala（执行）| /shala arms | /shala fury | /shala toggle | /shala debug | /shala config | /shala minimap | /shala status",
    STATUS_ENABLED = "启用",
    STATUS_DISABLED = "禁用",
    STATUS_SPEC = "专精",
    STATUS_DEBUG = "调试",
    STATUS_REQUIREMENTS = "依赖",
    SPEC_ARMS = "武器战（双手）",
    SPEC_FURY = "狂暴战（双持）",
    SPEC_ARMS_KEY = "arms",
    SPEC_FURY_KEY = "fury",

    REQ_SUPERWOW_MISSING = "需要安装 SuperWoW。",
    REQ_SUPERWOW_BADVER = "SuperWoW 版本不支持（需要 1.5+）。",
    REQ_NAMPOWER_MISSING = "需要安装 Nampower。",
    REQ_NAMPOWER_BADVER = "Nampower 版本不支持（需要 %d.%d.%d+；当前 %d.%d.%d）。",
    REQ_UNITXP_MISSING = "需要安装 UnitXP_SP3。",
    REQ_UNITXP_BADVER = "UnitXP 缺少必要功能（behind/distanceBetween/version）。",

    UI_CONFIG_TITLE = "Shalamayne 配置",
    UI_DEBUG_TITLE = "Shalamayne 调试",
    UI_CLOSE = "关闭",
    UI_ENABLED = "启用",
    UI_SPEC = "专精",
    UI_ARMS = "武器战",
    UI_FURY = "狂暴战",
    UI_SHOW_DEBUG = "显示调试",
    UI_HS_RAGE = "英勇打击怒气 >=",
    UI_AOE_ENEMIES = "AOE 敌人数量 >=",
    UI_SUNDER_HP = "破甲目标血量 >",
    UI_FINISHER_EXECUTE_HP = "收尾斩杀目标血量 <",

    SPELL_BATTLE_STANCE = "战斗姿态",
    SPELL_DEFENSIVE_STANCE = "防御姿态",
    SPELL_BERSERKER_STANCE = "狂暴姿态",
    STANCE_BATTLE_NAME = "战斗姿态",
    STANCE_DEFENSIVE_NAME = "防御姿态",
    STANCE_BERSERKER_NAME = "狂暴姿态",
    SPELL_OVERPOWER = "压制",
    SPELL_MORTAL_STRIKE = "致死打击",
    SPELL_EXECUTE = "斩杀",
    SPELL_SWEEPING_STRIKES = "横扫攻击",
    SPELL_WHIRLWIND = "旋风斩",
    SPELL_BLOODTHIRST = "嗜血",
    SPELL_BLOODRAGE = "血性狂暴",
    SPELL_CLEAVE = "顺劈斩",
    SPELL_HEROIC_STRIKE = "英勇打击",
    SPELL_SUNDER_ARMOR = "破甲攻击",
    SPELL_SLAM = "猛击",

    COMBATLOG_ENEMY_DODGE_PATTERNS = {
      "躲闪了",
      "被(.+)躲闪",
    },
  },
}

-- Get the current client locale (fallback to enUS)
function Shalamayne_GetLocale()
  local locale = GetLocale and GetLocale() or "enUS"
  if locale == "zhCN" then return "zhCN" end
  return "enUS"
end

-- Get the localized strings table for the current locale
function Shalamayne_GetL()
  local locale = Shalamayne_GetLocale()
  return Shalamayne_Localization[locale] or Shalamayne_Localization.enUS
end
