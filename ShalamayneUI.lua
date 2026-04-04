-- Shalamayne Configuration UI Module
Shalamayne = Shalamayne or {}
Shalamayne.configFrame = nil

-- Helper function to create a labeled checkbox
local function CreateCheckbox(parent, label, x, y)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if cb.text then
    cb.text:SetText(label)
  else
    local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb.text = t
  end
  return cb
end

-- Helper function to create a standard button
local function CreateButton(parent, text, x, y, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetWidth(w or 90)
  b:SetHeight(22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(text)
  return b
end

-- Initialize and create the configuration frame (lazy loading)
local function CreateFrameOnce(L)
  if Shalamayne.configFrame then return end

  local f = CreateFrame("Frame", "Shalamayne_ConfigFrame", UIParent)
  f:SetWidth(360)
  f:SetHeight(284)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
  title:SetText(L.UI_CONFIG_TITLE)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

  local cbEnabled = CreateCheckbox(f, L.UI_ENABLED, 16, -40)
  local cbDebug = CreateCheckbox(f, L.UI_SHOW_DEBUG, 16, -62)

  local specLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  specLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -92)
  specLabel:SetText(L.UI_SPEC .. ":")

  local btnArms = CreateButton(f, L.UI_ARMS, 70, -96, 90)
  local btnFury = CreateButton(f, L.UI_FURY, 170, -96, 90)

  local hsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hsLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -130)
  hsLabel:SetText(L.UI_HS_RAGE)
  local hsBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  hsBox:SetAutoFocus(false)
  hsBox:SetWidth(40)
  hsBox:SetHeight(18)
  hsBox:SetPoint("TOPLEFT", f, "TOPLEFT", 150, -128)
  hsBox:SetNumeric(true)

  local aoeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  aoeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -154)
  aoeLabel:SetText(L.UI_AOE_ENEMIES)
  local aoeBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  aoeBox:SetAutoFocus(false)
  aoeBox:SetWidth(40)
  aoeBox:SetHeight(18)
  aoeBox:SetPoint("TOPLEFT", f, "TOPLEFT", 150, -152)
  aoeBox:SetNumeric(true)

  local sunderLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sunderLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -178)
  sunderLabel:SetText(L.UI_SUNDER_HP)
  local sunderBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  sunderBox:SetAutoFocus(false)
  sunderBox:SetWidth(40)
  sunderBox:SetHeight(18)
  sunderBox:SetPoint("TOPLEFT", f, "TOPLEFT", 150, -176)
  sunderBox:SetNumeric(true)

  local finLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  finLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -202)
  finLabel:SetText(L.UI_FINISHER_EXECUTE_HP)
  local finBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  finBox:SetAutoFocus(false)
  finBox:SetWidth(60)
  finBox:SetHeight(18)
  finBox:SetPoint("TOPLEFT", f, "TOPLEFT", 150, -200)
  finBox:SetNumeric(true)

  local slamLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  slamLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -226)
  slamLabel:SetText(L.UI_SLAM_SWING_PCT)
  local slamBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  slamBox:SetAutoFocus(false)
  slamBox:SetWidth(40)
  slamBox:SetHeight(18)
  slamBox:SetPoint("TOPLEFT", f, "TOPLEFT", 150, -224)
  slamBox:SetNumeric(false) -- Allow decimals

  local btnApply = CreateButton(f, "Apply", 240, -224, 90)

  -- Refresh UI elements to match current settings
  local function Refresh()
    cbEnabled:SetChecked(Shalamayne.enabled and 1 or 0)
    cbDebug:SetChecked(Shalamayne.debug and 1 or 0)
    hsBox:SetNumber(Shalamayne.heroicStrikeRage or 50)
    aoeBox:SetNumber(Shalamayne.aoeEnemies or 2)
    sunderBox:SetNumber(Shalamayne.sunderArmorHp or 1000)
    finBox:SetNumber(Shalamayne.finisherExecuteHp or 50000)
    slamBox:SetText(tostring(Shalamayne.slamSwingThreshold or 0.5))
  end

  cbEnabled:SetScript("OnClick", function() Shalamayne.enabled = cbEnabled:GetChecked() == 1 end)
  cbDebug:SetScript("OnClick", function()
    Shalamayne.debug = cbDebug:GetChecked() == 1
    if Shalamayne.debug then
      Shalamayne.ShowDebug(L)
    else
      Shalamayne.HideDebug()
    end
  end)

  btnArms:SetScript("OnClick", function() Shalamayne.spec = L.SPEC_ARMS_KEY end)
  btnFury:SetScript("OnClick", function() Shalamayne.spec = L.SPEC_FURY_KEY end)

  btnApply:SetScript("OnClick", function()
    Shalamayne.heroicStrikeRage = tonumber(hsBox:GetText()) or 50
    Shalamayne.aoeEnemies = tonumber(aoeBox:GetText()) or 2
    Shalamayne.sunderArmorHp = tonumber(sunderBox:GetText()) or 1000
    Shalamayne.finisherExecuteHp = tonumber(finBox:GetText()) or 50000
    Shalamayne.slamSwingThreshold = tonumber(slamBox:GetText()) or 0.5
    Refresh()
  end)

  f:SetScript("OnShow", Refresh)

  Shalamayne.configFrame = f
