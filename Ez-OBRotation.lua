local AddonName = "Ez-OBRotation"
local fontBold = "Interface\\AddOns\\Ez-OBRotation\\Fonts\\Luciole-Bold.ttf"
local fontReg = "Interface\\AddOns\\Ez-OBRotation\\Fonts\\Luciole-Regular.ttf"
local fontFallback = "Fonts\\FRIZQT__.TTF"

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

local hotkeyCache = {}
local cacheValid = false

local function ValidateFont(fontPath)
    local testString = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local success = pcall(testString.SetFont, testString, fontPath, 12, "OUTLINE")
    testString:Hide()
    testString:SetParent(nil)
    return success
end

local defaults = {
    fontSize = 24,
    fontPath = fontFallback,
    r = 1, g = 1, b = 1,
    anchor = "TOPRIGHT",
    minimapPos = 220,
}

local anchorMap = {
    ["Top Left"] = "TOPLEFT",
    ["Top Right"] = "TOPRIGHT",
    ["Bottom Left"] = "BOTTOMLEFT",
    ["Bottom Right"] = "BOTTOMRIGHT",
    ["Centered"] = "CENTER"
}
local reverseAnchorMap = {}
for k, v in pairs(anchorMap) do reverseAnchorMap[v] = k end

local anchorOffsets = {
    TOPRIGHT = {-2, -2},
    TOPLEFT = {2, -2},
    BOTTOMRIGHT = {-2, 2},
    BOTTOMLEFT = {2, 2},
    CENTER = {0, 0}
}

local function InvalidateHotkeyCache()
    wipe(hotkeyCache)
    cacheValid = false
end

local function GetBindCommand(slot)
    if not slot then return nil end
    if slot <= 12 then return "ACTIONBUTTON"..slot end
    if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON"..(slot-60) end
    if slot >= 49 and slot <= 60 then return "MULTIACTIONBAR2BUTTON"..(slot-48) end
    if slot >= 25 and slot <= 36 then return "MULTIACTIONBAR3BUTTON"..(slot-24) end
    if slot >= 37 and slot <= 48 then return "MULTIACTIONBAR4BUTTON"..(slot-36) end
    if slot >= 73 and slot <= 84 then return "MULTIACTIONBAR5BUTTON"..(slot-72) end
    if slot >= 85 and slot <= 96 then return "MULTIACTIONBAR6BUTTON"..(slot-84) end
    if slot >= 97 and slot <= 108 then return "MULTIACTIONBAR7BUTTON"..(slot-96) end
    if slot >= 109 and slot <= 120 then return "MULTIACTIONBAR8BUTTON"..(slot-108) end
    return nil
end

local function BuildHotkeyCache()
    if cacheValid then return end
    wipe(hotkeyCache)
    
    for slot = 1, 180 do
        if HasAction(slot) then
            local actionType, actionID = GetActionInfo(slot)
            local command = GetBindCommand(slot)
            local key = command and GetBindingKey(command)
            
            if key and key ~= "" then
                if actionType == "spell" and actionID then
                    if not hotkeyCache[actionID] then
                        hotkeyCache[actionID] = key
                    end
                end
            end
        end
    end
    cacheValid = true
end

local function FindKeyForSpell(spellID)
    if not spellID then return nil end
    
    BuildHotkeyCache()
    if hotkeyCache[spellID] then
        return hotkeyCache[spellID]
    end
    
    local slots = C_ActionBar.FindSpellActionButtons(spellID)
    if slots then
        for _, slot in pairs(slots) do
            local command = GetBindCommand(slot)
            if command then
                local key = GetBindingKey(command)
                if key then
                    hotkeyCache[spellID] = key
                    return key
                end
            end
        end
    end
    
    local spellName = C_Spell.GetSpellName(spellID)
    if spellName then
        local lowerName = spellName:lower()
        for slot = 1, 180 do
            if HasAction(slot) then
                local actionType, actionID = GetActionInfo(slot)
                if actionType == "macro" and actionID then
                    local _, _, body = GetMacroInfo(actionID)
                    if body and body:lower():find(lowerName, 1, true) then
                        local command = GetBindCommand(slot)
                        if command then
                            local key = GetBindingKey(command)
                            if key then
                                hotkeyCache[spellID] = key
                                return key
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

