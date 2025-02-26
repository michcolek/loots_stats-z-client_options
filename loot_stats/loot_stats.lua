-- loot_stats.lua - Optimized module for tracking and displaying loot statistics
-- Author: Original by EgzoT, optimized for OTClient Mehah

-- Module namespace to avoid global pollution
LootStats = {}

-- ====
-- Module Constants
-- ====
local DEFAULT_SETTINGS = {
    showLootOnScreen = true,
    amountLootOnScreen = 5,
    delayTimeLootOnScreen = 2000,
    ignoreMonsterLevelSystem = false,
    ignoreLastSignWhenDot = false
}

-- ====
-- Module Variables
-- ====

-- Settings (loaded from g_settings)
local settings = table.copy(DEFAULT_SETTINGS)

-- UI elements
local lootStatsButton
local lootStatsWindow
local confirmWindow

-- Data structures
local mainScreenLoot = {}         -- Holds current loot display information
local activeIcons = {}            -- Holds active loot icon widgets
local lootDatabase = {}           -- Stores all monster loot statistics
local widgetCache = {}            -- Cache for loot icon widgets
local scheduledEvents = {}        -- Tracks all event handlers
local uniqueIdCounter = 1         -- For generating unique IDs

-- Item database
local itemDatabase = {}           -- Cache for item name to client ID lookups
local hasSafeUI = true            -- Flag to track if UI functions are available

-- Path handling
local function getResourcePath(file)
    local paths = {
        '/loot_stats/' .. file,
        'loot_stats/' .. file,
        '/' .. file,
        file
    }
    
    for _, path in ipairs(paths) do
        if g_resources.fileExists(path) then
            return path
        end
    end
    
    return '/loot_stats/' .. file -- Default path even if not found
end

-- ====
-- Logging Helper
-- ====

function LootStats.log(level, message)
    if g_logger then
        if level == "info" then
            g_logger.info("[LootStats] " .. message)
        elseif level == "warning" then
            g_logger.warning("[LootStats] " .. message)
        elseif level == "error" then
            g_logger.error("[LootStats] " .. message)
        end
    else
        -- Fallback if g_logger is not available
        print("[LootStats] [" .. level .. "] " .. message)
    end
end

-- ====
-- Style Creation
-- ====

function LootStats.createStyles()
    -- Check if g_ui exists
    if not g_ui then
        LootStats.log("error", "g_ui is not available. Cannot create styles.")
        hasSafeUI = false
        return
    end
    
    -- Define style directly without using the file system
    local lootIconStyle = [[
    LootIcon < UIItem
      size: 32 32
      virtual: true
      phantom: false
    ]]
    
    local lootItemBoxStyle = [[
    LootItemBox < UIWidget
      id: lootItemBox
      border-width: 1
      border-color: #000000
      color: #ffffff
      text-align: center
      size: 150 90

      Item
        id: item
        phantom: true
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        image-color: #ffffffff
        margin-top: 5

      Label
        id: text
        text-align: center
        color: #ffffff
        anchors.top: item.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
    ]]
    
    local lootMonsterBoxStyle = [[
    LootMonsterBox < UIWidget
      id: lootMonsterBox
      border-width: 1
      border-color: #000000
      color: #ffffff
      text-align: center
      size: 150 90

      Creature
        id: creature
        phantom: true
        height: 40
        width: 40
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        image-color: #ffffffff
        margin-top: 5

      Label
        id: text
        text-align: center
        color: #ffffff
        anchors.top: creature.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
    ]]
    
    -- Try to create the styles with proper error handling
    local success = pcall(function() g_ui.createStyle(lootIconStyle) end)
    if not success then
        LootStats.log("warning", "Failed to create LootIcon style")
    end
    
    success = pcall(function() g_ui.createStyle(lootItemBoxStyle) end)
    if not success then
        LootStats.log("warning", "Failed to create LootItemBox style")
    end
    
    success = pcall(function() g_ui.createStyle(lootMonsterBoxStyle) end)
    if not success then
        LootStats.log("warning", "Failed to create LootMonsterBox style")
    end
}

-- ====
-- Settings Management
-- ====

function LootStats.loadSettings()
    LootStats.log("info", "Loading settings")
    
    -- Check if g_settings exists
    if not g_settings then
        LootStats.log("warning", "g_settings is not available. Using default settings.")
        return
    end
    
    -- Load settings from global settings with error handling
    for key, defaultValue in pairs(DEFAULT_SETTINGS) do
        local settingKey = 'loot_stats_' .. key
        
        local success, value = pcall(function() return g_settings.get(settingKey) end)
        
        if success and value ~= nil then
            if type(defaultValue) == 'boolean' then
                local success, boolValue = pcall(function() return g_settings.getBoolean(settingKey, defaultValue) end)
                if success then
                    settings[key] = boolValue
                end
            elseif type(defaultValue) == 'number' then
                local success, numValue = pcall(function() return g_settings.getNumber(settingKey, defaultValue) end)
                if success then
                    settings[key] = numValue
                end
            else
                local success, strValue = pcall(function() return g_settings.getString(settingKey, defaultValue) end)
                if success then
                    settings[key] = strValue
                end
            end
        else
            settings[key] = defaultValue
        end
    end
    
    -- If client_options module exists and has current settings, use those
    if modules.client_options and type(modules.client_options.getOption) == 'function' then
        for key, _ in pairs(settings) do
            local success, optionValue = pcall(function() return modules.client_options.getOption(key) end)
            if success and optionValue ~= nil then
                settings[key] = optionValue
            end
        end
    end
}

function LootStats.saveSettings()
    -- Check if g_settings exists
    if not g_settings then
        LootStats.log("warning", "g_settings is not available. Cannot save settings.")
        return
    end
    
    -- Save settings to global settings with error handling
    for key, value in pairs(settings) do
        pcall(function() g_settings.set('loot_stats_' .. key, value) end)
    end
}

-- ====
-- Settings Getters and Setters
-- ====

function LootStats.getSetting(key)
    return settings[key]
}

function LootStats.setSetting(key, value)
    if settings[key] == value then return end
    
    settings[key] = value
    pcall(function() g_settings.set('loot_stats_' .. key, value) end)
    
    -- Apply the setting change
    if key == 'showLootOnScreen' then
        if value then
            LootStats.refreshLootDisplay()
        else
            LootStats.destroyLootIcons()
        end
    elseif key == 'amountLootOnScreen' then
        LootStats.refreshLootDisplay()
    end
    
    -- Notify the options panel of the change
    if modules.client_options and LootStats.optionsPanel then
        LootStats.updateOptionsUI()
    end
}

-- Exposed setter functions (for Options Panel)
function LootStats.setShowLootOnScreen(value)
    LootStats.setSetting('showLootOnScreen', value)
}

