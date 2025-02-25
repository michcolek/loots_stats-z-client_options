-- Loot Stats Module for OTClient Mehah
-- Updated version compatible with new interface

-- UI elements
local lootStatsButton
local lootStatsWindow
local lootIconOnScreen = {}
local mainScreenTab = {}
local cacheLastTime = { t = 0, i = 1 }

-- Module state variables 
local lootStatsTable = {}
local showLootOnScreen = true
local amountLootOnScreen = 5
local delayTimeLootOnScreen = 2000
local ignoreMonsterLevelSystem = false
local ignoreLastSignWhenDot = false

-- Item information
local items = {}
local loadedVersionItems = 0

-- Event callbacks
local onRefreshLootStatsTable = {}
local onAddLootLog = {}

function init()
    -- Connect game events
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd, 
        onTextMessage = checkLootTextMessage
    })

    -- Initialize settings
    loadSettings()
    
    -- Create UI elements
    createUIElements()
    
    -- Load items if game is connected
    if g_game.isOnline() then
        setupInterface()
    end
end

function terminate()
    -- Disconnect game events
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onTextMessage = checkLootTextMessage
    })
    
    -- Save settings
    saveSettings()
    
    -- Remove UI elements
    destroyUIElements()
    
    -- Clear data
    lootStatsTable = {}
    mainScreenTab = {}
    items = {}
    
    -- Clear any remaining loot icons
    destroyLootIcons()
end

function loadSettings()
    showLootOnScreen = g_settings.getBoolean('loot_stats_addIconsToScreen', true)
    
    local storedAmount = g_settings.getNumber('loot_stats_amountLootOnScreen')
    if storedAmount and storedAmount > 0 and storedAmount <= 20 then
        amountLootOnScreen = storedAmount
    else
        amountLootOnScreen = 5
    end
    
    local storedDelay = g_settings.getNumber('loot_stats_delayTimeLootOnScreen')
    if storedDelay and storedDelay >= 500 and storedDelay <= 10000 then
        delayTimeLootOnScreen = storedDelay
    else
        delayTimeLootOnScreen = 2000
    end
    
    ignoreMonsterLevelSystem = g_settings.getBoolean('loot_stats_ignoreMonsterLevelSystem', false)
    ignoreLastSignWhenDot = g_settings.getBoolean('loot_stats_ignoreLastSignWhenDot', false)
end

function saveSettings()
    g_settings.set('loot_stats_addIconsToScreen', showLootOnScreen)
    g_settings.set('loot_stats_amountLootOnScreen', amountLootOnScreen)
    g_settings.set('loot_stats_delayTimeLootOnScreen', delayTimeLootOnScreen)
    g_settings.set('loot_stats_ignoreMonsterLevelSystem', ignoreMonsterLevelSystem)
    g_settings.set('loot_stats_ignoreLastSignWhenDot', ignoreLastSignWhenDot)
end

function onGameStart()
    setupInterface()
end

function onGameEnd()
    -- Save settings and clear data
    saveSettings()
    destroyLootIcons()
    
    if lootStatsWindow then
        lootStatsWindow:hide()
    end
end

function setupInterface()
    -- Create button in main panel if it doesn't exist
    if modules.game_mainpanel and not lootStatsButton then
        lootStatsButton = modules.game_mainpanel.addToggleButton('lootStatsButton', tr('Loot Stats'), 
            '/loot_stats/ui/img/icon', toggle, false, 5)
    end
end

function createUIElements()
    -- Load the icons style
    g_ui.importStyle('loot_icons')
    
    -- Create the main window from UI file
    lootStatsWindow = g_ui.displayUI('loot_stats')
    lootStatsWindow:hide()
    
    -- Setup window handlers
    if lootStatsWindow then
        local monstersTab = lootStatsWindow:getChildById('monstersTab')
        local allLootTab = lootStatsWindow:getChildById('allLootTab')
        
        if monstersTab then
            monstersTab.onMouseRelease = function(widget, mousePosition, mouseButton)
                whenClickMonstersTab(widget, mousePosition, mouseButton)
            end
        end
        
        if allLootTab then
            allLootTab.onMouseRelease = function(widget, mousePosition, mouseButton)
                whenClickAllLootTab(widget, mousePosition, mouseButton)
            end
        end
        
        local closeButton = lootStatsWindow:getChildById('closeButton')
        if closeButton then
            closeButton.onClick = toggle
        end
    end
    
    -- Initialize options panel for client_options module if it exists
    if modules.client_options then
        modules.client_options.addTab('Loot Stats', createOptionsPanel(), '/loot_stats/ui/img/icon')
    end
