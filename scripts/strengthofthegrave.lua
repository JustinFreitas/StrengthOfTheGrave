-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
IS_FGC = false
IS_FGU = true
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
    if StringManager and StringManager.isBlank then
        return StringManager.isBlank(s)
    end
    if type(s) ~= "string" then
        return false
    end
    return (string.gsub(s, "%s+", "") == "")
end

function checkFGC()
    if UtilityManager and UtilityManager.isClientFGU then
        return not UtilityManager.isClientFGU()
    end
    if Session and Session.VersionMajor then
        return Session.VersionMajor < 4
    end
    if Interface and Interface.getVersion then
        local sVersion = tostring(Interface.getVersion() or "")
        local sMajor = sVersion:match("^(%d+)")
        local nMajor = tonumber(sMajor) or 0
        return nMajor < 4
    end
    return false
end

function isClientFGU()
    return not checkFGC()
end

-- Helper to safely get the previous result handler for a given action type.
local function getResultHandlerSafe(sType)
    if ActionsManager and ActionsManager.getResultHandler then
        return ActionsManager.getResultHandler(sType)
    end
    if sType == "save" and ActionSave and ActionSave.onSave then
        return ActionSave.onSave
    end
    return nil
end

-- Helper to safely get an actor from a node/string, preferring modern getActor on FGU and resolveActor on FGC.
function getActorSafe(v)
    if not v then return nil end
    if IS_FGC or checkFGC() then
        return ActorManager.resolveActor(v)
    end
    if ActorManager.getActor then
        return ActorManager.getActor(v)
    end
    return ActorManager.resolveActor(v)
end

-- Helper to safely get an actor's type and node, preferring modern methods on FGU and getTypeAndNode on FGC.
function getTypeAndNodeSafe(v)
    if not v then return nil, nil end
    if IS_FGC or checkFGC() then
        if ActorManager.getTypeAndNode then
            return ActorManager.getTypeAndNode(v)
        end
        return ActorManager.getActorTypeAndNode(v)
    end
    if ActorManager.isPC and ActorManager.getCreatureNode and ActorManager.getCTNode then
        local bIsPC = ActorManager.isPC(v)
        if bIsPC then
            return "pc", ActorManager.getCreatureNode(v)
        else
            return "ct", ActorManager.getCTNode(v) or ActorManager.getCreatureNode(v)
        end
    end
    if ActorManager.getTypeAndNode then
        return ActorManager.getTypeAndNode(v)
    end
    return ActorManager.getActorTypeAndNode(v)
end

function getTargetTypeAndNode(v)
    return getTypeAndNodeSafe(v)
end

-- Helper to safely check for effects, preferring modern CoreRPG or 5E-specific EffectManager if available.
local function hasEffectSafe(rActor, sEffect, rTarget, bTargetedOnly)
    if EffectManager and EffectManager.hasEffect then
        return EffectManager.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    if EffectManager5E and EffectManager5E.hasEffect then
        return EffectManager5E.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    return false
end

-- Helper to safely fetch saves from the 5E ruleset.
local function getSaveSafe(nodeActor, sSave)
    if ActorManager5E and ActorManager5E.getSave then
        return ActorManager5E.getSave(nodeActor, sSave)
    end
    return 0, false, false, ""
end

-- Helper to safely call the ruleset's damage application function.
local function applyDamageFinal(rSource, rTarget, p3, p4, p5)
    if type(p3) == "table" then
        -- FGU or re-applying from onSaveNew where p3 is rRoll
        local rRoll = p3
        if type(ActionDamage_applyDamage) == "function" then
            if IS_FGC or checkFGC() then
                ActionDamage_applyDamage(rSource, rTarget, rRoll.bSecret, rRoll.sDesc, rRoll.nTotal)
            else
                ActionDamage_applyDamage(rSource, rTarget, rRoll)
            end
        elseif ActionHealthD20 and type(ActionHealthD20.apply) == "function" and ActionHealthD20.apply ~= applyDamage_v2 then
            ActionHealthD20.apply(rSource, rTarget, rRoll)
        elseif ActionDamage then
            if type(ActionDamage.applyDamage) == "function" and ActionDamage.applyDamage ~= applyDamage_v2 and ActionDamage.applyDamage ~= applyDamage_FGU and ActionDamage.applyDamage ~= applyDamage_FGC then
                if IS_FGC or checkFGC() then
                    ActionDamage.applyDamage(rSource, rTarget, rRoll.bSecret, rRoll.sDesc, rRoll.nTotal)
                else
                    ActionDamage.applyDamage(rSource, rTarget, rRoll)
                end
            elseif type(ActionDamage.apply) == "function" and ActionDamage.apply ~= applyDamage_v2 and ActionDamage.apply ~= applyDamage_FGU and ActionDamage.apply ~= applyDamage_FGC then
                ActionDamage.apply(rSource, rTarget, rRoll)
            end
        end
    else
        -- FGC: p3 is bSecret, p4 is sDamage, p5 is nTotal
        local bSecret, sDamage, nTotal = p3, p4, p5
        if type(ActionDamage_applyDamage) == "function" then
            ActionDamage_applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
        elseif ActionDamage and type(ActionDamage.applyDamage) == "function" and ActionDamage.applyDamage ~= applyDamage_v2 and ActionDamage.applyDamage ~= applyDamage_FGU and ActionDamage.applyDamage ~= applyDamage_FGC then
            ActionDamage.applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
        end
    end
