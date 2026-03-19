-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
USER_ISHOST = false

local ActionDamage_applyDamage
local ActionSave_onSave
local DEFAULT_STRENGTH_OF_THE_GRAVE_DC_MOD = 5
local HP_TEMPORARY = "hp.temporary"
local HP_TOTAL = "hp.total"
local HP_WOUNDS = "hp.wounds"
local HPTEMP = "hptemp"
local HPTOTAL = "hptotal"
local MSGFONT = "msgfont"
local NAME = "name"
local NIL = "nil"
local UNCONSCIOUS_EFFECT_LABEL = "Unconscious"
local WOUNDS = "wounds"

function onInit()
    USER_ISHOST = User.isHost()

	if USER_ISHOST then
		Comm.registerSlashHandler("sg", processChatCommand)
		Comm.registerSlashHandler("sotg", processChatCommand)
		Comm.registerSlashHandler("strengthofthegrave", processChatCommand)
        ActionSave_onSave = ActionSave.onSave
        ActionSave.onSave = onSaveNew
        if ActionHealthD20 and ActionHealthD20.apply then
            ActionDamage_applyDamage = ActionHealthD20.apply
            ActionHealthD20.apply = applyDamage_v2
        elseif ActionDamage and ActionDamage.applyDamage then
            ActionDamage_applyDamage = ActionDamage.applyDamage
            if isClientFGU() then
                ActionDamage.applyDamage = applyDamage_FGU
            else
                ActionDamage.applyDamage = applyDamage_FGC
            end
        end
    end
end

function getCTNodeForDisplayName(sDisplayName)
	for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
        if ActorManager.getDisplayName(nodeCT) == sDisplayName then
            return nodeCT
        end
    end

    return nil
end

function processChatCommand(_, sParams)
    local nodeCT = getCTNodeForDisplayName(sParams)
    if nodeCT == nil then
        displayChatMessage(sParams .. " was not found in the Combat Tracker, skipping StrengthOfTheGrave application.")
        return
    end

    applyStrengthOfTheGrave(nodeCT)
end

function displayChatMessage(sFormattedText)
	if not sFormattedText then return end

	local msg = {font = MSGFONT, icon = "strengthofthegrave_icon", secret = true, text = sFormattedText}
    Comm.addChatMessage(msg) -- local, not broadcast
end

function applyStrengthOfTheGrave(nodeCT)
    local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(nodeCT)
	if not nodeTarget then
		return
	end

    local sWounds
    if sTargetNodeType == "pc" then
        sWounds = HP_WOUNDS
    elseif sTargetNodeType == "ct" then
        sWounds = WOUNDS
	else
		return
	end

    local sDisplayName = ActorManager.getDisplayName(nodeTarget)
    if not EffectManager5E.hasEffect(nodeTarget, UNCONSCIOUS_EFFECT_LABEL) then
        displayChatMessage(sDisplayName .. " is not an unconscious actor, skipping StrengthOfTheGrave application.")
        return
    end

    local aTargetHealthData = getTargetHealthData(sTargetNodeType, nodeTarget, {})
    local nWounds = aTargetHealthData.nTotalHP - 1
    DB.setValue(nodeTarget, sWounds, "number", nWounds)
    EffectManager.removeEffect(nodeCT, UNCONSCIOUS_EFFECT_LABEL)
    EffectManager.removeEffect(nodeCT, "Prone")
    displayChatMessage("StrengthOfTheGrave was applied to " .. sDisplayName .. ".")
end

function isClientFGU()
    return Session.VersionMajor >= 4
end

