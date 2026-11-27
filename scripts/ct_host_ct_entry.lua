local CANDIDATE_SLOTS = { 7, 8, 5, 4, 3, 2, 1 }
local nMenuSlot = nil

function onInit()
	if super and super.onInit then
		super.onInit();
	end

	nMenuSlot = nil
	if hasMenuItem then
		for _, nSlot in ipairs(CANDIDATE_SLOTS) do
			if not hasMenuItem(nSlot) then
				nMenuSlot = nSlot
				break
			end
		end
	else
		nMenuSlot = 7
	end

	if nMenuSlot then
		registerMenuItem("Apply StrengthOfTheGrave to Unconscious Actor", "white_strengthofthegrave_icon", nMenuSlot)
	end
end

function onMenuSelection(selection, subselection, subsubselection)
    if nMenuSlot and selection == nMenuSlot then
        local nodeCT = getDatabaseNode()
        if nodeCT then
            applyStrengthOfTheGrave(nodeCT)
        end
        return
    end

    if super and super.onMenuSelection then
        super.onMenuSelection(selection, subselection, subsubselection)
    end
end

function applyStrengthOfTheGrave(nodeCT)
    StrengthOfTheGrave.applyStrengthOfTheGrave(nodeCT)
end
