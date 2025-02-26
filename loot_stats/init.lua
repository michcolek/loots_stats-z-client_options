-- Funkcja inicjalizacyjna modułu
local initCallback = nil
local terminateCallback = nil

function init()
    -- Załaduj główny plik modułu
    g_modules.importModule('loot_stats')
    
    -- Załaduj moduł opcji
    g_modules.importModule('loot_stats/loot_stats_options')
    
    -- Utwórz katalog na ikony
    if g_resources.directoryExists('/images/game') and not g_resources.directoryExists('/images/game/loot_stats') then
        g_resources.makeDir('/images/game/loot_stats')
    end
    
    -- Skopiuj ikonę jeśli nie istnieje
    if not g_resources.fileExists('/images/game/loot_stats/icon.png') and g_resources.fileExists('/loot_stats/ui/img/icon.png') then
        local iconData = g_resources.readFileContents('/loot_stats/ui/img/icon.png')
        if iconData then
            g_resources.writeFileContents('/images/game/loot_stats/icon.png', iconData)
        end
    end
    
    -- Zainicjuj moduł loot_stats
    LootStats.init()
    
    -- Podłącz zdarzenia gry
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
    
    -- Inicjalizuj opcje jeśli już jesteśmy połączeni
    if g_game.isOnline() then
        onGameStart()
    end
    
    return true
end

function terminate()
    -- Odłącz zdarzenia gry
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
    
    -- Wyczyść zdarzenia zaplanowane
    if initCallback then
        removeEvent(initCallback)
        initCallback = nil
    end
    
    if terminateCallback then
        removeEvent(terminateCallback)
        terminateCallback = nil
    end
    
    -- Zakończ moduł opcji
    if modules.loot_stats_options then
        modules.loot_stats_options.terminate()
    end
    
    -- Zakończ główny moduł
    if modules.loot_stats then
        modules.loot_stats.terminate()
    end
    
    return true
end

function onGameStart()
    initCallback = scheduleEvent(function()
        if modules.loot_stats_options then
            modules.loot_stats_options.init()
        end
        initCallback = nil
    end, 500)
end

function onGameEnd()
    if initCallback then
        removeEvent(initCallback)
        initCallback = nil
    end
    
    terminateCallback = scheduleEvent(function()
        if modules.loot_stats_options then
            modules.loot_stats_options.terminate()
        end
        terminateCallback = nil
    end, 500)
end