end

function onInit()
    IS_FGC = checkFGC()
    IS_FGU = not IS_FGC
    USER_ISHOST = (Session and Session.IsHost) or (User and User.isHost and User.isHost()) or false

    -- Initialize upvalues safely without capturing our own wrappers
    if ActionHealthD20 and ActionHealthD20.apply and ActionHealthD20.apply ~= applyDamage_v2 then
        ActionDamage_applyDamage = ActionHealthD20.apply
    elseif ActionDamage then
        if ActionDamage.applyDamage and ActionDamage.applyDamage ~= applyDamage_v2 and ActionDamage.applyDamage ~= applyDamage_FGU and ActionDamage.applyDamage ~= applyDamage_FGC then
            ActionDamage_applyDamage = ActionDamage.applyDamage
        elseif ActionDamage.apply and ActionDamage.apply ~= applyDamage_v2 and ActionDamage.apply ~= applyDamage_FGU and ActionDamage.apply ~= applyDamage_FGC then
            ActionDamage_applyDamage = ActionDamage.apply
        end
    end

    -- Capture ruleset result handlers safely (Host and Client)
    local fExistingSave = getResultHandlerSafe("save")
    if fExistingSave ~= onSaveNew then
        ActionSave_onSave_Ruleset = fExistingSave
    end

    -- Register result handlers on all instances
    if ActionsManager and ActionsManager.registerResultHandler then
        ActionsManager.registerResultHandler("save", onSaveNew)
    end

    if USER_ISHOST then
        Comm.registerSlashHandler("sg", processChatCommand)
        Comm.registerSlashHandler("sotg", processChatCommand)
        Comm.registerSlashHandler("strengthofthegrave", processChatCommand)

        -- Hook damage functions with strict idempotency guards
        if ActionHealthD20 and ActionHealthD20.apply then
            if ActionHealthD20.apply ~= applyDamage_v2 then
                ActionDamage_applyDamage = ActionHealthD20.apply
                ActionHealthD20.apply = applyDamage_v2
            end
        elseif ActionDamage then
            if ActionDamage.applyDamage then
                if ActionDamage.applyDamage ~= applyDamage_v2 and ActionDamage.applyDamage ~= applyDamage_FGU and ActionDamage.applyDamage ~= applyDamage_FGC then
                    ActionDamage_applyDamage = ActionDamage.applyDamage
                    ActionDamage.applyDamage = applyDamage_v2
                end
            elseif ActionDamage.apply then
                if ActionDamage.apply ~= applyDamage_v2 and ActionDamage.apply ~= applyDamage_FGU and ActionDamage.apply ~= applyDamage_FGC then
                    ActionDamage_applyDamage = ActionDamage.apply
                    ActionDamage.apply = applyDamage_v2
                end
            end
        end
    end
end

function getCTNodeForDisplayName(sDisplayName)
    for _, nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
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

function onSaveNew(rSource, rTarget, rRoll)
    if rRoll.bStrengthOfTheGrave == nil then
        if type(ActionSave_onSave_Ruleset) == "function" then
            ActionSave_onSave_Ruleset(rSource, rTarget, rRoll)
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

        applyDamageFinal(rSource, rTarget or rSource, rDamageRoll)
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
            applyDamageFinal(rSource, rTarget or rSource, rDamageRoll)
        end
    end
end

