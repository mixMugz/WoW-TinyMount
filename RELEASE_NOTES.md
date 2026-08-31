# Release Notes

## 1.5.0 — A toy on its own

Extras have always belonged to the mount. They ride on a `/click` line above
`/mnt`, and they are held back wherever the mount is held back — in combat, in
the saddle, on cooldown. That is right for a passenger, and wrong for a toy you
simply want to use.

**`/click ttoy<id>` fires a toy from any macro at all.**

```text
/click ttoy140309
```

One that hearths, one that opens a profession, one that carries nothing else.
No `/mnt` anywhere in sight. And it works **in combat** — on a boss, mid-pull —
as well as mounted or in a vehicle.

Such a macro is not touched in any other way. TinyMount does not paint its icon,
does not take over its tooltip, never greys it out: the slot stays exactly as
your bar addon drew it. Only the button behind the name is ours.

**There are no checks on it, and that is the design rather than a shortcut.**
Filtering a button means writing an attribute to it, and writing an attribute is
forbidden in combat — so a filtered button freezes on whatever it held when the
fight started. A toy that came off cooldown mid-fight would stay dead until the
fight ended, and say nothing about why. A button nobody touches cannot be wrong
that way.

The cost is the client's own complaint when the toy is on cooldown or is not
yours, and that is all it costs — a `/click` that fails stops nothing below it.
`/tmq` on the line above silences it, which is what `/tmq` has been for since
1.3.0.

The names are read from your whole macro list, account and character both, at
login, across a loading screen, when you save a macro, and when you drop out of
combat. Never while repainting a slot — so a `ttoy` button costs nothing at all
while you play. It appears in none of the hot paths: not in the cooldown storm
that re-arms extras, not in the repaint pass, not in the bar addon's redraws.

The old `tmt` / `tms` / `tmi` extras are untouched and behave exactly as before,
mount and all. The two are deliberately separate rather than one thing with a
setting, because every state one of them cares about is a state the other
ignores on purpose.

## 1.4.0 — Honest slot

The slot now tells you more of what it knows before you press it, and does a
great deal less work while it is at it.

**`000` summons a random favourite.** One id in the whole language is not an id:

```text
/mnt [m:a]11111;000
```

Alt for the one you chose, anything else for pot luck. It is the same call that
sits behind Blizzard's own button at the top of the mount journal, so the slot
wears their art for it and the tooltip is theirs as well, in your language.
Write it as three digits — `0` and `00` land in the same place, but `000` lines
up with the ids around it and reads as deliberate.

It greys out where it will not work, the same as a named mount. There is no one
mount to ask about until the key goes down, so the answer comes from Blizzard's
spell for it instead — which turns out to know perfectly well whether you are
somewhere you may mount.

**The slot did not grey out when a fight started.** It greyed out if you hovered
it, or pressed a modifier, or did anything else that made the bar redraw — which
is what made this hard to see and easy to dismiss. Entering combat, the bar addon
answers the same moment with a pass of its own that rewrites the icon's
saturation, and it lands after TinyMount. Leaving combat looked right only
because both were writing the same answer there. The slot is now painted a
second time, a frame later, on that one event.

**The slot now greys where the mount will not come out, not only in combat.**
Step into a building that refuses mounts and the icon says so before you press
anything; step out and it lights up again. Hover it while it is grey and the
tooltip carries the client's own sentence for why — *Can only be used
outdoors*, in your language, because it is the client's line and not ours.

The reading comes from `C_MountJournal.GetMountUsabilityByID`, which is the
client answering about **that mount, in that spot**, by the same rules it uses
to grey out its own mount journal. It is deliberately not `IsIndoors()` or the
`[indoors]` conditional: a garrison, a cave and half the buildings in a capital
are all indoors and all let you mount, so those would have greyed the slot
several times an evening for nothing. A slot that lies about being dead is
worse than one that never greys.

Aboard something it stays lit regardless — no room refuses to let you dismount
in it.

Walking into a building is not something the client announces — `ZONE_CHANGED_INDOORS`
sounds as though it would and does not fire for most of them. What it does
announce is that the set of things you can use has changed, which is the same
news said differently, and is how its own buttons know to grey themselves. That
is watched instead, and answered with one question rather than a repaint, so the
slot changes colour on the doorstep without the event's noise costing anything.

**And the press goes quiet there too**, the way it already did in combat. Once
the client has said this one cannot come out here, asking it anyway changes
nothing except that it says so out loud — and the slot has been grey for a while
by then, saying it quietly. Nothing is given up: the summon was never going to
happen.

**Cooldown events no longer repaint anything.** `SPELL_UPDATE_COOLDOWN` fires on
every cast and every global, and each one used to sweep every button on your
bars asking what it held — several hundred thousand questions to the client over
a dungeon, to repaint nothing, since no macro condition can read a cooldown in
the first place. They now go straight to the one thing they have something to
say about: whether an extra is ready.