function LootStats.setAmountLootOnScreen(value)
    value = tonumber(value) or 5
    value = math.max(1, math.min(20, value))
    LootStats.setSetting('amountLootOnScreen', value)
}

function LootStats.setDelayTimeLootOnScreen(value)
    value = tonumber(value) or 2000
    value = math.max(500, math.min(10000, value))
    LootStats.setSetting('delayTimeLootOnScreen', value)
}

function LootStats.setIgnoreMonsterLevelSystem(value)
    LootStats.setSetting('ignoreMonsterLevelSystem', value)
}

function LootStats.setIgnoreLastSignWhenDot(value)
    LootStats.setSetting('ignoreLastSignWhenDot', value)
}

-- ====
-- Widget Cache Management
-- ====

function LootStats.initWidgetCache()
    -- Clean existing cache
    for _, widget in pairs(widgetCache) do
        if widget and not pcall(function() return widget:isDestroyed() end) and not widget:isDestroyed() then
            pcall(function() widget:destroy() end)
        end
    end
    
    widgetCache = {}
    
    -- Check if we have the required modules
    if not modules.game_interface or type(modules.game_interface.getMapPanel) ~= 'function' then
        LootStats.log("warning", "game_interface module not found or getMapPanel not available")
        return
    end
    
    -- Get the map panel
    local mapPanel = modules.game_interface.getMapPanel()
    if not mapPanel then
        LootStats.log("warning", "Map panel not found, widget cache initialization skipped")
        return
    end
    
    -- Pre-create widgets for cache
    for i = 1, 20 do
        -- Create with proper error handling
        local success, widget = pcall(function()
            return g_ui.createWidget('LootIcon', mapPanel)
        end)
        
        if success and widget then
            widget:setId('lootStatsIcon' .. i)
            widget:hide()
            table.insert(widgetCache, widget)
        else
            LootStats.log("warning", "Failed to create LootIcon widget #" .. i)
        end
    end
}

function LootStats.getIconFromCache()
    -- Find a hidden widget in the cache
    for _, widget in pairs(widgetCache) do
        if widget and not pcall(function() return widget:isDestroyed() end) and 
           not widget:isDestroyed() and not widget:isVisible() then
            return widget
        end
    end
    
    -- If no modules available, return nil
    if not modules.game_interface or type(modules.game_interface.getMapPanel) ~= 'function' then
        return nil
    end
    
    -- Create a new widget if necessary
    local mapPanel = modules.game_interface.getMapPanel()
    if mapPanel then
        local success, widget = pcall(function()
            return g_ui.createWidget('LootIcon', mapPanel)
        end)
        
        if success and widget then
            widget:setId('lootStatsIcon' .. (#widgetCache + 1))
            table.insert(widgetCache, widget)
            return widget
        end
    end
    
    return nil
}

-- ====
-- Item Database Management
-- ====

function LootStats.initItemDatabase()
    -- Initialize item database from items.otb if possible
    itemDatabase = {}
    
    -- Check if required functions exist
    if not g_things then
        LootStats.log("warning", "g_things is not available. Using default item IDs.")
        return
    end
    
    -- Safely check the function we need
    if not pcall(function() return type(g_things.getThingType) == 'function' end) then
        LootStats.log("warning", "getThingType function not available. Using default item IDs.")
        return
    end
    
    -- Constants for OTClient
    local ThingCategoryItem = 0 -- This seems to be the category for items in OTClient
    
    -- Attempt to cache common items by name - with updated ID range for Mehah
    LootStats.log("info", "Initializing item database cache")
    
    -- Try a wider range of item IDs to account for different client versions
    for id = 500, 15000 do -- Start from 500 to avoid low-ID errors
        -- Use pcall to safely attempt to get each item
        local success, itemType = pcall(function() 
            return g_things.getThingType(id, ThingCategoryItem) 
        end)
        
        if success and itemType then
            -- Check if itemType has a isNull method and if it's not null
            if not pcall(function() return itemType:isNull() end) or not itemType:isNull() then
                -- Try to get the name safely
                local success, name = pcall(function() 
                    return itemType:getName() 
                end)
                
                if success and name and name ~= "" then
                    itemDatabase[name:lower()] = id
                end
            end
        end
        
        -- Progress update every 1000 items
        if id % 1000 == 0 then
            LootStats.log("info", "Item scan progress: " .. id)
        end
    end
    
    LootStats.log("info", "Item database initialized with " .. table.size(itemDatabase) .. " items")
}

function LootStats.getItemClientId(itemName)
    if not itemName then
        return 3547 -- Default item ID (paper)
    end
    
    local nameLower = itemName:lower()
    
    -- Check cache first
    if itemDatabase[nameLower] then
        return itemDatabase[nameLower]
    end
    
    -- Use a set of common/fallback item IDs if not found
    local commonItems = {
        gold = 3031,
        coin = 3031,
        sword = 3264,
        axe = 3274,
        club = 3270,
        shield = 3410,
        armor = 3361,
        plate = 3357,
        helmet = 3353,
        legs = 3364,
        boots = 3079,
        ring = 3004,
        amulet = 3025,
        rune = 3152,
        wand = 3074,
        rod = 3066,
        potion = 7634,
        vial = 2874,
        bag = 2853,
        backpack = 2854,
        scroll = 2815,
        book = 2821,
        flask = 2874,
        key = 2086
    }
    
    -- Check if the item name contains any common item keywords
    for keyword, id in pairs(commonItems) do
        if nameLower:find(keyword) then
            itemDatabase[nameLower] = id -- Cache for future use
            return id
        end
    end
    
    -- If not found, use a default item ID (paper)
    itemDatabase[nameLower] = 3547
    return 3547
}

-- ====
-- Game Event Handlers
-- ====

function LootStats.onGameStart()
    LootStats.log("info", "Game started")
    
    -- Set up main panel button if not already created
    if hasSafeUI and modules.game_mainpanel and not lootStatsButton then
        pcall(function()
            -- Try with both paths to maximize compatibility
            local iconPath = g_resources.fileExists('/images/game/loot_stats') 
                and '/images/game/loot_stats' 
                or '/loot_stats/ui/img/icon'
                
            lootStatsButton = modules.game_mainpanel.addToggleButton(
                'lootStatsButton', 
                tr('Loot Stats'), 
                iconPath, 
                function() LootStats.toggle() end, 
                false, 
                5
            )
        end)
    end
    
    -- Update options panel if exists
    if LootStats.optionsPanel then
        LootStats.updateOptionsUI()
    end
    
    -- Clear any existing loot icons
    LootStats.destroyLootIcons()
    
    -- Reset data structures
    mainScreenLoot = {}
    uniqueIdCounter = 1
    
    -- Ensure widget cache is ready
    if hasSafeUI then
        pcall(function() LootStats.initWidgetCache() end)
    end
}

