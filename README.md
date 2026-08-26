# TinyMount

Summon mounts by id, not by name — short macros with a live action bar icon.

## Why

A WoW macro is capped at **255 bytes**, and a localised client spends two bytes
per letter. A `/cast` list of six mount names in Russian, German or Korean does
not fit — you end up truncating names until the macro silently stops working.

Numeric ids fit easily. This macro is 45 bytes:

```
/mnt [af,nmnt]11111;[f,nmnt]22222;[nmnt]33333
```

The same thing spelled out in mount names is around 250 and climbing.

## Install

Copy the `TinyMount` folder — the one inside this repository, not the repository
folder itself — into `Interface/AddOns/`. The name has to stay `TinyMount`, which
is why it is already spelled that way here.

## Usage

Make a normal macro and put it on your bar:

```
/mnt [m:cs]11111;[m:as]22222;[m:ac]33333;[m:c]44444;[m:s]55555;[m:a]66666;77777
```

That is it. No `#showtooltip` — it does nothing here, the client cannot read
custom commands. Pick any icon in the macro editor; TinyMount overwrites it.

Ids can be **either spellIDs or mountIDs**, whichever you have at hand.

### What you get on the bar

* the icon changes **as you hold a modifier**, before you click anything
* the tooltip shows the mount that key would actually summon
* mounted, the slot turns into a dismount button — same key, both ways

### Dismounting

**While you are mounted the command always dismounts.** Conditions are not
consulted at all — no modifier, no `[flyable]`, nothing in the macro can change
that, and the slot shows the dismount icon to say so.

So one key does both directions and you never need a `[mounted]` branch or a
separate `/dismount` line. If you would rather keep riding while a modifier is
held, this is the one behaviour you cannot express in the macro — it is decided
before the macro is read.

## Extras

An off-GCD toy or a cosmetic spell can go off together with the mount, on a
`/click` line above the command:

```
/click tmt140309
/mnt [m:cs]11111;22222
```

`140309` is the Prismatic Bauble, so that macro shimmers you rainbow before it
puts you on a mount.

The name is the whole configuration — `tm`, one letter for the kind, then the
id. TinyMount builds a hidden secure button under that name the first time it
sees the macro, so there is nothing to set up and no settings file.

| | Kind | Use it for |
|---|---|---|
| `tmt` | toy | anything out of the toy box |
| `tms` | spell | a spell you know |
| `tmi` | item | something that really sits in your bags |

All lower case, and that is the only spelling — the name is looked up exactly as
written, so `TMT140309` is a different button, and a button that does not exist
does nothing at all.

Pick the kind by what the id *is*, not by where you found it. A toy you have
learned is `tmt`, even though its id is an item id and the tooltip calls it an
item — the physical item is gone from your bags, so `tmi` has nothing to reach
for and the click does nothing at all.

`/click` takes conditionals of its own, and they are independent of the mount's.
Spell them out in full — the shorthand below is expanded by `/mnt` and nothing
else reads it:

```
/click [mod:shift]tms121183
/mnt [m:a]11111;22222
```

`121183` is a paladin's Contemplation, held here to shift-clicks only.

**It has to be `/click`, not `/use` or `/cast`.** Two different reasons, and both
are hard:

* TinyMount cannot fire the extra for you. Casting a spell or using an item from
  an addon is protected — the client checks who is calling, and an addon is
  never a valid caller. `C_MountJournal.SummonByID` is the one exception this
  addon is built on, and it does not extend to anything else. A secure button
  sidesteps it honestly: your keypress drives the click, not TinyMount.
* A `/use` or `/cast` line makes the client treat the whole slot as a spell
  action. It takes the icon over natively, repaints it faster than any addon can
  answer, and adds a proc glow for good measure — the live icon simply stops
  working. `/click` resolves to nothing, so the slot stays ours.

### When the extra stays quiet

It is held back in four states, and in all four it is held back silently — no
red line, no "not ready yet" out of the speakers:

* **Mounted.** The press is a dismount, and there is nothing to accompany.
* **In combat.** No mount can be summoned in combat at all, so the slot greys
  out and the key does nothing whatsoever — TinyMount does not even ask, because
  asking is what earns the client's complaint. Mounted is the exception: the key
  still dismounts and the slot stays lit. The tooltip answers either way.
