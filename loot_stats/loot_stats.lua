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
    end
end

-- ====
-- Settings Management
-- ====

function LootStats.loadSettings()
    LootStats.log("info", "Loading settings")
    
    -- Load settings from global settings
    for key, defaultValue in pairs(DEFAULT_SETTINGS) do
        local settingKey = 'loot_stats_' .. key
        local value = g_settings.get(settingKey)
        
        if value ~= nil then
            if type(defaultValue) == 'boolean' then
                settings[key] = g_settings.getBoolean(settingKey, defaultValue)
            elseif type(defaultValue) == 'number' then
                settings[key] = g_settings.getNumber(settingKey, defaultValue)
            else
                settings[key] = g_settings.getString(settingKey, defaultValue)
            end
        else
            settings[key] = defaultValue
        end
    end
    
    -- If client_options module exists and has current settings, use those
    if modules.client_options and modules.client_options.getOption then
        for key, _ in pairs(settings) do
            local optionValue = modules.client_options.getOption(key)
            if optionValue ~= nil then
                settings[key] = optionValue
            end
        end
    end
end

function LootStats.saveSettings()
    -- Save settings to global settings
    for key, value in pairs(settings) do
        g_settings.set('loot_stats_' .. key, value)
    end
end

-- ====
-- Settings Getters and Setters
-- ====

function LootStats.getSetting(key)
    return settings[key]
end

function LootStats.setSetting(key, value)
    if settings[key] == value then return end
    
    settings[key] = value
    g_settings.set('loot_stats_' .. key, value)
    
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
end

-- Exposed setter functions (for Options Panel)
function LootStats.setShowLootOnScreen(value)
    LootStats.setSetting('showLootOnScreen', value)
end

function LootStats.setAmountLootOnScreen(value)
    value = tonumber(value) or 5
    value = math.max(1, math.min(20, value))
    LootStats.setSetting('amountLootOnScreen', value)
end

function LootStats.setDelayTimeLootOnScreen(value)
    value = tonumber(value) or 2000
    value = math.max(500, math.min(10000, value))
    LootStats.setSetting('delayTimeLootOnScreen', value)
end

function LootStats.setIgnoreMonsterLevelSystem(value)
    LootStats.setSetting('ignoreMonsterLevelSystem', value)
end

function LootStats.setIgnoreLastSignWhenDot(value)
    LootStats.setSetting('ignoreLastSignWhenDot', value)
end

-- ====
-- Module Initialization and Termination
-- ====

function LootStats.init()
    LootStats.log("info", "Initializing module")
    
    -- Import UI styles with error handling - first try the combined file
    local success = pcall(function() 
        g_ui.importStyle('loot_stats') 
    end)
    
    -- If combined file fails, try loading individual files
    if not success then
        -- Try loading styles individually
        pcall(function() g_ui.importStyle('loot_icons') end)
        pcall(function() g_ui.importStyle('loot_item_box') end)
    end
    
    -- Load settings
    LootStats.loadSettings()
    
    -- Connect game events
    connect(g_game, {
        onGameStart = LootStats.onGameStart,
        onGameEnd = LootStats.onGameEnd,
        onTextMessage = LootStats.onTextMessage
    })
    
    -- Connect creature events
    connect(Creature, {
        onDeath = LootStats.onMonsterDeath
    })
    
    -- Create UI elements
    LootStats.createLootStatsWindow()
    
    -- Create module button in client_topmenu if available
    if modules.client_topmenu then
        lootStatsButton = modules.client_topmenu.addRightGameToggleButton(
            'lootStatsButton', 
            tr('Loot Stats'), 
            '/images/game/loot_stats', 
            function() LootStats.toggle() end
        )
        lootStatsButton:setOn(false)
    end
    
    -- Initialize if game already started
    if g_game.isOnline() then
        LootStats.onGameStart()
    end
    
    -- Create options panel if client_options is available
    if modules.client_options then
        LootStats.setupOptionsPanel()
    end
    
    -- Initialize widget cache
    LootStats.initWidgetCache()
    
    -- Initialize item database
    LootStats.initItemDatabase()