function LootStats.onGameEnd()
    LootStats.log("info", "Game ended")
    
    -- Save settings
    LootStats.saveSettings()
    
    -- Hide window
    if lootStatsWindow and pcall(function() return lootStatsWindow:isVisible() end) and lootStatsWindow:isVisible() then
        pcall(function() lootStatsWindow:hide() end)
    end
    
    -- Clean up loot icons
    LootStats.destroyLootIcons()
    
    -- Reset button state
    if lootStatsButton then
        pcall(function() lootStatsButton:setOn(false) end)
    end
    
    -- Clear active events
    LootStats.clearScheduledEvents()
}

function LootStats.onMonsterDeath(creature)
    -- Record monster outfit for later display
    if not creature then return end
    
    -- Get creature name with proper error handling
    local name
    if not pcall(function() name = creature:getName() end) then
        return
    end
    
    if not name or name == "" then return end
    
    -- Use a small delay to ensure the creature is still valid
    local eventId = "monster_death_" .. os.time() .. "_" .. uniqueIdCounter
    uniqueIdCounter = uniqueIdCounter + 1
    
    scheduledEvents[eventId] = scheduleEvent(function()
        local lowerName = string.lower(name)
        
        -- Handle monster level system if enabled
        if not settings.ignoreMonsterLevelSystem then
            if string.find(name, '%[') and string.find(name, '%]') then
                local nameWithoutBracket = string.sub(name, 0, string.find(name, '%[') - 1)
                if string.sub(nameWithoutBracket, string.len(nameWithoutBracket)) == ' ' then
                    nameWithoutBracket = string.sub(name, 0, string.len(nameWithoutBracket) - 1)
                end
                
                lowerName = string.lower(nameWithoutBracket)
            end
        end
        
        -- Store outfit if this monster exists in our stats
        if lootDatabase[lowerName] and not lootDatabase[lowerName].outfit then
            pcall(function() lootDatabase[lowerName].outfit = creature:getOutfit() end)
        end
        
        -- Remove event from scheduledEvents
        scheduledEvents[eventId] = nil
    end, 200)
}

function LootStats.onTextMessage(mode, message)
    -- Check parameter validity
    if not message then return end
    
    -- Get the message mode with error handling
    local messageMode = mode
    local isLootMessage = false
    
    -- Try with MessageModes.Loot if available
    if pcall(function() return MessageModes.Loot end) then
        isLootMessage = (messageMode == MessageModes.Loot)
    else
        -- Fallback: In many OTClient versions, these are common loot message modes
        isLootMessage = (messageMode == 20 or messageMode == 22 or messageMode == 3)
    end
    
    if not isLootMessage then
        -- Alternative check: Look for "Loot of" pattern at the beginning of the message
        if not message:match("^Loot of ") then
            return
        end
    end
    
    -- Check for loot pattern
    local fromLootValue, toLootValue = string.find(message, 'Loot of ')
    if not toLootValue then return end
    
    -- Extract monster name
    local lootMonsterName = string.sub(message, toLootValue + 1, string.find(message, ':') - 1)
    
    -- Remove 'a ' or 'an ' prefix if present
    local isAFromLootValue, isAToLootValue = string.find(lootMonsterName, 'a ')
    if isAToLootValue then
        lootMonsterName = string.sub(lootMonsterName, isAToLootValue + 1)
    end
    
    local isANFromLootValue, isANToLootValue = string.find(lootMonsterName, 'an ')
    if isANToLootValue then
        lootMonsterName = string.sub(lootMonsterName, isANToLootValue + 1)
    end
    
    -- Handle monster level in brackets if needed
    if not settings.ignoreMonsterLevelSystem then
        local bracketStart = string.find(lootMonsterName, '%[')
        if bracketStart then
            lootMonsterName = string.sub(lootMonsterName, 1, bracketStart - 2)
        end
    end
    
    -- Convert to lowercase for consistent keys
    local monsterKey = string.lower(lootMonsterName)
    
    -- Add monster entry if doesn't exist
    if not lootDatabase[monsterKey] then
        lootDatabase[monsterKey] = { loot = {}, count = 0 }
    end
    
    -- Increment monster count
    lootDatabase[monsterKey].count = lootDatabase[monsterKey].count + 1
    
    -- Parse loot string
    local lootString = string.sub(message, string.find(message, ': ') + 2)
    
    -- Remove trailing dot if needed
    if not settings.ignoreLastSignWhenDot and string.sub(lootString, -1) == '.' then
        lootString = string.sub(lootString, 1, -2)
    end
    
    -- Process each loot item
    local lootToScreen = {}
    for word in string.gmatch(lootString, '([^,]+)') do
        -- Remove leading space
        if string.sub(word, 1, 1) == ' ' then
            word = string.sub(word, 2)
        end
        
        -- Remove 'a ' or 'an ' prefix
        local isAPrefix, isAEnd = string.find(word, 'a ')
        if isAEnd then
            word = string.sub(word, isAEnd + 1)
        end
        
        local isANPrefix, isANEnd = string.find(word, 'an ')
        if isANEnd then
            word = string.sub(word, isANEnd + 1)
        end
        
        -- Check if first character is a number (for stackable items)
        if tonumber(string.sub(word, 1, 1)) then
            local itemCount = tonumber(string.match(word, "%d+"))
            local countStart, countEnd = string.find(word, tostring(itemCount))
            
            if countEnd and countEnd + 2 <= #word then
                local itemName = string.sub(word, countEnd + 2)
                
                -- Add to monster loot
                if not lootDatabase[monsterKey].loot[itemName] then
                    lootDatabase[monsterKey].loot[itemName] = { count = 0 }
                end
                lootDatabase[monsterKey].loot[itemName].count = 
                    lootDatabase[monsterKey].loot[itemName].count + itemCount
                
                -- Add to screen display
                if not lootToScreen[itemName] then
                    lootToScreen[itemName] = { count = 0 }
                end
                lootToScreen[itemName].count = lootToScreen[itemName].count + itemCount
            end
        else
            -- Single item (count = 1)
            if not lootDatabase[monsterKey].loot[word] then
                lootDatabase[monsterKey].loot[word] = { count = 0 }
            end
            lootDatabase[monsterKey].loot[word].count = 
                lootDatabase[monsterKey].loot[word].count + 1
            
            if not lootToScreen[word] then
                lootToScreen[word] = { count = 0 }
            end
            lootToScreen[word].count = lootToScreen[word].count + 1
        end
    end
    
    -- Display loot on screen if enabled
    if settings.showLootOnScreen and hasSafeUI then
        LootStats.addLootToScreen(lootToScreen)
    end
    
    -- Update UI if visible
    if lootStatsWindow and pcall(function() return lootStatsWindow:isVisible() end) and lootStatsWindow:isVisible() then
        LootStats.updateDisplayedList()
    end
}

