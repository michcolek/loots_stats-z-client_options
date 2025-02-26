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
    
    -- Check if required functions exist with pcall to avoid errors
    local hasStyleDefinedFn = pcall(function() return type(g_ui.isStyleDefined) == 'function' end)
    local canCreateStyle = pcall(function() return type(g_ui.createStyle) == 'function' end)
    
    if not (hasStyleDefinedFn and canCreateStyle) then
        LootStats.log("warning", "Some UI functions are missing. Limited functionality available.")
        hasSafeUI = false
        return
    end
    
    -- Create the LootIcon style programmatically
    local styleExists = pcall(function() return g_ui.isStyleDefined('LootIcon') end)
    if not styleExists or not g_ui.isStyleDefined('LootIcon') then
        -- First try to import from file
        local success = pcall(function() g_ui.importStyle('loot_icons') end)
        
        -- If that fails, create the style through code
        if not success then
            LootStats.log("info", "Creating LootIcon style programmatically")
            pcall(function()
                g_ui.createStyle([[
                LootIcon < UIItem
                  size: 32 32
                  virtual: true
                  phantom: false
                ]])
            end)
        end
    end
    
    -- Similarly create other needed styles
    styleExists = pcall(function() return g_ui.isStyleDefined('LootItemBox') and g_ui.isStyleDefined('LootMonsterBox') end)
    if not styleExists or not (g_ui.isStyleDefined('LootItemBox') and g_ui.isStyleDefined('LootMonsterBox')) then
        local success = pcall(function() g_ui.importStyle('loot_item_box') end)
        
        if not success then
            LootStats.log("info", "Creating item box styles programmatically")
            pcall(function()
                g_ui.createStyle([[
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
                ]])
            end)
            
            pcall(function()
                g_ui.createStyle([[
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
                ]])
            end)
        end
    end
    
    -- Create main window style if needed
    styleExists = pcall(function() return g_ui.isStyleDefined('MessageBoxWindow') end)
    if not styleExists or not g_ui.isStyleDefined('MessageBoxWindow') then
        local success = pcall(function() g_ui.importStyle('loot_stats') end)
        
        if not success then
            LootStats.log("info", "Creating main window style programmatically")
            pcall(function()
                g_ui.createStyle([[
                MainWindow
                  id: lootStatsMain
                  !text: tr('Loot Statistics')
                  size: 550 515
                  @onEscape: modules.loot_stats.toggle()
                ]])
            end)
        end
    end
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
end

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
    
    -- Check for critical dependencies
    if not g_ui then
        LootStats.log("error", "g_ui is not available. Module cannot function properly.")
        return
    end
    
    -- Create required styles first
    LootStats.createStyles()
    
    -- Load settings
    LootStats.loadSettings()
    
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
    
    -- Create UI elements only if we have safe UI access
    if hasSafeUI then
        pcall(function() LootStats.createLootStatsWindow() end)
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
    
    -- Create options panel if client_options is available
    if modules.client_options then
        pcall(function() LootStats.setupOptionsPanel() end)
    end
    
    -- Initialize widget cache (with error handling)
    if hasSafeUI then
        pcall(function() LootStats.initWidgetCache() end)
    end
    
    -- Initialize item database
    pcall(function() LootStats.initItemDatabase() end)
    
    LootStats.log("info", "Module initialization complete" .. (hasSafeUI and "" or " with limited functionality"))
    LootStats.log("info", "To use item database features, place items.xml and items.otb files in loot_stats/items_versions/[version]/")
end

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
end