end
    -- Create UI elements
    function LootStats.createLootStatsWindow()
        if lootStatsWindow then return end
        
        -- Create a basic window if the template fails to load
        local success, result = pcall(function() 
            return g_ui.displayUI('loot_stats')
        end)
        
        if not success or not result then
            -- Create a simple window as fallback
            LootStats.log("warning", "Failed to load loot_stats UI, creating basic window")
            lootStatsWindow = g_ui.createWidget('MainWindow', rootWidget)
            lootStatsWindow:setId('lootStatsMain')
            lootStatsWindow:setText('Loot Statistics')
            lootStatsWindow:setSize({width = 400, height = 400})
            
            -- Add close button
            local closeButton = g_ui.createWidget('Button', lootStatsWindow)
            closeButton:setId('closeButton')
            closeButton:setText('Close')
            closeButton:setWidth(60)
            closeButton:setAnchor(AnchorRight, 'parent', AnchorRight)
            closeButton:setAnchor(AnchorBottom, 'parent', AnchorBottom)
            closeButton.onClick = function() LootStats.toggle() end
            
            -- Add tabs
            local monstersTab = g_ui.createWidget('TabButton', lootStatsWindow)
            monstersTab:setId('monstersTab')
            monstersTab:setText('Monsters')
            monstersTab:setChecked(true)
            monstersTab:setAnchor(AnchorLeft, 'parent', AnchorLeft)
            monstersTab:setAnchor(AnchorTop, 'parent', AnchorTop)
            monstersTab:setWidth(80)
            monstersTab.onMouseRelease = function(widget, mousePos, mouseButton)
                LootStats.showMonstersList(widget, mousePos, mouseButton)
            end
            
            local allLootTab = g_ui.createWidget('TabButton', lootStatsWindow)
            allLootTab:setId('allLootTab')
            allLootTab:setText('All Loot')
            allLootTab:setAnchor(AnchorLeft, 'monstersTab', AnchorRight)
            allLootTab:setAnchor(AnchorTop, 'parent', AnchorTop)
            allLootTab:setWidth(80)
            allLootTab.onMouseRelease = function(widget, mousePos, mouseButton)
                LootStats.showAllLootList(widget, mousePos, mouseButton)
            end
            
            -- Add items panel
            local panel = g_ui.createWidget('Panel', lootStatsWindow)
            panel:setId('itemsPanel')
            panel:setAnchor(AnchorLeft, 'parent', AnchorLeft)
            panel:setAnchor(AnchorRight, 'parent', AnchorRight)
            panel:setAnchor(AnchorTop, 'monstersTab', AnchorBottom)
            panel:setAnchor(AnchorBottom, 'closeButton', AnchorTop)
            panel:setMarginTop(10)
            panel:setMarginBottom(10)
        else
            lootStatsWindow = result
        
            -- Connect tab buttons
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
            
            -- Connect close button
            local closeButton = lootStatsWindow:getChildById('closeButton')
            if closeButton then
                closeButton.onClick = function() LootStats.toggle() end
            end
            
            -- Connect clear data button if it exists
            local clearButton = lootStatsWindow:getChildById('clearButton')
            if clearButton then
                clearButton.onClick = function() LootStats.confirmClearData() end
            end
        end
        
        lootStatsWindow:hide()
    end

function LootStats.terminate()
    LootStats.log("info", "Terminating module")
    
    -- Save settings
    LootStats.saveSettings()
    
    -- Disconnect event handlers
    disconnect(g_game, {
        onGameStart = LootStats.onGameStart,
        onGameEnd = LootStats.onGameEnd,
        onTextMessage = LootStats.onTextMessage
    })
    
    disconnect(Creature, {
        onDeath = LootStats.onMonsterDeath
    })
    
    -- Clean up scheduled events
    LootStats.clearScheduledEvents()
    
    -- Clean up UI elements
    LootStats.destroyLootIcons()
    
    -- Destroy widget cache
    for _, widget in pairs(widgetCache) do
        if widget and not widget:isDestroyed() then
            widget:destroy()
        end
    end
    widgetCache = {}
    
    -- Destroy main window
    if lootStatsWindow then
        lootStatsWindow:destroy()
        lootStatsWindow = nil
    end
    
    -- Destroy button
    if lootStatsButton then
        lootStatsButton:destroy()
        lootStatsButton = nil
    end
    
    -- Clear data
    lootDatabase = {}
    mainScreenLoot = {}
    activeIcons = {}
    scheduledEvents = {}
    uniqueIdCounter = 1
end