-- ====
-- UI Management
-- ====

function LootStats.createLootStatsWindow()
    if lootStatsWindow then return end
    
    -- Try to create a basic window from code rather than loading from file
    local success, window = pcall(function()
        local mainWindow = g_ui.createWidget('MainWindow', rootWidget)
        mainWindow:setId('lootStatsMain')
        mainWindow:setText(tr('Loot Statistics'))
        mainWindow:setSize({width = 550, height = 515})
        mainWindow:setVisible(false)
        
        -- Add tabs
        local monstersTab = g_ui.createWidget('TabButton', mainWindow)
        monstersTab:setId('monstersTab')
        monstersTab:setText(tr('Monsters'))
        monstersTab:setChecked(true)
        monstersTab:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        monstersTab:setAnchor(AnchorTop, 'parent', AnchorTop)
        monstersTab:setWidth(150)
        monstersTab:setMarginTop(5)
        monstersTab:setMarginLeft(10)
        
        local allLootTab = g_ui.createWidget('TabButton', mainWindow)
        allLootTab:setId('allLootTab')
        allLootTab:setText(tr('All Loot'))
        allLootTab:setAnchor(AnchorLeft, 'monstersTab', AnchorRight)
        allLootTab:setAnchor(AnchorTop, 'parent', AnchorTop)
        allLootTab:setWidth(150)
        allLootTab:setMarginTop(5)
        allLootTab:setMarginLeft(10)
        
        -- Creature view panel
        local panelCreatureView = g_ui.createWidget('Panel', mainWindow)
        panelCreatureView:setId('panelCreatureView')
        panelCreatureView:setAnchor(AnchorTop, 'monstersTab', AnchorBottom)
        panelCreatureView:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        panelCreatureView:setHeight(0)
        panelCreatureView:setWidth(250)
        panelCreatureView:setMarginTop(5)
        panelCreatureView:setMarginLeft(10)
        panelCreatureView:setVisible(false)
        
        -- Create creature view widget
        local creatureView = g_ui.createWidget('Creature', panelCreatureView)
        creatureView:setId('creatureView')
        creatureView:setHeight(40)
        creatureView:setWidth(40)
        creatureView:setAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        creatureView:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        
        -- Create text view for creature
        local textCreatureView = g_ui.createWidget('Label', panelCreatureView)
        textCreatureView:setId('textCreatureView')
        textCreatureView:setTextAlign(AlignLeft)
        textCreatureView:setColor('#ffffff')
        textCreatureView:setHeight(50)
        textCreatureView:setWidth(205)
        textCreatureView:setAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        textCreatureView:setAnchor(AnchorLeft, 'creatureView', AnchorRight)
        textCreatureView:setMarginLeft(5)
        
        -- Content panel
        local contentPanel = g_ui.createWidget('Panel', mainWindow)
        contentPanel:setId('contentPanel')
        contentPanel:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        contentPanel:setAnchor(AnchorRight, 'parent', AnchorRight)
        contentPanel:setAnchor(AnchorTop, 'panelCreatureView', AnchorBottom)
        contentPanel:setAnchor(AnchorBottom, 'parent', AnchorBottom)
        contentPanel:setMarginTop(10)
        contentPanel:setMarginBottom(40)
        contentPanel:setMarginLeft(10)
        contentPanel:setMarginRight(10)
        
        -- Items panel with scrollbar
        local itemsPanel = g_ui.createWidget('Panel', contentPanel)
        itemsPanel:setId('itemsPanel')
        itemsPanel:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        itemsPanel:setAnchor(AnchorRight, 'parent', AnchorRight)
        itemsPanel:setAnchor(AnchorTop, 'parent', AnchorTop)
        itemsPanel:setAnchor(AnchorBottom, 'parent', AnchorBottom)
        itemsPanel:setLayout('grid')
        itemsPanel:setGridSize(3, 0)
        
        -- Bottom panel with buttons
        local bottomPanel = g_ui.createWidget('Panel', mainWindow)
        bottomPanel:setId('bottomPanel')
        bottomPanel:setHeight(30)
        bottomPanel:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        bottomPanel:setAnchor(AnchorRight, 'parent', AnchorRight)
        bottomPanel:setAnchor(AnchorBottom, 'parent', AnchorBottom)
        
        -- Clear button
        local clearButton = g_ui.createWidget('Button', bottomPanel)
        clearButton:setId('clearButton')
        clearButton:setText(tr('Clear Data'))
        clearButton:setWidth(80)
        clearButton:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        clearButton:setAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        clearButton:setMarginLeft(10)
        
        -- Close button
        local closeButton = g_ui.createWidget('Button', bottomPanel)
        closeButton:setId('closeButton')
        closeButton:setText(tr('Close'))
        closeButton:setWidth(64)
        closeButton:setAnchor(AnchorRight, 'parent', AnchorRight)
        closeButton:setAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        closeButton:setMarginRight(10)
        
        return mainWindow
    end)
    
    if success and window then
        lootStatsWindow = window
        
        -- Connect events
        local monstersTab = lootStatsWindow:getChildById('monstersTab')
        if monstersTab then
            monstersTab.onMouseRelease = function(widget, mousePos, mouseButton)
                LootStats.showMonstersList(widget, mousePos, mouseButton)
            end
        end
        
        local allLootTab = lootStatsWindow:getChildById('allLootTab')
        if allLootTab then
            allLootTab.onMouseRelease = function(widget, mousePos, mouseButton)
                LootStats.showAllLootList(widget, mousePos, mouseButton)
            end
        end
        
        local closeButton = lootStatsWindow:getChildById('closeButton')
        if closeButton then
            closeButton.onClick = function() LootStats.toggle() end
        end
        
        local clearButton = lootStatsWindow:getChildById('clearButton')
        if clearButton then
            clearButton.onClick = function() LootStats.confirmClearData() end
        end
    else
        LootStats.log("error", "Failed to create main window: " .. tostring(window))
    end
}

function LootStats.toggle()
    if not hasSafeUI then
        LootStats.log("warning", "Cannot toggle window - UI functions are limited")
        return
    end
    
    if not lootStatsWindow then
        pcall(function() LootStats.createLootStatsWindow() end)
        if not lootStatsWindow then return end
    end
    
    if pcall(function() return lootStatsWindow:isVisible() end) and lootStatsWindow:isVisible() then
        pcall(function() lootStatsWindow:hide() end)
        if lootStatsButton then
            pcall(function() lootStatsButton:setOn(false) end)
        end
    else
        pcall(function() 
            lootStatsWindow:show()
            lootStatsWindow:raise()
            lootStatsWindow:focus() 
        end)
        
        if lootStatsButton then
            pcall(function() lootStatsButton:setOn(true) end)
        end
        
        LootStats.updateDisplayedList()
    end
}