end

function createOptionsPanel()
    -- Create options panel
    local optionsPanel = g_ui.createWidget('Panel')
    
    -- Apply styles for the panel
    optionsPanel:setId('lootStatsOptionsPanel')
    optionsPanel:setLayout(UIVerticalLayout.create(optionsPanel))
    optionsPanel:setHeight(480)
    
    -- Create options widgets
    local showLootOnScreenCheckBox = g_ui.createWidget('CheckBox', optionsPanel)
    showLootOnScreenCheckBox:setId('showLootOnScreen')
    showLootOnScreenCheckBox:setText('Show loot on screen')
    showLootOnScreenCheckBox:setChecked(showLootOnScreen)
    showLootOnScreenCheckBox.onCheckChange = function(widget, checked)
        showLootOnScreen = checked
        g_settings.set('loot_stats_addIconsToScreen', checked)
    end
    
    -- Amount of loot slider
    local amountLabel = g_ui.createWidget('Label', optionsPanel)
    amountLabel:setText('Amount of loot on screen: ' .. amountLootOnScreen)
    amountLabel:setId('amountLootOnScreenLabel')
    
    local amountSlider = g_ui.createWidget('HorizontalScrollBar', optionsPanel)
    amountSlider:setId('amountLootOnScreen')
    amountSlider:setMinimum(1)
    amountSlider:setMaximum(20)
    amountSlider:setValue(amountLootOnScreen)
    amountSlider.onValueChange = function(scroll, value)
        amountLootOnScreen = value
        amountLabel:setText('Amount of loot on screen: ' .. value)
        g_settings.set('loot_stats_amountLootOnScreen', value)
    end
    
    -- Delay time slider
    local delayLabel = g_ui.createWidget('Label', optionsPanel)
    delayLabel:setText('Time delay to delete loot from screen: ' .. delayTimeLootOnScreen)
    delayLabel:setId('delayTimeLootOnScreenLabel')
    
    local delaySlider = g_ui.createWidget('HorizontalScrollBar', optionsPanel)
    delaySlider:setId('delayTimeLootOnScreen')
    delaySlider:setMinimum(500)
    delaySlider:setMaximum(10000)
    delaySlider:setStep(100)
    delaySlider:setValue(delayTimeLootOnScreen)
    delaySlider.onValueChange = function(scroll, value)
        delayTimeLootOnScreen = value
        delayLabel:setText('Time delay to delete loot from screen: ' .. value)
        g_settings.set('loot_stats_delayTimeLootOnScreen', value)
    end
    
    -- Add a separator
    local separator = g_ui.createWidget('HorizontalSeparator', optionsPanel)
    
    -- Ignore monster level system checkbox
    local ignoreMonsterLevelSystemCheckBox = g_ui.createWidget('CheckBox', optionsPanel)
    ignoreMonsterLevelSystemCheckBox:setId('ignoreMonsterLevelSystem')
    ignoreMonsterLevelSystemCheckBox:setText('Ignore monster level system')
    ignoreMonsterLevelSystemCheckBox:setTooltip('When OFF - ignore level in bracket ("Monster [100]" -> "Monster")\nWhen ON don\'t ignore level in bracket ("Monster [100]" -> "Monster [100]")')
    ignoreMonsterLevelSystemCheckBox:setChecked(ignoreMonsterLevelSystem)
    ignoreMonsterLevelSystemCheckBox.onCheckChange = function(widget, checked)
        ignoreMonsterLevelSystem = checked
        g_settings.set('loot_stats_ignoreMonsterLevelSystem', checked)
    end
    
    -- Ignore last sign when dot checkbox
    local ignoreLastSignWhenDotCheckBox = g_ui.createWidget('CheckBox', optionsPanel)
    ignoreLastSignWhenDotCheckBox:setId('ignoreLastSignWhenDot')
    ignoreLastSignWhenDotCheckBox:setText('Ignore last sign when dot')
    ignoreLastSignWhenDotCheckBox:setTooltip('When OFF delete last character in log, when it is dot.\nWhen ON don\'t delete last character in log, when it is dot.')
    ignoreLastSignWhenDotCheckBox:setChecked(ignoreLastSignWhenDot)
    ignoreLastSignWhenDotCheckBox.onCheckChange = function(widget, checked)
        ignoreLastSignWhenDot = checked
        g_settings.set('loot_stats_ignoreLastSignWhenDot', checked)
    end
    
    -- Add a separator
    local separator2 = g_ui.createWidget('HorizontalSeparator', optionsPanel)
    
    -- Clear data button
    local clearDataButton = g_ui.createWidget('Button', optionsPanel)
    clearDataButton:setId('clearData')
    clearDataButton:setText('Clear data')
    clearDataButton.onClick = function()
        clearData()
    end
    
    return optionsPanel