local function GetCurrentSuggestedSpell()
    if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
        local spells = C_AssistedCombat.GetRotationSpells()
        if spells and spells[1] then
            return spells[1]
        end
    end
    return nil
end

f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if not _G.EzOBR_Config then _G.EzOBR_Config = CopyTable(defaults) end
        if not _G.EzOBR_Config.anchor then _G.EzOBR_Config.anchor = "TOPRIGHT" end
        if not _G.EzOBR_Config.minimapPos then _G.EzOBR_Config.minimapPos = 220 end
        if not _G.EzOBR_Config.fontPath then _G.EzOBR_Config.fontPath = fontFallback end
        
        local customFontsAvailable = ValidateFont(fontBold) and ValidateFont(fontReg)
        if not customFontsAvailable then
            print("|cffFFFF00Ez-OBRotation:|r Custom fonts not found. If on Mac, check:")
            print("  - Folder is named exactly: Ez-OBRotation")
            print("  - Subfolder is named exactly: Fonts")
            print("  - Files are: Luciole-Bold.ttf, Luciole-Regular.ttf")
            _G.EzOBR_Config.fontPath = fontFallback
        end
        
        if not ValidateFont(_G.EzOBR_Config.fontPath) then
            _G.EzOBR_Config.fontPath = fontFallback
        end
        
        self:CreateMenu()
        self:CreateMinimapButton()
        self:StartDetective()
        
        print("|cff00FF00Ez-OBRotation:|r Loaded!")
    elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
        InvalidateHotkeyCache()
    end
end)