-- Other UI functions and events would be here (clearScheduledEvents, destroyLootIcons, etc.)

-- ====
-- Loot Display Functions
-- ====

function LootStats.clearScheduledEvents()
    for id, event in pairs(scheduledEvents) do
        if event then
            pcall(function() removeEvent(event) end)
        end
    end
    scheduledEvents = {}
}

function LootStats.addLootToScreen(lootItems)
    if not lootItems or not hasSafeUI then return end
    
    -- Create a new loot entry
    local lootEntry = {
        loot = lootItems,
        id = os.time() * 1000 + uniqueIdCounter
    }
    uniqueIdCounter = uniqueIdCounter + 1
    
    -- Add to mainScreenLoot
    table.insert(mainScreenLoot, 1, lootEntry)
    
    -- Trim list to maximum size
    while #mainScreenLoot > settings.amountLootOnScreen do
        table.remove(mainScreenLoot)
    end
    
    -- Schedule removal
    local id = lootEntry.id
    if scheduleEvent then
        scheduledEvents[id] = scheduleEvent(function()
            LootStats.removeLootFromScreen(id)
            scheduledEvents[id] = nil
        end, settings.delayTimeLootOnScreen)
    else
        LootStats.log("warning", "scheduleEvent function not available, cannot auto-remove loot display")
    end
    
    -- Update the display
    LootStats.refreshLootDisplay()
}

function LootStats.removeLootFromScreen(id)
    -- Find and remove the entry with matching id
    for i, entry in ipairs(mainScreenLoot) do
        if entry.id == id then
            table.remove(mainScreenLoot, i)
            break
        end
    end
    
    -- Update the display
    LootStats.refreshLootDisplay()
}

function LootStats.destroyLootIcons()
    -- Hide all active icons
    for _, icon in pairs(activeIcons) do
        if icon and not pcall(function() return icon:isDestroyed() end) and not icon:isDestroyed() then
            pcall(function() icon:hide() end)
        end
    end
    activeIcons = {}
}

function LootStats.refreshLootDisplay()
    -- If missing UI capabilities, exit
    if not hasSafeUI then return end
    
    -- Clean up existing icons
    LootStats.destroyLootIcons()
    
    -- If disabled or no game interface, exit
    if not settings.showLootOnScreen or not modules.game_interface or
       type(modules.game_interface.getMapPanel) ~= 'function' then
        return
    end
    
    -- Get map panel for placement
    local mapPanel
    if not pcall(function() mapPanel = modules.game_interface.getMapPanel() end) or not mapPanel then
        return
    end
    
    -- Calculate position based on top menu
    local yOffset = 0
    if modules.client_topmenu then
        pcall(function()
            local topMenu = modules.client_topmenu.getTopMenu()
            if topMenu and topMenu:isVisible() then
                yOffset = topMenu:getHeight()
            end
        end)
    end
    
    -- Display each row of loot
    for rowIndex, lootEntry in ipairs(mainScreenLoot) do
        if lootEntry and lootEntry.loot then
            -- Count items in this row
            local itemCount = 0
            for _ in pairs(lootEntry.loot) do
                itemCount = itemCount + 1
            end
            
            -- Calculate row position
            local rowWidth = itemCount * 32
            local rowX = math.floor((mapPanel:getWidth() - rowWidth) / 2)
            local rowY = yOffset + ((rowIndex - 1) * 32)
            
            -- Skip if off-screen
            if rowY >= mapPanel:getHeight() - 32 then
                goto continue
            end
            
            -- Create icons for items
            for itemName, itemData in pairs(lootEntry.loot) do
                -- Skip if off-screen
                if rowX >= mapPanel:getWidth() - 32 then
                    goto nextItem
                end
                
                -- Get icon from cache
                local icon = LootStats.getIconFromCache()
                if icon then
                    -- Set item properties
                    local clientId = LootStats.getItemClientId(itemName)
                    pcall(function() 
                        icon:setItemId(clientId)
                        if itemData.count > 1 then
                            icon:setItemCount(itemData.count)
                        else
                            icon:setItemCount(1)
                        end
                    end)
                    
                    -- Position icon and make visible
                    pcall(function()
                        icon:setPosition({x = rowX, y = rowY})
                        icon:show()
                    end)
                    
                    -- Add to active icons list
                    table.insert(activeIcons, icon)
                    
                    rowX = rowX + 32
                end
                
                ::nextItem::
            end
        end
        
        ::continue::
    end
}

function LootStats.updateDisplayedList()
    -- Skip if window not visible
    if not lootStatsWindow or not pcall(function() return lootStatsWindow:isVisible() end) or not lootStatsWindow:isVisible() then
        return
    end
    
    -- Check which tab is active
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    
    if monstersTab and pcall(function() return monstersTab:isOn() end) and monstersTab:isOn() then
        LootStats.displayMonstersList()
    elseif allLootTab and pcall(function() return allLootTab:isOn() end) and allLootTab:isOn() then
        LootStats.displayAllLootList()
    end
}

function LootStats.showMonstersList(widget, mousePos, mouseButton)
    if mouseButton ~= MouseLeftButton then return end
    
    -- Update tab state
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    if allLootTab then pcall(function() allLootTab:setOn(false) end) end
    pcall(function() widget:setOn(true) end)
    
    -- Hide creature view panel
    local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
    if panelCreatureView then
        pcall(function()
            panelCreatureView:setHeight(0)
            panelCreatureView:setVisible(false)
        end)
    end
    
    -- Show monster list
    LootStats.displayMonstersList()
}

function LootStats.showAllLootList(widget, mousePos, mouseButton)
    if mouseButton ~= MouseLeftButton then return end
    
    -- Update tab state
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    if monstersTab then pcall(function() monstersTab:setOn(false) end) end
    pcall(function() widget:setOn(true) end)
    
    -- Hide creature view panel
    local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
    if panelCreatureView then
        pcall(function()
            panelCreatureView:setHeight(0)
            panelCreatureView:setVisible(false)
        end)
    end
    
    -- Show all loot list
    LootStats.displayAllLootList()
}

-- ====
-- Stats Display Functions
-- ====