function LootStats.clearScheduledEvents()
    for id, event in pairs(scheduledEvents) do
        if event then
            removeEvent(event)
        end
    end
    scheduledEvents = {}
end

-- ====
-- Widget Cache Management
-- ====

function LootStats.initWidgetCache()
    -- Clean existing cache
    for _, widget in pairs(widgetCache) do
        if widget and not widget:isDestroyed() then
            widget:destroy()
        end
    end
    
    widgetCache = {}
    
    -- Pre-create widgets for cache
    local mapPanel = modules.game_interface.getMapPanel()
    if mapPanel then
        for i = 1, 20 do
            local widget = g_ui.createWidget('LootIcon', mapPanel)
            widget:setId('lootStatsIcon' .. i)
            widget:hide()
            table.insert(widgetCache, widget)
        end
    end
end

function LootStats.getIconFromCache()
    -- Find a hidden widget in the cache
    for _, widget in pairs(widgetCache) do
        if not widget:isVisible() then
            return widget
        end
    end
    
    -- Create a new widget if necessary
    local mapPanel = modules.game_interface.getMapPanel()
    if mapPanel then
        local widget = g_ui.createWidget('LootIcon', mapPanel)
        widget:setId('lootStatsIcon' .. (#widgetCache + 1))
        table.insert(widgetCache, widget)
        return widget
    end
    
    return nil
end

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
    if not g_things.getThingType then
        LootStats.log("warning", "getThingType function not available. Using default item IDs.")
        return
    end
    
    -- Constants for OTClient
    local ThingCategoryItem = 0 -- This seems to be the category for items in OTClient
    
    -- Attempt to cache common items by name
    LootStats.log("info", "Initializing item database cache")
    for id = 100, 5000 do -- Limiting to a reasonable range for performance
        local success, itemType = pcall(function() 
            return g_things.getThingType(id, ThingCategoryItem) 
        end)
        
        if success and itemType and not itemType:isNull() then
            local success, name = pcall(function() return itemType:getName():lower() end)
            if success and name and name ~= "" then
                itemDatabase[name] = id
            end
        end
    end
    LootStats.log("info", "Item database initialized with " .. table.size(itemDatabase) .. " items")
end

function LootStats.getItemClientId(itemName)
    if not itemName then
        return 3547 -- Default item ID (paper)
    end
    
    local nameLower = itemName:lower()
    
    -- Check cache first
    if itemDatabase[nameLower] then
        return itemDatabase[nameLower]
    end
    
    -- If g_things is not available, return default
    if not g_things or not g_things.getThingType then
        return 3547
    end
    
    -- Constants for OTClient
    local ThingCategoryItem = 0
    
    -- Try to find by name (limit search range for performance)
    for id = 100, 5000 do
        local success, itemType = pcall(function() 
            return g_things.getThingType(id, ThingCategoryItem) 
        end)
        
        if success and itemType and not itemType:isNull() then
            local success, name = pcall(function() return itemType:getName():lower() end)
            if success and name == nameLower then
                -- Cache for future use
                itemDatabase[nameLower] = id
                return id
            end
        end
    end
    
    -- Cache this item as not found to avoid future lookups
    itemDatabase[nameLower] = 3547
    return 3547 -- Default item ID (paper)
end

-- ====
-- Game Event Handlers
-- ====

function LootStats.onGameStart()
    LootStats.log("info", "Game started")
    
    -- Set up main panel button if not already created
    if modules.game_mainpanel and not lootStatsButton then
        lootStatsButton = modules.game_mainpanel.addToggleButton(
            'lootStatsButton', 
            tr('Loot Stats'), 
            '/images/game/loot_stats', 
            LootStats.toggle, 
            false, 
            5
        )
    end
    
    -- Update options panel if exists
    if LootStats.optionsPanel then
        LootStats.updateOptionsUI()
    end
    
    -- Make sure window is hidden when starting
    if lootStatsWindow and lootStatsWindow:isVisible() then
        lootStatsWindow:hide()
    end
    
    -- Clear any existing loot icons
    LootStats.destroyLootIcons()
    
    -- Reset data structures
    mainScreenLoot = {}
    uniqueIdCounter = 1
    
    -- Ensure widget cache is ready
    LootStats.initWidgetCache()
    
    -- Ensure item database is ready
    LootStats.initItemDatabase()
end

function LootStats.onGameEnd()
    LootStats.log("info", "Game ended")
    
    -- Save settings
    LootStats.saveSettings()
    
    -- Hide window
    if lootStatsWindow and lootStatsWindow:isVisible() then
        lootStatsWindow:hide()
    end
    
    -- Clean up loot icons
    LootStats.destroyLootIcons()
    
    -- Reset button state
    if lootStatsButton then
        lootStatsButton:setOn(false)
    end
    
    -- Clear active events
    LootStats.clearScheduledEvents()
end

function LootStats.onMonsterDeath(creature)
    -- Record monster outfit for later display
    if not creature then return end
    
    -- Get creature name
    local name = creature:getName()
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
            lootDatabase[lowerName].outfit = creature:getOutfit()
        end
        
        -- Remove event from scheduledEvents
        scheduledEvents[eventId] = nil
    end, 200)
end

function LootStats.onTextMessage(mode, message)
    -- Only process loot messages
    if not message or mode ~= MessageModes.Loot then return end
    
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
    if settings.showLootOnScreen then
        LootStats.addLootToScreen(lootToScreen)
    end
    
    -- Update UI if visible
    if lootStatsWindow and lootStatsWindow:isVisible() then
        LootStats.updateDisplayedList()
    end
end

-- ====
-- UI Management
-- ====

function LootStats.createLootStatsWindow()
    if lootStatsWindow then return end
    
    -- Create a basic window if the template fails to load
    local success, result = pcall(function() 
        return g_ui.displayUI('loot_stats')
    end)
    
    if not success or not result then
        -- Create a simple window as fallback
        LootStats.log("warning", "Failed to load loot_stats UI, creating basic window")
        lootStatsWindow = g_ui.createWidget('MainWindow', rootWidget)
        lootStatsWindow:setId('lootStatsMain')
        lootStatsWindow:setText('Loot Statistics')
        lootStatsWindow:setSize({width = 400, height = 400})
        
        -- Add close button
        local closeButton = g_ui.createWidget('Button', lootStatsWindow)
        closeButton:setId('closeButton')
        closeButton:setText('Close')
        closeButton:setWidth(60)
        closeButton:setAnchor(AnchorRight, 'parent', AnchorRight)
        closeButton:setAnchor(AnchorBottom, 'parent', AnchorBottom)
        closeButton.onClick = function() LootStats.toggle() end
        
        -- Add tabs
        local monstersTab = g_ui.createWidget('TabButton', lootStatsWindow)
        monstersTab:setId('monstersTab')
        monstersTab:setText('Monsters')
        monstersTab:setChecked(true)
        monstersTab:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        monstersTab:setAnchor(AnchorTop, 'parent', AnchorTop)
        monstersTab:setWidth(80)
        monstersTab.onMouseRelease = function(widget, mousePos, mouseButton)
            LootStats.showMonstersList(widget, mousePos, mouseButton)
        end
        
        local allLootTab = g_ui.createWidget('TabButton', lootStatsWindow)
        allLootTab:setId('allLootTab')
        allLootTab:setText('All Loot')
        allLootTab:setAnchor(AnchorLeft, 'monstersTab', AnchorRight)
        allLootTab:setAnchor(AnchorTop, 'parent', AnchorTop)
        allLootTab:setWidth(80)
        allLootTab.onMouseRelease = function(widget, mousePos, mouseButton)
            LootStats.showAllLootList(widget, mousePos, mouseButton)
        end
        
        -- Add items panel
        local panel = g_ui.createWidget('Panel', lootStatsWindow)
        panel:setId('itemsPanel')
        panel:setAnchor(AnchorLeft, 'parent', AnchorLeft)
        panel:setAnchor(AnchorRight, 'parent', AnchorRight)
        panel:setAnchor(AnchorTop, 'monstersTab', AnchorBottom)
        panel:setAnchor(AnchorBottom, 'closeButton', AnchorTop)
        panel:setMarginTop(10)
        panel:setMarginBottom(10)
    else
        lootStatsWindow = result
    
        -- Connect tab buttons
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
        
        -- Connect close button
        local closeButton = lootStatsWindow:getChildById('closeButton')
        if closeButton then
            closeButton.onClick = function() LootStats.toggle() end
        end
        
        -- Connect clear data button if it exists
        local clearButton = lootStatsWindow:getChildById('clearButton')
        if clearButton then
            clearButton.onClick = function() LootStats.confirmClearData() end
        end
    end
    
    lootStatsWindow:hide()
end

function LootStats.toggle()
    if not lootStatsWindow then
        LootStats.createLootStatsWindow()
    end
    
    if lootStatsWindow:isVisible() then
        lootStatsWindow:hide()
        if lootStatsButton then
            lootStatsButton:setOn(false)
        end
    else
        lootStatsWindow:show()
        lootStatsWindow:raise()
        lootStatsWindow:focus()
        if lootStatsButton then
            lootStatsButton:setOn(true)
        end
        LootStats.updateDisplayedList()
    end
end

function LootStats.confirmClearData()
    if confirmWindow then
        confirmWindow:destroy()
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
        
        if monstersTab then monstersTab:setOn(false) end
        if allLootTab then allLootTab:setOn(false) end
        
        -- Hide creature view
        local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
        if panelCreatureView then
            panelCreatureView:setHeight(0)
            panelCreatureView:setVisible(false)
        end
        
        -- Clear item panel
        local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
        if itemsPanel then
            itemsPanel:destroyChildren()
        end
        
        -- Destroy confirmation window
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        
        LootStats.log("info", "All loot data cleared")
    end
    
    local function noCallback()
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
    end
    
    -- Create confirmation window
    confirmWindow = displayGeneralBox(
        tr('Clear Data'), 
        tr('Do you want to clear all loot statistics?\nThis action cannot be undone.'), 
        {
            { text=tr('Yes'), callback=yesCallback },
            { text=tr('No'), callback=noCallback }
        }, 
        yesCallback,
        noCallback
    )
    
    confirmWindow.onEscape = noCallback
end

-- ====
-- Loot Display Functions
-- ====

function LootStats.addLootToScreen(lootItems)
    if not lootItems then return end
    
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
    scheduledEvents[id] = scheduleEvent(function()
        LootStats.removeLootFromScreen(id)
        scheduledEvents[id] = nil
    end, settings.delayTimeLootOnScreen)
    
    -- Update the display
    LootStats.refreshLootDisplay()
end

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
end

function LootStats.destroyLootIcons()
    -- Hide all active icons
    for _, icon in pairs(activeIcons) do
        if icon and not icon:isDestroyed() then
            icon:hide()
        end
    end
    activeIcons = {}
end

function LootStats.refreshLootDisplay()
    -- Clean up existing icons
    LootStats.destroyLootIcons()
    
    -- If disabled or no game interface, exit
    if not settings.showLootOnScreen or not modules.game_interface then
        return
    end
    
    -- Get map panel for placement
    local mapPanel = modules.game_interface.getMapPanel()
    if not mapPanel then return end
    
    -- Calculate position based on top menu
    local yOffset = 0
    if modules.client_topmenu then
        local topMenu = modules.client_topmenu.getTopMenu()
        if topMenu and topMenu:isVisible() then
            yOffset = topMenu:getHeight()
        end
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
                    icon:setItemId(clientId)
                    if itemData.count > 1 then
                        icon:setItemCount(itemData.count)
                    else
                        icon:setItemCount(1)
                    end
                    
                    -- Position icon and make visible
                    icon:setPosition({x = rowX, y = rowY})
                    icon:show()
                    
                    -- Add to active icons list
                    table.insert(activeIcons, icon)
                    
                    rowX = rowX + 32
                end
                
                ::nextItem::
            end
        end
        
        ::continue::
    end
end

-- ====
-- Stats Display Functions
-- ====

function LootStats.updateDisplayedList()
    -- Skip if window not visible
    if not lootStatsWindow or not lootStatsWindow:isVisible() then
        return
    end
    
    -- Check which tab is active
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    
    if monstersTab and monstersTab:isOn() then
        LootStats.displayMonstersList()
    elseif allLootTab and allLootTab:isOn() then
        LootStats.displayAllLootList()
    end
end

function LootStats.showMonstersList(widget, mousePos, mouseButton)
    if mouseButton ~= MouseLeftButton then return end
    
    -- Update tab state
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    if allLootTab then allLootTab:setOn(false) end
    widget:setOn(true)
    
    -- Hide creature view panel
    local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
    if panelCreatureView then
        panelCreatureView:setHeight(0)
        panelCreatureView:setVisible(false)
    end
    
    -- Show monster list
    LootStats.displayMonstersList()
end

function LootStats.showAllLootList(widget, mousePos, mouseButton)
    if mouseButton ~= MouseLeftButton then return end
    
    -- Update tab state
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    if monstersTab then monstersTab:setOn(false) end
    widget:setOn(true)
    
    -- Hide creature view panel
    local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
    if panelCreatureView then
        panelCreatureView:setHeight(0)
        panelCreatureView:setVisible(false)
    end
    
    -- Show all loot list
    LootStats.displayAllLootList()
end

function LootStats.displayMonstersList()
    local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
    if not itemsPanel then return end
    
    -- Clear existing items
    itemsPanel:destroyChildren()
    
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
            
            -- Set creature image
            local creatureWidget = w:getChildById('creature')
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
            
            return w
        end)
        
        if not success then
            LootStats.log("error", "Failed to create monster widget: " .. tostring(widget))
            goto continue
        end
        
        -- Connect click event
        widget.onMouseRelease = function(w, mousePos, mouseButton)
            if mouseButton == MouseLeftButton then
                LootStats.selectMonster(w)
            end
        end
        
        ::continue::
    end
