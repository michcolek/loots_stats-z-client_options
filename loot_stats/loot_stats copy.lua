-- Loot Stats Module for OTClient Mehah
-- Updated version compatible with new interface

local lootStatsWindow = nil
local loadBox = nil
local characterList = nil
local errorBox = nil
local waitingWindow = nil

-- Module state variables
local lootStatsTable = {}
local showLootOnScreen = true
local amountLootOnScreen = 5
local delayTimeLootOnScreen = 2000
local ignoreMonsterLevelSystem = false
local ignoreLastSignWhenDot = false

-- UI elements
local lootIconOnScreen = {}
local mainScreenTab = {}
local cacheLastTime = { t = 0, i = 1 }

-- Item information
local items = {}
local ownParser = false
local loadedVersionItems = 0

-- Events tracking
local onRefreshLootStatsTable = {}
local onAddLootLog = {}
local onChangeShowLootOnScreen = {}
local onChangeAmountLootOnScreen = {}
local onChangeDelayTimeLootOnScreen = {}
local onChangeIgnoreMonsterLevelSystem = {}
local onChangeIgnoreLastSignWhenDot = {}

-- Interface tracking
local lootStatsButton = nil

function init()
    -- Load the UI files first using the correct path
    g_ui.importStyle('ui/loot_icons')

    -- Connect game events
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onClientVersionChange = loadClientVersionItems,
        onTextMessage = checkLootTextMessage
    })

    -- Initialize settings
    loadSettings()
    
    -- Add tab to options
    initOptionsUI()
    
    -- Create main window
    createMainWindow()
    
    -- Initialize the parser
    if g_game.getClientVersion() ~= 0 then
        loadClientVersionItems()
    end
    
    -- Create button in interface
    if g_game.isOnline() then
        setupInterface()
    end
end

function terminate()
    -- Disconnect game events
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onClientVersionChange = loadClientVersionItems,
        onTextMessage = checkLootTextMessage
    })
    
    -- Save settings
    saveSettings()
    
    -- Remove UI elements
    removeOptionsUI()
    destroyMainWindow()
    
    -- Clear any remaining loot icons
    destroyLootIcons()
    
    -- Remove button from interface
    if lootStatsButton then
        lootStatsButton:destroy()
        lootStatsButton = nil
    end
    
    -- Clear data
    lootStatsTable = {}
    mainScreenTab = {}
    items = {}
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
    -- Create button in main panel
    if modules.game_mainpanel and not lootStatsButton then
        lootStatsButton = modules.game_mainpanel.addToggleButton('lootStatsButton', tr('Loot Stats'), 
        '/loot_stats/ui/img/icon', toggle, false, 5)
    end
end

function createMainWindow()
    -- Use try-catch approach to load the UI
    local success, result = pcall(function()
        return g_ui.loadUI('ui/loot_stats', modules.game_interface.getRootWidget())
    end)
    
    if not success then
        -- Try another path if the first one failed
        success, result = pcall(function()
            return g_ui.loadUI('/loot_stats/ui/loot_stats', modules.game_interface.getRootWidget())
        end)
    end
    
    if not success then
        -- Final fallback - try making it with code
        local window = g_ui.createWidget('MainWindow', modules.game_interface.getRootWidget())
        window:setId('lootStatsMain')
        window:setText('Loot Statistics')
        window:setSize(550, 515)
        window:setFocusable(false)
        lootStatsWindow = window
    else
        lootStatsWindow = result
    end
    
    -- Ensure we have a window
    if not lootStatsWindow then
        g_logger.error("Failed to create loot stats window")
        return
    end
    
    lootStatsWindow:hide()
    
    -- Setup window elements - with error checking
    local monstersTab = lootStatsWindow:recursiveGetChildById('monstersTab')
    local allLootTab = lootStatsWindow:recursiveGetChildById('allLootTab')
    local closeButton = lootStatsWindow:recursiveGetChildById('closeButton')
    
    -- Connect events if widgets exist
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
    
    if closeButton then
        closeButton.onClick = function()
            toggle()
        end
    end
    
    -- Update layout
    updateLayout()
end

function destroyMainWindow()
    if lootStatsWindow then
        lootStatsWindow:destroy()
        lootStatsWindow = nil
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

function updateLayout()
    if not lootStatsWindow then return end
    
    -- Get UI elements - with error checking
    local itemsPanel = lootStatsWindow:recursiveGetChildById('itemsPanel')
    local monstersTab = lootStatsWindow:recursiveGetChildById('monstersTab')
    local allLootTab = lootStatsWindow:recursiveGetChildById('allLootTab')
    local panelCreatureView = lootStatsWindow:recursiveGetChildById('panelCreatureView')
    
    -- Default tab selection (if widgets exist)
    if monstersTab then
        monstersTab:setOn(true)
    end
    
    -- Initial state for creature view (if widget exists)
    if panelCreatureView then
        panelCreatureView:setHeight(0)
        panelCreatureView:setVisible(false)
    end
