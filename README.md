# Strength of the Grave

https://github.com/JustinFreitas/StrengthOfTheGrave

Strength of the Grave v1.0.0, by Justin Freitas

ReadMe and Usage Notes

When damage is applied to an NPC or PC with the Strength of the Grave trait, the target will roll a charisma save with a DC of 5 + the damage taken.  If success, the target will be left with one hit point instead of dying.  If the damage type is at least part radiant or the hit is a critical hit, Strength of the Grave has no effect and will not be triggered (target will go unconscious, as normal).

There is a radial menu option in the 10 o'clock position when right clicking on a CT actor that allows for Strength of the Grave to be applied to an Unconscious actor.  If invoked, it will leave the actor with one wound remaining until max hp and also remove the Unconscious and Prone effects if they exist.  This will work even if the target doesn't have the Strength of the Grave trait.

A chat command /sg (or /sotg or /strengthofthegrave) was added to do the application to apply the Strength of the Grave result to the specified Combat Tracker actor (case sensitive).  The first match found will be used.  This will work even if the target doesn't have the Strength of the Grave trait.  For example: /sg PCName

Changelist:
- v1.0.0 - Initial version, from Undead Fortitude v2.0.5 as base.