end

function LootStats.selectMonster(widget)
    if not widget then return end
    
    -- Update tab state
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    
    if monstersTab then monstersTab:setOn(false) end
    if allLootTab then allLootTab:setOn(false) end
    
    -- Show creature view panel
    local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
    if not panelCreatureView then return end
    
    panelCreatureView:setHeight(40)
    panelCreatureView:setVisible(true)
    
    -- Copy creature to panel
    local creatureView = panelCreatureView:getChildById('creatureView')
    local creatureWidget = widget:getChildById('creature')
    
    if creatureView and creatureWidget then
        creatureView:setCreature(creatureWidget:getCreature())
    end
    
    -- Set text info
    local textView = panelCreatureView:getChildById('textCreatureView')
    local textWidget = widget:getChildById('text')
    
    if textView and textWidget then
        textView:setText(textWidget:getText())
    end
    
    -- Extract monster name from text
    local monsterName = ""
    local text = textWidget:getText()
    for word in string.gmatch(text, '([^'..'\n'..']+)') do
        monsterName = word
        break
    end
    
    -- Show monster loot
    LootStats.displayMonsterLoot(monsterName)
end

function LootStats.displayMonsterLoot(monsterName)
    LootStats.displayLootList(string.lower(monsterName))
end

function LootStats.displayAllLootList()
    LootStats.displayLootList("*all")
