-- loot_stats.lua - Module for tracking and displaying loot statistics
-- Author: Original by EgzoT, updated for OTClient Mehah

-- Module namespace
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

-- Nowa funkcja do uzyskiwania dostępu do ustawień (dla modułu opcji)
function LootStats.getSettings()
    return settings
end

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
    if modules.client_options and optionsPanel then
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
    
    -- Create required styles
    pcall(function() 
        g_ui.importStyle('loot_icons')
        g_ui.importStyle('loot_item_box')
    end)
    
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
    
    -- Create UI elements
    pcall(function() LootStats.createLootStatsWindow() end)
    
    -- Create module button in game_mainpanel if available
    if modules.game_mainpanel then
        pcall(function()
            lootStatsButton = modules.game_mainpanel.addToggleButton(
                'lootStatsButton', 
                tr('Loot Stats'), 
                '/images/game/loot_stats', 
                function() LootStats.toggle() end,
                false,
                5
            )
        end)
    end
    
    -- Initialize if game already started
    if g_game and g_game.isOnline() then
        LootStats.onGameStart()
    end
    
    -- Initialize widget cache
    pcall(function() LootStats.initWidgetCache() end)
    
    -- Initialize item database
    pcall(function() LootStats.initItemDatabase() end)
    
    LootStats.log("info", "Module initialization complete")
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
        end
    end
end

function LootStats.getIconFromCache()
    -- Find a hidden widget in the cache
    for _, widget in pairs(widgetCache) do
        if widget and not widget:isDestroyed() and not widget:isVisible() then
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
    if not pcall(function() return type(g_things.getItemType) == 'function' end) then
        LootStats.log("warning", "getItemType function not available. Using default item IDs.")
        return
    end
    
    -- Attempt to cache common items by name
    LootStats.log("info", "Initializing item database cache")
    for id = 100, 20000 do
        local success, itemType = pcall(function() 
            return g_things.getItemType(id) 
        end)
        
        if success and itemType and not pcall(function() return itemType:isNull() end) and not itemType:isNull() then
            local success, name = pcall(function() return itemType:getName():lower() end)
            if success and name and name ~= "" then
                itemDatabase[name] = id
            end
        end
    end
    LootStats.log("info", "Item database initialized")
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
    if not g_things or not pcall(function() return type(g_things.getItemType) == 'function' end) then
        return 3547
    end
    
    -- Try to find by name (limit search range for performance)
    for id = 100, 20000 do
        local success, itemType = pcall(function() 
            return g_things.getItemType(id) 
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
    
    -- Clean up any existing loot icons
    LootStats.destroyLootIcons()
    
    -- Reset data structures
    mainScreenLoot = {}
    uniqueIdCounter = 1
    
    -- Ensure widget cache is ready
    pcall(function() LootStats.initWidgetCache() end)
    
    -- Ensure item database is ready
    pcall(function() LootStats.initItemDatabase() end)
    
    -- Update options panel if exists
    if optionsPanel then
        LootStats.updateOptionsUI()
    end
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

function LootStats.onTextMessage(mode, message)
    -- Check if this is a loot message
    if not message then return end
    
    -- Determine if this is a loot message
    local isLootMessage = false
    if MessageModes and MessageModes.Loot then
        isLootMessage = (mode == MessageModes.Loot)
    else
        -- Fallback detection - many clients use mode 20 or 22 for loot
        isLootMessage = (mode == 20 or mode == 22)
    end
    
    if not isLootMessage then return end
    
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
    
    -- Handle monster level system
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
    
    -- Try to load the UI
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
        LootStats.log("error", "Failed to load loot_stats UI")
        return
    end
    
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
    
    -- Connect clear data button
    local clearButton = lootStatsWindow:getChildById('clearButton')
    if clearButton then
        clearButton.onClick = function() LootStats.confirmClearData() end
    end
    
    lootStatsWindow:hide()
end

function LootStats.toggle()
    if not lootStatsWindow then
        LootStats.createLootStatsWindow()
        if not lootStatsWindow then return end
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
    if not mapPanel then
        return
    end
    
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
        
        local widget = g_ui.createWidget('LootMonsterBox', itemsPanel)
        
        -- Format text
        local text = monsterName:gsub("^%l", string.upper) .. '\n' .. 'Count: ' .. monsterData.count
        
        if totalMonsters > 0 then
            local percentage = monsterData.count * 100 / totalMonsters
            text = text .. '\n' .. 'Chance: ' .. LootStats.formatNumber(percentage, 3, true) .. ' %'
        end
        
        local textWidget = widget:getChildById('text')
        if textWidget then
            textWidget:setText(text)
        end
        
        -- Set creature image
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
        
        -- Connect click event
        widget.onMouseRelease = function(w, mousePos, mouseButton)
            if mouseButton == MouseLeftButton then
                LootStats.selectMonster(w)
            end
        end
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
        
        local widget = g_ui.createWidget('LootItemBox', itemsPanel)
        
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
        local textWidget = widget:getChildById('text')
        if textWidget then
            textWidget:setText(text)
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
    
    -- Determine decimal position with safe handling
    local firstNonZeroPos = 1
    if decimalPart > 0 then
        firstNonZeroPos = math.floor(math.log10(decimalPart)) + 1
    end
    
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

-- Return module for usage
return LootStats