end

-- Show the configuration window
function Shalamayne.ShowConfig(L)
  CreateFrameOnce(L)
  if Shalamayne.configFrame then
    Shalamayne.configFrame:Show()
  end
end

-- Hide the configuration window
function Shalamayne.HideConfig()
  if Shalamayne.configFrame then
    Shalamayne.configFrame:Hide()
  end
end


-- Shalamayne Debug UI Module
Shalamayne = Shalamayne or {}
Shalamayne.debugFrame = nil
Shalamayne.lines = {}
Shalamayne.maxLines = 12

-- Initialize and create the debug frame (lazy loading)
local function CreateFrameOnceDebug(L)
  if Shalamayne.debugFrame then return end

  local f = CreateFrame("Frame", "Shalamayne_DebugFrame", UIParent)
  f:SetWidth(420)
  f:SetHeight(220)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
  title:SetText(L.UI_DEBUG_TITLE)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
  close:SetScript("OnClick", function()
    Shalamayne.debug = false
    Shalamayne.HideDebug()
  end)

  local content = {}
  for i = 1, Shalamayne.maxLines do
    local line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -18 - (i * 14))
    line:SetJustifyH("LEFT")
    line:SetText("")
    content[i] = line
  end

  Shalamayne.debugFrame = f
  Shalamayne.lines = content
end

-- Show the debug window
function Shalamayne.ShowDebug(L)
  CreateFrameOnceDebug(L)
  if Shalamayne.debugFrame then
    Shalamayne.debugFrame:Show()
  end
end

-- Hide the debug window
function Shalamayne.HideDebug()
  if not Shalamayne.debugFrame then return end
  Shalamayne.debugFrame:Hide()
end

-- Check if the debug window is currently visible
function Shalamayne.IsShown()
  return Shalamayne.debugFrame and Shalamayne.debugFrame:IsShown()
end

-- Push a new line of text to the debug window (shifts older lines up)
function Shalamayne.PushLine(text)
  if not (Shalamayne and Shalamayne.debug) then return end
  if not Shalamayne.debugFrame then return end

  local lines = Shalamayne.lines
  for i = Shalamayne.maxLines, 2, -1 do
    lines[i]:SetText(lines[i - 1]:GetText() or "")
  end
  lines[1]:SetText(text)
end


-- Shalamayne Minimap Button Module
Shalamayne = Shalamayne or {}
Shalamayne.button = nil

local atan2f = math.atan2 or atan2
local degf = math.deg or function(r) return r * 180 / math.pi end

-- Create or return the existing minimap button
local function GetOrCreateButton(L)
  if Shalamayne.button then return Shalamayne.button end

  local b = CreateFrame("Button", "ShalamayneButton", Minimap)
  b:SetWidth(32)
  b:SetHeight(32)
  b:SetFrameStrata("MEDIUM")
  b:SetMovable(true)
  b:EnableMouse(true)
  b:RegisterForDrag("LeftButton")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.bg:SetAllPoints(b)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture("Interface\\Icons\\Ability_Warrior_OffensiveStance")
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.icon:SetWidth(18)
  b.icon:SetHeight(18)

  b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
  b.highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b.highlight:SetBlendMode("ADD")
  b.highlight:SetAllPoints(b)

  -- Update button position based on the saved angle
  local function UpdatePosition()
    local angle = (Shalamayne.minimapAngle or 0) * (math.pi / 180)
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end

  -- Calculate the angle from the cursor to the minimap center and save it
  local function SetAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetScale()
    cx, cy = cx / scale, cy / scale

    local angle = degf(atan2f(cy - my, cx - mx))
    if angle < 0 then angle = angle + 360 end
    Shalamayne.minimapAngle = angle
    UpdatePosition()
  end

  b:SetScript("OnDragStart", function() b.isDragging = true end)
  b:SetScript("OnDragStop", function() b.isDragging = false end)
  b:SetScript("OnUpdate", function()
    if b.isDragging then
      SetAngleFromCursor()
    end
  end)

  b:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      Shalamayne.ShowConfig(L)
    else
      Shalamayne_ToggleEnabled()
    end
  end)

  b.UpdatePosition = UpdatePosition
  Shalamayne.button = b
  UpdatePosition()

  return b
end

-- Refresh the minimap button visibility and position
function Shalamayne.Refresh(L)
  local show = true
  if Shalamayne and Shalamayne.showMinimap ~= nil then
    show = Shalamayne.showMinimap
  end
  local b = GetOrCreateButton(L)
  if show then
    b:Show()
    b:UpdatePosition()
  else
    b:Hide()
  end
end
