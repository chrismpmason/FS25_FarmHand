--
-- FarmHandShellScreen
--
-- Build-2 UI rebuild, SUB-SLICE 1: an EMPTY full-screen tabbed shell. Proves the
-- frame + tab-switching in isolation before any content is ported.
--
-- A custom ScreenElement (NOT the heavy TabbedMenu machinery) — most self-
-- contained for a mod and least likely to fight the layout system. Loaded via
-- g_gui:loadGui, shown with g_gui:showGui, closed via onClickBack -> showGui("").
-- Left-hand nav with four tabs (Roster / Hire / College / Overview) swapping
-- placeholder content panes. No real content, no manager/logic changes.
--
-- The existing K dialog (FarmHandsDialog) is deliberately untouched and keeps
-- working; this shell opens on a TEMPORARY key while it is built out.
--

FarmHandShellScreen = {}

-- Install-once guard for the GUI load (a real boolean; see FarmHandsDialog note).
FarmHandShellScreen.guiLoaded = false
FarmHandShellScreen.INSTANCE = nil

local FarmHandShellScreen_mt = Class(FarmHandShellScreen, ScreenElement)
local modDirectory = g_currentModDirectory

-- Note: g_gui:loadGui auto-binds every id in the XML to self.<id> (no
-- registerControls needed — that method doesn't exist on the FS25 10.0.0 GUI
-- chain). So self.tabRoster / self.paneRoster etc. resolve after load; see
-- onGuiSetupFinished. The XML ids must match those names.

--- Load the shell GUI once and remember the controller instance.
function FarmHandShellScreen.register()
    if FarmHandShellScreen.guiLoaded then
        return
    end

    local controller = FarmHandShellScreen.new()
    g_gui:loadGui(modDirectory .. "gui/FarmHandShellScreen.xml", "FarmHandShellScreen", controller)
    FarmHandShellScreen.INSTANCE = controller
    FarmHandShellScreen.guiLoaded = true
end

function FarmHandShellScreen.new(target, customMt)
    local self = ScreenElement.new(target, customMt or FarmHandShellScreen_mt)

    -- Default to the Roster tab.
    self.activeTab = 1

    return self
end

function FarmHandShellScreen:onGuiSetupFinished()
    FarmHandShellScreen:superClass().onGuiSetupFinished(self)

    -- Index the active-tab highlight fills and the panes.
    self.tabHls = { self.tabHlRoster, self.tabHlHire, self.tabHlCollege, self.tabHlOverview }
    self.panes = { self.paneRoster, self.paneHire, self.paneCollege, self.paneOverview }

    -- Tab icons are PARKED (text-only tabs for now). The external ui_*.dds load
    -- without error but won't render in this ScreenElement context. The assets and
    -- this binding are kept; to re-enable, uncomment the icon <Bitmap> in each tab
    -- in FarmHandShellScreen.xml and the block below (and restore the label offset).
    -- local iconDir = modDirectory .. "gui/icons/"
    -- local icons = {
    --     { self.iconRoster, "ui_roster.dds" },
    --     { self.iconHire, "ui_hire.dds" },
    --     { self.iconCollege, "ui_college.dds" },
    --     { self.iconOverview, "ui_overview.dds" },
    -- }
    -- for _, entry in ipairs(icons) do
    --     local element, file = entry[1], entry[2]
    --     if element ~= nil and element.setImageFilename ~= nil then
    --         element:setImageFilename(iconDir .. file)
    --     end
    -- end
end

--- Show the shell (loads it on first use).
function FarmHandShellScreen.show()
    FarmHandShellScreen.register()
    if FarmHandShellScreen.INSTANCE ~= nil then
        g_gui:showGui("FarmHandShellScreen")
    end
end

function FarmHandShellScreen:onOpen()
    FarmHandShellScreen:superClass().onOpen(self)
    self:selectTab(self.activeTab or 1)
end

--- Show one tab's placeholder pane, hide the others, and highlight the active tab
--- by showing only its green fill (inactive tabs show no fill, so their icon +
--- label read as unselected).
function FarmHandShellScreen:selectTab(index)
    self.activeTab = index

    if self.panes ~= nil then
        for i, pane in ipairs(self.panes) do
            if pane ~= nil then
                pane:setVisible(i == index)
            end
        end
    end

    if self.tabHls ~= nil then
        for i, hl in ipairs(self.tabHls) do
            if hl ~= nil then
                hl:setVisible(i == index)
            end
        end
    end
end

-- Per-tab click handlers (kept thin and explicit).
function FarmHandShellScreen:onClickTabRoster()
    self:selectTab(1)
end

function FarmHandShellScreen:onClickTabHire()
    self:selectTab(2)
end

function FarmHandShellScreen:onClickTabCollege()
    self:selectTab(3)
end

function FarmHandShellScreen:onClickTabOverview()
    self:selectTab(4)
end

--- ESC / Back: close the shell and return to the game.
function FarmHandShellScreen:onClickBack()
    g_gui:showGui("")
    return true
end