end

function destroyUIElements()
    -- Clean up main window
    if lootStatsWindow then
        lootStatsWindow:destroy()
        lootStatsWindow = nil
    end
    
    -- Remove options panel
    if modules.client_options then
        modules.client_options.removeTab('Loot Stats')
    end
    
    -- Clean up button
    if lootStatsButton then
        lootStatsButton:destroy()
        lootStatsButton = nil
    end
end

function toggle()
    if lootStatsWindow then
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
            refreshListElements()
        end
    end
end

function formatNumber(value, decimals, cutDigits)
    decimals = decimals or 0
    cutDigits = cutDigits or false
    
    if value - math.floor(value) == 0 then
        return value
    end
    
    local decimalPart = 0
    local intPart = 0
    
    if value > 1 then
        decimalPart = value - math.floor(value)
        intPart = math.floor(value)
    else
        decimalPart = value
    end
    
    local firstNonZeroPos = 0
    if decimalPart > 0 then
        firstNonZeroPos = math.floor(math.log10(decimalPart)) + 1
    end
    
    local numberOfPoints = 1
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

function getItemClientId(itemName)
    -- Try to find the item by name
    if not itemName then return 3547 end -- default item ID
    
    for itemId = 100, 20000 do
        local itemType = g_things.getItemType(itemId)
        if itemType and itemType:getName() and itemType:getName():lower() == itemName:lower() then
            return itemType:getClientId()
        end
    end
    
    -- Return a default item ID if not found
    return 3547 -- default item
end

function checkLootTextMessage(messageMode, message)
    -- Ignore non-loot messages
    if not message or messageMode ~= MessageModes.Loot then return end
    
    -- Look for loot messages in the format "Loot of X: item1, item2, ..."
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
    
    -- Convert monster name to lowercase for consistent keys
    local monsterKey = string.lower(lootMonsterName)
    
    -- If monster not in table, add it
    if not lootStatsTable[monsterKey] then
        lootStatsTable[monsterKey] = { loot = {}, count = 0 }
    end
    
    -- Update monster kill count
    lootStatsTable[monsterKey].count = lootStatsTable[monsterKey].count + 1
    
    -- Parse loot string
    local lootString = string.sub(message, string.find(message, ': ') + 2)
    
    -- Remove trailing dot if needed
    if not ignoreLastSignWhenDot and string.sub(lootString, -1) == '.' then
        lootString = string.sub(lootString, 0, -2)
    end
    
    -- Process the loot items
    local lootToScreen = {}
    for word in string.gmatch(lootString, '([^,]+)') do
        -- Remove leading space
        if string.sub(word, 0, 1) == ' ' then
            word = string.sub(word, 2)
        end
        
        -- Remove 'a ' or 'an ' prefix
        local isAToLootValue, isAFromLootValue = string.find(word, 'a ')
        if isAFromLootValue then
            word = string.sub(word, isAFromLootValue + 1)
        end
        
        local isANToLootValue, isANFromLootValue = string.find(word, 'an ')
        if isANFromLootValue then
            word = string.sub(word, isANFromLootValue + 1)
        end
        
        -- Check if first character is a number (for multiple items)
        if tonumber(string.sub(word, 0, 1)) then
            local itemCount = tonumber(string.match(word, "%d+"))
            local delFN, delLN = string.find(word, tostring(itemCount))
            if delLN and delLN + 2 <= #word then
                local itemWord = string.sub(word, delLN + 2)
                
                -- Simple processing for items - just record them directly
                if not lootStatsTable[monsterKey].loot[itemWord] then
                    lootStatsTable[monsterKey].loot[itemWord] = {count = 0}
                end
                
                if not lootToScreen[itemWord] then
                    lootToScreen[itemWord] = {count = 0}
                end
                
                lootStatsTable[monsterKey].loot[itemWord].count = 
                    lootStatsTable[monsterKey].loot[itemWord].count + itemCount
                lootToScreen[itemWord].count = lootToScreen[itemWord].count + itemCount
            end
        else
            -- Single item
            if not lootStatsTable[monsterKey].loot[word] then
                lootStatsTable[monsterKey].loot[word] = {count = 0}
            end
            
            if not lootToScreen[word] then
                lootToScreen[word] = {count = 0}
            end
            
            lootStatsTable[monsterKey].loot[word].count = 
                lootStatsTable[monsterKey].loot[word].count + 1
            lootToScreen[word].count = lootToScreen[word].count + 1
        end
    end
    
    -- Show loot on screen if enabled
    if showLootOnScreen then
        addLootToScreen(lootToScreen)
    end
    
    -- Refresh UI if visible
    if lootStatsWindow and lootStatsWindow:isVisible() then
        refreshListElements()
    end
