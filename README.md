# TinyMount

Summon mounts by id, not by name — short macros with a live action bar icon.

## Why

A WoW macro is capped at **255 characters**, and localised mount names are long
— plenty run past thirty on their own, before you have written a single
conditional. Four or five of those and the macro is full. You end up truncating
names until it silently stops working, and a truncated name fails quietly, which
is the worst kind of failure.

Numeric ids are three to five digits. This macro is 45 characters:

```
/mnt [af,nmnt]11111;[f,nmnt]22222;[nmnt]33333
```

The same three mounts spelled out by name do not fit at all.

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
* aboard anything, the slot turns into an exit button — same key, both ways

### Getting off

**While you are aboard something the command gets you off it.** Conditions are
not consulted at all — no modifier, no `[flyable]`, nothing in the macro can
change that, and the slot shows the exit icon to say so.

Two states count as aboard, and they are asked in this order:

| State | What the key does | Tooltip |
|---|---|---|
| in a vehicle — a passenger seat, a turret, a siege engine | leaves it | *Leave Vehicle* |
| on a mount | dismounts | *Dismount* |

The vehicle is asked first because the driver of a two-seater is both at once,
and leaving the vehicle puts them on the ground either way.

Both work in combat and the slot stays lit for them, which is when getting off
matters most. The icon is the same picture for both — it is Blizzard's own, and
their exit-vehicle art and their dismount art have always been one file. The
tooltip is what tells them apart.

Flight paths are not covered, and cannot be: the client locks your action bars
for the whole flight, so there is no press to answer. Use Blizzard's own leave
button if you want off early.

So one key does both directions and you never need a `[mounted]` branch or a
separate `/dismount` line. If you would rather keep riding while a modifier is
held, this is the one behaviour you cannot express in the macro — it is decided
before the macro is read.

### Shapeshifted

Add one line above the command:

```
/cancelform
/mnt [m:cs]11111;22222
```

No condition on it. `/cancelform` out of a form is a no-op and says nothing, so
it will not draw the error that would stop the client reading the rest of the
macro. One keypress still does the whole thing — the form is down by the time
`/mnt` is read.

It goes at the very top, above a `/click` line too, since dropping the form is
also what lets the extra go off — most of them cannot be used shapeshifted
either:

```
/cancelform
/click tmt140309
/mnt [m:cs]11111;22222
```

Without it, `/mnt` from cat, bear, moonkin, travel form or ghost wolf answers
*You must be in humanoid form* and no mount comes out — while the very same
mount still summons fine from the mount journal.

That is not a bug in TinyMount and it cannot be fixed here. The journal calls
exactly the same function, `C_MountJournal.SummonByID`, on one bare line. The
function is not protected — TinyMount is built on that — but half of it is:
the client cancels your form when its own code is the caller and refuses to when
an addon is. There is no way around it from Lua either, because
`CancelShapeshiftForm` is protected outright and cancelling a form through the
buff functions is blocked by name, specifically so that addons cannot reach the
`[form]` conditional.

The macro can, though. `/cancelform` is run by the client under your own
keypress, which is secure, and that is the whole difference.

One thing to know if you share the macro across the account: `/cancelform` drops
a warrior's or monk's stance too, since the game files those under the same
mechanic. On a druid or a shaman there is nothing to lose.

**One quirk in flight form.** Pressed while you are flying, the extra draws a
red *you can't use that ability while pacified* — but the mount still comes out,
so it costs you nothing except the complaint.

The reason is a race you cannot arrange your way out of. `/cancelform` drops the
form instantly, but the client keeps you *pacified* for a moment longer, so by
the time the `/click` on the next line is read the form is gone, the extra looks
perfectly usable, and firing it still fails.

TinyMount does not try to silence it, and that is deliberate. That same moment
after `/cancelform` is when the extra legitimately fires on every ordinary press
out of cat, bear or moonkin form — suppressing it there to spare a rare flying
press would break the common case to tidy up the rare one.

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

### Where the button comes from

Worth reading before you copy a `/click` line somewhere else, because this is
the one thing about extras that surprises people.

TinyMount learns a name while it is **repainting a slot**. So it only ever sees
one that is written in a macro which is *on a bar* and carries a `/mnt` line —
those are the only macros it has any reason to read.

The button it then builds is a frame, and a frame's name is global. Once it
exists, **any** macro can click it: with no `/mnt` line, on any bar, out of any
macro at all. But something has to create it first, and only a mount macro on a
bar does that.