* **On cooldown.** The global cooldown does not count; an extra is meant to ride
  off it.
* **Not yours.** A spell this character has not learned, a toy that is in the
  box but locked to another class, an item you are out of.

The first two are macro conditionals under the hood, so the client enforces them
itself and goes on doing it through a fight. The last two have no conditional
behind them and are applied by TinyMount out of combat, which is the only place
they matter. Anything TinyMount cannot answer counts as held back: a press
that quietly does nothing costs you one press, while an extra that draws an
error stops the client reading the macro there and costs you the mount as
well.

### One macro, several characters

A macro can carry more than one `/click` line. Each is an ordinary line of the
macro, the client runs them in turn, and TinyMount builds a separate hidden
button for every name it finds — so they do not compete for anything:

```
/click tms121183
/click tmt140309
/mnt [m:cs]11111;22222
```

Because an extra this character does not have is quietly not armed, that macro
needs no conditionals to sort itself out: the paladin gets Contemplation and the
Bauble, the death knight gets the Bauble alone. Nothing to configure, and one
macro for the account.

The one limit is the global cooldown, and it is the same limit any macro has: if
the first line spends the GCD, the second may not get through. Extras are meant
to be things that ride off it.

Extras fire whether or not the mount does, and they fire first, in the order
they are written. If you need one without the other, use two keys.

## Shorthand

Conditions are what a mount macro is mostly made of, so they have short forms.
The rule: **with a colon it is a modifier, without one it is a state.**

### Modifiers

| Short | Expands to |
|-------|------------|
| `[m:c]` | `[mod:ctrl]` |
| `[m:s]` | `[mod:shift]` |
| `[m:a]` | `[mod:alt]` |
| `[m:cs]` | `[mod:ctrl,mod:shift]` |
| `[m:acs]` | `[mod:alt,mod:ctrl,mod:shift]` |
| `[nm:a]` | `[nomod:alt]` |

Letters are `c` ctrl, `s` shift, `a` alt, in any order. Combinations expand to
commas, which is AND — the only spelling of a modifier combination the client
actually documents.

### States

| Short | Expands to | | Short | Expands to |
|-------|------------|---|-------|------------|
| `mnt` / `nmnt` | mounted / nomounted | | `sw` / `nsw` | swimming / noswimming |
| `f` / `nf` | flyable / noflyable | | `in` / `out` | indoors / outdoors |
| `af` / `naf` | advflyable / noadvflyable | | `c` / `nc` | combat / nocombat |
| `fly` / `nfly` | flying / noflying | | `r` / `nr` | resting / noresting |

### Mixing

Anything not in the tables is passed through untouched, so full spellings and
every other conditional keep working next to the short ones:

```
/mnt [m:a,nmnt,f]11111;[@mouseover,spec:2]22222;33333
```

To add your own shorthand, edit the `CONDITIONS` table at the top of
`TinyMount.lua`.

## Finding ids

Paste into chat to list your favourite mounts with their spellIDs:

```
/run for _,i in ipairs(C_MountJournal.GetMountIDs()) do local n,s,_,_,_,_,f=C_MountJournal.GetMountInfoByID(i) if f then print(s,n) end end
```

Or search by a fragment of the name:

```
/run for _,i in ipairs(C_MountJournal.GetMountIDs()) do local n,s=C_MountJournal.GetMountInfoByID(i) if n:find("Obsidian") then print(s,n) end end
```

A spellID from Wowhead's URL works just as well.

## Compatibility

| Bars | Supported |
|------|-----------|
| Default Blizzard bars | yes |
| Dominos | yes — it builds from the Blizzard button template |
| Bartender4 and other LibActionButton-1.0 bars | yes |
| ElvUI | no — it ships a renamed fork of the library |

## Notes

* Only mounts. The command works because `C_MountJournal.SummonByID` is not
  protected; the same approach with an ordinary spell would be blocked.
* Dismounting mid-flight does exactly what you expect it to.
* If no branch of the macro matches — you are already mounted and everything is
  behind `[nmnt]`, say — the slot falls back to the icon you picked in the macro
  editor rather than lying about the last mount shown.

## Built with

Written end to end with Claude (Opus 5) in Claude Code — the Lua, the comments
in it, and this README. What the client actually permits was worked out the hard
way, in game, one silent failure at a time.

## License

MIT
