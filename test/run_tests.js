const { LuaFactory } = require('wasmoon');
const fs = require('fs');
const path = require('path');

async function runTests() {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();

    console.log("Setting up mock environment in Lua VM...");
    
    // Set up standard and custom Fantasy Grounds environment mocks
    await lua.doString(`
        -- Global mock setup
        _USER_ISHOST = true

        UtilityManager = {}
        Session = { IsHost = true, VersionMajor = 4 }
        Interface = {}
        local major, minor, patch = 4, 2, 0
        local sVersionOverride = nil
        function Interface.getVersion()
            if sVersionOverride ~= nil then
                return sVersionOverride
            end
            return major, minor, patch
        end
        function Interface.setVersion(ma, mi, pa)
            sVersionOverride = nil
            major, minor, patch = ma, mi, pa
        end
        function Interface.setVersionString(s)
            sVersionOverride = s
        end

        ActionSave = {
            onSave = function(rSource, rTarget, rRoll)
                table.insert(ActionsManager.save_calls, { rSource = rSource, rTarget = rTarget, rRoll = rRoll })
            end
        }

        User = {
            isHost = function() return _USER_ISHOST == true end
        }

        StringManager = {
            isBlank = function(s)
                if type(s) ~= "string" then return false end
                return s:gsub("%s+", "") == ""
            end
        }

        ActorManager = {
            getActor = function(v) return v end,
            resolveActor = function(v)
                if type(v) == "table" then
                    local res = {}
                    for k, val in pairs(v) do res[k] = val end
                    res.sResolved = true
                    res.sCreatureNode = v._path
                    return res
                end
                return { sResolved = true, sCreatureNode = tostring(v), _path = tostring(v) }
            end,
            isPC = function(v) return v and v._isPC == true end,
            getCreatureNode = function(v) return v end,
            getCTNode = function(v) return v end,
            getTypeAndNode = function(v)
                if not v then return nil, nil end
                return (v._isPC and "pc" or "ct"), v
            end,
            getActorTypeAndNode = function(v)
                if not v then return nil, nil end
                return (v._isPC and "pc_legacy" or "ct_legacy"), v
            end,
            getDisplayName = function(v)
                if type(v) == "table" then
                    return (v._data and v._data["name"]) or v._name or "Unknown"
                end
                return tostring(v)
            end,
            getCreatureNodeName = function(v)
                if type(v) == "table" then return v._path end
                return tostring(v)
            end
        }

        ActorManager5E = {
            getSave = function(nodeActor, sSave)
                if nodeActor and nodeActor._cha_save then
                    return nodeActor._cha_save.mod or 0, nodeActor._cha_save.adv or false, nodeActor._cha_save.dis or false, nodeActor._cha_save.text or ""
                end
                return 0, false, false, ""
            end
        }

        EffectManager = {
            hasEffect = function(rActor, sEffect, rTarget, bTargetedOnly)
                if not rActor or not rActor._effects then return false end
                for _, eff in ipairs(rActor._effects) do
                    if eff == sEffect then return true end
                end
                return false
            end,
            removeEffect = function(nodeCT, sEffect)
                if not nodeCT or not nodeCT._effects then return end
                local newEffects = {}
                for _, eff in ipairs(nodeCT._effects) do
                    if eff ~= sEffect then
                        table.insert(newEffects, eff)
                    end
                end
                nodeCT._effects = newEffects
            end
        }

        CombatManager = {
            CT_LIST = "combattracker.list"
        }

        ModifierStack = {
            wasReset = false,
            reset = function()
                ModifierStack.wasReset = true
            end
        }

        -- Original implementation functions to restore in clearMocks
        local function originalActionHealthApply(rSource, rTarget, rRoll)
            table.insert(ActionHealthD20.calls, { rSource = rSource, rTarget = rTarget, rRoll = rRoll })
        end

        local function originalActionDamageApplyDamage(rSource, rTarget, p3, p4, p5)
            table.insert(ActionDamage.calls, {
                rSource = rSource,
                rTarget = rTarget,
                p3 = p3,
                p4 = p4,
                p5 = p5,
                rRoll = (type(p3) == "table" and p3 or nil),
                bSecret = (type(p3) ~= "table" and p3 or (p3 and p3.bSecret)),
                sDamage = (type(p3) ~= "table" and p4 or (p3 and p3.sDesc)),
                nTotal = (type(p3) ~= "table" and p5 or (p3 and p3.nTotal))
            })
        end

        ActionHealthD20 = {
            apply = originalActionHealthApply,
            calls = {}
        }

        ActionDamage = {
            applyDamage = originalActionDamageApplyDamage,
            apply = originalActionDamageApplyDamage,
            calls = {}
        }

        ActionsManager = {
            _handlers = {},
            _original_handlers = {
                save = function(rSource, rTarget, rRoll)
                    table.insert(ActionsManager.save_calls, { rSource = rSource, rTarget = rTarget, rRoll = rRoll })
                end
            },
            save_calls = {},
            getResultHandler = function(sType)
                return ActionsManager._original_handlers[sType]
            end,
            registerResultHandler = function(sType, callback)
                ActionsManager._handlers[sType] = callback
            end,
            total = function(rRoll)
                return rRoll.nTotalOverride or 10
            end,
            createActionMessage = function(rSource, rRoll)
                return { text = "Action message for " .. (rRoll.sDesc or "") }
            end,
            outputResult = function(bSecret, rSource, rTarget, msgLong, msgShort)
                table.insert(ActionsManager.outputs, {
                    bSecret = bSecret,
                    rSource = rSource,
                    rTarget = rTarget,
                    msgLong = msgLong,
                    msgShort = msgShort
                })
            end,
            applyModifiersAndRoll = function(rSource, rTarget, bMulti, rRoll)
                table.insert(ActionsManager.rolls, {
                    rSource = rSource,
                    rTarget = rTarget,
                    bMulti = bMulti,
                    rRoll = rRoll
                })
            end,
            outputs = {},
            rolls = {}
        }

        Comm = {
            _slash_handlers = {},
            registerSlashHandler = function(cmd, callback)
                Comm._slash_handlers[cmd] = callback
            end,
            addChatMessage = function(msg)
                table.insert(Comm.chat_messages, msg)
            end,
            deliverChatMessage = function(msg)
                table.insert(Comm.delivered_messages, msg)
            end,
            chat_messages = {},
            delivered_messages = {}
        }

        -- Database Mock
        db_store = {}
        DB = {
            getValue = function(arg1, arg2, arg3)
                if type(arg1) == "table" then
                    local val = arg1._data and arg1._data[arg2]
                    if val == nil then return arg3 end
                    return val
                elseif type(arg1) == "string" then
                    local val = db_store[arg1]
                    if val == nil then return arg2 end
                    if type(val) == "table" then
                        return (val._data and val._data["value"]) or arg2
                    end
                    return val
                end
                return arg3 or arg2
            end,
            setValue = function(arg1, arg2, arg3, arg4)
                if type(arg1) == "table" then
                    if not arg1._data then arg1._data = {} end
                    arg1._data[arg2] = arg4
                    if arg1._path then
                        local absolutePath = arg1._path .. "." .. arg2
                        db_store[absolutePath] = arg4
                    end
                elseif type(arg1) == "string" then
                    db_store[arg1] = arg3
                end
            end,
            getText = function(node, subpath, default)
                if type(node) == "table" then
                    if subpath then
                        return (node._data and node._data[subpath]) or default or ""
                    else
                        return (node._data and node._data["value"]) or default or ""
                    end
                elseif type(node) == "string" then
                    local val = db_store[node]
                    if type(val) == "table" then
                        return (val._data and val._data["value"]) or default or ""
                    end
                    return val or subpath or ""
                end
                return ""
            end,
            getChildren = function(arg1, arg2)
                if type(arg1) == "string" then
                    local children = {}
                    for path, node in pairs(db_store) do
                        if type(node) == "table" and node._parent_path == arg1 then
                            children[node._name] = node
                        end
                    end
                    return children
                elseif type(arg1) == "table" then
                    local subpath = arg2
                    for k, v in pairs(arg1._children or {}) do
                        if k == subpath then
                            return v
                        end
                    end
                    return {}
                end
                return {}
            end,
            createChild = function(parent, childName)
                local parentNode = parent
                if type(parent) == "string" then
                    parentNode = db_store[parent]
                    if not parentNode then
                        parentNode = { _path = parent, _children = {}, _data = {} }
                        db_store[parent] = parentNode
                    end
                end
                if not parentNode._children then parentNode._children = {} end
                local newChild
                if childName then
                    newChild = parentNode._children[childName]
                    if not newChild then
                        newChild = { _path = (parentNode._path and (parentNode._path .. "." .. childName) or childName), _name = childName, _children = {}, _data = {} }
                        parentNode._children[childName] = newChild
                        if parentNode._path then
                            db_store[parentNode._path .. "." .. childName] = newChild
                        end
                    end
                else
                    local id = "id-" .. string.format("%05d", (parentNode._childCount or 0) + 1)
                    parentNode._childCount = (parentNode._childCount or 0) + 1
                    newChild = { _path = (parentNode._path and (parentNode._path .. "." .. id) or id), _name = id, _children = {}, _data = {} }
                    parentNode._children[id] = newChild
                    if parentNode._path then
                        db_store[parentNode._path .. "." .. id] = newChild
                    end
                end
                newChild.createChild = function(self, name)
                    return DB.createChild(self, name)
                end
                return newChild
            end,
            findNode = function(sNodePath)
                return db_store[sNodePath]
            end,
            getPath = function(...)
                local args = {...}
                local path_parts = {}
                for i, v in ipairs(args) do
                    if type(v) == "table" then
                        table.insert(path_parts, v._path)
                    elseif type(v) == "string" and v ~= "" then
                        table.insert(path_parts, v)
                    end
                end
                return table.concat(path_parts, ".")
            end
        }

        -- Helpers to setup environment state in tests
        function clearMocks()
            db_store = {}
            ActionHealthD20.calls = {}
            ActionDamage.calls = {}
            ActionHealthD20.apply = originalActionHealthApply
            ActionDamage.applyDamage = originalActionDamageApplyDamage
            ActionDamage.apply = originalActionDamageApplyDamage
            ActionsManager.outputs = {}
            ActionsManager.rolls = {}
            ActionsManager.save_calls = {}
            Comm.chat_messages = {}
            Comm.delivered_messages = {}
            ModifierStack.wasReset = false
        end
    `);

    // Load the strengthofthegrave.lua source
    console.log("Loading strengthofthegrave.lua...");
    const scriptPath = path.join(__dirname, '../scripts/strengthofthegrave.lua');
    const code = fs.readFileSync(scriptPath, 'utf8');
    await lua.doString(code);

    // List of test cases to run
    const testCases = [
        {
            name: "onInit registers save result handler and slash commands",
            code: `
                clearMocks()
                _USER_ISHOST = true
                onInit()
                
                assert(ActionsManager._handlers["save"] == onSaveNew, "onSaveNew not registered for save")
                assert(Comm._slash_handlers["sg"] == processChatCommand, "sg slash handler not registered")
                assert(Comm._slash_handlers["sotg"] == processChatCommand, "sotg slash handler not registered")
                assert(Comm._slash_handlers["strengthofthegrave"] == processChatCommand, "strengthofthegrave slash handler not registered")
            `
        },
        {
            name: "getCTNodeForDisplayName finds actor by name",
            code: `
                clearMocks()
                local nodeCT = {
                    _name = "sorcerer",
                    _parent_path = "combattracker.list",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Shadow Sorcerer"
                    }
                }
                db_store["combattracker.list.id-00001"] = nodeCT
                
                local found = getCTNodeForDisplayName("Shadow Sorcerer")
                assert(found == nodeCT, "Should find the correct CT node")
                
                local notFound = getCTNodeForDisplayName("Nonexistent")
                assert(notFound == nil, "Should return nil for nonexistent actor")
            `
        },
        {
            name: "processChatCommand triggers application or shows error",
            code: `
                clearMocks()
                -- Try with nonexistent actor
                processChatCommand(nil, "Ghost")
                assert(#Comm.chat_messages == 1, "Should have added a chat message")
                assert(string.find(Comm.chat_messages[1].text, "not found in the Combat Tracker"), "Should show not found error")
                
                -- Try with existing actor (not unconscious)
                local nodeCT = {
                    _name = "sorcerer",
                    _parent_path = "combattracker.list",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Shadow Sorcerer"
                    },
                    _effects = {}
                }
                db_store["combattracker.list.id-00001"] = nodeCT
                
                Comm.chat_messages = {}
                processChatCommand(nil, "Shadow Sorcerer")
                assert(#Comm.chat_messages == 1, "Should have added a chat message")
                assert(string.find(Comm.chat_messages[1].text, "is not an unconscious actor"), "Should show unconscious error")
            `
        },
        {
            name: "applyStrengthOfTheGrave applies healing to unconscious actor",
            code: `
                clearMocks()
                local nodeCT = {
                    _name = "sorcerer",
                    _parent_path = "combattracker.list",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Shadow Sorcerer",
                        hptotal = 30,
                        hptemp = 0,
                        wounds = 30
                    },
                    _effects = {"Unconscious", "Prone"},
                    _isPC = false
                }
                db_store["combattracker.list.id-00001"] = nodeCT
                
                applyStrengthOfTheGrave(nodeCT)
                
                -- Check wounds: total HP - 1 = 29
                assert(nodeCT._data.wounds == 29, "Wounds should be set to total HP - 1 (29), got " .. tostring(nodeCT._data.wounds))
                
                -- Check effects removed
                local hasUnconscious = false
                local hasProne = false
                for _, eff in ipairs(nodeCT._effects) do
                    if eff == "Unconscious" then hasUnconscious = true end
                    if eff == "Prone" then hasProne = true end
                end
                assert(not hasUnconscious, "Unconscious effect should be removed")
                assert(not hasProne, "Prone effect should be removed")
                
                -- Check success message
                assert(#Comm.chat_messages == 1, "Should display chat message")
                assert(string.find(Comm.chat_messages[1].text, "StrengthOfTheGrave was applied to Shadow Sorcerer"), "Should show success message")
            `
        },
        {
            name: "hasStrengthOfTheGraveTrait parses PC featurelist and trait variants",
            code: `
                clearMocks()
                
                local function checkPCFeature(featureName, expected)
                    local actor = {
                        _path = "charsheet.id-00001",
                        _isPC = true,
                        _children = {
                            featurelist = {
                                ["feature-1"] = {
                                    _data = {
                                        name = featureName
                                    }
                                }
                            },
                            powers = {}
                        },
                        _data = {
                            ["hp.total"] = 25,
                            ["hp.temporary"] = 0,
                            ["hp.wounds"] = 10
                        }
                    }
                    db_store["charsheet.id-00001"] = actor
                    
                    local res = hasStrengthOfTheGraveTrait("pc", actor, {})
                    if expected == nil then
                        assert(res == nil, "Expected no trait for: " .. featureName)
                    else
                        assert(res ~= nil, "Expected trait for: " .. featureName)
                        assert(res.nStaticDC == expected.nStaticDC, "nStaticDC mismatch for: " .. featureName)
                        assert(res.nModDC == expected.nModDC, "nModDC mismatch for: " .. featureName)
                        assert(not not res.bNoMods == not not expected.bNoMods, "bNoMods mismatch for: " .. featureName)
                        assert(res.sTrimmedTraitNameForSave == expected.sTrimmedTraitNameForSave, "sTrimmedTraitNameForSave mismatch for: " .. featureName)
                    end
                end
                
                checkPCFeature("Strength of the Grave", {
                    sTrimmedTraitNameForSave = "Strength of the Grave"
                })
                
                checkPCFeature("Strength of the Grave (DC 10)", {
                    nStaticDC = 10,
                    sTrimmedTraitNameForSave = "Strength of the Grave"
                })
                
                checkPCFeature("Strength of the Grave (Mod 2, No Mods)", {
                    nModDC = 2,
                    bNoMods = true,
                    sTrimmedTraitNameForSave = "Strength of the Grave"
                })
                
                checkPCFeature("Darkvision", nil)
            `
        },
        {
            name: "processStrengthOfTheGrave trigger logic (damage, radiant, critical, uses)",
            code: `
                clearMocks()
                
                local actor = {
                    _name = "sorcerer",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Shadow Sorcerer",
                        hptotal = 20,
                        hptemp = 0,
                        wounds = 10
                    },
                    _effects = {},
                    _cha_save = { mod = 3 }
                }
                
                local traitData = {
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    nPrepared = 1,
                    nCast = 0,
                    sTrimmedTraitNameForSave = "Strength of the Grave"
                }
                
                -- Case A: Damage not enough to drop to 0 HP (10 wounds + 5 dmg < 20 HP)
                local triggered = processStrengthOfTheGrave(traitData, 5, "[DAMAGE] piercing", actor, false)
                assert(not triggered, "Should not trigger if damage does not reduce to 0 HP")
                
                -- Case B: Damage reduces to 0 HP (10 wounds + 10 dmg >= 20 HP). Should trigger save.
                triggered = processStrengthOfTheGrave(traitData, 10, "[DAMAGE] slashing", actor, false)
                assert(triggered, "Should trigger if damage reduces to 0 HP")
                assert(#ActionsManager.rolls == 1, "Should roll charisma save")
                assert(ActionsManager.rolls[1].rRoll.bStrengthOfTheGrave == "true", "Roll should be flagged as Strength of the Grave")
                assert(ActionsManager.rolls[1].rRoll.nDamage == 10, "Roll should carry damage amount")
                
                -- Case C: Radiant damage. Should not trigger.
                ActionsManager.rolls = {}
                triggered = processStrengthOfTheGrave(traitData, 10, "[DAMAGE] radiant [TYPE: radiant]", actor, false)
                assert(not triggered, "Should not trigger on radiant damage")
                
                -- Case D: Critical damage. Should not trigger.
                ActionsManager.rolls = {}
                triggered = processStrengthOfTheGrave(traitData, 10, "[DAMAGE] [CRITICAL] slashing", actor, false)
                assert(not triggered, "Should not trigger on critical hit")
                
                -- Case E: Radiant damage with No Mods. Should trigger.
                local noModsData = {
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    bNoMods = true,
                    nPrepared = 1,
                    nCast = 0,
                    sTrimmedTraitNameForSave = "Strength of the Grave"
                }
                ActionsManager.rolls = {}
                triggered = processStrengthOfTheGrave(noModsData, 10, "[DAMAGE] radiant [TYPE: radiant]", actor, false)
                assert(triggered, "Should trigger on radiant damage with No Mods")
                
                -- Case F: Already unconscious. Should not trigger.
                table.insert(actor._effects, "Unconscious")
                ActionsManager.rolls = {}
                triggered = processStrengthOfTheGrave(traitData, 10, "[DAMAGE] slashing", actor, false)
                assert(not triggered, "Should not trigger if target is already unconscious")
            `
        },
        {
            name: "onSaveNew save results and power slot decrement",
            code: `
                clearMocks()
                
                local charNode = {
                    _path = "charsheet.id-00001",
                    _isPC = true,
                    _children = {
                        powers = {
                            ["power-1"] = {
                                _data = {
                                    name = "Strength of the Grave",
                                    prepared = 1,
                                    cast = 0
                                }
                            }
                        }
                    },
                    _data = {
                        name = "Shadow Sorcerer",
                        ["hp.total"] = 20,
                        ["hp.temporary"] = 0,
                        ["hp.wounds"] = 10
                    }
                }
                db_store["charsheet.id-00001"] = charNode

                local source = charNode
                
                local roll = {
                    bStrengthOfTheGrave = "true",
                    sTrimmedTraitNameForSave = "Strength of the Grave",
                    nDamage = 10,
                    sDamage = "[DAMAGE] slashing =10",
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    sModDC = "5",
                    sStaticDC = "nil",
                    nTotalOverride = 15 -- Save result 15 vs DC 5 + 10 = 15. Success!
                }
                
                -- Trigger onSaveNew with Success
                onSaveNew(source, source, roll)
                
                -- Success leaves 1 HP: total 20, wounds 10 -> applied damage 9
                assert(#ActionHealthD20.calls == 1 or #ActionDamage.calls == 1, "Should apply damage")
                local appliedRoll = ActionHealthD20.calls[1] and ActionHealthD20.calls[1].rRoll or ActionDamage.calls[1].rRoll
                assert(appliedRoll.nTotal == 9, "Should apply 9 damage to leave 1 HP, got " .. tostring(appliedRoll.nTotal))
                assert(appliedRoll.sDesc == "[DAMAGE] slashing =9", "Damage description adjusted")
                
                -- Check power cast count incremented
                local powerNode = charNode._children.powers["power-1"]
                assert(powerNode._data.cast == 1, "Cast count should be incremented to 1, got " .. tostring(powerNode._data.cast))
                
                -- Verify output message contains SUCCESS
                assert(#ActionsManager.outputs == 1, "Should output result message")
                assert(string.find(ActionsManager.outputs[1].msgLong.text, "%[SUCCESS%]"), "Message should contain [SUCCESS]")
                
                -- Clear and test Failure
                clearMocks()
                roll.nTotalOverride = 14 -- DC is 15. Failure!
                onSaveNew(source, source, roll)
                
                -- Failure should apply original damage (10)
                assert(#ActionHealthD20.calls == 1 or #ActionDamage.calls == 1, "Should apply damage on failure")
                local appliedRollFail = ActionHealthD20.calls[1] and ActionHealthD20.calls[1].rRoll or ActionDamage.calls[1].rRoll
                assert(appliedRollFail.nTotal == 10, "Should apply original 10 damage, got " .. tostring(appliedRollFail.nTotal))
                assert(string.find(ActionsManager.outputs[1].msgLong.text, "%[FAILURE%]"), "Message should contain [FAILURE]")
            `
        },
        {
            name: "applyDamage_v2 intercept integration (FGU 3-arg)",
            code: `
                clearMocks()
                _USER_ISHOST = true
                onInit()

                local source = { _name = "orc", _data = { name = "Orc" } }
                local target = {
                    _path = "charsheet.id-00001",
                    _isPC = true,
                    _data = {
                        name = "Shadow Sorcerer",
                        ["hp.total"] = 20,
                        ["hp.temporary"] = 0,
                        ["hp.wounds"] = 10
                    },
                    _effects = {},
                    _cha_save = { mod = 3 },
                    _children = {
                        featurelist = {
                            ["f1"] = { _data = { name = "Strength of the Grave" } }
                        },
                        powers = {
                            ["p1"] = { _data = { name = "Strength of the Grave", prepared = 1, cast = 0 } }
                        }
                    }
                }
                db_store["charsheet.id-00001"] = target

                local rRoll = {
                    sDesc = "[DAMAGE] piercing",
                    nTotal = 10, -- drops 10 HP to 0 HP -> triggers Strength of the Grave
                    bSecret = false
                }

                applyDamage_v2(source, target, rRoll)

                -- Damage intercepted: save rolled
                assert(#ActionHealthD20.calls == 0 and #ActionDamage.calls == 0, "Damage should be intercepted")
                assert(#ActionsManager.rolls == 1, "Charisma save rolled")
                local saveRoll = ActionsManager.rolls[1].rRoll
                assert(saveRoll.bStrengthOfTheGrave == "true", "Roll flagged as Strength of the Grave")
                assert(saveRoll.nDamage == 10, "Damage is 10")
            `
        },
        {
            name: "checkFGC version detection permutations",
            code: `
                UtilityManager.isClientFGU = function() return true end
                assert(checkFGC() == false, "FGU via UtilityManager should be false")

                UtilityManager.isClientFGU = function() return false end
                assert(checkFGC() == true, "FGC via UtilityManager should be true")

                UtilityManager.isClientFGU = nil
                Session.VersionMajor = 4
                assert(checkFGC() == false, "FGU via Session.VersionMajor 4 should be false")

                Session.VersionMajor = 3
                assert(checkFGC() == true, "FGC via Session.VersionMajor 3 should be true")

                Session.VersionMajor = nil
                Interface.setVersionString("3.3.16")
                assert(checkFGC() == true, "FGC string version '3.3.16' should be true")

                Interface.setVersionString("4.1.2")
                assert(checkFGC() == false, "FGU string version '4.1.2' should be false")

                -- Restore defaults
                UtilityManager.isClientFGU = function() return true end
                Session.VersionMajor = 4
                Interface.setVersion(4, 2, 0)
                IS_FGC = false
                IS_FGU = true
            `
        },
        {
            name: "getActorSafe FGC vs FGU routing and nil safety",
            code: `
                local mockNode = { _path = "charsheet.id-00001", sName = "Sorcerer" }
                
                IS_FGC = false
                local fguActor = getActorSafe(mockNode)
                assert(fguActor.sResolved == nil, "FGU should call ActorManager.getActor")

                IS_FGC = true
                local fgcActor = getActorSafe(mockNode)
                assert(fgcActor.sResolved == true, "FGC should call ActorManager.resolveActor")

                assert(getActorSafe(nil) == nil, "nil should safely return nil")

                IS_FGC = false
                IS_FGU = true
            `
        },
        {
            name: "getTypeAndNodeSafe FGC vs FGU routing and nil safety",
            code: `
                local mockNode = { _path = "ct.entry1", sName = "Sorcerer", _isPC = false }

                IS_FGC = true
                local sTypeFGC, nodeFGC = getTypeAndNodeSafe(mockNode)
                assert(sTypeFGC == "ct", "FGC should call ActorManager.getTypeAndNode")

                ActorManager.getTypeAndNode = nil
                local sTypeLegacy, nodeLegacy = getTypeAndNodeSafe(mockNode)
                assert(sTypeLegacy == "ct_legacy", "FGC should fall back to getActorTypeAndNode")

                -- Restore
                ActorManager.getTypeAndNode = function(v) if not v then return nil, nil end return (v._isPC and "pc" or "ct"), v end

                local sTypeNil, nodeNil = getTypeAndNodeSafe(nil)
                assert(sTypeNil == nil and nodeNil == nil, "nil should return nil, nil")

                IS_FGC = false
                IS_FGU = true
            `
        },
        {
            name: "onInit idempotency and /reload recursion safety",
            code: `
                clearMocks()
                _USER_ISHOST = true

                -- Call onInit 3 times simulating /reload
                onInit()
                onInit()
                onInit()

                assert(ActionsManager._handlers["save"] == onSaveNew, "save handler should be onSaveNew")
                assert(ActionHealthD20.apply == applyDamage_v2, "ActionHealthD20.apply should be applyDamage_v2")

                local nonSotgSource = { _name = "Hero" }
                local nonSotgTarget = { _name = "Goblin", _data = {} }
                local nonSotgRoll = { sDesc = "[DAMAGE] piercing", nTotal = 5, bSecret = false }
                
                ActionHealthD20.calls = {}
                ActionDamage.calls = {}
                applyDamage_v2(nonSotgSource, nonSotgTarget, nonSotgRoll)
                assert(#ActionHealthD20.calls == 1 or #ActionDamage.calls == 1, "applyDamage_v2 should execute cleanly without recursion")
            `
        },
        {
            name: "applyDamage_v2 handles FGC 5-argument damage application",
            code: `
                clearMocks()
                _USER_ISHOST = true
                IS_FGC = true
                IS_FGU = false

                local savedHealth = ActionHealthD20
                ActionHealthD20 = nil

                onInit()

                local source = { _name = "orc", _data = { name = "Orc" } }
                local targetSorcerer = {
                    _path = "charsheet.id-00001",
                    _isPC = true,
                    _data = {
                        name = "Shadow Sorcerer",
                        ["hp.total"] = 20,
                        ["hp.temporary"] = 0,
                        ["hp.wounds"] = 10
                    },
                    _effects = {},
                    _cha_save = { mod = 3 },
                    _children = {
                        featurelist = {
                            ["f1"] = { _data = { name = "Strength of the Grave" } }
                        },
                        powers = {
                            ["p1"] = { _data = { name = "Strength of the Grave", prepared = 1, cast = 0 } }
                        }
                    }
                }
                db_store["charsheet.id-00001"] = targetSorcerer

                -- Call with FGC 5-argument signature: (rSource, rTarget, bSecret, sDamage, nTotal)
                applyDamage_v2(source, targetSorcerer, false, "[DAMAGE] slashing", 10)

                assert(#ActionDamage.calls == 0, "Damage should be intercepted for Strength of the Grave roll")
                assert(#ActionsManager.rolls == 1, "Charisma save should be rolled")
                assert(ActionsManager.rolls[1].rRoll.bStrengthOfTheGrave == "true", "Roll flagged as Strength of the Grave")
                assert(ActionsManager.rolls[1].rRoll.nDamage == 10, "Roll carries 10 damage")

                -- Simulate non-lethal damage on non-SotG target via FGC 5-arg signature
                local targetGoblin = {
                    _name = "goblin",
                    _path = "combattracker.list.id-00002",
                    _data = {
                        name = "Goblin",
                        hptotal = 15,
                        hptemp = 0,
                        wounds = 0
                    },
                    _effects = {},
                    _children = {}
                }
                db_store["combattracker.list.id-00002"] = targetGoblin

                applyDamage_v2(source, targetGoblin, false, "[DAMAGE] piercing", 4)
                assert(#ActionDamage.calls == 1, "Non-SotG damage should pass through to ActionDamage.applyDamage")
                assert(ActionDamage.calls[1].p5 == 4 or ActionDamage.calls[1].nTotal == 4, "Should pass 4 damage")
                assert(ActionDamage.calls[1].p4 == "[DAMAGE] piercing" or ActionDamage.calls[1].sDamage == "[DAMAGE] piercing", "Should pass piercing desc")
                assert(ActionDamage.calls[1].p3 == false or ActionDamage.calls[1].bSecret == false, "Should pass bSecret = false")

                -- Restore
                ActionHealthD20 = savedHealth
                IS_FGC = false
                IS_FGU = true
            `
        },
        {
            name: "onSaveNew passes standard saves to ruleset handler but bypasses it for SotG saves",
            code: `
                clearMocks()
                _USER_ISHOST = true
                onInit()

                local source = { _name = "hero", _data = { name = "Hero" } }
                local target = { _name = "sorcerer", _data = { name = "Sorcerer" } }

                -- 1. Standard ruleset save (bStrengthOfTheGrave == nil)
                local standardRoll = {
                    sType = "save",
                    sDesc = "Dexterity Save",
                    nTotal = 16
                }
                onSaveNew(source, target, standardRoll)
                assert(#ActionsManager.save_calls == 1, "Standard save should pass through to ruleset handler")
                assert(ActionsManager.save_calls[1].rRoll == standardRoll, "Ruleset handler should receive original roll")
                assert(#ActionsManager.outputs == 0, "No custom SotG output should be emitted for standard saves")

                -- 2. Strength of the Grave save (bStrengthOfTheGrave ~= nil)
                ActionsManager.save_calls = {}
                local sotgRoll = {
                    bStrengthOfTheGrave = "true",
                    sTrimmedTraitNameForSave = "Strength of the Grave",
                    nDamage = 10,
                    sDamage = "[DAMAGE] slashing =10",
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    sModDC = "5",
                    sStaticDC = "nil",
                    nTotalOverride = 15 -- Save result is 15 (DC 5 + 10 = 15) -> Success!
                }
                onSaveNew(source, target, sotgRoll)
                assert(#ActionsManager.save_calls == 0, "Ruleset handler should NOT be called for SotG save (prevent duplicate output)")
                assert(#ActionsManager.outputs == 1, "Custom SotG output should be emitted")
                assert(string.find(ActionsManager.outputs[1].msgLong.text, "%[SUCCESS%]"), "Should output SUCCESS")
            `
        }
    ];

    console.log(`Running ${testCases.length} tests...`);
    let passedCount = 0;
    let failedCount = 0;

    for (const tc of testCases) {
        try {
            await lua.doString(tc.code);
            console.log(`✔ [PASS] ${tc.name}`);
            passedCount++;
        } catch (err) {
            console.error(`✘ [FAIL] ${tc.name}`);
            console.error(`  Error: ${err.message}`);
            failedCount++;
        }
    }

    // Clean up
    lua.global.close();

    console.log("\n=== Test Summary ===");
    console.log(`Total:  ${testCases.length}`);
    console.log(`Passed: ${passedCount}`);
    console.log(`Failed: ${failedCount}`);

    if (failedCount > 0) {
        console.error("\nTests failed!");
        process.exit(1);
    } else {
        console.log("\nAll tests passed successfully!");
        process.exit(0);
    }
}

runTests().catch(err => {
    console.error("Unhandled rejection / error during tests:", err);
    process.exit(1);
});
