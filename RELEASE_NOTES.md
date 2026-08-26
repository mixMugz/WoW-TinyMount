# Release Notes

## 1.2.0 — Vehicles

The key already got you off a mount. It now gets you off everything else too.

* **Vehicles.** In a passenger seat, a turret, a siege engine — anything the
  game will let you climb out of — the slot turns into an exit button and the
  key leaves the vehicle.
* It works in combat and the slot stays lit for it, same as dismounting always
  has. The tooltip says which of the two you are about to do.
* The icon is the same for both, because Blizzard's exit-vehicle art and their
  dismount art are one and the same file. The tooltip is what tells them apart.
* The vehicle is checked before the mount: the driver of a two-seater is both at
  once, and leaving puts them on the ground either way.
* The extra stands down in a vehicle, the same way it already did while mounted:
  there, the press has one job.
* **One quirk, documented rather than worked around:** pressed in druid flight
  form, the extra draws a red *you can't use that ability while pacified*. The
  mount still comes out, so it costs nothing but the complaint. Flying pacifies
  you and `/cancelform` does not rescue it — the client stays pacified a moment
  longer than the form lasts. Silencing the extra through that window was tried
  and reverted: the same window is where it legitimately fires on every ordinary
  press out of cat or bear form.
* Flight paths are out of scope — the client locks the action bars for the whole
  flight, so there is no press to answer.

**Shorthand for specialisation.** `[sp:2]` is `[spec:2]`, `[nsp:2]` is
`[nospec:2]`. Two characters a branch, which matters once you are writing a branch
per specialisation per flight state — a druid spends a dozen of them. Shorthands
that take an argument live in a new `ARG_CONDITIONS` table; adding another is
one line, and any word with a colon that is not listed still passes through
untouched.

**Shapeshifted, documented at last.** `/mnt` from cat, bear, moonkin, travel
form or ghost wolf answers *You must be in humanoid form* while the very same
mount summons fine from the mount journal. That is not fixable in an addon:
the journal calls the identical `C_MountJournal.SummonByID`, but the client
cancels your form only when its own code is the caller. Put a bare
`/cancelform` above the command and the macro does it for you, in one keypress
and with no condition needed. The README now explains why, so the next person
to hit it stops digging sooner.

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
255 characters a macro gets.

* `/mnt` takes spellIDs or mountIDs, in the usual `[conditions]id;[conditions]id`
  shape.
* Shorthand for the conditions a mount macro is actually made of, so that six
  mounts fit where two names used to.
* The action bar icon is live: it follows the modifier you are holding, before
  you click anything, and the tooltip shows the mount that key would summon.
* While mounted the command always dismounts, and the slot shows it.
* Works with the default bars, Dominos, Bartender4, and anything else built on
  LibActionButton-1.0.