function LootStats.displayMonstersList()
    local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
    if not itemsPanel then return end
    
    -- Clear existing items
    pcall(function() itemsPanel:destroyChildren() end)
    
    -- Calculate total monsters for percentages
    local totalMonsters = 0
    for _, data in pairs(lootDatabase) do
        totalMonsters = totalMonsters + data.count
    end
    
    -- Sort monsters by name
    local sortedMonsters = {}
    for monsterName, monsterData in pairs(lootDatabase) do
        table.insert(sortedMonsters, {name = monsterName, data = monsterData})
    end
    
    table.sort(sortedMonsters, function(a, b)
        return a.name < b.name
    end)
    
    -- Add monster entries
    for _, monsterInfo in ipairs(sortedMonsters) do
        local monsterName = monsterInfo.name
        local monsterData = monsterInfo.data
        
        -- Try to create the widget safely
        local success, widget = pcall(function()
            local w = g_ui.createWidget('LootMonsterBox', itemsPanel)
            
            -- Format text
            local text = monsterName:gsub("^%l", string.upper) .. '\n' .. 'Count: ' .. monsterData.count
            
            if totalMonsters > 0 then
                local percentage = monsterData.count * 100 / totalMonsters
                text = text .. '\n' .. 'Chance: ' .. LootStats.formatNumber(percentage, 3, true) .. ' %'
            end
            
            local textWidget = w:getChildById('text')
            if textWidget then
                textWidget:setText(text)
            end
            
            return w
        end)
        
        if not success then
            LootStats.log("error", "Failed to create monster widget: " .. tostring(widget))
            goto continue
        end
        
        -- Set creature image
        pcall(function()
            local creatureWidget = widget:getChildById('creature')
            if creatureWidget then
                local creature = Creature.create()
                creature:setDirection(2)
                
                if monsterData.outfit then
                    creature:setOutfit(monsterData.outfit)
                else
                    local defaultOutfit = { 
                        type = 160, 
                        feet = 114, 
                        addons = 0, 
                        legs = 114, 
                        auxType = 7399, 
                        head = 114, 
                        body = 114 
                    }
                    creature:setOutfit(defaultOutfit)
                end
                
                creatureWidget:setCreature(creature)
            end
        end)
        
        -- Connect click event
        widget.onMouseRelease = function(w, mousePos, mouseButton)
            if mouseButton == MouseLeftButton then
                LootStats.selectMonster(w)
            end
        end
        
        ::continue::
    end
}

function LootStats.selectMonster(widget)
    if not widget then return end
    
    -- Update tab state
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    
    if monstersTab then pcall(function() monstersTab:setOn(false) end) end
    if allLootTab then pcall(function() allLootTab:setOn(false) end) end
    
    -- Show creature view panel
    local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
    if not panelCreatureView then return end
    
    pcall(function()
        panelCreatureView:setHeight(40)
        panelCreatureView:setVisible(true)
    end)
    
    -- Copy creature to panel
    local creatureView = panelCreatureView:getChildById('creatureView')
    local creatureWidget = widget:getChildById('creature')
    
    if creatureView and creatureWidget then
        pcall(function() creatureView:setCreature(creatureWidget:getCreature()) end)
    end
    
    -- Set text info
    local textView = panelCreatureView:getChildById('textCreatureView')
    local textWidget = widget:getChildById('text')
    
    if textView and textWidget then
        pcall(function() textView:setText(textWidget:getText()) end)
    end
    
    -- Extract monster name from text
    local monsterName = ""
    local text
    if pcall(function() text = textWidget:getText() end) and text then
        for word in string.gmatch(text, '([^'..'\n'..']+)') do
            monsterName = word
            break
        end
    end
    
    -- Show monster loot
    LootStats.displayMonsterLoot(monsterName)
}

function LootStats.displayMonsterLoot(monsterName)
    LootStats.displayLootList(string.lower(monsterName))
}

function LootStats.displayAllLootList()
    LootStats.displayLootList("*all")
}

function LootStats.displayLootList(monsterName)
    local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
    if not itemsPanel then return end
    
    -- Clear existing items
    pcall(function() itemsPanel:destroyChildren() end)
    
    -- Determine which loot to show
    local lootItems = {}
    local totalCount = 0
    
    if monsterName == "*all" then
        -- Show all loot
        for _, monsterData in pairs(lootDatabase) do
            totalCount = totalCount + monsterData.count
            
            for itemName, itemInfo in pairs(monsterData.loot) do
                if not lootItems[itemName] then
                    lootItems[itemName] = {count = 0, plural = itemInfo.plural}
                end
                lootItems[itemName].count = lootItems[itemName].count + itemInfo.count
            end
        end
    else
        -- Show monster-specific loot
        if lootDatabase[monsterName] then
            totalCount = lootDatabase[monsterName].count
            
            for itemName, itemInfo in pairs(lootDatabase[monsterName].loot) do
                lootItems[itemName] = {
                    count = itemInfo.count,
                    plural = itemInfo.plural
                }
            end
        end
    end
    
    -- Sort items by name
    local sortedItems = {}
    for itemName, itemInfo in pairs(lootItems) do
        table.insert(sortedItems, {name = itemName, info = itemInfo})
    end
    
    table.sort(sortedItems, function(a, b)
        return a.name < b.name
    end)
    
    -- Create item widgets
    for _, itemData in ipairs(sortedItems) do
        local itemName = itemData.name
        local itemInfo = itemData.info
        
        -- Create widget safely
        local success, widget = pcall(function()
            local w = g_ui.createWidget('LootItemBox', itemsPanel)
            
            -- Prepare text
            local text = itemName:gsub("^%l", string.upper) .. '\n' .. 'Count: ' .. itemInfo.count
            
            -- Add drop chance or average
            if totalCount > 0 then
                if itemInfo.plural and itemInfo.count > totalCount then
                    local avg = itemInfo.count / totalCount
                    text = text .. '\n' .. 'Average: ' .. LootStats.formatNumber(avg, 3, true) .. ' / kill'
                else
                    local chance = itemInfo.count * 100 / totalCount
                    text = text .. '\n' .. 'Chance: ' .. LootStats.formatNumber(chance, 3, true) .. ' %'
                end
            end
            
            -- Set text
            local textWidget = w:getChildById('text')
            if textWidget then
                textWidget:setText(text)
            end
            
            return w
        end)
        
        if not success then
            LootStats.log("error", "Failed to create item widget: " .. tostring(widget))
            goto continue
        end
        
        -- Set item
        pcall(function()
            local itemWidget = widget:getChildById('item')
            if itemWidget then
                local clientId = LootStats.getItemClientId(itemName)
                local item = Item.create(clientId)
                
                if itemInfo.plural and itemInfo.count > 1 then
                    item:setCount(math.min(itemInfo.count, 100))
                end
                
                itemWidget:setItem(item)
            end
        end)
        
        ::continue::
    end
}

