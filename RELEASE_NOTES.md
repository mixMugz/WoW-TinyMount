# Release Notes

## 1.1.0 — Extras

A mount macro can now carry a second thing that goes off with it: a toy, a
spell, or an item. It rides on a `/click` line above the command.

```
/click tmt140309
/mnt [m:cs]11111;22222
```

The button name is the whole configuration — `tm`, then `t` for toy, `s` for
spell or `i` for item, then the id, all in lower case. There is nothing to set
up and still no settings file.

* `/click` takes conditionals of its own, independent of the mount's.
* The extra is held back — silently, with no error text and no "not ready yet"
  out of the speakers — while you are mounted, while you are in combat, while it
  is on cooldown, and on any character that does not have it. The global cooldown
  does not count.
* That last one means a macro can carry a `/click` line per character and sort
  itself out: the paladin's spell stays quiet on the death knight, and one macro
  serves the account.
* In combat the slot greys out, because no mount can be summoned there anyway.
  Mounted it stays lit — dismounting works in a fight, and that is exactly when
  you want it. The tooltip answers either way.

It has to be `/click` rather than `/use` or `/cast`, for two independent
reasons. Both are explained in the README, and neither has a way around it.

## 1.0.0 — Initial release

Summon mounts by id instead of by name, so that a macro full of them fits in the
255 bytes a macro gets.

* `/mnt` takes spellIDs or mountIDs, in the usual `[conditions]id;[conditions]id`
  shape.
* Shorthand for the conditions a mount macro is actually made of, so that six
  mounts fit where two names used to.
* The action bar icon is live: it follows the modifier you are holding, before
  you click anything, and the tooltip shows the mount that key would summon.
* While mounted the command always dismounts, and the slot shows it.
* Works with the default bars, Dominos, Bartender4, and anything else built on
  LibActionButton-1.0.