end

function LootStats.displayLootList(monsterName)
    local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
    if not itemsPanel then return end
    
    -- Clear existing items
    itemsPanel:destroyChildren()
    
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
        local itemWidget = widget:getChildById('item')
        if itemWidget then
            local clientId = LootStats.getItemClientId(itemName)
            local item = Item.create(clientId)
            
            if itemInfo.plural and itemInfo.count > 1 then
                item:setCount(math.min(itemInfo.count, 100))
            end
            
            itemWidget:setItem(item)
        end
        
        ::continue::
    end
end

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
    
    -- Determine decimal position
    local firstNonZeroPos = math.floor(math.log10(decimalPart)) + 1
    
    -- Calculate rounding
    local numberOfPoints
    if cutDigits then
        numberOfPoints = math.pow(10, decimals - math.floor(math.log10(value)) - 1)
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
end

-- ====
-- Options Panel Integration
-- ====

function LootStats.setupOptionsPanel()
    -- Check if the module already has a panel registered
    if not modules.client_options or not modules.client_options.getPanel then
        return
    end
    
    -- First try to find an existing panel
    LootStats.optionsPanel = modules.client_options.getPanel():recursiveGetChildById('lootStatsPanel')
    
    -- If panel doesn't exist, try to create it
    if not LootStats.optionsPanel then
        -- Try to load from the options file
        local success = pcall(function() 
            LootStats.optionsPanel = g_ui.loadUI('loot_options', modules.client_options.getPanel())
        end)
        
        -- If loading failed, create panel manually
        if not success or not LootStats.optionsPanel then
            LootStats.log("warning", "Failed to load loot_options UI, creating basic options panel")
            
            local panel = g_ui.createWidget('Panel', modules.client_options.getPanel())
            panel:setId('lootStatsPanel')
            panel:setLayout(UIVerticalLayout.create(panel))
            panel:setVisible(false)
            
            local titleLabel = g_ui.createWidget('Label', panel)
            titleLabel:setText('Loot Stats Settings')
            titleLabel:setAlign(AlignCenter)
            
            local showLootCheckbox = g_ui.createWidget('OptionCheckBox', panel)
            showLootCheckbox:setId('showLootOnScreen')
            showLootCheckbox:setText('Show the loot on the screen')
            showLootCheckbox.onCheckChange = function(widget, checked)
                LootStats.setShowLootOnScreen(checked)
            end
            
            local clearDataButton = g_ui.createWidget('Button', panel)
            clearDataButton:setId('clearData')
            clearDataButton:setText('Clear Data')
            clearDataButton.onClick = function()
                LootStats.confirmClearData()
            end
            
            LootStats.optionsPanel = panel
        end
    end
    
    -- Make sure the loot stats category exists
    if modules.client_options.addTab then
        pcall(function() 
            modules.client_options.addTab('Loot Stats', LootStats.optionsPanel, '/images/game/loot_stats')
        end)
    end
    
    -- Connect UI elements to settings
    LootStats.updateOptionsUI()