function LootStats.confirmClearData()
    if not hasSafeUI then
        LootStats.log("warning", "Cannot show confirm dialog - UI functions are limited")
        -- Provide a direct clear option as fallback
        lootDatabase = {}
        mainScreenLoot = {}
        LootStats.destroyLootIcons()
        return
    end
    
    if confirmWindow then
        pcall(function() confirmWindow:destroy() end)
        confirmWindow = nil
        return
    end
    
    local function yesCallback()
        -- Clear all data
        lootDatabase = {}
        mainScreenLoot = {}
        LootStats.destroyLootIcons()
        
        -- Reset UI
        local monstersTab = lootStatsWindow:getChildById('monstersTab')
        local allLootTab = lootStatsWindow:getChildById('allLootTab')
        
        if monstersTab then pcall(function() monstersTab:setOn(false) end) end
        if allLootTab then pcall(function() allLootTab:setOn(false) end) end
        
        -- Hide creature view
        local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
        if panelCreatureView then
            pcall(function()
                panelCreatureView:setHeight(0)
                panelCreatureView:setVisible(false)
            end)
        end
        
        -- Clear item panel
        local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
        if itemsPanel then
            pcall(function() itemsPanel:destroyChildren() end)
        end
        
        -- Destroy confirmation window
        if confirmWindow then
            pcall(function() confirmWindow:destroy() end)
            confirmWindow = nil
        end
        
        LootStats.log("info", "All loot data cleared")
    end
    
    local function noCallback()
        if confirmWindow then
            pcall(function() confirmWindow:destroy() end)
            confirmWindow = nil
        end
    end
    
    -- Create confirmation window with proper error handling
    local success
    success, confirmWindow = pcall(function()
        return displayGeneralBox(
            tr('Clear Data'), 
            tr('Do you want to clear all loot statistics?\nThis action cannot be undone.'), 
            {
                { text=tr('Yes'), callback = yesCallback },
                { text=tr('No'), callback = noCallback }
            }, 
            yesCallback,
            noCallback
        )
    end)
    
    if success and confirmWindow then
        confirmWindow.onEscape = noCallback
    else
        -- If display box fails, just execute the action
        yesCallback()
    end
}

-- ====
-- Helper Functions
-- ====

function LootStats.formatNumber(value, decimals, cutDigits)
    decimals = decimals or 0
    cutDigits = cutDigits or false
    
    -- Handle integer values
    if value - math.floor(value) == 0 then
        return value
    end
    
    -- Split into integer and decimal parts
    local decimalPart = 0
    local intPart = 0
    
    if value > 1 then
        decimalPart = value - math.floor(value)
        intPart = math.floor(value)
    else
        decimalPart = value
    end
    
    -- Handle case where decimalPart is too small for log10
    if decimalPart <= 0 then
        return intPart
    end
    
    -- Determine decimal position with safe handling
    local firstNonZeroPos = 1
    pcall(function() firstNonZeroPos = math.floor(math.log10(decimalPart)) + 1 end)
    
    -- Calculate rounding
    local numberOfPoints
    if cutDigits then
        -- Safe handling of log10
        local logValue = 0
        pcall(function() logValue = math.floor(math.log10(value)) end)
        numberOfPoints = math.pow(10, decimals - logValue - 1)
    else
        numberOfPoints = math.pow(10, firstNonZeroPos * -1 + decimals)
    end
    
    local valuePow = decimalPart * numberOfPoints
    if valuePow - math.floor(valuePow) >= 0.5 then
        valuePow = math.ceil(valuePow)
    else
        valuePow = math.floor(valuePow)
    end
    
    return intPart + valuePow / numberOfPoints
}

-- ====
-- Options Panel Integration
-- ====

function LootStats.setupOptionsPanel()
    -- Check if client_options module is available
    if not modules.client_options then
        LootStats.log("warning", "client_options module not available")
        return
    end
    
    -- Get options panel function from different module access methods
    local optionsPanel
    
    -- Method 1: Try getPanel() function
    if type(modules.client_options.getPanel) == 'function' then
        local success
        success, optionsPanel = pcall(function() return modules.client_options.getPanel() end)
        
        if not success or not optionsPanel then
            -- Method 2: Direct module UI access
            success, optionsPanel = pcall(function() return modules.client_options.ui end)
            
            if not success or not optionsPanel then
                -- Method 3: Find by widget ID
                success, optionsPanel = pcall(function() return g_ui.getRootWidget():recursiveGetChildById('optionsTabContent') end)
            end
        end
    else
        -- Alternative method: Find by widget ID
        local success
        success, optionsPanel = pcall(function() return g_ui.getRootWidget():recursiveGetChildById('optionsTabContent') end)
    end
    
    if not optionsPanel then
        LootStats.log("warning", "Could not find options panel")
        return
    end
    
    -- Create a simple options panel directly
    local lootStatsOptions = g_ui.createWidget('Panel', nil)
    lootStatsOptions:setId('lootStatsPanel')
    lootStatsOptions:setLayout(UIVerticalLayout.create())
    lootStatsOptions:setHeight(300)
    
    -- Add title
    local titleLabel = g_ui.createWidget('Label', lootStatsOptions)
    titleLabel:setText('Loot Stats Settings')
    titleLabel:setMarginTop(10)
    titleLabel:setMarginBottom(10)
    
    -- Add show loot option
    local showLootCheckbox = g_ui.createWidget('CheckBox', lootStatsOptions)
    showLootCheckbox:setId('showLootOnScreen')
    showLootCheckbox:setText('Show loot on screen')
    showLootCheckbox:setChecked(settings.showLootOnScreen)
    showLootCheckbox.onCheckChange = function(widget, checked)
        LootStats.setShowLootOnScreen(checked)
    end
    
    -- Add amount option text
    local amountLabel = g_ui.createWidget('Label', lootStatsOptions)
    amountLabel:setText('Amount of loot on screen: ' .. settings.amountLootOnScreen)
    amountLabel:setMarginTop(10)
    
    -- Add amount slider
    local amountSlider = g_ui.createWidget('HorizontalScrollBar', lootStatsOptions)
    amountSlider:setId('amountLootOnScreen')
    amountSlider:setMinimum(1)
    amountSlider:setMaximum(20)
    amountSlider:setValue(settings.amountLootOnScreen)
    amountSlider.onValueChange = function(widget, value)
        settings.amountLootOnScreen = value
        amountLabel:setText('Amount of loot on screen: ' .. value)
        LootStats.setAmountLootOnScreen(value)
    end
    
    -- Add delay option text
    local delayLabel = g_ui.createWidget('Label', lootStatsOptions)
    delayLabel:setText('Time delay to delete loot from screen: ' .. settings.delayTimeLootOnScreen)
    delayLabel:setMarginTop(10)
    
    -- Add delay slider
    local delaySlider = g_ui.createWidget('HorizontalScrollBar', lootStatsOptions)
    delaySlider:setId('delayTimeLootOnScreen')
    delaySlider:setMinimum(500)
    delaySlider:setMaximum(10000)
    delaySlider:setStep(100)
    delaySlider:setValue(settings.delayTimeLootOnScreen)
    delaySlider.onValueChange = function(widget, value)
        settings.delayTimeLootOnScreen = value
        delayLabel:setText('Time delay to delete loot from screen: ' .. value)
        LootStats.setDelayTimeLootOnScreen(value)
    end
    
    -- Add ignore monster level option
    local ignoreMonsterCheckbox = g_ui.createWidget('CheckBox', lootStatsOptions)
    ignoreMonsterCheckbox:setId('ignoreMonsterLevelSystem')
    ignoreMonsterCheckbox:setText('Ignore monster level system')
    ignoreMonsterCheckbox:setChecked(settings.ignoreMonsterLevelSystem)
    ignoreMonsterCheckbox.onCheckChange = function(widget, checked)
        LootStats.setIgnoreMonsterLevelSystem(checked)
    end
    
    -- Add ignore dot option
    local ignoreDotCheckbox = g_ui.createWidget('CheckBox', lootStatsOptions)
    ignoreDotCheckbox:setId('ignoreLastSignWhenDot')
    ignoreDotCheckbox:setText('Ignore last sign when dot')
    ignoreDotCheckbox:setChecked(settings.ignoreLastSignWhenDot)
    ignoreDotCheckbox.onCheckChange = function(widget, checked)
        LootStats.setIgnoreLastSignWhenDot(checked)
    end
    
    -- Add clear data button
    local clearDataButton = g_ui.createWidget('Button', lootStatsOptions)
    clearDataButton:setId('clearData')
    clearDataButton:setText('Clear Data')
    clearDataButton:setMarginTop(20)
    clearDataButton.onClick = function()
        LootStats.confirmClearData()
    end
    
    -- Try all available methods to add the tab to options
    LootStats.optionsPanel = lootStatsOptions
    
    local added = false
    
    -- Method 1: addTab function
    if type(modules.client_options.addTab) == 'function' then
        local success = pcall(function()
            modules.client_options.addTab('Loot Stats', lootStatsOptions, '/images/game/loot_stats')
            added = true
        end)
    end
    
    -- Method 2: Try to use direct panel insertion
    if not added then
        local success = pcall(function()
            optionsPanel:addChild(lootStatsOptions)
            lootStatsOptions:setVisible(false)
            added = true
        end)
    end
    
    if not added then
        LootStats.log("warning", "Could not add options panel to client_options module")
    end
}