function f:CreateMinimapButton()
    local btn = CreateFrame("Button", "EzOBR_MinimapButton", Minimap)
    btn:SetSize(33, 33)
    btn:SetFrameLevel(8)
    btn:SetFrameStrata("MEDIUM")
    
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(56, 56)
    border:SetPoint("TOPLEFT")
    
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function UpdatePos()
        local angle = math.rad(EzOBR_Config.minimapPos)
        local radius = (Minimap:GetWidth() / 2) + 5
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self) self:LockHighlight() self.isDragging = true end)
    btn:SetScript("OnDragStop", function(self) self:UnlockHighlight() self.isDragging = false end)
    btn:SetScript("OnUpdate", function(self)
        if self.isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            EzOBR_Config.minimapPos = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            UpdatePos()
        end
    end)
    
    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", function()
        local panel = _G["EzOBR_OptionsPanel"]
        if panel then
            if panel:IsShown() then
                panel:Hide()
            else
                panel:ClearAllPoints()
                panel:SetPoint("CENTER")
                panel:Show()
            end
        end
    end)
    
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ez-OBRotation")
        GameTooltip:AddLine("Left-click to toggle settings", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePos()
end

function f:CreateMenu()
    local panel = CreateFrame("Frame", "EzOBR_OptionsPanel", UIParent, "BackdropTemplate")
    panel.name = "Ez-OBRotation"
    panel:SetSize(400, 420)
    panel:SetPoint("CENTER")
    panel:Hide()
    panel:SetFrameStrata("DIALOG")
    
    table.insert(UISpecialFrames, "EzOBR_OptionsPanel")
    
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 1)
    
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Ez-OBRotation Settings")

    local slider = CreateFrame("Slider", "EzOBR_SizeSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOP", title, "BOTTOM", 0, -40)
    slider:SetWidth(200)
    slider:SetMinMaxValues(10, 50)
    slider:SetValue(EzOBR_Config.fontSize)
    slider:SetValueStep(1)
    _G[slider:GetName() .. 'Low']:SetText("10")
    _G[slider:GetName() .. 'High']:SetText("50")
    _G[slider:GetName() .. 'Text']:SetText("Font Size: " .. EzOBR_Config.fontSize)
    
    slider:SetScript("OnValueChanged", function(self, value)
        EzOBR_Config.fontSize = math.floor(value)
        _G[self:GetName() .. 'Text']:SetText("Font Size: " .. EzOBR_Config.fontSize)
    end)

    local colorBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    colorBtn:SetPoint("TOP", slider, "BOTTOM", 0, -25)
    colorBtn:SetSize(120, 25)
    colorBtn:SetText("Text Color")
    
    local colorPreview = panel:CreateTexture(nil, "ARTWORK")
    colorPreview:SetSize(20, 20)
    colorPreview:SetPoint("LEFT", colorBtn, "RIGHT", 10, 0)
    colorPreview:SetColorTexture(EzOBR_Config.r, EzOBR_Config.g, EzOBR_Config.b)

    colorBtn:SetScript("OnClick", function()
        local function OnColorSelect()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            EzOBR_Config.r, EzOBR_Config.g, EzOBR_Config.b = r, g, b
            colorPreview:SetColorTexture(r, g, b)
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = EzOBR_Config.r, g = EzOBR_Config.g, b = EzOBR_Config.b,
            swatchFunc = OnColorSelect,
        })
    end)

    local dropLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropLabel:SetPoint("TOP", colorBtn, "BOTTOM", -40, -20)
    dropLabel:SetText("Text Position:")

    local drop = CreateFrame("Frame", "EzOBR_PosDropdown", panel, "UIDropDownMenuTemplate")
    drop:SetPoint("LEFT", dropLabel, "RIGHT", -10, -2)
    local function InitDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for k, v in pairs(anchorMap) do
            info.text = k
            info.func = function()
                EzOBR_Config.anchor = v
                UIDropDownMenu_SetText(drop, k)
            end
            info.checked = (EzOBR_Config.anchor == v)
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(drop, InitDropdown)
    UIDropDownMenu_SetWidth(drop, 100)
    UIDropDownMenu_SetText(drop, reverseAnchorMap[EzOBR_Config.anchor] or "Top Right")

    local fontLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOP", dropLabel, "BOTTOM", 40, -30)
    fontLabel:SetText("Font Style:")
    
    local fontButtons = {
        {"Luciole Bold", fontBold},
        {"Luciole Regular", fontReg},
        {"Standard (Friz)", "Fonts\\FRIZQT__.TTF"},
        {"Combat (Skurri)", "Fonts\\SKURRI.TTF"},
    }
    
    local lastFontBtn = nil
    for i, fontData in ipairs(fontButtons) do
        local fbtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        if i == 1 then
            fbtn:SetPoint("TOP", fontLabel, "BOTTOM", 0, -5)
        else
            fbtn:SetPoint("TOP", lastFontBtn, "BOTTOM", 0, -3)
        end
        fbtn:SetSize(140, 22)
        fbtn:SetText(fontData[1])
        
        fbtn:SetScript("OnClick", function()
            if ValidateFont(fontData[2]) then
                EzOBR_Config.fontPath = fontData[2]
                print("|cff00FF00Ez-OBRotation:|r Font changed to " .. fontData[1])
            else
                print("|cffFF0000Ez-OBRotation:|r Font not available: " .. fontData[1])
            end
        end)
        lastFontBtn = fbtn
    end

    SLASH_EZOBR1 = "/ezobr"
    SlashCmdList["EZOBR"] = function()
        if panel:IsShown() then
            panel:Hide()
        else
            panel:Show()
        end
    end
end