function onSaveNew(rSource, rTarget, rRoll)
    if rRoll.bStrengthOfTheGrave == nil then
        if ActionSave_onSave then
            ActionSave_onSave(rSource, rTarget, rRoll)
        end
        return
    end

    if ActionD20 and ActionD20.decodeAdvantage then
        ActionD20.decodeAdvantage(rRoll)
    elseif ActionsManager2 and ActionsManager2.decodeAdvantage then
        ActionsManager2.decodeAdvantage(rRoll)
    end
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll)
	Comm.deliverChatMessage(rMessage)

    local nModDC
    if rRoll.sModDC == nil or rRoll.sModDC == NIL then
        nModDC = DEFAULT_STRENGTH_OF_THE_GRAVE_DC_MOD
    else
        nModDC = tonumber(rRoll.sModDC)
    end

    local nDamage = tonumber(rRoll.nDamage)
    local nDC
    if rRoll.sStaticDC == nil or rRoll.sStaticDC == NIL then
        nDC = nModDC + nDamage
    else
        nDC = tonumber(rRoll.sStaticDC)
    end

    local msgShort = {font = MSGFONT}
	local msgLong = {font = MSGFONT}
    local nChaSave = ActionsManager.total(rRoll)
	msgShort.text = rRoll.sTrimmedTraitNameForSave
	msgLong.text = rRoll.sTrimmedTraitNameForSave .. " [" .. nChaSave ..  "]"
    msgLong.text = msgLong.text .. "[vs. DC " .. nDC .. "]"
	msgShort.text = msgShort.text .. " ->"
	msgLong.text = msgLong.text .. " ->"
    msgShort.text = msgShort.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]"
    msgLong.text = msgLong.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]"
	msgShort.icon = "roll_cast"

	if nChaSave >= nDC then
		msgLong.text = msgLong.text .. " [SUCCESS]"
	else
		msgLong.text = msgLong.text .. " [FAILURE]"
	end

    ActionsManager.outputResult(rRoll.bSecret, rSource, nil, msgLong, msgShort)

    -- Strength of the Grave processing
    local nAllHP = rRoll.nTotalHP + rRoll.nTempHP
    local bSecret = (rRoll.bSecret == "1" or rRoll.bSecret == true)

    if nChaSave >= nDC then
        -- Strength of the Grave save was made!
        local vPower = getOrCreateStrengthOfTheGravePower(rSource)
        local nPrepared, nCast = getPreparedAndCastFromStrengthOfTheGravePower(vPower)
        if nCast < nPrepared then
            setCastValueOnPower(vPower, nCast + 1)
        end
        nDamage = nAllHP - rRoll.nWounds - 1
        local sDamage = string.gsub(rRoll.sDamage, "=%-?%d+", "=" .. nDamage)

        local rDamageRoll = {
            sType = "damage",
            sDesc = sDamage,
            nTotal = tonumber(nDamage),
            aDice = {},
            bSecret = bSecret
        }

        if ActionHealthD20 and ActionHealthD20.apply then
            ActionDamage_applyDamage(rSource, rTarget or rSource, rDamageRoll)
        elseif isClientFGU() then
            ActionDamage_applyDamage(rSource, rTarget or rSource, rDamageRoll)
        else
            ActionDamage_applyDamage(rSource, rTarget or rSource, bSecret, sDamage, nDamage)
        end
    else
        -- Strength of the Grave save was NOT made
        if tonumber(rRoll.nWounds) < tonumber(rRoll.nTotalHP) then
            local rDamageRoll = {
                sType = "damage",
                sDesc = rRoll.sDamage,
                nTotal = tonumber(rRoll.nDamage),
                aDice = {},
                bSecret = bSecret
            }
            if ActionHealthD20 and ActionHealthD20.apply then
                ActionDamage_applyDamage(rSource, rTarget or rSource, rDamageRoll)
            elseif isClientFGU() then
                ActionDamage_applyDamage(rSource, rTarget or rSource, rDamageRoll)
            else
                ActionDamage_applyDamage(rSource, rTarget or rSource, bSecret, rRoll.sDamage, tonumber(rRoll.nDamage))
            end
        end
    end
end


function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
 end

