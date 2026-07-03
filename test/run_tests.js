const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { LuaFactory } = require('wasmoon');

async function runTests() {
    console.log("Setting up Lua VM via wasmoon...");
    const luaFactory = new LuaFactory();
    const lua = await luaFactory.createEngine();

    // 1. Mock FGU environment globals
    console.log("Mocking FGU environment globals...");
    
    await lua.doString(`
        Interface = {}
        OptionsManager = {}
        Comm = {}
        DB = {}
        ActorManager = {}
        ActorManager5E = {}
        CombatManager = {}
        EffectManager = {}
        StringManager = {}
        User = {}
        Session = { VersionMajor = 4 }
        ActionDamage = {}
        ActionsManager = {}
        ModifierStack = {}
        
        -- Mock User
        function User.isHost() return true end

        -- Mock StringManager
        StringManager.trim = function(s)
            if not s then return "" end
            return s:match("^%s*(.-)%s*$")
        end
        StringManager.isBlank = function(s)
            if type(s) ~= "string" then return true end
            return s:gsub("%s+", "") == ""
        end

        -- Mock OptionsManager
        local options = {}
        function OptionsManager.registerOption2() end
        function OptionsManager.isOption(key, val)
            return options[key] == val
        end
        function OptionsManager.setOption(key, val)
            options[key] = val
        end

        -- Mock Comm
        local chatMessages = {}
        function Comm.registerSlashHandler() end
        function Comm.addChatMessage(msg)
            table.insert(chatMessages, msg.text)
        end
        function Comm.deliverChatMessage(msg)
            table.insert(chatMessages, msg.text)
        end
        function Comm.getChatMessages()
            return chatMessages
        end
        function Comm.clearChatMessages()
            chatMessages = {}
        end

        -- Mock CombatManager
        CombatManager.CT_LIST = "combattracker"
        function CombatManager.requestActivation() end

        -- Mock ModifierStack
        function ModifierStack.reset() end

        -- Mock ActionsManager
        local resultHandlers = {}
        function ActionsManager.registerResultHandler(rollType, handler)
            resultHandlers[rollType] = handler
        end
        function ActionsManager.getResultHandler(rollType)
            return resultHandlers[rollType]
        end
        
        rolledRoll = nil
        function ActionsManager.applyModifiersAndRoll(rSource, rTarget, bSecret, rRoll)
            rolledRoll = rRoll
        end

        local totalResult = 15
        function ActionsManager.total(rRoll)
            return totalResult
        end
        function ActionsManager.setTotalResult(val)
            totalResult = val
        end
        function ActionsManager.outputResult() end

        -- Mock ActorManager5E
        function ActorManager5E.getSave(nodeActor, sSave)
            return 3, false, false, "" -- mod=3, noAdv, noDis
        end

        -- Mock Database structure
        dbData = {}
        dbChildren = {}
        
        function DB.setNodeValue(path, val)
            dbData[path] = val
        end
        
        function DB.setValue(node, field, typeStr, val)
            local nodePath = ""
            if type(node) == "table" and node.path then
                nodePath = node.path
            elseif type(node) == "string" then
                nodePath = node
            end
            dbData[nodePath .. "." .. field] = val
        end
        
        function DB.getValue(node, field, default)
            if type(node) == "table" and node.label and field == "label" then
                return node.label
            end
            local nodePath = ""
            if type(node) == "table" and node.path then
                nodePath = node.path
            elseif type(node) == "string" then
                nodePath = node
            end
            local fullPath = nodePath .. "." .. field
            if dbData[fullPath] ~= nil then
                return dbData[fullPath]
            end
            return default
        end

        function DB.getText(node, field, default)
            return DB.getValue(node, field, default)
        end

        function DB.setChildren(nodePath, children)
            dbChildren[nodePath] = {}
            for k, v in pairs(children) do
                dbChildren[nodePath][k] = true
            end
        end

        function DB.getChildren(node, field)
            local nodePath = ""
            if type(node) == "table" and node.path then
                nodePath = node.path
            elseif type(node) == "string" then
                nodePath = node
            end
            
            local fullPath = nodePath
            if field then
                fullPath = nodePath .. "." .. field
            end
            
            local children = dbChildren[fullPath] or {}
            local list = {}
            for k, v in pairs(children) do
                list[k] = { path = fullPath .. "." .. k }
            end
            return list
        end

        -- Enable createChild mocking
        local mockNodeIndex = 1
        function createMockNode(nodePath)
            local node = { path = nodePath }
            function node.createChild(name)
                mockNodeIndex = mockNodeIndex + 1
                local childName = name or ("child" .. mockNodeIndex)
                local childPath = nodePath .. "." .. childName
                
                -- Register child in dbChildren
                if not dbChildren[nodePath] then
                    dbChildren[nodePath] = {}
                end
                dbChildren[nodePath][childName] = true
                
                return createMockNode(childPath)
            end
            return node
        end

        function DB.findNode(nodePath)
            return createMockNode(nodePath)
        end

        -- Mock ActorManager
        local actorMap = {}
        local actorPC = {}
        function ActorManager.getActor(nodeCT)
            return actorMap[nodeCT.path]
        end
        function ActorManager.setActor(nodeCTPath, actor)
            actorMap[nodeCTPath] = actor
        end
        function ActorManager.isPC(v)
            if type(v) == "table" and v.path then
                if actorPC[v.path] == true or v.path:find("charsheet") then
                    return true
                end
            end
            return false
        end
        function ActorManager.setPC(nodeCTPath, val)
            actorPC[nodeCTPath] = val
        end
        function ActorManager.getCreatureNode(v)
            if type(v) == "table" and v.sCreatureNode then
                return DB.findNode(v.sCreatureNode)
            end
            local rActor = actorMap[v.path]
            if rActor and rActor.sCreatureNode then
                return DB.findNode(rActor.sCreatureNode)
            end
            return DB.findNode("charsheet.id-00001")
        end
        function ActorManager.getCTNode(v)
            if type(v) == "table" and v.path then
                return DB.findNode(v.path)
            end
            return nil
        end
        function ActorManager.getDisplayName(node)
            return "Mock Hero"
        end
        function ActorManager.getCreatureNodeName(node)
            return "charsheet.id-00001"
        end

        -- Mock EffectManager
        local activeEffects = {}
        function EffectManager.hasEffect(rActor, sEffect)
            return activeEffects[sEffect] == true
        end
        function EffectManager.setEffect(sEffect, val)
            activeEffects[sEffect] = val
        end
        function EffectManager.removeEffect(nodeCT, sEffect)
            activeEffects[sEffect] = false
        end

        -- Mock ActionDamage
        appliedDamageTotal = nil
        function ActionDamage.applyDamage(rSource, rTarget, rRoll)
            appliedDamageTotal = rRoll.nTotal
        end
    `);

    // 2. Load the actual strengthofthegrave script
    console.log("Loading scripts/strengthofthegrave.lua into VM...");
    const luaCodePath = path.join(__dirname, '../scripts/strengthofthegrave.lua');
    const luaCode = fs.readFileSync(luaCodePath, 'utf8');
    
    await lua.doString(luaCode);
    console.log("StrengthOfTheGrave loaded successfully inside VM.\n");

    // 3. Define and run test assertions
    console.log("Running Unit Tests...");
    let testsPassed = 0;
    let testsFailed = 0;

    async function runAssert(fnName, expected, luaCodeToRun) {
        try {
            const result = await lua.doString(luaCodeToRun);
            assert.strictEqual(result, expected);
            console.log(`  ✓ PASS: ${fnName} -> got ${result}`);
            testsPassed++;
        } catch (err) {
            console.error(`  ✗ FAIL: ${fnName} -> expected ${expected}, got error or mismatch: ${err.message}`);
            testsFailed++;
        }
    }

    // --- TEST 1: getDecomposedTraitName parsing ---
    await lua.doString(`
        local trait = { path = "charsheet.id-00001.featurelist.feat1" }
        DB.setNodeValue("charsheet.id-00001.featurelist.feat1.name", "Strength of the Grave (DC 15)")
        decomp = getDecomposedTraitName(trait)
    `);
    await runAssert("getDecomposedTraitName start", 1, "return decomp.nStrengthOfTheGraveStart");
    await runAssert("getDecomposedTraitName suffix", " (DC 15)", "return decomp.sStrengthOfTheGraveTraitSuffix");

    // --- TEST 2: getStrengthOfTheGraveData with PC ---
    await lua.doString(`
        nodeChar = { path = "charsheet.id-00001" }
        DB.setChildren("charsheet.id-00001.featurelist", {
            ["feat1"] = true
        })
        DB.setNodeValue("charsheet.id-00001.featurelist.feat1.name", "Strength of the Grave DC 14")
        
        -- HP: 15 max, 10 wounds (5 current HP)
        DB.setNodeValue("charsheet.id-00001.hp.total", 15)
        DB.setNodeValue("charsheet.id-00001.hp.temporary", 0)
        DB.setNodeValue("charsheet.id-00001.hp.wounds", 10)
        
        -- Register ActorManager
        local actorPC = { sCreatureNode = "charsheet.id-00001", sName = "Sariel", sType = "charsheet" }
        ActorManager.setActor("combattracker.entry1", actorPC)
        ActorManager.setActor("charsheet.id-00001", actorPC)
        ActorManager.setPC("combattracker.entry1", true)
        ActorManager.setPC("charsheet.id-00001", true)
        nodeCT = { path = "combattracker.entry1" }
        
        onInit()
        aData = hasStrengthOfTheGraveTrait("pc", nodeChar, nil)
    `);
    await runAssert("hasStrengthOfTheGraveTrait total HP", 15, "return aData.nTotalHP");
    await runAssert("hasStrengthOfTheGraveTrait Static DC", 14, "return aData.nStaticDC");

    // --- TEST 3: applyDamage_v2 -> normal damage (HP remains > 0) ---
    await lua.doString(`
        appliedDamageTotal = nil
        rolledRoll = nil
        local roll = { sDesc = "[DAMAGE]", nTotal = 3, bSecret = false }
        applyDamage_v2(nil, nodeCT, roll)
    `);
    await runAssert("Normal damage applied (no save)", 3, "return appliedDamageTotal");
    await runAssert("No save roll triggered", true, "return rolledRoll == nil");

    // --- TEST 4: applyDamage_v2 -> save roll triggered (HP drops to 0) ---
    await lua.doString(`
        appliedDamageTotal = nil
        rolledRoll = nil
        local roll = { sDesc = "[DAMAGE] sword", nTotal = 6, bSecret = false }
        applyDamage_v2(nil, nodeCT, roll)
    `);
    // Gromph has 5 HP. 6 damage would drop him to -1. Save should be triggered.
    await runAssert("Save roll was triggered", "save", "return rolledRoll.sType");
    await runAssert("Save roll has bStrengthOfTheGrave", "true", "return rolledRoll.bStrengthOfTheGrave");

    // --- TEST 5: applyDamage_v2 -> Critical hit (no save, damage applies directly) ---
    await lua.doString(`
        appliedDamageTotal = nil
        rolledRoll = nil
        local roll = { sDesc = "[DAMAGE][CRITICAL]", nTotal = 6, bSecret = false }
        applyDamage_v2(nil, nodeCT, roll)
    `);
    await runAssert("Critical damage applied directly (no save)", 6, "return appliedDamageTotal");
    await runAssert("No save triggered for critical", true, "return rolledRoll == nil");

    // --- TEST 6: onSaveNew -> Save success (roll >= DC) ---
    await lua.doString(`
        appliedDamageTotal = nil
        ActionsManager.setTotalResult(16) -- roll result is 16
        
        local saveRoll = {
            bStrengthOfTheGrave = "true",
            sStaticDC = "14",
            nTotalHP = 15,
            nTempHP = 0,
            nWounds = 10,
            nDamage = 6,
            sDamage = "[DAMAGE]",
            sTrimmedTraitNameForSave = "Strength of the Grave"
        }
        onSaveNew(nodeCT, nodeCT, saveRoll)
    `);
    // Success -> Cap damage so we drop to exactly 1 HP (Wounds = 14)
    // 15 total HP - 10 wounds = 5 current HP.
    // To leave 1 HP, we must apply 4 damage.
    await runAssert("Save Success -> damage capped to leave at 1 HP", 4, "return appliedDamageTotal");
    await runAssert("Save Success -> cast charge incremented", 1, "return DB.getValue('charsheet.id-00001.powers.child3', 'cast', 0)");

    // --- TEST 7: onSaveNew -> Save failure (roll < DC) ---
    await lua.doString(`
        appliedDamageTotal = nil
        ActionsManager.setTotalResult(10) -- roll result is 10 (DC is 14)
        
        -- Reset power cast back to 0
        DB.setValue({path='charsheet.id-00001.powers.child3'}, 'cast', 'number', 0)
        
        local saveRoll = {
            bStrengthOfTheGrave = "true",
            sStaticDC = "14",
            nTotalHP = 15,
            nTempHP = 0,
            nWounds = 10,
            nDamage = 6,
            sDamage = "[DAMAGE]",
            sTrimmedTraitNameForSave = "Strength of the Grave"
        }
        onSaveNew(nodeCT, nodeCT, saveRoll)
    `);
    // Failure -> Apply full 6 damage
    await runAssert("Save Failure -> full damage applied", 6, "return appliedDamageTotal");
    await runAssert("Save Failure -> cast charge remains 0", 0, "return DB.getValue('charsheet.id-00001.powers.child3', 'cast', 0)");

    // 4. Print Summary
    console.log(`\nTest Summary: ${testsPassed} passed, ${testsFailed} failed.`);
    
    if (testsFailed > 0) {
        process.exit(1);
    }
}

runTests().catch(err => {
    console.error("Test execution failed: ", err);
    process.exit(1);
});
