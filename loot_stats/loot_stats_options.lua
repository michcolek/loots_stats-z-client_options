-- loot_stats_options.lua - Options panel integration for loot stats module

-- Module namespace
LootStatsOptions = {}

-- Local variables
local optionsPanel

function LootStatsOptions.init()
    -- Check if client_options module exists
    if not modules.client_options then
        g_logger.warning("[LootStatsOptions] client_options module not found")
        return
    end

    -- Check if LootStats module exists and has required functions
    if not modules.loot_stats or type(modules.loot_stats.getSettings) ~= 'function' then
        g_logger.warning("[LootStatsOptions] loot_stats module not found or missing required functions")
        return
    end

    -- Get access to settings from the main module
    local settings = modules.loot_stats.getSettings()
  
    -- Create options panel
    local success, panel = pcall(function()
        return g_ui.loadUI('loot_stats_options', modules.client_options.getPanel())
    end)
    
    if not success or not panel then
        -- Try alternative path
        success, panel = pcall(function()
            return g_ui.loadUI('/loot_stats/loot_stats_options', modules.client_options.getPanel())
        end)
    end
    
    if not success or not panel then
        g_logger.error("[LootStatsOptions] Failed to load options panel UI")
        return
    end
    
    optionsPanel = panel

    -- Connect UI elements to settings
    local showLootCheckBox = optionsPanel:recursiveGetChildById('showLootOnScreen')
    if showLootCheckBox then
        showLootCheckBox:setChecked(settings.showLootOnScreen)
        showLootCheckBox.onCheckChange = function(widget, checked)
            modules.loot_stats.setShowLootOnScreen(checked)
        end
    end
  
    local amountLootSpinBox = optionsPanel:recursiveGetChildById('amountLootOnScreen')
    if amountLootSpinBox then
        amountLootSpinBox:setValue(settings.amountLootOnScreen)
        amountLootSpinBox.onValueChange = function(widget, value)
            modules.loot_stats.setAmountLootOnScreen(value)
        end
    end
  
    local delayTimeSpinBox = optionsPanel:recursiveGetChildById('delayTimeLootOnScreen')
    if delayTimeSpinBox then
        delayTimeSpinBox:setValue(settings.delayTimeLootOnScreen)
        delayTimeSpinBox.onValueChange = function(widget, value)
            modules.loot_stats.setDelayTimeLootOnScreen(value)
        end
    end
  
    local ignoreMonsterLevelCheckBox = optionsPanel:recursiveGetChildById('ignoreMonsterLevelSystem')
    if ignoreMonsterLevelCheckBox then
        ignoreMonsterLevelCheckBox:setChecked(settings.ignoreMonsterLevelSystem)
        ignoreMonsterLevelCheckBox.onCheckChange = function(widget, checked)
            modules.loot_stats.setIgnoreMonsterLevelSystem(checked)
        end
    end
  
    local ignoreDotCheckBox = optionsPanel:recursiveGetChildById('ignoreLastSignWhenDot')
    if ignoreDotCheckBox then
        ignoreDotCheckBox:setChecked(settings.ignoreLastSignWhenDot)
        ignoreDotCheckBox.onCheckChange = function(widget, checked)
            modules.loot_stats.setIgnoreLastSignWhenDot(checked)
        end
    end

    -- Add button to client options
    if modules.client_options.addButton then
        modules.client_options.addButton('Loot Stats', 'Loot Display', optionsPanel)
    end
end

function LootStatsOptions.updateUI()
    if not optionsPanel then return end
    
    -- Get current settings
    local settings = modules.loot_stats.getSettings()
    
    -- Update UI elements
    local showLootCheckBox = optionsPanel:recursiveGetChildById('showLootOnScreen')
    if showLootCheckBox then
        showLootCheckBox:setChecked(settings.showLootOnScreen)
    end
    
    local amountLootSpinBox = optionsPanel:recursiveGetChildById('amountLootOnScreen')
    if amountLootSpinBox then
        amountLootSpinBox:setValue(settings.amountLootOnScreen)
    end
    
    local delayTimeSpinBox = optionsPanel:recursiveGetChildById('delayTimeLootOnScreen')
    if delayTimeSpinBox then
        delayTimeSpinBox:setValue(settings.delayTimeLootOnScreen)
    end
    
    local ignoreMonsterLevelCheckBox = optionsPanel:recursiveGetChildById('ignoreMonsterLevelSystem')
    if ignoreMonsterLevelCheckBox then
        ignoreMonsterLevelCheckBox:setChecked(settings.ignoreMonsterLevelSystem)
    end
    
    local ignoreDotCheckBox = optionsPanel:recursiveGetChildById('ignoreLastSignWhenDot')
    if ignoreDotCheckBox then
        ignoreDotCheckBox:setChecked(settings.ignoreLastSignWhenDot)
    end
end

function LootStatsOptions.terminate()
    -- Remove button from options
    if modules.client_options and modules.client_options.removeButton then
        pcall(function()
            modules.client_options.removeButton('Loot Stats', 'Loot Display')
        end)
    end
    
    -- Destroy panel if exists
    if optionsPanel and not optionsPanel:isDestroyed() then
        optionsPanel:destroy()
        optionsPanel = nil
    end
end

-- Return module for usage
return LootStatsOptions