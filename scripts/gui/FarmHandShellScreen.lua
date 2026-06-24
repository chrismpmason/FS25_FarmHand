--
-- FarmHandShellScreen
--
-- Build-2 UI rebuild. SUB-SLICE 1 built the empty tabbed shell; SUB-SLICE 2 ports
-- the Roster view into its pane (live hand list: click to set active, dismiss with
-- confirm). Hire / College / Overview stay placeholders, ported in later slices.
--
-- A custom ScreenElement (NOT the heavy TabbedMenu machinery) — most self-
-- contained for a mod and least likely to fight the layout system. Loaded via
-- g_gui:loadGui, shown with g_gui:showGui, closed via onClickBack -> showGui("").
-- The Roster list reuses the K dialog's proven SmoothList pattern and reads the
-- SAME manager state (no manager/logic changes). The K dialog stays untouched.
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

    -- Roster snapshot for the list (rebuilt on open / Roster select / change).
    self.rosterHands = {}

    return self
end

function FarmHandShellScreen:onGuiSetupFinished()
    FarmHandShellScreen:superClass().onGuiSetupFinished(self)

    -- Index the active-tab highlight fills and the panes.
    self.tabHls = { self.tabHlRoster, self.tabHlHire, self.tabHlCollege, self.tabHlOverview }
    self.panes = { self.paneRoster, self.paneHire, self.paneCollege, self.paneOverview }

    -- Roster list focus (mirrors the K dialog's handList linking).
    if self.rosterList ~= nil then
        FocusManager:linkElements(self.rosterList, FocusManager.TOP, nil)
        FocusManager:linkElements(self.rosterList, FocusManager.BOTTOM, nil)
    end

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

    -- Refresh the Roster list whenever its tab is shown.
    if index == 1 then
        self:refreshRoster()
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

-- ---- Roster pane (live hand list) -----------------------------------------

--- Rebuild the roster snapshot from the manager, reload the list, and select the
--- active hand's row (native-green highlight). No active hand -> no selection.
function FarmHandShellScreen:refreshRoster()
    local manager = FarmHand.manager
    self.rosterHands = manager ~= nil and manager:getWorkersList() or {}

    if self.rosterList == nil then
        return
    end
    self.rosterList:reloadData()

    local selectIndex = nil
    for i, hand in ipairs(self.rosterHands) do
        if manager ~= nil and hand.id == manager.activeHandId then
            selectIndex = i
            break
        end
    end
    if selectIndex ~= nil then
        self.rosterList:setSelectedItem(1, selectIndex)
    end
end

-- SmoothList data source (the shell has one list for now: the roster).
function FarmHandShellScreen:getNumberOfSections(list)
    return 1
end

function FarmHandShellScreen:getNumberOfItemsInSection(list, section)
    return self.rosterHands ~= nil and #self.rosterHands or 0
end

function FarmHandShellScreen:getTitleForSectionHeader(list, section)
    return ""
end

function FarmHandShellScreen:populateCellForItemInSection(list, section, index, cell)
    local hand = self.rosterHands ~= nil and self.rosterHands[index] or nil
    if hand == nil then
        return
    end

    local mgr = FarmHand.manager

    local nameEl = cell:getAttribute("name")
    if nameEl ~= nil then nameEl:setText(hand.name) end

    local tierEl = cell:getAttribute("tier")
    if tierEl ~= nil and mgr ~= nil then
        if mgr:getTier(hand) >= 3 then
            tierEl:setText(mgr:getTierName(hand))
        else
            tierEl:setText(string.format("%s %d%%", mgr:getTierName(hand),
                math.floor(mgr:getTierProgress(hand) * 100 + 0.5)))
        end
    end

    local gradeEl = cell:getAttribute("grade")
    if gradeEl ~= nil and mgr ~= nil then gradeEl:setText(mgr:getGradeName(hand)) end

    local wageEl = cell:getAttribute("wage")
    if wageEl ~= nil and mgr ~= nil then wageEl:setText(string.format("£%d", mgr:getWorkerMonthlyWage(hand))) end

    local expEl = cell:getAttribute("exp")
    if expEl ~= nil then expEl:setText(string.format("%.1f ha", hand.hectaresWorked or 0)) end

    local isActive = mgr ~= nil and mgr.activeHandId == hand.id
    local activeEl = cell:getAttribute("active")
    if activeEl ~= nil then
        activeEl:setText(isActive and g_i18n:getText("farmhand_ui_active") or "")
    end

    -- Dim inactive rows; the active row reads bright (and is green-selected).
    local shade = isActive and 1.0 or 0.6
    for _, n in ipairs({ "name", "tier", "grade", "wage", "exp" }) do
        local e = cell:getAttribute(n)
        if e ~= nil then e:setTextColor(shade, shade, shade, 1) end
    end
end

--- Click a row -> set that hand active (the real activeHandId the worker system
--- uses). Re-clicking the active hand clears it, matching the K dialog's toggle.
function FarmHandShellScreen:onClickHand(item)
    local index = item.indexInSection or (self.rosterList ~= nil and self.rosterList.selectedIndex)
    if index == nil then
        return
    end
    local hand = self.rosterHands ~= nil and self.rosterHands[index] or nil
    if hand == nil then
        return
    end

    local manager = FarmHand.manager
    if manager ~= nil and hand.id == manager.activeHandId then
        manager:clearActiveHand()
        self:refreshRoster()
        return
    end

    if manager ~= nil then
        manager:setActiveHand(hand.id)
    end
    self.rosterList:reloadData()
    self.rosterList:setSelectedItem(1, index)
end

--- Dismiss the selected hand, confirmed via YesNoDialog (id stashed on self, as
--- the K dialog does). On confirm -> manager:removeWorker -> refresh.
function FarmHandShellScreen:onClickDismiss()
    local index = self.rosterList ~= nil and self.rosterList.selectedIndex or nil
    local hand = index ~= nil and self.rosterHands ~= nil and self.rosterHands[index] or nil
    if hand == nil then
        return
    end

    self.pendingDismissId = hand.id
    YesNoDialog.show(
        self.onDismissConfirmed,
        self,
        string.format("Dismiss %s? Their experience, certificates and course progress will be lost.", hand.name))
end

function FarmHandShellScreen:onDismissConfirmed(yes)
    local handId = self.pendingDismissId
    self.pendingDismissId = nil
    if not yes or handId == nil then
        return
    end

    local manager = FarmHand.manager
    if manager ~= nil then
        manager:removeWorker(handId)
    end
    self:refreshRoster()
end

--- ESC / Back: close the shell and return to the game.
function FarmHandShellScreen:onClickBack()
    g_gui:showGui("")
    return true
end