function getOrCreateStrengthOfTheGravePower(vActor)
    if not vActor or not ActorManager.isPC(vActor) then return nil end

    local rCurrentActor = ActorManager.resolveActor(vActor)
    local nodeCharSheet = DB.findNode(rCurrentActor.sCreatureNode)
    for _,vPower in pairs(DB.getChildren(nodeCharSheet, "powers")) do
        if DB.getValue(vPower, NAME, ""):lower() == "strength of the grave" then
            return vPower
        end
    end

    local nodePowers = nodeCharSheet.createChild("powers")
    if not nodePowers then
        return nil;
    end

    local nodeNewPower = nodePowers.createChild()
    if not nodeNewPower then
        return nil
    end

    DB.setValue(nodeNewPower, NAME, "string", "Strength of the Grave")
    DB.setValue(nodeNewPower, "prepared", "number", 1)
    DB.setValue(nodeNewPower, "cast", "number", 0)
    DB.setValue(nodeNewPower, "locked", "number", 1)
    DB.setValue(nodeNewPower, "shortdescription", "string", "When you are reduced to 0 hit points and are not killed outright, you can make a Charisma saving throw. If you succeed, you drop to 1 hit point instead. You can't use this feature again until you finish a long rest.")
    return nodeNewPower
end

function getPreparedAndCastFromStrengthOfTheGravePower(vPower)
    return DB.getValue(vPower, "prepared", 0), DB.getValue(vPower, "cast", 0)
end

function setCastValueOnPower(vPower, nCast)
    DB.setValue(vPower, "cast", "number", nCast)
end

function hasAvailableStrengthOfTheGrave(aData)
    return aData
           and aData.nPrepared > 0
           and aData.nCast < aData.nPrepared
end

function hasStrengthOfTheGraveTrait(sTargetNodeType, nodeTarget, rRoll)
    local aTraits
	if sTargetNodeType == "pc" then
        -- This was traitlist when spawned from Undead Fortitude but Shadow Magic is a Sorcerer subclass from Xanathar's that shows in the feature list.
        aTraits = DB.getChildren(nodeTarget, "featurelist")
    elseif sTargetNodeType == "ct" then
        aTraits = DB.getChildren(nodeTarget, "traits")
	else
		return
	end

    for _, aTrait in pairs(aTraits) do
        local aDecomposedTraitName = getDecomposedTraitName(aTrait)
        if aDecomposedTraitName.nStrengthOfTheGraveStart ~= nil then
            return getStrengthOfTheGraveData(aDecomposedTraitName, aTraits, sTargetNodeType, nodeTarget, rRoll)
        end
    end
end

function getTargetHealthData_FGC(sTargetNodeType, nodeTarget)
    local nTotalHP = DB.getValue(nodeTarget, HP_TOTAL, 0)
    local nTempHP = DB.getValue(nodeTarget, HP_TEMPORARY, 0)
    local nWounds = DB.getValue(nodeTarget, HP_WOUNDS, 0)
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, HP_TOTAL, 0)
		nTempHP = DB.getValue(nodeTarget, HP_TEMPORARY, 0)
		nWounds = DB.getValue(nodeTarget, HP_WOUNDS, 0)
    elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, HPTOTAL, 0)
		nTempHP = DB.getValue(nodeTarget, HPTEMP, 0)
		nWounds = DB.getValue(nodeTarget, WOUNDS, 0)
	end

    return {
        nTotalHP = nTotalHP,
        nTempHP = nTempHP,
        nWounds = nWounds
    }
end

function getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rRoll)
    local nTotalHP = DB.getValue(nodeTarget, HP_TOTAL, 0)
    local nTempHP = DB.getValue(nodeTarget, HP_TEMPORARY, 0)
    local nWounds = DB.getValue(nodeTarget, HP_WOUNDS, 0)
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, HP_TOTAL, 0)
		nTempHP = DB.getValue(nodeTarget, HP_TEMPORARY, 0)
		nWounds = DB.getValue(nodeTarget, HP_WOUNDS, 0)
    elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, HPTOTAL, 0)
		nTempHP = DB.getValue(nodeTarget, HPTEMP, 0)
		nWounds = DB.getValue(nodeTarget, WOUNDS, 0)
	elseif sTargetNodeType == "ct" and ActorManager.isRecordType(nodeTarget, "vehicle") then
		if (rRoll.sSubtargetPath or "") ~= "" then
			nTotalHP = DB.getValue(DB.getPath(rRoll.sSubtargetPath, "hp"), 0)
			nWounds = DB.getValue(DB.getPath(rRoll.sSubtargetPath, WOUNDS), 0)
			nTempHP = 0
		else
			nTotalHP = DB.getValue(nodeTarget, HPTOTAL, 0)
			nTempHP = DB.getValue(nodeTarget, HPTEMP, 0)
			nWounds = DB.getValue(nodeTarget, WOUNDS, 0)
		end
	end

    return {
        nTotalHP = nTotalHP,
        nTempHP = nTempHP,
        nWounds = nWounds
    }
