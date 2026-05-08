-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
local USER_ISHOST = false

local ActionDamage_applyDamage
local ActionSave_onSave_Ruleset
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

-- Helper to safely check if a string is blank, preferring the modern StringManager method.
local function isBlankSafe(s)
    if StringManager.isBlank then
        return StringManager.isBlank(s)
    end
    if type(s) ~= "string" then
        return false
    end
    return (string.gsub(s, "%s+", "") == "")
end

-- Helper to safely get an actor from a node/string, preferring the modern getActor method.
local function getActorSafe(v)
    if ActorManager.getActor then
        return ActorManager.getActor(v)
    end
    return ActorManager.resolveActor(v)
end

-- Helper to safely get an actor's type and node, preferring the modern getTypeAndNode method.
local function getTypeAndNodeSafe(v)
    if ActorManager.getTypeAndNode then
        return ActorManager.getTypeAndNode(v)
    end
    return ActorManager.getActorTypeAndNode(v)
end

-- Helper to safely check for effects, preferring the modern CoreRPG or 5E-specific EffectManager if available.
local function hasEffectSafe(rActor, sEffect, rTarget, bTargetedOnly)
    if EffectManager.hasEffect then
        return EffectManager.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    if EffectManager5E and EffectManager5E.hasEffect then
        return EffectManager5E.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    return EffectManager.hasEffect(rActor, sEffect)
end

-- Helper to safely fetch saves from the 5E ruleset.
local function getSaveSafe(nodeActor, sSave)
    if ActorManager5E and ActorManager5E.getSave then
        return ActorManager5E.getSave(nodeActor, sSave)
    end
    return 0, false, false, ""
end

-- Helper to safely call the ruleset's damage application function.
local function applyDamageFinal(rSource, rTarget, rRoll, bSecret, sDamage, nTotal)
    if type(ActionDamage_applyDamage) == "function" then
        if isClientFGU() then
            ActionDamage_applyDamage(rSource, rTarget, rRoll)
        else
            ActionDamage_applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
        end
    elseif ActionHealthD20 and type(ActionHealthD20.apply) == "function" then
         ActionHealthD20.apply(rSource, rTarget, rRoll)
    elseif ActionDamage then
        if type(ActionDamage.applyDamage) == "function" then
            if isClientFGU() then
                ActionDamage.applyDamage(rSource, rTarget, rRoll)
            else
                ActionDamage.applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
            end
        elseif type(ActionDamage.apply) == "function" then
            if isClientFGU() then
                ActionDamage.apply(rSource, rTarget, rRoll)
            else
                ActionDamage.apply(rSource, rTarget, bSecret, sDamage, nTotal)
            end
        end
    end
end

function onInit()
    USER_ISHOST = User.isHost()

    -- Initialize upvalues on all instances (Host and Client)
    if ActionHealthD20 and ActionHealthD20.apply then
        ActionDamage_applyDamage = ActionHealthD20.apply
    elseif ActionDamage then
        if ActionDamage.applyDamage then
            ActionDamage_applyDamage = ActionDamage.applyDamage
        elseif ActionDamage.apply then
            ActionDamage_applyDamage = ActionDamage.apply
        end
    end

    -- Capture ruleset result handlers from ActionsManager (Host and Client)
    -- This ensures we get the actual local functions even if they aren't in the global table.
    ActionSave_onSave_Ruleset = ActionsManager.getResultHandler("save")

    -- Register result handlers on all instances
    ActionsManager.registerResultHandler("save", onSaveNew)

	if USER_ISHOST then
		Comm.registerSlashHandler("sg", processChatCommand)
		Comm.registerSlashHandler("sotg", processChatCommand)
		Comm.registerSlashHandler("strengthofthegrave", processChatCommand)
        
        -- Hook damage functions to intercept damage rolls
        if ActionHealthD20 and ActionHealthD20.apply then
            ActionHealthD20.apply = applyDamage_v2
        elseif ActionDamage then
            if ActionDamage.applyDamage then
                if isClientFGU() then
                    ActionDamage.applyDamage = applyDamage_FGU
                else
                    ActionDamage.applyDamage = applyDamage_FGC
                end
            elseif ActionDamage.apply then
                if isClientFGU() then
                    ActionDamage.apply = applyDamage_FGU
                else
                    ActionDamage.apply = applyDamage_FGC
                end
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
	if isBlankSafe(sFormattedText) then return end

	local msg = {font = MSGFONT, icon = "strengthofthegrave_icon", secret = true, text = sFormattedText}
    Comm.addChatMessage(msg) -- local, not broadcast
end