Which is why this does nothing whatsoever:

```
/use Healthstone
/click tmt140309
```

— if `tmt140309` has never appeared in a mount macro on a bar. Clicking a button
that does not exist is not an error, so there is nothing to see: no red line, no
sound, no hint that the line was ever read. Put the name in your mount macro
once and press it, and the same name starts working everywhere.

The frame itself lives until you log out, because nothing in the client destroys
a frame. It stops *firing*, though, the moment the name is gone from every macro
TinyMount reads: editing any macro empties every button, and the macros fill
back in only the names they still spell. So taking a `/click` line out does what
you would expect it to, even though the frame behind it stays where it is,
doing nothing.

### When the extra stays quiet

It is held back in four states, and in all four it is held back silently — no
red line, no "not ready yet" out of the speakers:

* **Aboard something.** Mounted, or in a vehicle. The press is an exit and there
  is nothing to accompany.
* **In combat.** No mount can be summoned in combat at all, so the slot greys
  out and the key does nothing whatsoever — TinyMount does not even ask, because
  asking is what earns the client's complaint. Being aboard is the exception:
  the key still gets you off and the slot stays lit. The tooltip answers either
  way.
* **On cooldown.** The global cooldown does not count; an extra is meant to ride
  off it.
* **Not yours.** A spell this character has not learned, a toy that is in the
  box but locked to another class, an item you are out of.

Mounted and in combat are macro conditionals under the hood, so the client
enforces them itself and goes on doing it through a fight. The rest have no
conditional behind them and are applied by TinyMount out of combat, which is the
only place they matter — in a fight the conditional has already emptied the
button. Anything TinyMount cannot answer counts as held back, and a press that
quietly does nothing is the cheap outcome.

The macro itself is never at risk. A line that fails stops nothing below it —
only `/stopmacro` and a condition matching nothing end a macro early — so the
mount comes out either way. What an unheld extra costs is the noise, and for
the lines TinyMount does not manage there is [`/tmq`](#silencing-a-line).

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

## Silencing a line

`/tmq` mutes the client's complaint about the line under it — the red text and
the spoken one both — and turns everything back on by itself a fraction of a
second later.

```
#showtooltip Divine Steed
/tmq
/use item:140309
/cast Divine Steed
```

The toy is off the global cooldown, so both lines go off. On the presses where
it is still on cooldown you simply hear nothing about it, and the spell casts as
usual.

**One command, and no closing one.** `/tmq` covers the frame it is read in,
which is the frame the error turns up in. There is nothing to switch back on
afterwards — and so nothing that stays muted if you later edit the line away.

Worth knowing:

* it silences **everything** for that fraction of a second, not only cooldown
  errors. You asked for it by hand, on a line whose failure you already
  understand
* the spoken error is a client setting with no per-message switch, so TinyMount
  turns it off and puts it back to **whatever it was**. If you had error speech
  off already, it stays off
* it changes nothing about what the macro does. A line that fails still fails,
  it just does so without an audience
* you do not need it above a `/click` extra — those hold themselves back
  silently to begin with. `/tmq` is for the ordinary `/use` and `/cast` lines
  TinyMount has nothing to do with

## Shorthand

Conditions are what a mount macro is mostly made of, so they have short forms.
The rule: **a colon means the condition takes an argument.** `m:` is the
modifier one, `sp:` is the specialisation one, and everything without a colon is
a plain state.

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

### Specialisation

| Short | Expands to |
|-------|------------|
| `[sp:2]` | `[spec:2]` |
| `[nsp:2]` | `[nospec:2]` |
| `[sp:1/2]` | `[spec:1/2]` |

Two characters a branch, which sounds like nothing until you are a druid: four
specialisations against `af` / `f` / `nf` is a dozen branches, and `spec:`
appears in every one of them.

```
/mnt [sp:1,af]11111;[sp:1]22222;[sp:2,af]33333;[sp:2]44444
```

### Mixing

Anything not in the tables is passed through untouched, so full spellings and
every other conditional keep working next to the short ones:

```
/mnt [m:a,nmnt,f]11111;[@mouseover,spec:2]22222;33333
```

To add your own shorthand, edit `CONDITIONS` at the top of `TinyMount.lua` for
plain states, or `ARG_CONDITIONS` just below it for ones that take an argument —
a line each.

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
