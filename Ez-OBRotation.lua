----------------------------------------------------------------------
-- Ez-OBRotation - MIDNIGHT BETA (V12 - OPTIMIZED)
-- Features: V5 Hybrid Logic + UI Restoration + Performance Optimizations
-- Changes: Cached Button List, Pre-calculated Commands
----------------------------------------------------------------------

local AddonName = "Ez-OBRotation"
-- Exact icon path based on your files
local iconPath = "Interface\\AddOns\\Ez-OBRotation\\Ez-OBRotation.jpg"

local fontBold = "Interface\\AddOns\\Ez-OBRotation\\Fonts\\Luciole-Bold.ttf"
local fontReg  = "Interface\\AddOns\\Ez-OBRotation\\Fonts\\Luciole-Regular.ttf"

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")

-- GLOBAL VARIABLES
local settingsCategory = nil 
local usingBartender = false
local buttonCache = {} -- Optimization: Cache buttons to avoid rebuilding table every 0.1s

local defaults = {
    fontSize = 24,       -- Keybind Text Size
    stackFontSize = 14,  -- Stack Count Text Size
    fontPath = fontBold, 
    r = 1, g = 1, b = 1, 
    anchor = "TOPRIGHT",
    minimapPos = 45,
}

local anchorOffsets = {
    TOPRIGHT = {-2, -2},
    TOPLEFT = {2, -2},
    BOTTOMRIGHT = {-2, 2},
    BOTTOMLEFT = {2, 2},
    CENTER = {0, 0}
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

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if not _G.EzOBR_Config then _G.EzOBR_Config = CopyTable(defaults) end
        for k,v in pairs(defaults) do
            if _G.EzOBR_Config[k] == nil then _G.EzOBR_Config[k] = v end
        end

        usingBartender = C_AddOns.IsAddOnLoaded("Bartender4")
        
        -- Build the cache of buttons once on login
        self:BuildButtonCache()

        self:CreateMenu()
        self:CreateMinimapButton()
        self:StartTracker()
        
        print("|cff00FF00Ez-OBRotation:|r V12 Loaded (English & Optimized).")
    end
end)

----------------------------------------------------------------------
-- LOGIC HELPERS
----------------------------------------------------------------------

-- Optimization: Determine the binding command ONCE per button, not every frame
local function DetermineButtonCommand(btn)
    local name = btn:GetName()
    if not name then return nil end

    local id = tonumber(name:match("Button(%d+)")) or btn:GetID()
    
    if name:find("MultiBar6Button") then return "MULTIACTIONBAR6BUTTON"..id 
    elseif name:find("MultiBar7Button") then return "MULTIACTIONBAR7BUTTON"..id 
    elseif name:find("MultiBar5Button") then return "MULTIACTIONBAR5BUTTON"..id 
    elseif name:find("MultiBarBottomRight") then return "MULTIACTIONBAR2BUTTON"..id
    elseif name:find("MultiBarBottomLeft") then return "MULTIACTIONBAR1BUTTON"..id
    elseif name:find("MultiBarRight") then return "MULTIACTIONBAR3BUTTON"..id
    elseif name:find("MultiBarLeft") then return "MULTIACTIONBAR4BUTTON"..id
    elseif name:find("ActionButton") then return "ACTIONBUTTON"..id
    -- Bartender fallback (often mapped to clicks, handled via Spell Lookup mostly)
    elseif name:find("BT4Button") then return "CLICK "..name..":LeftButton"
    end
    return nil
end

-- Reverse lookup: Slot ID to Command
local function GetCommandForSlot(slot)
    if not slot then return nil end
    if slot <= 12 then return "ACTIONBUTTON"..slot end
    if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON"..(slot-60) end
    if slot >= 49 and slot <= 60 then return "MULTIACTIONBAR2BUTTON"..(slot-48) end
    if slot >= 25 and slot <= 36 then return "MULTIACTIONBAR3BUTTON"..(slot-24) end
    if slot >= 37 and slot <= 48 then return "MULTIACTIONBAR4BUTTON"..(slot-36) end
    if slot >= 145 and slot <= 156 then return "MULTIACTIONBAR5BUTTON"..(slot-144) end
    if slot >= 157 and slot <= 168 then return "MULTIACTIONBAR6BUTTON"..(slot-156) end
    if slot >= 169 and slot <= 180 then return "MULTIACTIONBAR7BUTTON"..(slot-168) end
    return nil
end

local function FormatKey(key)
    if not key then return nil end
    key = key:upper()
    key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a")
    key = key:gsub("MOUSE WHEEL UP", "MWU"):gsub("MOUSE WHEEL DOWN", "MWD")
    key = key:gsub("MOUSE BUTTON", "M"):gsub("BUTTON", "M")
    key = key:gsub("NUM PAD", "N")
    return key
