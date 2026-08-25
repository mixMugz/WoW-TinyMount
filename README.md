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

Drop the folder into `Interface/AddOns/`. **It must be named `TinyMount`**, not
`WoW-TinyMount` — rename it if you cloned the repository directly.

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

## License

MIT
