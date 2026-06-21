--
-- FarmHandsDialog
--
-- Modal roster panel. Lists the employed hands (name + held certificates) and
-- lets the player click one to make it the active hand. Subclass of the base
-- MessageDialog, opened via the FARMHAND_OPEN input action.
--
-- Built on the same pattern as the game's own roster dialogs: load one GUI XML
-- via g_gui:loadGui, show with g_gui:showDialog, and feed a SmoothList through
-- the get/populate callbacks below.
--

FarmHandsDialog = {}

-- Install-once flag. MUST be a real boolean: assigning nil to a Lua table field
-- does not create the key, so guarding on `FarmHandsDialog.INSTANCE ~= nil`
-- resolved up the MessageDialog metatable chain to an INHERITED non-nil INSTANCE
-- and made register() early-return before ever calling g_gui:loadGui.
FarmHandsDialog.guiLoaded = false

-- The loaded controller instance, set in register() once the GUI is loaded.
FarmHandsDialog.INSTANCE = nil

local FarmHandsDialog_mt = Class(FarmHandsDialog, MessageDialog)
local modDirectory = g_currentModDirectory

--- Load the dialog GUI once and remember the instance.
function FarmHandsDialog.register()
    -- Guard on a real boolean set only AFTER loadGui succeeds. (Do NOT guard on
    -- INSTANCE: it can resolve to an inherited non-nil value via the metatable.)
    if FarmHandsDialog.guiLoaded then
        return
    end

    local dialog = FarmHandsDialog.new()
    g_gui:loadGui(modDirectory .. "gui/FarmHandsDialog.xml", "FarmHandsDialog", dialog)
    FarmHandsDialog.INSTANCE = dialog
    FarmHandsDialog.guiLoaded = true
end

function FarmHandsDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or FarmHandsDialog_mt)

    -- Snapshots for the list, rebuilt on each show / mode switch / hire.
    self.hands = {}      -- roster (HANDS view)
    self.candidates = {} -- hire pool (HIRE view)

    -- Current view: "hands" (roster, click = set active) or "hire" (pool, click = hire).
    self.mode = "hands"

    return self
end

--- Show the panel, refreshing the roster first.
function FarmHandsDialog.show()
    FarmHandsDialog.register()

    local dialog = FarmHandsDialog.INSTANCE
    if dialog == nil then
        return
    end

    -- Always open on the HANDS view. refreshContents rebuilds the snapshot,
    -- reloads the SmoothList (self.handList), and sets the toggle label + selection.
    dialog.mode = "hands"
    dialog:refreshContents()

    g_gui:showDialog("FarmHandsDialog")
end

--- Rebuild the displayed list for the current mode, reload the SmoothList, and
--- update the toggle-button label. Used on open, on mode toggle, and after a hire.
function FarmHandsDialog:refreshContents()
    local manager = FarmHand.manager

    if self.mode == "hire" then
        self.candidates = manager ~= nil and manager.candidates or {}
    else
        self.hands = manager ~= nil and manager:getWorkersList() or {}
    end

    -- The toggle button is labelled by the view it switches TO.
    if self.modeButton ~= nil then
        local key = self.mode == "hire" and "farmhand_ui_view_hands" or "farmhand_ui_view_hire"
        self.modeButton:setText(g_i18n:getText(key))
    end

    if self.handList == nil then
        return
    end
    self.handList:reloadData()

    -- Highlight the active hand in HANDS view, the first candidate in HIRE. When
    -- the hire pool is empty (only the placeholder row) select nothing, so the
    -- placeholder is not rendered as a green selected row.
    if self.mode == "hire" then
        if #self.candidates > 0 then
            self.handList:setSelectedItem(1, 1)
        end
    else
        -- Select the active hand's row. With no active hand (toggled off), select
        -- nothing so no row renders as green/active.
        local selectIndex = nil
        for i, hand in ipairs(self.hands) do
            if manager ~= nil and hand.id == manager.activeHandId then
                selectIndex = i
                break
            end
        end
        if selectIndex ~= nil then
            self.handList:setSelectedItem(1, selectIndex)
        end
    end
end

--- Toggle between the roster (HANDS) and the hire pool (HIRE) views.
function FarmHandsDialog:onClickToggleMode()
    self.mode = self.mode == "hire" and "hands" or "hire"
    self:refreshContents()
end

function FarmHandsDialog:onGuiSetupFinished()
    FarmHandsDialog:superClass().onGuiSetupFinished(self)

    if self.handList ~= nil then
        FocusManager:linkElements(self.handList, FocusManager.TOP, nil)
        FocusManager:linkElements(self.handList, FocusManager.BOTTOM, nil)
    end
end

-- ---- SmoothList data source ------------------------------------------------