end

----------------------------------------------------------------------
-- OPTIMIZATION: CACHE BUILDER
----------------------------------------------------------------------
function f:BuildButtonCache()
    buttonCache = {}
    
    local function AddButtons(prefix, count)
        for i = 1, count do
            local btn = _G[prefix..i]
            if btn then
                -- Pre-calculate the command to avoid string parsing every frame
                btn.ezCommand = DetermineButtonCommand(btn)
                table.insert(buttonCache, btn)
            end
        end
    end

    -- Add Standard Blizzard Bars
    AddButtons("MultiBar6Button", 12)
    AddButtons("MultiBar7Button", 12)
    AddButtons("MultiBar5Button", 12)
    AddButtons("ActionButton", 12)
    AddButtons("MultiBarBottomRightButton", 12)
    AddButtons("MultiBarBottomLeftButton", 12)
    AddButtons("MultiBarRightButton", 12)
    AddButtons("MultiBarLeftButton", 12)

    -- Add Bartender Bars
    if usingBartender then
        AddButtons("BT4Button", 120)
    end
end

----------------------------------------------------------------------
-- CORE TRACKER (MAIN LOOP)
----------------------------------------------------------------------
function f:StartTracker()
    local lastButton = nil
    
    -- High frequency ticker (0.1s)
    C_Timer.NewTicker(0.1, function()
        
        -- 1. FIND ACTIVE BUTTON (Scanning the cache)
        local activeBtn = nil
        
        for _, btn in ipairs(buttonCache) do
            local hasArrow = false
            
            -- Check for the specific Assisted Combat Frame
            if btn.AssistedCombatRotationFrame and btn.AssistedCombatRotationFrame:IsShown() then
                hasArrow = true
                btn.AssistedCombatRotationFrame:SetAlpha(0) -- Hide arrow
            -- Check for standard proc glow
            elseif btn.SpellActivationAlert and btn.SpellActivationAlert:IsShown() then
                hasArrow = true
            end

            if hasArrow then
                activeBtn = btn
                break 
            end
        end

        -- CLEANUP PREVIOUS BUTTON
        if lastButton and lastButton ~= activeBtn then
            if lastButton.EzOBR_Text then lastButton.EzOBR_Text:Hide() end
            -- Restore original HotKey when not active
            if lastButton.HotKey then lastButton.HotKey:SetAlpha(1) end
        end
        lastButton = activeBtn

        if not activeBtn then return end

        -- 2. VISUAL CLEANUP (CLEAN UI)
        
        -- Hide Original HotKey (Fixes "White Dot" issue)
        if activeBtn.HotKey then
            activeBtn.HotKey:SetAlpha(0)
        end

        -- Resize Stack Count
        local countFrame = activeBtn.Count or _G[activeBtn:GetName().."Count"]
        if countFrame then
            local currentFont, _, _ = countFrame:GetFont()
            countFrame:SetFont(currentFont, EzOBR_Config.stackFontSize, "OUTLINE")
        end

        -- 3. DETERMINE KEYBIND
        local finalKey = nil
        
        -- Method A: Use Pre-calculated Command (Fastest)
        if activeBtn.ezCommand then
            local key = GetBindingKey(activeBtn.ezCommand)
            if key and key ~= "" then finalKey = key end
        end

        -- Method B: Spell Lookup (Hybrid Fallback)
        -- If button has no key, find where the recommended spell lives
        if not finalKey and C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
            local spellID = C_AssistedCombat.GetNextCastSpell()
            if spellID and spellID > 0 then
                local slots = C_ActionBar.FindSpellActionButtons(spellID)
                if slots then
                    for _, slot in pairs(slots) do
                        local command = GetCommandForSlot(slot)
                        if command then
                            local key = GetBindingKey(command)
                            if key and key ~= "" then
                                finalKey = key
                                break 
                            end
                        end
                    end
                end
            end
        end

        -- 4. RENDER TEXT
        if not activeBtn.EzOBR_Text then
            activeBtn.EzOBR_Text = activeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            activeBtn.EzOBR_Text:SetDrawLayer("OVERLAY", 7)
        end
        
        local text = activeBtn.EzOBR_Text
        text:Show()
        
        -- Apply Font
        if not pcall(text.SetFont, text, EzOBR_Config.fontPath, EzOBR_Config.fontSize, "OUTLINE") then
            text:SetFont("Fonts\\FRIZQT__.TTF", EzOBR_Config.fontSize, "OUTLINE")
        end
        text:SetTextColor(EzOBR_Config.r, EzOBR_Config.g, EzOBR_Config.b, 1)

        -- Apply Position
        text:ClearAllPoints()
        local point = EzOBR_Config.anchor or "TOPRIGHT"
        local offsets = anchorOffsets[point] or anchorOffsets.TOPRIGHT
        text:SetPoint(point, activeBtn, point, offsets[1], offsets[2])
        
        local displayText = FormatKey(finalKey) or ""
        text:SetText(displayText)
    end)