end

function addLootToScreen(lootItems)
    -- Remove old loot displays if needed
    for i = 1, amountLootOnScreen do
        mainScreenTab[i] = {}
        if i + 1 <= amountLootOnScreen then
            mainScreenTab[i] = mainScreenTab[i + 1]
        else
            if lootItems ~= nil then
                mainScreenTab[i] = { loot = lootItems }
                if g_clock.millis() == cacheLastTime.t then
                    mainScreenTab[i].id = g_clock.millis() * 100 + cacheLastTime.i
                    cacheLastTime.i = cacheLastTime.i + 1
                else
                    mainScreenTab[i].id = g_clock.millis()
                    cacheLastTime.t = g_clock.millis()
                    cacheLastTime.i = 1
                end
                
                -- Schedule removal after delay
                scheduleEvent(function()
                    removeLootFromScreen(mainScreenTab[i].id)
                end, delayTimeLootOnScreen)
            else
                mainScreenTab[i] = nil
            end
        end
    end
    
    refreshLootOnScreen()
end

function removeLootFromScreen(id)
    for index, item in pairs(mainScreenTab) do
        if item.id == id then
            mainScreenTab[index] = nil
            addLootToScreen(nil)
            refreshLootOnScreen()
            break
        end
    end
end

function refreshLootOnScreen()
    -- Clear existing icons
    destroyLootIcons()
    
    -- Get map panel for placement
    local mapPanel = modules.game_interface.getMapPanel()
    if not mapPanel then return end
    
    -- Calculate dimensions
    local screenWidth = mapPanel:getWidth()
    local iconSize = 32
    
    -- Calculate starting positions
    local actualY = 0
    local topMenu = modules.client_topmenu and modules.client_topmenu.getTopMenu()
    if topMenu and topMenu:isVisible() then
        actualY = topMenu:getHeight()
    end
    
    -- Display loot icons
    for rowIndex, rowData in pairs(mainScreenTab) do
        if actualY <= mapPanel:getHeight() - iconSize and rowData and rowData.loot then
            -- Calculate starting X position to center the row
            local rowItemCount = 0
            for _ in pairs(rowData.loot) do rowItemCount = rowItemCount + 1 end
            
            local rowWidth = rowItemCount * iconSize
            local actualX = (screenWidth - rowWidth) / 2
            
            -- Create icons for this row
            for itemName, itemData in pairs(rowData.loot) do
                if actualX <= mapPanel:getWidth() - iconSize then
                    -- Create icon widget
                    local iconWidget = g_ui.createWidget("LootIcon", mapPanel)
                    iconWidget:setSize({width = iconSize, height = iconSize})
                    iconWidget:setX(actualX)
                    iconWidget:setY(actualY)
                    
                    -- Use a simplified approach to get item ID
                    local clientId = getItemClientId(itemName) or 3547
                    iconWidget:setItemId(clientId)
                    
                    if itemData.count > 1 then
                        iconWidget:setItemCount(itemData.count)
                    end
                    
                    -- Add to tracking list
                    table.insert(lootIconOnScreen, iconWidget)
                    
                    -- Move to next position
                    actualX = actualX + iconSize
                end
            end
            
            -- Move to next row
            actualY = actualY + iconSize
        end
    end
