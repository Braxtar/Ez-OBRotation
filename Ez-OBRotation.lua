----------------------------------------------------------------------
-- Ez-OBRotation - One Button Rotation Keybind Display
-- Shows keybinds on the assisted combat rotation button
-- Works with both Bartender4 and Blizzard default action bars
----------------------------------------------------------------------

local AddonName = "Ez-OBRotation"
local iconPath = "Interface\\AddOns\\Ez-OBRotation\\Ez OBRotation.png"

local fontBold = "Interface\\AddOns\\Ez-OBRotation\\Fonts\\Luciole-Bold.ttf"
local fontReg  = "Interface\\AddOns\\Ez-OBRotation\\Fonts\\Luciole-Regular.ttf"

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")

-- GLOBAL CATEGORY HOLDER
local settingsCategory = nil 

local usingBartender = false

local defaults = {
    fontSize = 24,
    fontPath = fontBold, 
    r = 1, g = 1, b = 1, 
    anchor = "TOPRIGHT",
    minimapPos = 45,
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

f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if not _G.EzOBR_Config then _G.EzOBR_Config = CopyTable(defaults) end
        if not _G.EzOBR_Config.anchor then _G.EzOBR_Config.anchor = "TOPRIGHT" end
        if not _G.EzOBR_Config.minimapPos then _G.EzOBR_Config.minimapPos = 45 end
        if not _G.EzOBR_Config.fontPath then _G.EzOBR_Config.fontPath = fontBold end

        usingBartender = C_AddOns.IsAddOnLoaded("Bartender4")
        
        self:CreateMenu()
        self:CreateMinimapButton()
        self:StartDetective()
        
        print("|cff00FF00Ez-OBRotation:|r Loaded with Luciole fonts.")
    end
end)

----------------------------------------------------------------------
-- 2. MINIMAP BUTTON
----------------------------------------------------------------------
function f:CreateMinimapButton()
    local btn = CreateFrame("Button", "EzOBR_MinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameLevel(8)
    
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    -- Use a reliable WoW icon - the custom icon path may not exist
    icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")

    local function UpdatePos()
        local angle = math.rad(EzOBR_Config.minimapPos)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
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
    
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button) 
        if not settingsCategory then 
            Settings.OpenToCategory("Ez-OBRotation") 
            return 
        end
        if SettingsPanel:IsShown() then
            SettingsPanel:Hide()
        else
            Settings.OpenToCategory(settingsCategory:GetID())
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

----------------------------------------------------------------------
-- 3. SETTINGS MENU
----------------------------------------------------------------------
function f:CreateMenu()
    local panel = CreateFrame("Frame", "EzOBR_OptionsPanel", UIParent)
    panel.name = "Ez-OBRotation"
    
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settingsCategory)

    local menuIcon = panel:CreateTexture(nil, "ARTWORK")
    menuIcon:SetSize(64, 64)
    menuIcon:SetPoint("TOPLEFT", 16, -10)
    menuIcon:SetTexture(iconPath)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", menuIcon, "RIGHT", 10, 0)
    title:SetText("Ez-OBRotation Settings")

    local modeText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    modeText:SetPoint("TOPLEFT", menuIcon, "BOTTOMLEFT", 0, -10)
    modeText:SetText(usingBartender and "|cff00FF00Mode: Bartender4 detected|r" or "|cff00FF00Mode: Blizzard Action Bars|r")

    local slider = CreateFrame("Slider", "EzOBR_SizeSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", modeText, "BOTTOMLEFT", 0, -40)
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

    -- COLOR PICKER
    local colorBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    colorBtn:SetPoint("LEFT", slider, "RIGHT", 40, 0)
    colorBtn:SetSize(100, 25)
    colorBtn:SetText("Text Color")
    local colorPreview = colorBtn:CreateTexture(nil, "BACKGROUND")
    colorPreview:SetSize(20, 20)
    colorPreview:SetPoint("RIGHT", colorBtn, "LEFT", -5, 0)
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

    -- DROPDOWN POSITION
    local dropLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -40)
    dropLabel:SetText("Position:")

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

    -- FONT BUTTONS
    local fontButtons = {
        {"Luciole Bold", fontBold},        
        {"Luciole Regular", fontReg},      
        {"Standard (Friz)", "Fonts\\FRIZQT__.TTF"}, 
        {"Combat (Skurri)", "Fonts\\SKURRI.TTF"},   
    }
    
    local lastBtn = nil
    for i, fontData in ipairs(fontButtons) do
        local btn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
        if i == 1 then
            btn:SetPoint("TOPLEFT", dropLabel, "BOTTOMLEFT", 0, -30)
        else
            btn:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -5)
        end
        btn:SetSize(160, 25)
        btn:SetText(fontData[1])
        
        local btnText = btn:GetFontString()
        if btnText then
            pcall(btnText.SetFont, btnText, fontData[2], 12) 
        end

        btn:SetScript("OnClick", function() 
            EzOBR_Config.fontPath = fontData[2]
            print("|cff00FF00Ez-OBRotation:|r Font changed to " .. fontData[1])
        end)
        lastBtn = btn
    end

    SLASH_EZOBR1 = "/ezobr"
    SlashCmdList["EZOBR"] = function() Settings.OpenToCategory(settingsCategory:GetID()) end
end