function applyStrengthOfTheGrave(nodeCT)
    local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(nodeCT)
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
    if not hasEffectSafe(nodeTarget, UNCONSCIOUS_EFFECT_LABEL) then
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
    -- Passthrough to ruleset handler
    if type(ActionSave_onSave_Ruleset) == "function" then
        ActionSave_onSave_Ruleset(rSource, rTarget, rRoll)
    end

    if rRoll.bStrengthOfTheGrave == nil then
        return
    end

    -- Explicitly decode advantage/disadvantage using 5E-specific managers to ensure we don't just sum all dice.
    if ActionD20 and ActionD20.decodeAdvantage then
        ActionD20.decodeAdvantage(rRoll)
    elseif ActionsManager2 and ActionsManager2.decodeAdvantage then
        ActionsManager2.decodeAdvantage(rRoll)
    end

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

    local bSecret = (rRoll.bSecret == "1" or rRoll.bSecret == true)
    ActionsManager.outputResult(bSecret, rSource, nil, msgLong, msgShort)

    -- Strength of the Grave processing
    local nAllHP = tonumber(rRoll.nTotalHP or 0) + tonumber(rRoll.nTempHP or 0)
    local rOriginalAttacker = nil
    if rRoll.sOriginalAttacker then
        rOriginalAttacker = getActorSafe(rRoll.sOriginalAttacker)
    end
    local rActualSource = rOriginalAttacker or rSource

    if nChaSave >= nDC then
        -- Strength of the Grave save was made!
        local vPower = getOrCreateStrengthOfTheGravePower(rSource)
        local nPrepared, nCast = getPreparedAndCastFromStrengthOfTheGravePower(vPower)
        if nCast < nPrepared then
            setCastValueOnPower(vPower, nCast + 1)
        end
        nDamage = nAllHP - tonumber(rRoll.nWounds or 0) - 1
        local sDamage = string.gsub(rRoll.sDamage, "=%-?%d+", "=" .. nDamage)

        local rDamageRoll = {
            sType = "damage",
            sDesc = sDamage,
            nTotal = tonumber(nDamage),
            aDice = {},
            bSecret = bSecret
        }
        applyDamageFinal(rActualSource, rTarget or rSource, rDamageRoll, bSecret, sDamage, nDamage)
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
            applyDamageFinal(rActualSource, rTarget or rSource, rDamageRoll, bSecret, rRoll.sDamage, tonumber(rRoll.nDamage))
        end
    end
end


function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
 end

function getOrCreateStrengthOfTheGravePower(vActor)
    if not vActor or not ActorManager.isPC(vActor) then return nil end

    local rCurrentActor = getActorSafe(vActor)
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

function processStrengthOfTheGrave(aData, nTotal, sDamage, rSource, rTarget, bSecret)
    local nAllHP = aData.nTotalHP + aData.nTempHP
    if aData.nWounds + nTotal >= nAllHP
       and (aData.bNoMods or not string.find(sDamage, "%[TYPE:.*radiant.*%]"))
       and (aData.bNoMods or not string.find(sDamage, "%[CRITICAL%]"))
       and not hasEffectSafe(rTarget, UNCONSCIOUS_EFFECT_LABEL)
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
        local nMod, bADV, bDIS, sAddText = getSaveSafe(rTarget, "charisma")
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
        rRoll.bStrengthOfTheGrave = "true"
        rRoll.nDamage = nTotal
        rRoll.sDamage = sDamage
        rRoll.nTotalHP = aData.nTotalHP
        rRoll.nTempHP = aData.nTempHP
        rRoll.nWounds = aData.nWounds
        rRoll.sModDC = tostring(aData.nModDC) -- override number, can be nil
        rRoll.sStaticDC = tostring(aData.nStaticDC) -- override number, can be nil
        rRoll.sTrimmedTraitNameForSave = aData.sTrimmedTraitNameForSave
        if rSource ~= nil then
            rRoll.sOriginalAttacker = ActorManager.getCreatureNodeName(rSource)
        end

        ModifierStack.reset()  -- Modifiers were being applied to the save from the original dmg roll.  Clear it before save.
        ActionsManager.applyModifiersAndRoll(rTarget, rTarget, false, rRoll)
        return true
    end
end

function applyDamage_FGC(rSource, rTarget, bSecret, sDamage, nTotal)
	local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(rTarget)
	if not nodeTarget then return end

    local aData = hasStrengthOfTheGraveTrait(sTargetNodeType, nodeTarget, nil)
    local bStrengthOfTheGraveTriggered
    if aData then
        bStrengthOfTheGraveTriggered = processStrengthOfTheGrave(aData, nTotal, sDamage, rSource, rTarget, bSecret)
    end

    if not bStrengthOfTheGraveTriggered then
        applyDamageFinal(rSource, rTarget, nil, bSecret, sDamage, nTotal)
    end
end

function applyDamage_FGU(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(rTarget)
	if not nodeTarget then return end

    local aData = hasStrengthOfTheGraveTrait(sTargetNodeType, nodeTarget, rRoll)
    local bStrengthOfTheGraveTriggered
    if aData then
        bStrengthOfTheGraveTriggered = processStrengthOfTheGrave(aData, rRoll.nTotal, rRoll.sDesc, rSource, rTarget, false)
    end

    if not bStrengthOfTheGraveTriggered then
        applyDamageFinal(rSource, rTarget, rRoll)
    end
end

function applyDamage_v2(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(rTarget)
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
        bStrengthOfTheGraveTriggered = processStrengthOfTheGrave(aData, rRoll.nTotal, rRoll.sDesc, rSource, rTarget, rRoll.bSecret)
    end

    if not bStrengthOfTheGraveTriggered then
        applyDamageFinal(rSource, rTarget, rRoll)
    end
end