function f:StartDetective()
    local function IsSBAButton(btn)
        if not btn then return false end
        if not btn:IsVisible() then return false end
        if btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame:IsShown() then
            return true
        end
        return false
    end

    local function FindSBAButton()
        local barPrefixes = {
            "ActionButton",
            "MultiBarBottomLeftButton",
            "MultiBarBottomRightButton",
            "MultiBarRightButton",
            "MultiBarLeftButton",
            "MultiBar5Button",
            "MultiBar6Button",
            "MultiBar7Button",
            "MultiBar8Button",
        }
        for _, prefix in ipairs(barPrefixes) do
            for i = 1, 12 do
                local btn = _G[prefix..i]
                if btn and IsSBAButton(btn) then
                    return btn
                end
            end
        end
        for i = 1, 180 do
            local btn = _G["BT4Button"..i]
            if btn and IsSBAButton(btn) then
                return btn
            end
        end
        return nil
    end

    local hookedButtons = {}
    
    local function HideGlows(btn)
        if btn.SpellActivationAlert then
            btn.SpellActivationAlert:SetAlpha(0)
        end
        if btn.AssistedCombatRotationFrame then
            btn.AssistedCombatRotationFrame:SetAlpha(0)
            
            if not hookedButtons[btn] then
                hookedButtons[btn] = true
                local frame = btn.AssistedCombatRotationFrame
                hooksecurefunc(frame, "Show", function(self)
                    if btn.EzOBR_Text and btn.EzOBR_Text:IsShown() then
                        self:SetAlpha(0)
                    end
                end)
                local origSetAlpha = frame.SetAlpha
                frame.SetAlpha = function(self, alpha)
                    if btn.EzOBR_Text and btn.EzOBR_Text:IsShown() then
                        origSetAlpha(self, 0)
                    else
                        origSetAlpha(self, alpha)
                    end
                end
            end
        end
    end

    local function RestoreGlows(btn)
        if btn.SpellActivationAlert then
            btn.SpellActivationAlert:SetAlpha(1)
        end
        if btn.AssistedCombatRotationFrame then
            btn.AssistedCombatRotationFrame:SetAlpha(1)
        end
    end

    local lastActiveButton = nil
    local lastKeyText = nil
    
    local function FormatKey(key)
        if not key then return nil end
        return key
            :gsub("SHIFT%-", "S")
            :gsub("CTRL%-", "C")
            :gsub("ALT%-", "A")
            :gsub("NUMPAD", "N")
            :gsub("MOUSEWHEELDOWN", "WD")
            :gsub("MOUSEWHEELUP", "WU")
            :gsub("BUTTON(%d+)", "M%1")
    end

    C_Timer.NewTicker(0.03, function()
        local sbaButton = FindSBAButton()

        if lastActiveButton and lastActiveButton ~= sbaButton then
            if lastActiveButton.EzOBR_Text then
                lastActiveButton.EzOBR_Text:Hide()
            end
            RestoreGlows(lastActiveButton)
            lastKeyText = nil
        end

        lastActiveButton = sbaButton

        if not sbaButton then return end

        HideGlows(sbaButton)

        if not sbaButton.EzOBR_Text then
            sbaButton.EzOBR_Text = sbaButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            sbaButton.EzOBR_Text:SetDrawLayer("OVERLAY", 7)
        end
        
        local text = sbaButton.EzOBR_Text
        text:Show()
        
        if not pcall(text.SetFont, text, EzOBR_Config.fontPath, EzOBR_Config.fontSize, "OUTLINE") then
            text:SetFont(fontFallback, EzOBR_Config.fontSize, "OUTLINE")
        end
        text:SetTextColor(EzOBR_Config.r, EzOBR_Config.g, EzOBR_Config.b, 1)

        text:ClearAllPoints()
        local point = EzOBR_Config.anchor or "TOPRIGHT"
        local offsets = anchorOffsets[point] or anchorOffsets.TOPRIGHT
        text:SetPoint(point, sbaButton, point, offsets[1], offsets[2])

        local spellID = nil
        
        if sbaButton.action then
            local actionType, id = GetActionInfo(sbaButton.action)
            if actionType == "spell" then
                spellID = id
            elseif actionType == "macro" then
                spellID = GetMacroSpell(id)
            end
        end
        
        if not spellID and sbaButton._state_action then
            local actionType, id = GetActionInfo(sbaButton._state_action)
            if actionType == "spell" then
                spellID = id
            elseif actionType == "macro" then
                spellID = GetMacroSpell(id)
            end
        end
        
        if not spellID and sbaButton.GetAttribute then
            local actionSlot = sbaButton:GetAttribute("action")
            if actionSlot and actionSlot > 0 then
                local actionType, id = GetActionInfo(actionSlot)
                if actionType == "spell" then
                    spellID = id
                elseif actionType == "macro" then
                    spellID = GetMacroSpell(id)
                end
            end
        end
        
        if not spellID then
            spellID = GetCurrentSuggestedSpell()
        end
        
        local foundKey = FindKeyForSpell(spellID)
        local formattedKey = FormatKey(foundKey) or ""
        
        if formattedKey ~= lastKeyText then
            text:SetText(formattedKey)
            lastKeyText = formattedKey
        end
    end)
end