function trim(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function getOrCreateStrengthOfTheGravePower(vActor)
    if not vActor or not ActorManager.isPC(vActor) then return nil end

    local rCurrentActor = getActorSafe(vActor)
    if not rCurrentActor then return nil end
    local sCreatureNode = rCurrentActor.sCreatureNode or (type(vActor) == "table" and vActor.getNodeName and vActor.getNodeName())
    local nodeCharSheet
    if sCreatureNode then
        nodeCharSheet = DB.findNode(sCreatureNode)
    elseif type(vActor) == "databasenode" or (type(vActor) == "table" and vActor._path) then
        nodeCharSheet = vActor
    end
    if not nodeCharSheet then return nil end

    for _, vPower in pairs(DB.getChildren(nodeCharSheet, "powers")) do
        if DB.getValue(vPower, NAME, ""):lower() == "strength of the grave" then
            return vPower
        end
    end

    local nodePowers
    if DB.createChild then
        nodePowers = DB.createChild(nodeCharSheet, "powers")
    elseif nodeCharSheet.createChild then
        nodePowers = nodeCharSheet.createChild("powers")
    end
    if not nodePowers then
        return nil
    end

    local nodeNewPower
    if DB.createChild then
        nodeNewPower = DB.createChild(nodePowers)
    elseif nodePowers.createChild then
        nodeNewPower = nodePowers.createChild()
    end
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
    if not vPower then return 1, 0 end
    return DB.getValue(vPower, "prepared", 0), DB.getValue(vPower, "cast", 0)
end

function setCastValueOnPower(vPower, nCast)
    if not vPower then return end
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
        aTraits = DB.getChildren(nodeTarget, "featurelist")
    elseif sTargetNodeType == "ct" then
        aTraits = DB.getChildren(nodeTarget, "traits")
    else
        return nil
    end

    for _, aTrait in pairs(aTraits or {}) do
        local aDecomposedTraitName = getDecomposedTraitName(aTrait)
        if aDecomposedTraitName.nStrengthOfTheGraveStart ~= nil then
            return getStrengthOfTheGraveData(aDecomposedTraitName, aTraits, sTargetNodeType, nodeTarget, rRoll)
        end
    end
    return nil
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
    elseif sTargetNodeType == "ct" and ActorManager.isRecordType and ActorManager.isRecordType(nodeTarget, "vehicle") then
        if rRoll and type(rRoll) == "table" and (rRoll.sSubtargetPath or "") ~= "" then
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
    if IS_FGC or checkFGC() then
        return getTargetHealthData_FGC(sTargetNodeType, nodeTarget)
    else
        return getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rRoll)
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
       and not hasEffectSafe(rTarget, UNCONSCIOUS_EFFECT_LABEL)
       and aData.nTotalHP > aData.nWounds then

        local sDisplayName = ActorManager.getDisplayName(rTarget)
        local vPower = getOrCreateStrengthOfTheGravePower(rTarget)
        local nPrepared, nCast = getPreparedAndCastFromStrengthOfTheGravePower(vPower)

        if nCast >= nPrepared then
            displayChatMessage(sDisplayName .. " has used all of their Strength of the Grave for the day.")
            return false
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

        ModifierStack.reset()  -- Modifiers were being applied to the save from the original dmg roll.  Clear it before save.
        ActionsManager.applyModifiersAndRoll(rTarget, rTarget, false, rRoll)
        return true
    end
    return false
end

function applyDamage_v2(rSource, rTarget, p3, p4, p5)
    local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(rTarget)
    if not nodeTarget then return end

    local bSecret, sDamage, nTotal
    local isDamageRoll = true

    if type(p3) == "table" then
        -- FGU: p3 is rRoll
        local rRoll = p3
        if rRoll.sDesc then
            if rRoll.sDesc:match("%[HEAL") or rRoll.sDesc:match("%[RECOVERY") or rRoll.sDesc:match("%[FHEAL") or rRoll.sDesc:match("%[REGEN") then
                isDamageRoll = false
            end
        end
        if (rRoll.nTotal or 0) < 0 then
            isDamageRoll = false
        end
        bSecret = rRoll.bSecret
        sDamage = rRoll.sDesc or ""
        nTotal = rRoll.nTotal or 0
    else
        -- FGC: p3 is bSecret, p4 is sDamage, p5 is nTotal
        bSecret = p3
        sDamage = p4 or ""
        nTotal = tonumber(p5) or 0
        if nTotal < 0 then
            isDamageRoll = false
        end
    end

    local rRollHealth = (type(p3) == "table") and p3 or { sDesc = sDamage, nTotal = nTotal }
    local aData = hasStrengthOfTheGraveTrait(sTargetNodeType, nodeTarget, rRollHealth)
    local bStrengthOfTheGraveTriggered = false
    if aData and isDamageRoll and hasAvailableStrengthOfTheGrave(aData) then
        bStrengthOfTheGraveTriggered = processStrengthOfTheGrave(aData, nTotal, sDamage, rTarget, bSecret)
    end

    if not bStrengthOfTheGraveTriggered then
        applyDamageFinal(rSource, rTarget, p3, p4, p5)
    end
end

function applyDamage_FGU(rSource, rTarget, rRoll)
    applyDamage_v2(rSource, rTarget, rRoll)
end

function applyDamage_FGC(rSource, rTarget, bSecret, sDamage, nTotal)
    applyDamage_v2(rSource, rTarget, bSecret, sDamage, nTotal)
end