function LootStats.clearScheduledEvents()
    for id, event in pairs(scheduledEvents) do
        if event then
            pcall(function() removeEvent(event) end)
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
end

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
    if not pcall(function() return type(g_things.getThingType) == 'function' end) then
        LootStats.log("warning", "getThingType function not available. Using default item IDs.")
        return
    end
    
    -- Constants for OTClient
    local ThingCategoryItem = 0 -- This seems to be the category for items in OTClient
    
    -- Attempt to cache common items by name
    LootStats.log("info", "Initializing item database cache")
    for id = 150, 5000 do -- Starting from 150 to avoid known invalid IDs
        local success, itemType = pcall(function() 
            return g_things.getThingType(id, ThingCategoryItem) 
        end)
        
        if success and itemType and not pcall(function() return itemType:isNull() end) and not itemType:isNull() then
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
    if not g_things or not pcall(function() return type(g_things.getThingType) == 'function' end) then
        return 3547
    end
    
    -- Constants for OTClient
    local ThingCategoryItem = 0
    
    -- Try to find by name (limit search range for performance)
    for id = 150, 5000 do
        local success, itemType = pcall(function() 
            return g_things.getThingType(id, ThingCategoryItem) 
        end)
        
        if success and itemType and not pcall(function() return itemType:isNull() end) and not itemType:isNull() then
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
    if hasSafeUI and modules.game_mainpanel and not lootStatsButton then
        pcall(function()
            lootStatsButton = modules.game_mainpanel.addToggleButton(
                'lootStatsButton', 
                tr('Loot Stats'), 
                '/images/game/loot_stats', 
                LootStats.toggle, 
                false, 
                5
            )
        end)
    end
    
    -- Update options panel if exists
    if LootStats.optionsPanel then
        LootStats.updateOptionsUI()
    end
    
    -- Make sure window is hidden when starting
    if lootStatsWindow and pcall(function() return lootStatsWindow:isVisible() end) and lootStatsWindow:isVisible() then
        pcall(function() lootStatsWindow:hide() end)
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
    
    -- Ensure item database is ready
    pcall(function() LootStats.initItemDatabase() end)
end

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
end

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
end

function LootStats.onTextMessage(mode, message)
    -- Check parameter validity
    if not message then return end
    
    -- Get the message mode with error handling
    local messageMode = mode
    if not pcall(function() return MessageModes.Loot end) then
        -- If MessageModes is not available, try to guess
        -- In some OTClient versions, loot messages have mode 20 or 22
        if messageMode ~= 20 and messageMode ~= 22 then
            return
        end
    else
        -- If we can check the proper mode, only process loot messages
        if messageMode ~= MessageModes.Loot then
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
end

-- ====
-- UI Management
-- ====

function LootStats.createLootStatsWindow()
    if lootStatsWindow then return end
    
    -- Create window (with error handling)
    local success, result = pcall(function() 
        return g_ui.displayUI('loot_stats')
    end)
    
    if not success or not result then
        -- Try alternative path
        success, result = pcall(function() 
            return g_ui.displayUI('/loot_stats/loot_stats')
        end)
    end
    
    if not success or not result then
        -- Create a simple window as fallback
        LootStats.log("warning", "Failed to load loot_stats UI, creating basic window")
        
        success, lootStatsWindow = pcall(function()
            local window = g_ui.createWidget('MainWindow', rootWidget)
            window:setId('lootStatsMain')
            window:setText('Loot Statistics')
            window:setSize({width = 400, height = 400})
            return window
        end)
        
        if not success then
            LootStats.log("error", "Failed to create basic window: " .. tostring(lootStatsWindow))
            return
        end
        
        -- Add close button
        pcall(function()
            local closeButton = g_ui.createWidget('Button', lootStatsWindow)
            closeButton:setId('closeButton')
            closeButton:setText('Close')
            closeButton:setWidth(60)
            closeButton:setAnchor(AnchorRight, 'parent', AnchorRight)
            closeButton:setAnchor(AnchorBottom, 'parent', AnchorBottom)
            closeButton.onClick = function() LootStats.toggle() end
        end)
        
        -- Add tabs
        pcall(function()
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
        end)
        
        pcall(function()
            local allLootTab = g_ui.createWidget('TabButton', lootStatsWindow)
            allLootTab:setId('allLootTab')
            allLootTab:setText('All Loot')
            allLootTab:setAnchor(AnchorLeft, 'monstersTab', AnchorRight)
            allLootTab:setAnchor(AnchorTop, 'parent', AnchorTop)
            allLootTab:setWidth(80)
            allLootTab.onMouseRelease = function(widget, mousePos, mouseButton)
                LootStats.showAllLootList(widget, mousePos, mouseButton)
            end
        end)
        
        -- Add items panel
        pcall(function()
            local panel = g_ui.createWidget('Panel', lootStatsWindow)
            panel:setId('itemsPanel')
            panel:setAnchor(AnchorLeft, 'parent', AnchorLeft)
            panel:setAnchor(AnchorRight, 'parent', AnchorRight)
            panel:setAnchor(AnchorTop, 'monstersTab', AnchorBottom)
            panel:setAnchor(AnchorBottom, 'closeButton', AnchorTop)
            panel:setMarginTop(10)
            panel:setMarginBottom(10)
        end)
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
    
    pcall(function() lootStatsWindow:hide() end)