end

----------------------------------------------------------------------
-- UI: MINIMAP BUTTON
----------------------------------------------------------------------
function f:CreateMinimapButton()
    local btn = CreateFrame("Button", "EzOBR_MinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetSize(32, 32)
    btn:SetFrameLevel(8)
    
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(iconPath) 
    icon:SetSize(32, 32)
    icon:SetPoint("CENTER")
    
    -- Circular Mask
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mask:SetSize(30, 30)
    mask:SetPoint("CENTER")
    icon:AddMaskTexture(mask)
    
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local function UpdatePos()
        local angle = math.rad(EzOBR_Config.minimapPos)
        local r = 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
    end
    
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self) self:LockHighlight() self.isDragging = true end)
    btn:SetScript("OnDragStop", function(self) self:UnlockHighlight() self.isDragging = false end)
    btn:SetScript("OnUpdate", function(self)
        if self.isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local dx = (cx / scale) - mx
            local dy = (cy / scale) - my
            EzOBR_Config.minimapPos = math.deg(math.atan2(dy, dx))
            UpdatePos()
        end
    end)
    
    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", function() 
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
        GameTooltip:AddLine("Left-Click: Options", 1, 1, 1)
        GameTooltip:AddLine("Right-Click + Drag: Move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePos()
end

----------------------------------------------------------------------
-- UI: OPTIONS MENU
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

    -- SLIDER 1: KEYBIND SIZE
    local sliderFont = CreateFrame("Slider", "EzOBR_SizeSlider", panel, "OptionsSliderTemplate")
    sliderFont:SetPoint("TOPLEFT", menuIcon, "BOTTOMLEFT", 0, -40)
    sliderFont:SetMinMaxValues(10, 50)
    sliderFont:SetValue(EzOBR_Config.fontSize)
    sliderFont:SetValueStep(1)
    _G[sliderFont:GetName() .. 'Low']:SetText("10")
    _G[sliderFont:GetName() .. 'High']:SetText("50")
    _G[sliderFont:GetName() .. 'Text']:SetText("Keybind Size: " .. EzOBR_Config.fontSize)
    
    sliderFont:SetScript("OnValueChanged", function(self, value)
        EzOBR_Config.fontSize = math.floor(value)
        _G[self:GetName() .. 'Text']:SetText("Keybind Size: " .. EzOBR_Config.fontSize)
    end)

    -- SLIDER 2: STACK SIZE
    local sliderStack = CreateFrame("Slider", "EzOBR_StackSizeSlider", panel, "OptionsSliderTemplate")
    sliderStack:SetPoint("TOPLEFT", sliderFont, "BOTTOMLEFT", 0, -40)
    sliderStack:SetMinMaxValues(8, 30)
    sliderStack:SetValue(EzOBR_Config.stackFontSize or 14)
    sliderStack:SetValueStep(1)
    _G[sliderStack:GetName() .. 'Low']:SetText("8")
    _G[sliderStack:GetName() .. 'High']:SetText("30")
    _G[sliderStack:GetName() .. 'Text']:SetText("Stack Size: " .. (EzOBR_Config.stackFontSize or 14))
    
    sliderStack:SetScript("OnValueChanged", function(self, value)
        EzOBR_Config.stackFontSize = math.floor(value)
        _G[self:GetName() .. 'Text']:SetText("Stack Size: " .. EzOBR_Config.stackFontSize)
    end)

    -- COLOR PICKER
    local colorBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    colorBtn:SetPoint("LEFT", sliderFont, "RIGHT", 40, 0)
    colorBtn:SetSize(120, 25)
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

    -- ANCHOR DROPDOWN
    local dropLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropLabel:SetPoint("TOPLEFT", sliderStack, "BOTTOMLEFT", 0, -40)
    dropLabel:SetText("Text Anchor:")

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
    UIDropDownMenu_SetWidth(drop, 120)
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
        
        btn:SetScript("OnClick", function() 
            EzOBR_Config.fontPath = fontData[2]
            print("|cff00FF00Ez-OBRotation:|r Font changed to: " .. fontData[1])
        end)
        lastBtn = btn
    end

    SLASH_EZOBR1 = "/ezobr"
    SlashCmdList["EZOBR"] = function() Settings.OpenToCategory(settingsCategory:GetID()) end
end