end

function destroyLootIcons()
    for _, icon in ipairs(lootIconOnScreen) do
        if icon then
            icon:destroy()
        end
    end
    lootIconOnScreen = {}
end

function refreshListElements()
    if not lootStatsWindow then return end
    
    local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
    if not itemsPanel then return end
    
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    
    -- Clear any existing items
    itemsPanel:destroyChildren()
    
    if monstersTab and monstersTab:isOn() then
        refreshMonstersList(itemsPanel)
    elseif allLootTab and allLootTab:isOn() then
        refreshLootList(itemsPanel, "*all")
    end
end

function refreshMonstersList(itemsPanel)
    if not itemsPanel then return end
    
    for monsterName, monsterData in pairs(lootStatsTable) do
        local widget = g_ui.createWidget('LootMonsterBox', itemsPanel)
        
        local text = monsterName .. '\n' .. 'Count: ' .. monsterData.count
        
        local totalMonsters = 0
        for _, data in pairs(lootStatsTable) do
            totalMonsters = totalMonsters + data.count
        end
        
        if totalMonsters > 0 then
            local percentage = monsterData.count * 100 / totalMonsters
            text = text .. '\n' .. 'Chance: ' .. formatNumber(percentage, 3, true) .. ' %'
        end
        
        local textWidget = widget:getChildById('text')
        if textWidget then
            textWidget:setText(text)
        end
        
        -- Set creature image if available
        local creatureWidget = widget:getChildById('creature')
        if creatureWidget then
            local creature = Creature.create()
            creature:setDirection(2)
            
            if monsterData.outfit then
                creature:setOutfit(monsterData.outfit)
            else
                local defaultOutfit = { type = 160, feet = 114, addons = 0, legs = 114, auxType = 7399, head = 114, body = 114 }
                creature:setOutfit(defaultOutfit)
            end
            
            creatureWidget:setCreature(creature)
        end
        
        -- Connect click event
        widget.onMouseRelease = function(self, mousePos, mouseButton)
            if mouseButton == MouseLeftButton then
                showMonsterDetails(self, mousePos)
            end
        end
    end
end

function showMonsterDetails(widget, mousePos)
    local monstersTab = lootStatsWindow:getChildById('monstersTab')
    local allLootTab = lootStatsWindow:getChildById('allLootTab')
    local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
    local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
    
    if monstersTab then monstersTab:setOn(false) end
    if allLootTab then allLootTab:setOn(false) end
    
    -- Show creature view panel
    if panelCreatureView then
        panelCreatureView:setHeight(40)
        panelCreatureView:setVisible(true)
        
        -- Set creature
        local creatureView = panelCreatureView:getChildById('creatureView')
        local creatureWidget = widget:getChildById('creature')
        
        if creatureView and creatureWidget then
            local creature = creatureWidget:getCreature()
            creatureView:setCreature(creature)
        end
        
        -- Set text
        local textView = panelCreatureView:getChildById('textCreatureView')
        local textWidget = widget:getChildById('text')
        
        if textView and textWidget then
            local text = textWidget:getText()
            textView:setText(text)
            
            -- Get monster name from text
            local monsterName = ""
            for word in string.gmatch(text, '([^'..'\n'..']+)') do
                monsterName = word
                break
            end
            
            -- Show monster's loot
            if itemsPanel then
                refreshLootList(itemsPanel, monsterName)
            end
        end
    end
end

