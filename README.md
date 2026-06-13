# Strength of the Grave

https://github.com/JustinFreitas/StrengthOfTheGrave

Strength of the Grave v1.5, by Justin Freitas

ReadMe and Usage Notes

When damage is applied to an NPC or PC with the Strength of the Grave trait, the target will roll a Charisma save with a DC of 5 + the damage taken.  On a success, the target is left with one hit point instead of dropping to zero.  If the damage type is at least partly radiant, or the hit is a critical hit, Strength of the Grave has no effect and will not be triggered (the target will go unconscious as normal).

The save DC can be customized in the trait name.  Add "DC N" to use a fixed DC of N, "Mod N" to change the +5 modifier to +N, or "No Mods" to ignore the radiant and critical exclusions.  For example: Strength of the Grave (DC 12).

Strength of the Grave is limited to one use per long rest.  The extension tracks this with a power entry named "Strength of the Grave" on the character, using its prepared and cast counts.  Once cast equals prepared, it will not trigger again until reset.

There is a radial menu option in the 10 o'clock position when right clicking on a Combat Tracker actor that allows Strength of the Grave to be applied to an Unconscious actor.  If invoked, it leaves the actor with one wound remaining short of max hit points and removes the Unconscious and Prone effects if they exist.  This is a manual GM override and works even if the target doesn't have the Strength of the Grave trait, and it does not consume the per long rest use.

A chat command /sg (or /sotg or /strengthofthegrave) was added to apply the Strength of the Grave result to the specified Combat Tracker actor (case sensitive).  The first match found will be used.  This will work even if the target doesn't have the Strength of the Grave trait.  For example: /sg PCName

The extension supports both Fantasy Grounds Classic (FGC) and Fantasy Grounds Unity (FGU).

Changelist:
- v1.0.0 - Initial version, from Undead Fortitude v2.0.5 as base.
- v1.0.1 - Update icons.  Update gitignore for old UF outputs.
- v1.0.2 - Any chat messages that are only displayed to the GM should have the red eye icon ('secret = true').
- v1.0.5 - Use safe wrapper functions for getting actors and effects; fix deprecated ActorManager and EffectManager5E usage.
- v1.2 - Fix advantage/disadvantage summing bug and restore ruleset save handler passthrough.
- v1.4 - Use modern non-deprecated ActorManager methods for actor type and node resolution.
- v1.5 - Nil-safety and correctness fixes (DC and damage guards, boolean normalization, tightened radiant match, safer type/node resolution); add luacheck config and clear the lint.