end

-- Update the options tab in client_options module
function LootStats.updateOptionsUI()
    if not LootStats.optionsPanel then return end
    
    -- Update all UI elements with current settings
    local showLootCheckbox = LootStats.optionsPanel:recursiveGetChildById('showLootOnScreen')
    if showLootCheckbox then
        showLootCheckbox:setChecked(settings.showLootOnScreen)
    end
    
    local amountSlider = LootStats.optionsPanel:recursiveGetChildById('amountLootOnScreen')
    if amountSlider then
        local valueBar = amountSlider:recursiveGetChildById('valueBar')
        if valueBar then
            valueBar:setValue(settings.amountLootOnScreen)
        end
        amountSlider:setText('The amount of loot on the screen: ' .. settings.amountLootOnScreen)
    end
    
    local delaySlider = LootStats.optionsPanel:recursiveGetChildById('delayTimeLootOnScreen')
    if delaySlider then
        local valueBar = delaySlider:recursiveGetChildById('valueBar')
        if valueBar then
            valueBar:setValue(settings.delayTimeLootOnScreen)
        end
        delaySlider:setText('Time delay to delete loot from screen: ' .. settings.delayTimeLootOnScreen)
    end
    
    local ignoreMonsterCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreMonsterLevelSystem')
    if ignoreMonsterCheckbox then
        ignoreMonsterCheckbox:setChecked(settings.ignoreMonsterLevelSystem)
    end
    
    local ignoreDotCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreLastSignWhenDot')
    if ignoreDotCheckbox then
        ignoreDotCheckbox:setChecked(settings.ignoreLastSignWhenDot)
    end
