--
-- FarmHand
--
-- Entry point and bootstrap for the FarmHand employment mod.
--
-- Responsibilities of this file:
--   * expose the mod name / directory so other modules can locate resources,
--   * load the rest of the mod's scripts,
--   * create the central manager once a savegame is loaded,
--   * wire the in-game month rollover through to the manager's tick.
--
-- The actual employment logic lives in scripts/FarmHandManager.lua and the
-- modules it owns. This file should stay thin: load order and lifecycle only.
--

FarmHand = {}

FarmHand.MOD_NAME = g_currentModName
FarmHand.MOD_DIRECTORY = g_currentModDirectory
FarmHand.VERSION = "0.1.0.0"

-- Pull in the rest of the mod. Order matters: settings and worker model are
-- needed before the manager that uses them.
local sourceFiles = {
    "scripts/FarmHandSettings.lua",
    "scripts/FarmHandManager.lua",
}

for _, file in ipairs(sourceFiles) do
    source(FarmHand.MOD_DIRECTORY .. file)
end

-- The live manager instance for the loaded savegame, or nil between games.
FarmHand.manager = nil

--- Create the manager when a mission starts loading.
-- Appended to Mission00.load so it runs for every savegame, single- or
-- multiplayer, as part of normal mission setup.
function FarmHand:onMissionLoad(mission)
    FarmHand.manager = FarmHandManager.new(FarmHand.MOD_DIRECTORY, FarmHand.MOD_NAME)
    FarmHand.manager:load()
end

--- Tear the manager down when the mission ends so a fresh game starts clean.
function FarmHand:onMissionDelete()
    if FarmHand.manager ~= nil then
        FarmHand.manager:delete()
        FarmHand.manager = nil
    end
end

--- Forward the in-game month rollover to the manager.
-- Everything the mod does on a schedule (course progress, experience tally,
-- wages, retention, candidate refresh) is driven from here.
function FarmHand:onPeriodChanged()
    if FarmHand.manager ~= nil then
        FarmHand.manager:onMonthChanged()
    end
end

local function init()
    -- Lifecycle hooks into the base mission.
    Mission00.load = Utils.appendedFunction(Mission00.load, function(mission, ...)
        FarmHand:onMissionLoad(mission)
    end)

    Mission00.delete = Utils.prependedFunction(Mission00.delete, function(mission, ...)
        FarmHand:onMissionDelete()
    end)

    -- The month rollover is the mod's heartbeat.
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, FarmHand.onPeriodChanged, FarmHand)
end

init()