end

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
end

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
                { text=tr('Yes'), callback=yesCallback },
                { text=tr('No'), callback=noCallback }
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
end

-- ====
-- Loot Display Functions
-- ====

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
        if icon and not pcall(function() return icon:isDestroyed() end) and not icon:isDestroyed() then
            pcall(function() icon:hide() end)
        end
    end
    activeIcons = {}
end

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
end

-- ====
-- Stats Display Functions
-- ====

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
end

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
end

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
end

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
end

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
end

-- ====
-- Options Panel Integration
-- ====

function LootStats.setupOptionsPanel()
    -- Check if the module already has a panel registered
    if not modules.client_options or type(modules.client_options.getPanel) ~= 'function' then
        return
    end
    
    local panel
    if not pcall(function() panel = modules.client_options.getPanel() end) or not panel then
        return
    end
    
    -- Try to use existing panel or create a new one
    LootStats.optionsPanel = panel:recursiveGetChildById('lootStatsPanel')
    
    if not LootStats.optionsPanel then
        -- Create a new panel via loadUI with error handling
        local success, result = pcall(function()
            return g_ui.loadUI('loot_options', panel)
        end)
        
        if not success then
            -- Try alternative path
            success, result = pcall(function()
                return g_ui.loadUI('/loot_stats/loot_options', panel)
            end)
        end
        
        if success and result then
            LootStats.optionsPanel = result
        else
            -- Create fallback panel manually
            LootStats.log("warning", "Failed to load options panel, creating fallback panel")
            
            local success
            success, LootStats.optionsPanel = pcall(function()
                local newPanel = g_ui.createWidget('Panel', panel)
                newPanel:setId('lootStatsPanel')
                newPanel:fill('parent')
                newPanel:setVisible(false)
                return newPanel
            end)
            
            if not success then
                LootStats.log("error", "Failed to create fallback panel: " .. tostring(LootStats.optionsPanel))
                return
            end
            
            -- Create basic settings widgets
            pcall(function()
                local titleLabel = g_ui.createWidget('Label', LootStats.optionsPanel)
                titleLabel:setText('Loot Stats Settings')
                titleLabel:setPosition({x = 50, y = 20})
            end)
            
            pcall(function()
                local showLootCheckbox = g_ui.createWidget('CheckBox', LootStats.optionsPanel)
                showLootCheckbox:setId('showLootOnScreen')
                showLootCheckbox:setText('Show loot on screen')
                showLootCheckbox:setPosition({x = 30, y = 60})
                showLootCheckbox.onCheckChange = function(widget, checked)
                    LootStats.setShowLootOnScreen(checked)
                end
            end)
            
            pcall(function()
                local clearDataButton = g_ui.createWidget('Button', LootStats.optionsPanel)
                clearDataButton:setId('clearData')
                clearDataButton:setText('Clear Data')
                clearDataButton:setPosition({x = 100, y = 120})
                clearDataButton.onClick = function()
                    LootStats.confirmClearData()
                end
            end)
        end
        
        -- Try to register the panel
        if modules.client_options.addTab then
            pcall(function()
                modules.client_options.addTab('Loot Stats', LootStats.optionsPanel, '/images/game/loot_stats')
            end)
        elseif modules.client_options.addButton then
            pcall(function()
                modules.client_options.addButton('Interface', 'Loot Stats', LootStats.optionsPanel)
            end)
        end
    end
    
    -- Make sure callbacks are properly connected
    local showLootCheckbox = LootStats.optionsPanel:recursiveGetChildById('showLootOnScreen')
    if showLootCheckbox then
        showLootCheckbox.onCheckChange = function(widget, checked)
            LootStats.setShowLootOnScreen(checked)
        end
    end
    
    local amountLootScrollBar = LootStats.optionsPanel:recursiveGetChildById('amountLootOnScreen')
    if amountLootScrollBar then
        local valueBar = amountLootScrollBar:recursiveGetChildById('valueBar')
        if valueBar then
            valueBar.onValueChange = function(widget, value)
                LootStats.setAmountLootOnScreen(value)
            end
        end
    end
    
    local delayLootScrollBar = LootStats.optionsPanel:recursiveGetChildById('delayTimeLootOnScreen')
    if delayLootScrollBar then
        local valueBar = delayLootScrollBar:recursiveGetChildById('valueBar')
        if valueBar then
            valueBar.onValueChange = function(widget, value)
                LootStats.setDelayTimeLootOnScreen(value)
            end
        end
    end
    
    local ignoreMonsterCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreMonsterLevelSystem')
    if ignoreMonsterCheckbox then
        ignoreMonsterCheckbox.onCheckChange = function(widget, checked)
            LootStats.setIgnoreMonsterLevelSystem(checked)
        end
    end
    
    local ignoreDotCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreLastSignWhenDot')
    if ignoreDotCheckbox then
        ignoreDotCheckbox.onCheckChange = function(widget, checked)
            LootStats.setIgnoreLastSignWhenDot(checked)
        end
    end
    
    local clearDataButton = LootStats.optionsPanel:recursiveGetChildById('clearData')
    if clearDataButton then
        clearDataButton.onClick = function()
            LootStats.confirmClearData()
        end
    end
    
    -- Update UI with current settings
    LootStats.updateOptionsUI()