**A changed action slot repaints that slot, not all of them.** An item sitting
on a bar announces a change every time its stack moves in your bags, so a run
that loots a lot fires tens of thousands of these. The event names the slot it
means, and TinyMount now takes it at its word.

**`[resting]` and `[spec:N]` have events of their own.** They were being
repainted by the noise above, by accident, and would have gone stale the moment
it stopped. `[swimming]` is the one state left with no event anywhere in the
client — it repaints on the next thing that happens, usually the modifier press,
which is also when anyone is looking.

**What this was worth, honestly.** Measured with `GetFunctionCPUUsage`, the
whole addon costs **88 ms over a dungeon run** — and it was never far off that
before, either. The figure in the addon CPU list said 2000–12000 ms, and that
figure was not ours: `hooksecurefunc` bills the addon that installed a hook for
the time spent inside the function it hooked, so TinyMount was being charged for
how the bar addon redraws its own buttons. Several hundred thousand idle calls
into the client really were removed, and that is worth doing on its own merits.
It was never the two seconds anything appeared to say it was.

## 1.3.0 — Quiet

A macro line that fails says so out loud — red text across the screen and, for
most players, a voice line over it. It costs nothing else: a failed line stops
nothing below it, so the rest of the macro runs either way. What is left is the
noise, and now there is a way to turn it off for one line.

* **`/tmq`.** Put it above a line whose failure you already understand, and the
  client keeps that failure to itself. Both halves go — the text and the spoken
  error — for a fraction of a second, and everything comes back on its own.

  ```text
  #showtooltip Divine Steed
  /tmq
  /use item:140309
  /cast Divine Steed
  ```

  The toy rides off the global cooldown, so the spell casts whether or not the
  toy was ready. On the presses where it was not, nothing is said about it.
* **One command, not a pair.** A closing one would be read in the same frame as
  the opening one, while the error turns up later, off the event queue — so it
  would shut the window before there was anything to catch. Worse, an edit that
  removed the closing line would leave the client muted until the next reload.
  A window that closes itself has neither failure.
* The text is dropped before it is drawn rather than cleared afterwards, which
  is why nothing flickers. Clearing shows the message for a frame first.
* The spoken error has no per-message switch in the client, only a setting, so
  it is turned off and put back to **whatever it was**. Error speech you had
  already turned off stays off.
* You do not need it above a `/click` extra — those hold themselves back
  silently to begin with. `/tmq` is for the ordinary `/use` and `/cast` lines
  TinyMount has nothing to do with.

* A reload inside that fraction of a second used to leave the setting switched
  off until the next `/tmq`, because the timer that would have put it back went
  with the reload. It is now restored on the way out as well.

**A spell extra now carries its id rather than its name.** It used to be
resolved to a name first, which meant it could not be armed at all until the
client had that spell in its cache — so a spell extra could quietly fail to
exist for the first seconds of a session, and there was nothing to see when it
did. A secure button takes the id directly. Names were the ambiguous half
anyway: ranks, overridden spells and two spells sharing a name all resolve to
something, just not always the something you meant.

**An extra that was taken out of a macro went on firing.** The hidden button is
a frame, and nothing in the client destroys a frame — so a name that had once
worked kept working for the rest of the session, out of any other macro that
still spelled it, long after you had edited the line away. Editing a macro now
empties every button and lets the macros fill back in the ones they still ask
for. The frame is still there; it just does nothing, which from the outside is
the same thing.

**A toy extra that would not arm on a fresh character.** `C_ToyBox.IsToyUsable`
answers nothing at all until the client has filled the toy box in, and an
unanswered question disarms the button — by design, since a silent press is
cheaper than a red line. But nothing here was listening for the moment the
answer arrived, so on a character who had not opened the collection the extra
could stay quiet indefinitely and look broken. It now listens for
`TOYS_UPDATED`, and asks the client to fill the box at login rather than waiting
to be told.

**Two corrections to what was written here before.** A failed macro line does
**not** stop the client reading the lines below it — only `/stopmacro` and a
condition matching nothing end a macro early. The old wording claimed an extra
on cooldown would cost you the mount as well; it never did, it only made noise.
And the README now says plainly where an extra's button comes from: TinyMount
learns the name while repainting a slot, so it only ever reads macros that are
on a bar and carry a `/mnt` line. Copy a `/click` line into a macro that has
never met one, and it does nothing at all — silently, because clicking a button
that does not exist is not an error. That surprise has cost more than one
evening.

## 1.2.1 — Icon

* The addon list shows TinyMount's own icon instead of the default placeholder.
  Nothing else changed.

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

```text
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