end
function LootStats.updateOptionsUI()
    if not LootStats.optionsPanel then return end
    
    -- Update all UI elements with current settings
    local showLootCheckbox = LootStats.optionsPanel:recursiveGetChildById('showLootOnScreen')
    if showLootCheckbox then
        showLootCheckbox:setChecked(settings.showLootOnScreen)
    end
    
    local amountSlider = LootStats.optionsPanel:recursiveGetChildById('amountLootOnScreen')
    if amountSlider then
        local valueBar = amountSlider:recursiveGetChildById('valueBar')
        if valueBar then
            valueBar:setValue(settings.amountLootOnScreen)
        end
        amountSlider:setText('The amount of loot on the screen: ' .. settings.amountLootOnScreen)
    end
    
    local delaySlider = LootStats.optionsPanel:recursiveGetChildById('delayTimeLootOnScreen')
    if delaySlider then
        local valueBar = delaySlider:recursiveGetChildById('valueBar')
        if valueBar then
            valueBar:setValue(settings.delayTimeLootOnScreen)
        end
        delaySlider:setText('Time delay to delete loot from screen: ' .. settings.delayTimeLootOnScreen)
    end
    
    local ignoreMonsterCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreMonsterLevelSystem')
    if ignoreMonsterCheckbox then
        ignoreMonsterCheckbox:setChecked(settings.ignoreMonsterLevelSystem)
    end
    
    local ignoreDotCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreLastSignWhenDot')
    if ignoreDotCheckbox then
        ignoreDotCheckbox:setChecked(settings.ignoreLastSignWhenDot)
    end
end

-- Module return to make functions accessible
return LootStats