function LootStats.updateOptionsUI()
    if not LootStats.optionsPanel then return end
    
    -- Update all UI elements with current settings
    local showLootCheckbox = LootStats.optionsPanel:recursiveGetChildById('showLootOnScreen')
    if showLootCheckbox then
        pcall(function() showLootCheckbox:setChecked(settings.showLootOnScreen) end)
    end
    
    local amountSlider = LootStats.optionsPanel:recursiveGetChildById('amountLootOnScreen')
    if amountSlider then
        pcall(function() amountSlider:setValue(settings.amountLootOnScreen) end)
    end
    
    local delaySlider = LootStats.optionsPanel:recursiveGetChildById('delayTimeLootOnScreen')
    if delaySlider then
        pcall(function() delaySlider:setValue(settings.delayTimeLootOnScreen) end)
    end
    
    local ignoreMonsterCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreMonsterLevelSystem')
    if ignoreMonsterCheckbox then
        pcall(function() ignoreMonsterCheckbox:setChecked(settings.ignoreMonsterLevelSystem) end)
    end
    
    local ignoreDotCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreLastSignWhenDot')
    if ignoreDotCheckbox then
        pcall(function() ignoreDotCheckbox:setChecked(settings.ignoreLastSignWhenDot) end)
    end
}

-- ====
-- Module Initialization and Termination
-- ====

function LootStats.init()
    LootStats.log("info", "Initializing module")
    
    -- Load settings
    LootStats.loadSettings()
    
    -- Create styles
    LootStats.createStyles()
    
    -- Connect game events with error handling
    if g_game then
        pcall(function() 
            connect(g_game, {
                onGameStart = LootStats.onGameStart,
                onGameEnd = LootStats.onGameEnd,
                onTextMessage = LootStats.onTextMessage
            })
        end)
    else
        LootStats.log("warning", "g_game is not available. Game events will not be connected.")
    end
    
    -- Connect creature events if available
    if Creature then
        pcall(function() 
            connect(Creature, {
                onDeath = LootStats.onMonsterDeath
            })
        end)
    end
    
    -- Create module button in client_topmenu if available
    if hasSafeUI and modules.client_topmenu then
        pcall(function()
            lootStatsButton = modules.client_topmenu.addRightGameToggleButton(
                'lootStatsButton', 
                tr('Loot Stats'), 
                '/images/game/loot_stats', 
                function() LootStats.toggle() end
            )
            if lootStatsButton then
                lootStatsButton:setOn(false)
            end
        end)
    end
    
    -- Initialize if game already started
    if g_game and pcall(function() return g_game.isOnline() end) and g_game.isOnline() then
        LootStats.onGameStart()
    end
    
    -- Create options panel
    pcall(function() LootStats.setupOptionsPanel() end)
    
    -- Initialize widget cache
    if hasSafeUI then
        pcall(function() LootStats.initWidgetCache() end)
    end
    
    -- Initialize item database
    pcall(function() LootStats.initItemDatabase() end)
    
    LootStats.log("info", "Module initialization complete")
}

function LootStats.terminate()
    LootStats.log("info", "Terminating module")
    
    -- Save settings
    LootStats.saveSettings()
    
    -- Disconnect event handlers
    if g_game then
        pcall(function() 
            disconnect(g_game, {
                onGameStart = LootStats.onGameStart,
                onGameEnd = LootStats.onGameEnd,
                onTextMessage = LootStats.onTextMessage
            })
        end)
    end
    
    if Creature then
        pcall(function() 
            disconnect(Creature, {
                onDeath = LootStats.onMonsterDeath
            })
        end)
    end
    
    -- Clean up scheduled events
    LootStats.clearScheduledEvents()
    
    -- Clean up UI elements
    LootStats.destroyLootIcons()
    
    -- Destroy widget cache
    for _, widget in pairs(widgetCache) do
        if widget and not pcall(function() return widget:isDestroyed() end) and not widget:isDestroyed() then
            pcall(function() widget:destroy() end)
        end
    end
    widgetCache = {}
    
    -- Destroy main window
    if lootStatsWindow then
        pcall(function() lootStatsWindow:destroy() end)
        lootStatsWindow = nil
    end
    
    -- Destroy button
    if lootStatsButton then
        pcall(function() lootStatsButton:destroy() end)
        lootStatsButton = nil
    end
    
    -- Clear data
    lootDatabase = {}
    mainScreenLoot = {}
    activeIcons = {}
    scheduledEvents = {}
    uniqueIdCounter = 1
}

-- Return the module so it can be used
return LootStats