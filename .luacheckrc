-- Luacheck config for Fantasy Grounds (FGC/FGU) extension scripts.
-- FG injects a large set of engine globals and treats each <script> file's
-- top-level functions as implicit globals reachable across the package, so we
-- relax the "undefined/non-standard global" rules and whitelist the FG API.

std = "max"

-- FG ruleset/engine globals referenced by this extension.
read_globals = {
    "DB", "User", "Session", "Comm",
    "ActorManager", "ActorManager5E",
    "EffectManager", "EffectManager5E",
    "ActionsManager", "ActionsManager2", "ActionD20",
    "ActionDamage", "ActionHealthD20", "ActionSave",
    "CombatManager", "StringManager", "ModifierStack",
    "super", "registerMenuItem", "getDatabaseNode",
    "StrengthOfTheGrave",
}

-- FG scripts define cross-file functions as globals; allow setting them.
allow_defined_top = true

-- Keep line-length advice but at FG's wider, tab-indented style.
max_line_length = 160

-- Engine entry-point callbacks (onInit, onMenuSelection, ...) the FG runtime
-- invokes by name. They look "unused" to luacheck because nothing in our own
-- code calls them, and every top-level function here is an FG-reachable global,
-- so suppress the unused-global class outright. (131 = unused defined global.)
ignore = { "131" }

-- We intentionally monkey-patch ruleset damage handlers (ActionDamage.apply,
-- ActionHealthD20.apply, etc.) to intercept rolls. Allow writing those fields.
-- (122 = setting read-only field of a read_globals table.)
-- Per-file options override (don't merge with) the top-level set, so repeat 211.
files["scripts/strengthofthegrave.lua"] = {
    ignore = { "131", "122" },
}
