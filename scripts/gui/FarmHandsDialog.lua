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

    -- Roster snapshot for the list, rebuilt on each show.
    self.hands = {}

    return self
end

--- Show the panel, refreshing the roster first.
function FarmHandsDialog.show()
    FarmHandsDialog.register()

    local dialog = FarmHandsDialog.INSTANCE
    if dialog == nil then
        return
    end

    -- Rebuild the roster snapshot, then reload the list element directly.
    -- reloadData() lives on the SmoothList element (self.handList), not on the
    -- dialog itself.
    local manager = FarmHand.manager
    dialog.hands = manager ~= nil and manager:getWorkersList() or {}
    if dialog.handList ~= nil then
        dialog.handList:reloadData()
    end

    g_gui:showDialog("FarmHandsDialog")
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
    return #self.hands
end

function FarmHandsDialog:getTitleForSectionHeader(list, section)
    return g_i18n:getText("farmhand_ui_title")
end

function FarmHandsDialog:populateCellForItemInSection(list, section, index, cell)
    local hand = self.hands[index]
    if hand == nil then
        return
    end

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
end

-- ---- Interaction -----------------------------------------------------------

--- Click a hand row -> make that hand the active hand.
function FarmHandsDialog:onClickHand(item)
    local index = item.indexInSection or (self.handList ~= nil and self.handList.selectedIndex)
    local hand = self.hands[index]
    if hand == nil then
        return
    end

    local manager = FarmHand.manager
    if manager ~= nil then
        manager:setActiveHand(hand.id)
    end

    self.handList:reloadData()
end

function FarmHandsDialog:onListSelectionChanged(list, section, index)
    -- Selection highlight only; activation happens on click.
end

function FarmHandsDialog:onClickBack()
    self:close()
end