end

function LootStats.updateOptionsUI()
    if not LootStats.optionsPanel then return end
    
    -- Update all UI elements with current settings
    local showLootCheckbox = LootStats.optionsPanel:recursiveGetChildById('showLootOnScreen')
    if showLootCheckbox then
        pcall(function() showLootCheckbox:setChecked(settings.showLootOnScreen) end)
    end
    
    local amountSlider = LootStats.optionsPanel:recursiveGetChildById('amountLootOnScreen')
    if amountSlider then
        local valueBar = amountSlider:recursiveGetChildById('valueBar')
        if valueBar then
            pcall(function() valueBar:setValue(settings.amountLootOnScreen) end)
        end
        pcall(function() amountSlider:setText('The amount of loot on the screen: ' .. settings.amountLootOnScreen) end)
    end
    
    local delaySlider = LootStats.optionsPanel:recursiveGetChildById('delayTimeLootOnScreen')
    if delaySlider then
        local valueBar = delaySlider:recursiveGetChildById('valueBar')
        if valueBar then
            pcall(function() valueBar:setValue(settings.delayTimeLootOnScreen) end)
        end
        pcall(function() delaySlider:setText('Time delay to delete loot from screen: ' .. settings.delayTimeLootOnScreen) end)
    end
    
    local ignoreMonsterCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreMonsterLevelSystem')
    if ignoreMonsterCheckbox then
        pcall(function() ignoreMonsterCheckbox:setChecked(settings.ignoreMonsterLevelSystem) end)
    end
    
    local ignoreDotCheckbox = LootStats.optionsPanel:recursiveGetChildById('ignoreLastSignWhenDot')
    if ignoreDotCheckbox then
        pcall(function() ignoreDotCheckbox:setChecked(settings.ignoreLastSignWhenDot) end)
    end
end

-- Module return to make functions accessible
return LootStats