end

function loadClientVersionItems()
    print("Loading client version items")
    local version = g_game.getClientVersion()
    
    if version ~= loadedVersionItems then
        local otbPath = '/loot_stats/items_versions/' .. version .. '/items.otb'
        local xmlPath = 'items_versions/' .. version .. '/items.xml'
        
        if g_resources.fileExists(otbPath) then
            g_things.loadOtb(otbPath)
            if g_things.isOtbLoaded() then
                print("OTB file loaded.")
                ownParser = true
                parseItemsXML(xmlPath)
                print("XML file loaded using custom parser.")
            else
                print("Error loading OTB file.")
                return
            end
        else
            print("Required OTB files not found.")
            return
        end
        
        loadedVersionItems = version
    end
end

function parseItemsXML(path)
    items = {}
    
    local fileXML = g_resources.readFileContents(path)
    if not fileXML then
        print("Could not read XML file: " .. path)
        return
    end
    
    local itemsXMLString = {}
    for line in fileXML:gmatch("[^\r\n]+") do
        itemsXMLString[#itemsXMLString + 1] = line
    end
    
    local lastTableIdBackup = 0
    
    for a, b in ipairs(itemsXMLString) do
        local words = {}
        for word in b:gmatch("%S+") do
            table.insert(words, word)
        end
        
        if words[1] == '<item' then
            if string.sub(words[2] or "", 0, 2) == 'id' then
                local idFromString = tonumber(string.sub(words[2], string.find(words[2], '"') + 1, 
                    string.find(words[2], '"', string.find(words[2], '"') + 1) - 1))
                
                if idFromString then
                    items[idFromString] = {}
                    
                    for i=3, #words do
                        if string.find(words[i] or "", '=') then
                            local tabName = string.sub(words[i], 0, string.find(words[i], '=') - 1)
                            local checkWord = words[i]
                            
                            -- Safely handle word concatenation
                            local nextIndex = i + 1
                            while nextIndex <= #words and not (string.find(checkWord, '"') and string.find(checkWord, '"', string.find(checkWord, '"') + 1)) do
                                checkWord = checkWord..' '..words[nextIndex]
                                i = nextIndex
                                nextIndex = nextIndex + 1
                            end
                            
                            local firstQuote = string.find(checkWord, '"')
                            local secondQuote = string.find(checkWord, '"', firstQuote + 1)
                            
                            if firstQuote and secondQuote then
                                local tabValue = string.sub(checkWord, firstQuote + 1, secondQuote - 1)
                                items[idFromString][tabName] = tabValue
                            end
                        end
                    end
                    
                    lastTableIdBackup = idFromString
                end
                
            elseif words[1] == '<attribute' then
                local attKey = nil
                if words[2] and string.find(words[2], '"') then
                    attKey = string.sub(words[2], string.find(words[2], '"') + 1, 
                        string.find(words[2], '"', string.find(words[2], '"') + 1) - 1)
                end
                
                if attKey and items[lastTableIdBackup] then
                    local restWords = ''
                    for i=3, #words do
                        if restWords == '' then
                            restWords = words[i]
                        else
                            restWords = restWords..' '..words[i]
                        end
                    end
                    
                    if string.find(restWords, '"') then
                        local attValue = string.sub(restWords, string.find(restWords, '"') + 1, 
                            string.find(restWords, '"', string.find(restWords, '"') + 1) - 1)
                        
                        items[lastTableIdBackup][attKey] = attValue
                    end
                end
            end
        end
    end
end

function convertPluralToSingular(searchWord)
    for id, item in pairs(items) do
        if item.plural == searchWord then
            return item.name
        end
    end
    return false
end

function returnPluralNameFromLoot(lootMonsterName, itemWord)
    if lootStatsTable[string.lower(lootMonsterName)] and lootStatsTable[string.lower(lootMonsterName)].loot then
        for itemName, itemInfo in pairs(lootStatsTable[string.lower(lootMonsterName)].loot) do
            if itemInfo.plural == itemWord then
                return itemName
            end
        end
    end
    return false
end

function checkLootTextMessage(messageMode, message)
    if loadedVersionItems == 0 then
        return
    end
    
    local fromLootValue, toLootValue = string.find(message, 'Loot of ')
    if not toLootValue then
        return
    end
    
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
                
                -- Check if we already know this plural name
                local isPluralNameInLoot = returnPluralNameFromLoot(monsterKey, itemWord)
                
                if isPluralNameInLoot then
                    -- Update existing item
                    if not lootStatsTable[monsterKey].loot[isPluralNameInLoot] then
                        lootStatsTable[monsterKey].loot[isPluralNameInLoot] = {count = 0}
                    end
                    
                    if not lootToScreen[isPluralNameInLoot] then
                        lootToScreen[isPluralNameInLoot] = {count = 0}
                    end
                    
                    lootStatsTable[monsterKey].loot[isPluralNameInLoot].count = 
                        lootStatsTable[monsterKey].loot[isPluralNameInLoot].count + itemCount
                    lootToScreen[isPluralNameInLoot].count = lootToScreen[isPluralNameInLoot].count + itemCount
                else
                    -- Try to convert plural to singular
                    local pluralNameToSingular = convertPluralToSingular(itemWord)
                    if pluralNameToSingular then
                        if not lootStatsTable[monsterKey].loot[pluralNameToSingular] then
                            lootStatsTable[monsterKey].loot[pluralNameToSingular] = {count = 0}
                        end
                        
                        if not lootStatsTable[monsterKey].loot[pluralNameToSingular].plural then
                            lootStatsTable[monsterKey].loot[pluralNameToSingular].plural = itemWord
                        end
                        
                        if not lootToScreen[pluralNameToSingular] then
                            lootToScreen[pluralNameToSingular] = {count = 0}
                        end
                        
                        lootStatsTable[monsterKey].loot[pluralNameToSingular].count = 
                            lootStatsTable[monsterKey].loot[pluralNameToSingular].count + itemCount
                        lootToScreen[pluralNameToSingular].count = lootToScreen[pluralNameToSingular].count + itemCount
                    else
                        -- Unknown item, add as is
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
    
    if showLootOnScreen then
        addLootToScreen(lootToScreen)
    end
    
    -- Signal that data has been updated
    for _, callback in pairs(onRefreshLootStatsTable) do
        if type(callback) == "function" then
            callback()
        end
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
    local topMenu = modules.client_topmenu.getTopMenu()
    if topMenu and topMenu:isVisible() then
        actualY = topMenu:getHeight()
    end
    
    -- Display loot icons
    for rowIndex, rowData in pairs(mainScreenTab) do
        if actualY <= mapPanel:getHeight() - iconSize then
            -- Calculate starting X position to center the row
            local rowItemCount = 0
            for _ in pairs(rowData.loot) do rowItemCount = rowItemCount + 1 end
            
            local rowWidth = rowItemCount * iconSize
            local actualX = (screenWidth - rowWidth) / 2
            
            -- Create icons for this row
            for itemName, itemData in pairs(rowData.loot) do
                if actualX <= mapPanel:getWidth() - iconSize then
                    -- Create icon widget
                    local iconWidget = g_ui.createWidget("UIItem", mapPanel)
                    iconWidget:setSize({width = iconSize, height = iconSize})
                    iconWidget:setX(actualX)
                    iconWidget:setY(actualY)
                    iconWidget:setVirtual(true)
                    
                    -- Find item ID
                    local serverId = nil
                    for id, item in pairs(items) do
                        if item.name == itemName then
                            serverId = id
                            break
                        end
                    end
                    
                    -- Set item
                    if serverId then
                        local itemType = g_things.getItemType(serverId)
                        if itemType then
                            local clientId = itemType:getClientId()
                            if clientId ~= 0 then
                                iconWidget:setItemId(clientId)
                                if itemData.count > 1 then
                                    iconWidget:setItemCount(itemData.count)
                                end
                            else
                                iconWidget:setItemId(3547) -- fallback item
                            end
                        else
                            iconWidget:setItemId(3547) -- fallback item
                        end
                    else
                        iconWidget:setItemId(3547) -- fallback item
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
        icon:destroy()
    end
    lootIconOnScreen = {}
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

function refreshListElements()
    if not lootStatsWindow then return end
    
    local itemsPanel = lootStatsWindow:recursiveGetChildById('itemsPanel')
    if not itemsPanel then return end
    
    local monstersTab = lootStatsWindow:recursiveGetChildById('monstersTab')
    local allLootTab = lootStatsWindow:recursiveGetChildById('allLootTab')
    
    -- Clear any existing items
    itemsPanel:destroyChildren()
    
    if monstersTab and monstersTab:isOn() then
        refreshMonstersList()
    elseif allLootTab and allLootTab:isOn() then
        refreshLootList("*all")
    end
end

function refreshMonstersList()
    local itemsPanel = lootStatsWindow:recursiveGetChildById('itemsPanel')
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
    local monstersTab = lootStatsWindow:recursiveGetChildById('monstersTab')
    local allLootTab = lootStatsWindow:recursiveGetChildById('allLootTab')
    local panelCreatureView = lootStatsWindow:recursiveGetChildById('panelCreatureView')
    
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
            refreshLootList(monsterName)
        end
    end
end

function refreshLootList(monsterName)
    local itemsPanel = lootStatsWindow:recursiveGetChildById('itemsPanel')
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
        local serverId = nil
        for id, item in pairs(items) do
            if item.name == itemName then
                serverId = id
                break
            end
        end
        
        local itemWidget = widget:getChildById('item')
        if itemWidget then
            if serverId then
                local itemType = g_things.getItemType(serverId)
                if itemType then
                    local clientId = itemType:getClientId()
                    if clientId ~= 0 then
                        local item = Item.create(clientId)
                        
                        if itemInfo.plural and itemInfo.count > 1 then
                            local displayCount = math.min(itemInfo.count, 100)
                            item:setCount(displayCount)
                        end
                        
                        itemWidget:setItem(item)
                    else
                        itemWidget:setItemId(3547) -- fallback item
                    end
                else
                    itemWidget:setItemId(3547) -- fallback item
                end
            else
                itemWidget:setItemId(3547) -- fallback item
            end
        end
    end
end

function whenClickMonstersTab(widget, mousePosition, mouseButton)
    if mouseButton == MouseLeftButton then
        local allLootTab = lootStatsWindow:recursiveGetChildById('allLootTab')
        local panelCreatureView = lootStatsWindow:recursiveGetChildById('panelCreatureView')
        
        if allLootTab then allLootTab:setOn(false) end
        widget:setOn(true)
        
        if panelCreatureView then
            panelCreatureView:setHeight(0)
            panelCreatureView:setVisible(false)
        end
        
        refreshMonstersList()
    end
end

function whenClickAllLootTab(widget, mousePosition, mouseButton)
    if mouseButton == MouseLeftButton then
        local monstersTab = lootStatsWindow:recursiveGetChildById('monstersTab')
        local panelCreatureView = lootStatsWindow:recursiveGetChildById('panelCreatureView')
        
        if monstersTab then monstersTab:setOn(false) end
        widget:setOn(true)
        
        if panelCreatureView then
            panelCreatureView:setHeight(0)
            panelCreatureView:setVisible(false)
        end
        
        refreshLootList('*all')
    end
end

function clearData()
    local function yesCallback()
        lootStatsTable = {}
        mainScreenTab = {}
        cacheLastTime = { t = 0, i = 1 }
        
        refreshListElements()
        destroyLootIcons()
    end
    
    local function noCallback()
        -- Do nothing
    end
    
    local messageBox = displayGeneralBox(tr('Clear all values'), tr('Do you want clear all values?\nYou will lose all loot data!'), {
        { text=tr('Yes'), callback = yesCallback },
        { text=tr('No'), callback = noCallback },
        anchor=AnchorHorizontalCenter 
    }, yesCallback, noCallback)
end

function initOptionsUI()
    -- Create an options panel that will be added to the options window
    local optionsPanel = g_ui.createWidget('Panel')
    optionsPanel:setId('lootStatsOptionsPanel')
    
    -- Apply styles for the panel
    optionsPanel:setLayout(UIVerticalLayout.create(optionsPanel))
    optionsPanel:setHeight(480)
    optionsPanel:setWidth(300)
    
    -- Create options widgets
    local showLootOnScreenCheckBox = g_ui.createWidget('CheckBox', optionsPanel)
    showLootOnScreenCheckBox:setId('showLootOnScreen')
    showLootOnScreenCheckBox:setText('Show loot on screen')
    showLootOnScreenCheckBox:setChecked(showLootOnScreen)
    showLootOnScreenCheckBox.onCheckChange = function(widget, checked)
        showLootOnScreen = checked
        g_settings.set('loot_stats_addIconsToScreen', checked)
        for _, callback in pairs(onChangeShowLootOnScreen) do
            if type(callback) == "function" then
                callback(checked)
            end
        end
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
        for _, callback in pairs(onChangeAmountLootOnScreen) do
            if type(callback) == "function" then
                callback(value)
            end
        end
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
        for _, callback in pairs(onChangeDelayTimeLootOnScreen) do
            if type(callback) == "function" then
                callback(value)
            end
        end
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
        for _, callback in pairs(onChangeIgnoreMonsterLevelSystem) do
            if type(callback) == "function" then
                callback(checked)
            end
        end
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
        for _, callback in pairs(onChangeIgnoreLastSignWhenDot) do
            if type(callback) == "function" then
                callback(checked)
            end
        end
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
    
    -- Add the panel to the options UI
    modules.client_options.addTab('Loot Stats', optionsPanel, '/loot_stats/ui/img/icon')
end

function removeOptionsUI()
    modules.client_options.removeTab('Loot Stats')
end