function FarmHandsDialog:getNumberOfItemsInSection(list, section)
    if self.mode == "hire" then
        -- At least one row so the "no candidates" placeholder can render.
        return math.max(1, #self.candidates)
    end
    return #self.hands
end

function FarmHandsDialog:getTitleForSectionHeader(list, section)
    return g_i18n:getText("farmhand_ui_title")
end

function FarmHandsDialog:populateCellForItemInSection(list, section, index, cell)
    if self.mode == "hire" then
        self:populateCandidateCell(index, cell)
    else
        self:populateHandCell(index, cell)
    end
end

--- Populate a roster row (HANDS view): name, certificate summary, active marker.
function FarmHandsDialog:populateHandCell(index, cell)
    local hand = self.hands[index]
    if hand == nil then
        return
    end

    -- Re-enable in case this cell was the disabled hire placeholder on a prior load.
    cell:setDisabled(false)

    local nameEl = cell:getAttribute("name")
    if nameEl ~= nil then
        nameEl:setText(hand.name)
    end

    -- Certificate summary (just pesticides for now).
    local certs = {}
    if hand:hasCertificate(FarmHandCertificate.PESTICIDES) then
        certs[#certs + 1] = "PESTICIDES"
    end
    local certText = #certs > 0 and table.concat(certs, ", ") or g_i18n:getText("farmhand_ui_certs_none")
    local certsEl = cell:getAttribute("certs")
    if certsEl ~= nil then
        certsEl:setText(certText)
    end

    -- Active marker.
    local manager = FarmHand.manager
    local isActive = manager ~= nil and manager.activeHandId == hand.id
    local activeEl = cell:getAttribute("active")
    if activeEl ~= nil then
        activeEl:setText(isActive and g_i18n:getText("farmhand_ui_active") or "")
    end

    -- Dim inactive rows so the active hand reads at a glance. Set both branches
    -- every populate (cells are reused on reload, so colours must be refreshed).
    if isActive then
        if nameEl ~= nil then nameEl:setTextColor(1, 1, 1, 1) end
        if certsEl ~= nil then certsEl:setTextColor(0.85, 0.85, 0.85, 1) end
    else
        if nameEl ~= nil then nameEl:setTextColor(0.5, 0.5, 0.5, 1) end
        if certsEl ~= nil then certsEl:setTextColor(0.5, 0.5, 0.5, 1) end
    end
end

--- Populate a candidate row (HIRE view), or the empty-pool placeholder when the
--- pool is empty (a single dimmed "no candidates this month" row).
function FarmHandsDialog:populateCandidateCell(index, cell)
    local nameEl = cell:getAttribute("name")
    local certsEl = cell:getAttribute("certs")
    local activeEl = cell:getAttribute("active")
    if activeEl ~= nil then
        activeEl:setText("")
    end

    local candidate = self.candidates[index]
    if candidate == nil then
        -- Empty-pool placeholder: disabled so it greys out and is non-selectable
        -- (no green highlight), and clicks are ignored.
        cell:setDisabled(true)
        if nameEl ~= nil then
            nameEl:setText(g_i18n:getText("farmhand_ui_no_candidates"))
            nameEl:setTextColor(0.5, 0.5, 0.5, 1)
        end
        if certsEl ~= nil then
            certsEl:setText("")
        end
        return
    end

    -- Real candidate row: re-enable (cells are reused across reloads).
    cell:setDisabled(false)
    if nameEl ~= nil then
        nameEl:setText(candidate.name)
        nameEl:setTextColor(1, 1, 1, 1)
    end
    if certsEl ~= nil then
        certsEl:setText(g_i18n:getText("farmhand_ui_available"))
        certsEl:setTextColor(0.85, 0.85, 0.85, 1)
    end
end

-- ---- Interaction -----------------------------------------------------------

--- Click a list row. HANDS view -> set that hand active; HIRE view -> hire that
--- candidate. Dispatched by mode so the one SmoothList serves both views.
function FarmHandsDialog:onClickHand(item)
    local index = item.indexInSection or (self.handList ~= nil and self.handList.selectedIndex)
    if index == nil then
        return
    end

    if self.mode == "hire" then
        self:hireAtIndex(index)
        return
    end

    local hand = self.hands[index]
    if hand == nil then
        return
    end

    local manager = FarmHand.manager

    -- Click the already-active hand to toggle it OFF (no active hand), so no row
    -- reads as active and a dispatched helper bills the vanilla fee.
    if manager ~= nil and hand.id == manager.activeHandId then
        manager:clearActiveHand()
        self:refreshContents()
        return
    end

    if manager ~= nil then
        manager:setActiveHand(hand.id)
    end

    self.handList:reloadData()
    -- Keep the green selection on the row just made active (reload can reset it).
    self.handList:setSelectedItem(1, index)
end

--- Hire the candidate at the given row, then stay in HIRE view and refresh the
--- now-smaller pool so the player can keep hiring. No-op on the placeholder row.
function FarmHandsDialog:hireAtIndex(index)
    local candidate = self.candidates[index]
    if candidate == nil then
        return -- placeholder row; nothing to hire
    end

    local manager = FarmHand.manager
    if manager ~= nil then
        manager:hireCandidate(candidate.id)
    end

    self:refreshContents()
end

function FarmHandsDialog:onListSelectionChanged(list, section, index)
    -- Selection highlight only; activation happens on click.
end

function FarmHandsDialog:onClickBack()
    self:close()
end