end

function getTargetHealthData(sTargetNodeType, nodeTarget, rRoll)
    if isClientFGU() then
        return getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rRoll)
    else
        return getTargetHealthData_FGC(sTargetNodeType, nodeTarget)
    end
end

function getStrengthOfTheGraveData(aDecomposedTraitName, aTraits, sTargetNodeType, nodeTarget, rRoll)
    local sTrimmedSuffixLower = trim(aDecomposedTraitName.sStrengthOfTheGraveTraitSuffix):lower()
    local nStaticDC = tonumber(sTrimmedSuffixLower:match("dc%s*(-?%d+)"))
    local nModDC = tonumber(sTrimmedSuffixLower:match("mod%s*(-?%d+)"))
    local bNoMods = trim(sTrimmedSuffixLower):find("no%s*mods")

    local vPower = getOrCreateStrengthOfTheGravePower(nodeTarget)
    local nPrepared, nCast = getPreparedAndCastFromStrengthOfTheGravePower(vPower)

    local aTargetHealthData = getTargetHealthData(sTargetNodeType, nodeTarget, rRoll)
    return {
        nTotalHP = aTargetHealthData.nTotalHP,
        nTempHP = aTargetHealthData.nTempHP,
        nWounds = aTargetHealthData.nWounds,
        aTraits = aTraits,
        nStaticDC = nStaticDC,
        nModDC = nModDC,
        nPrepared = nPrepared,
        nCast = nCast,
        bNoMods = bNoMods,
        sTrimmedTraitNameForSave = aDecomposedTraitName.sTrimmedTraitNameForSave
    }
end

function getDecomposedTraitName(aTrait)
    local sTraitName = DB.getText(aTrait, "name")
    local sTraitNameLower = sTraitName:lower()
    local nStrengthOfTheGraveStart, nStrengthOfTheGraveEnd = sTraitNameLower:find("strength of the grave")
    local sStrengthOfTheGraveTraitPrefix, sStrengthOfTheGraveTraitSuffix, sTrimmedTraitNameForSave
    if nStrengthOfTheGraveStart ~= nil and nStrengthOfTheGraveEnd ~= nil then
        sStrengthOfTheGraveTraitPrefix = sTraitName:sub(1, nStrengthOfTheGraveStart - 1)
        sStrengthOfTheGraveTraitSuffix = sTraitName:sub(nStrengthOfTheGraveEnd + 1)
        sTrimmedTraitNameForSave = trim(sTraitName:sub(1, nStrengthOfTheGraveEnd))
    end

    return {
        sTraitName = sTraitName,
        sTraitNameLower = sTraitNameLower,
        nStrengthOfTheGraveStart = nStrengthOfTheGraveStart,
        nStrengthOfTheGraveEnd = nStrengthOfTheGraveEnd,
        sStrengthOfTheGraveTraitPrefix = sStrengthOfTheGraveTraitPrefix,
        sStrengthOfTheGraveTraitSuffix = sStrengthOfTheGraveTraitSuffix,
        sTrimmedTraitNameForSave = sTrimmedTraitNameForSave
    }
end