----------------------------------------------------------------------
-- 4. KEYBIND DETECTION LOGIC
----------------------------------------------------------------------
function f:StartDetective()
    
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

    local function FindKeyForSpell(spellID)
        if not spellID then return nil end
        local slots = C_ActionBar.FindSpellActionButtons(spellID)
        if slots then
            for _, slot in pairs(slots) do
                local command = GetBindCommand(slot)
                if command then
                    local key = GetBindingKey(command)
                    if key then return key end
                end
            end
        end
        return nil
    end

    local blizzardButtons = {}
    local function CacheBlizzardButtons()
        -- FIX: Added MultiBar7Button and MultiBar8Button for all action bars
        local barPrefixes = {
            "ActionButton", 
            "MultiBarBottomLeftButton", 
            "MultiBarBottomRightButton",
            "MultiBarRightButton", 
            "MultiBarLeftButton", 
            "MultiBar5Button",
            "MultiBar6Button", 
            "MultiBar7Button",  -- Added Bar 7
            "MultiBar8Button",  -- Added Bar 8
        }
        for _, prefix in ipairs(barPrefixes) do
            for i = 1, 12 do
                local btn = _G[prefix..i]
                if btn then blizzardButtons[#blizzardButtons + 1] = btn end
            end
        end
    end
    
    C_Timer.After(1, CacheBlizzardButtons)

    local function HasActiveGlow(btn)
        if btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame:IsShown() then return true end
        if btn.SpellActivationAlert and btn.SpellActivationAlert:IsShown() then return true end
        return false
    end

    local function FindBlizzardGlowButton()
        for _, btn in ipairs(blizzardButtons) do
            if HasActiveGlow(btn) then return btn end
        end
        return nil
    end

    local function FindBartenderGlowButton()
        for i = 1, 300 do
            local btn = _G["BT4Button"..i]
            if btn and btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame:IsShown() then return btn end
        end
        return nil
    end

    local function GetButtonActionSlot(btn)
        if not btn then return nil end
        local actionSlot = btn:GetAttribute("action")
        if actionSlot then return actionSlot end
        if btn.action then return btn.action end
        if btn.CalculateAction then return btn:CalculateAction() end
        return nil
    end

    -- Track which buttons we've hooked
    local hookedButtons = {}
    
    local function HideGlows(btn)
        if btn.SpellActivationAlert then 
            btn.SpellActivationAlert:SetAlpha(0) 
        end
        if btn.AssistedCombatRotationFrame then 
            -- Set alpha to 0
            btn.AssistedCombatRotationFrame:SetAlpha(0)
            
            -- Hook the frame to continuously enforce alpha=0 while our text is shown
            if not hookedButtons[btn] then
                hookedButtons[btn] = true
                
                -- Hook Show to immediately set alpha to 0
                if btn.AssistedCombatRotationFrame.Show then
                    hooksecurefunc(btn.AssistedCombatRotationFrame, "Show", function(self)
                        if btn.EzOBR_Text and btn.EzOBR_Text:IsShown() then
                            self:SetAlpha(0)
                        end
                    end)
                end
                
                -- Hook SetAlpha to prevent Blizzard from resetting it
                local origSetAlpha = btn.AssistedCombatRotationFrame.SetAlpha
                btn.AssistedCombatRotationFrame.SetAlpha = function(self, alpha)
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
        return key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a")
    end

    C_Timer.NewTicker(0.03, function()
        local currentButton = usingBartender and FindBartenderGlowButton() or FindBlizzardGlowButton()

        if lastActiveButton and lastActiveButton ~= currentButton then
            if lastActiveButton.EzOBR_Text then lastActiveButton.EzOBR_Text:Hide() end
            RestoreGlows(lastActiveButton)
            lastKeyText = nil
        end

        lastActiveButton = currentButton

        if not currentButton then return end

        local btn = currentButton
        
        -- Continuously enforce hiding - Blizzard may reset alpha every frame
        HideGlows(btn)

        if not btn.EzOBR_Text then
            btn.EzOBR_Text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.EzOBR_Text:SetDrawLayer("OVERLAY", 7)
        end
        
        local text = btn.EzOBR_Text
        text:Show()
        
        if not pcall(text.SetFont, text, EzOBR_Config.fontPath, EzOBR_Config.fontSize, "OUTLINE") then
            text:SetFont(fontBold, EzOBR_Config.fontSize, "OUTLINE")
        end
        text:SetTextColor(EzOBR_Config.r, EzOBR_Config.g, EzOBR_Config.b, 1)

        text:ClearAllPoints()
        local point = EzOBR_Config.anchor or "TOPRIGHT"
        local offsets = anchorOffsets[point] or anchorOffsets.TOPRIGHT
        text:SetPoint(point, btn, point, offsets[1], offsets[2])

        local actionSlot = GetButtonActionSlot(btn)
        local foundKey = nil
        
        if actionSlot then
            local actionType, id = GetActionInfo(actionSlot)
            if actionType == "spell" then
                foundKey = FindKeyForSpell(id)
            elseif actionType == "macro" then
                local spellID = GetMacroSpell(id)
                if spellID then foundKey = FindKeyForSpell(spellID) end
            end
        end

        local formattedKey = FormatKey(foundKey) or ""
        
        if formattedKey ~= lastKeyText then
            text:SetText(formattedKey)
            lastKeyText = formattedKey
        end
    end)
end
