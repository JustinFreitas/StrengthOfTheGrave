local BUTTON_POSITION_INDEX = 7

function onInit()
	if super and super.onInit then
		super.onInit();
	end

    registerMenuItem("Apply StrengthOfTheGrave to Unconscious Actor", "white_strengthofthegrave_icon", BUTTON_POSITION_INDEX)
end

function onMenuSelection(selection, subselection)
    local nodeCT = getDatabaseNode()
    if not nodeCT then return end

    if selection == BUTTON_POSITION_INDEX then
        applyStrengthOfTheGrave(nodeCT)
        return
    end

    if super and super.onMenuSelection then
        super.onMenuSelection(selection, subselection)
    end
end

function applyStrengthOfTheGrave(nodeCT)
    StrengthOfTheGrave.applyStrengthOfTheGrave(nodeCT)
end