function refreshLootList(itemsPanel, monsterName)
    if not itemsPanel then return end
    
    itemsPanel:destroyChildren()
    
    local lootItems = {}
    if monsterName == "*all" then
        -- Gather all loot
        for _, monsterData in pairs(lootStatsTable) do
            for itemName, itemInfo in pairs(monsterData.loot) do
                if not lootItems[itemName] then
                    lootItems[itemName] = {
                        count = 0, 
                        plural = itemInfo.plural
                    }
                end
                lootItems[itemName].count = lootItems[itemName].count + itemInfo.count
            end
        end
    else
        -- Get loot for specific monster
        local monsterKey = string.lower(monsterName)
        if lootStatsTable[monsterKey] and lootStatsTable[monsterKey].loot then
            for itemName, itemInfo in pairs(lootStatsTable[monsterKey].loot) do
                lootItems[itemName] = {
                    count = itemInfo.count,
                    plural = itemInfo.plural
                }
            end
        end
    end
    
    -- Display the loot items
    for itemName, itemInfo in pairs(lootItems) do
        local widget = g_ui.createWidget('LootItemBox', itemsPanel)
        
        local text = itemName .. '\n' .. 'Count: ' .. itemInfo.count
        
        -- Calculate chance
        local totalCount = 0
        if monsterName == "*all" then
            for _, monsterData in pairs(lootStatsTable) do
                totalCount = totalCount + monsterData.count
            end
        else
            local monsterKey = string.lower(monsterName)
            if lootStatsTable[monsterKey] then
                totalCount = lootStatsTable[monsterKey].count
            end
        end
        
        if totalCount > 0 then
            if itemInfo.plural then
                if itemInfo.count > totalCount then
                    local avg = itemInfo.count / totalCount
                    text = text .. '\n' .. 'Average: ' .. formatNumber(avg, 3, true) .. ' / 1'
                else
                    local chance = itemInfo.count * 100 / totalCount
                    text = text .. '\n' .. 'Chance: ' .. formatNumber(chance, 3, true) .. ' %'
                end
            else
                local chance = itemInfo.count * 100 / totalCount
                text = text .. '\n' .. 'Chance: ' .. formatNumber(chance, 3, true) .. ' %'
            end
        end
        
        local textWidget = widget:getChildById('text')
        if textWidget then
            textWidget:setText(text)
        end
        
        -- Set item image
        local itemWidget = widget:getChildById('item')
        if itemWidget then
            local clientId = getItemClientId(itemName) or 3547
            
            local item = Item.create(clientId)
            if item then
                if itemInfo.plural and itemInfo.count > 1 then
                    local displayCount = math.min(itemInfo.count, 100)
                    item:setCount(displayCount)
                end
                
                itemWidget:setItem(item)
            else
                itemWidget:setItemId(3547) -- fallback item
            end
        end
    end
end

function whenClickMonstersTab(widget, mousePosition, mouseButton)
    if mouseButton == MouseLeftButton then
        local allLootTab = lootStatsWindow:getChildById('allLootTab')
        local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
        local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
        
        if allLootTab then allLootTab:setOn(false) end
        widget:setOn(true)
        
        if panelCreatureView then
            panelCreatureView:setHeight(0)
            panelCreatureView:setVisible(false)
        end
        
        if itemsPanel then
            refreshMonstersList(itemsPanel)
        end
    end
end

function whenClickAllLootTab(widget, mousePosition, mouseButton)
    if mouseButton == MouseLeftButton then
        local monstersTab = lootStatsWindow:getChildById('monstersTab')
        local panelCreatureView = lootStatsWindow:getChildById('panelCreatureView')
        local itemsPanel = lootStatsWindow:getChildById('itemsPanel')
        
        if monstersTab then monstersTab:setOn(false) end
        widget:setOn(true)
        
        if panelCreatureView then
            panelCreatureView:setHeight(0)
            panelCreatureView:setVisible(false)
        end
        
        if itemsPanel then
            refreshLootList(itemsPanel, '*all')
        end
    end
end

function clearData()
    -- Check if a confirmation window already exists and destroy it
    if saveOverWindow then
        saveOverWindow:destroy()
        saveOverWindow = nil
        return
    end
    
    -- Create callbacks with direct reference to the window
    local yesCallback = function()
        lootStatsTable = {}
        mainScreenTab = {}
        cacheLastTime = { t = 0, i = 1 }
        
        refreshListElements()
        destroyLootIcons()
        
        if saveOverWindow then
            saveOverWindow:destroy()
            saveOverWindow = nil
        end
    end
    
    local noCallback = function()
        if saveOverWindow then
            saveOverWindow:destroy()
            saveOverWindow = nil
        end
    end
    
    -- Create the confirmation window using OTClient Mehah's API
    saveOverWindow = displayGeneralBox(
        tr('Clear all values'), 
        tr('Do you want clear all values?\nYou will lose all loot data!'), 
        {
            { text=tr('Yes'), callback = yesCallback },
            { text=tr('No'), callback = noCallback },
            anchor=AnchorHorizontalCenter 
        }, 
        yesCallback, 
        noCallback
    )
    
    -- Connect ESC key to close the window
    saveOverWindow.onEscape = noCallback
end