function processStrengthOfTheGrave(aData, nTotal, sDamage, rTarget, bSecret)
    local nAllHP = aData.nTotalHP + aData.nTempHP
    if aData.nWounds + nTotal >= nAllHP
       and (aData.bNoMods or not string.find(sDamage, "%[TYPE:.*radiant.*%]"))
       and (aData.bNoMods or not string.find(sDamage, "%[CRITICAL%]"))
       and not EffectManager5E.hasEffect(rTarget, UNCONSCIOUS_EFFECT_LABEL)
       and aData.nTotalHP > aData.nWounds then

        local sDisplayName = ActorManager.getDisplayName(rTarget)
        local vPower = getOrCreateStrengthOfTheGravePower(rTarget)
        local nPrepared, nCast = getPreparedAndCastFromStrengthOfTheGravePower(vPower)

        if nCast >= nPrepared then
            displayChatMessage(sDisplayName .. " has used all of their Strength of the Grave for the day.")
            return
        end

        local rRoll = { }
        rRoll.sType = "save"
        rRoll.aDice = { "d20" }
        local nMod, bADV, bDIS, sAddText = ActorManager5E.getSave(rTarget, "charisma")
        rRoll.nMod = nMod
        rRoll.sDesc = "[SAVE] Charisma for " .. aData.sTrimmedTraitNameForSave
        rRoll.sSaveDesc = ""
        if sAddText and sAddText ~= "" then
            rRoll.sDesc = rRoll.sDesc .. " " .. sAddText
        end

        if bADV then
            rRoll.sDesc = rRoll.sDesc .. " [ADV]"
        end

        if bDIS then
            rRoll.sDesc = rRoll.sDesc .. " [DIS]"
        end

        rRoll.bSecret = bSecret
        rRoll.bStrengthOfTheGrave = true
        rRoll.nDamage = nTotal
        rRoll.sDamage = sDamage
        rRoll.nTotalHP = aData.nTotalHP
        rRoll.nTempHP = aData.nTempHP
        rRoll.nWounds = aData.nWounds
        rRoll.sModDC = tostring(aData.nModDC) -- override number, can be nil
        rRoll.sStaticDC = tostring(aData.nStaticDC) -- override number, can be nil
        rRoll.sTrimmedTraitNameForSave = aData.sTrimmedTraitNameForSave

        ModifierStack.reset()  -- Modifiers were being applied to the save from the original dmg roll.  Clear it before save.
        ActionsManager.applyModifiersAndRoll(rTarget, rTarget, false, rRoll)
        return true
    end
end

function applyDamage_FGC(rSource, rTarget, bSecret, sDamage, nTotal)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
	if not nodeTarget then return end

    local aData = hasStrengthOfTheGraveTrait(sTargetNodeType, nodeTarget, nil)
    local bStrengthOfTheGraveTriggered
    if aData then
        bStrengthOfTheGraveTriggered = processStrengthOfTheGrave(aData, nTotal, sDamage, rTarget, bSecret)
    end

    if not bStrengthOfTheGraveTriggered then
        ActionDamage_applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
    end
end

function applyDamage_FGU(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
	if not nodeTarget then return end

    local aData = hasStrengthOfTheGraveTrait(sTargetNodeType, nodeTarget, rRoll)
    local bStrengthOfTheGraveTriggered
    if aData then
        bStrengthOfTheGraveTriggered = processStrengthOfTheGrave(aData, rRoll.nTotal, rRoll.sDesc, rTarget, false)
    end

    if not bStrengthOfTheGraveTriggered then
        ActionDamage_applyDamage(rSource, rTarget, rRoll)
    end
end

function applyDamage_v2(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
	if not nodeTarget then return end

    local isDamageRoll = true
    if rRoll and rRoll.sDesc then
        if rRoll.sDesc:match("%[HEAL") or rRoll.sDesc:match("%[RECOVERY") or rRoll.sDesc:match("%[FHEAL") or rRoll.sDesc:match("%[REGEN") then
            isDamageRoll = false
        elseif (rRoll.nTotal or 0) < 0 then
            isDamageRoll = false
        end
    end

    local aData = hasStrengthOfTheGraveTrait(sTargetNodeType, nodeTarget, rRoll)
    local bStrengthOfTheGraveTriggered
    if aData and isDamageRoll and hasAvailableStrengthOfTheGrave(aData) then
        bStrengthOfTheGraveTriggered = processStrengthOfTheGrave(aData, rRoll.nTotal, rRoll.sDesc, rTarget, rRoll.bSecret)
    end

    if not bStrengthOfTheGraveTriggered then
        ActionDamage_applyDamage(rSource, rTarget, rRoll)
    end
end
