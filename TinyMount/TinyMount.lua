-- TinyMount/TinyMount.lua
-- Adds a /mnt slash command that summons a mount by id, and repaints any
-- action bar slot holding such a macro with the icon of the mount the currently
-- held modifiers select.
--
-- The point is macro length. A macro is capped at 255 characters and localised
-- mount names are long -- plenty run past thirty on their own, before a single
-- conditional -- so a /cast list of six of them does not fit. Numeric ids are
-- three to five digits and do, with room to spare.
--
-- Two halves, independent of each other:
--
--   * the command -- SecureCmdOptionParse does the whole macro conditional
--     syntax for us, so [mod:alt], [indoors], [combat] and the rest all work.
--     C_MountJournal.SummonByID is not protected, which is the only reason a
--     custom slash command can summon at all -- the same trick with a regular
--     spell would be blocked.
--
--   * the icon -- the client parses macro bodies itself to resolve #showtooltip
--     and knows nothing about /mnt, so the icon has to be painted by hand.
--     Both the Blizzard button family (ActionBarButtonTemplate, which Dominos
--     also builds from) and LibActionButton-1.0 (Bartender4) keep their texture
--     in a plain `.icon` field, so one repaint covers every bar addon.
--
-- While you are aboard something the command gets you off it instead, whatever
-- the conditions say, and the slot shows the exit icon. A mount and a vehicle
-- are two spellings of the same answer. One key both ways.
--
-- The slot also says when the answer is no. It greys where the mount will not
-- come out -- in combat, and in a room the game refuses to let you mount in --
-- the tooltip carries the client's own sentence for which of the two, and the
-- press goes quiet rather than earning the complaint. All three read the same
-- answer out of one place, UsableHere, so they cannot drift apart. What they
-- never do is guess: the verdict is the client's, never IsIndoors, for the
-- reason written over that function.
--
-- On top of the standard conditionals there is a shorthand, because a mount
-- macro is mostly made of them:
--
--   [m:cs]     ->  [mod:ctrl,mod:shift]     c = ctrl, s = shift, a = alt
--   [nm:a]     ->  [nomod:alt]
--   [nmnt,af]  ->  [nomounted,advflyable]   see CONDITIONS below
--   [sp:2,af]  ->  [spec:2,advflyable]      see ARG_CONDITIONS below
--
-- It expands before the string ever reaches SecureCmdOptionParse, and unknown
-- words are passed through, so full spellings still work and can be mixed in.
-- Modifier combinations expand to commas, i.e. AND -- the only spelling of a
-- combination the client is documented to take; [mod:ctrlshift] is folklore.
--
-- An off-GCD extra -- a toy, a cosmetic spell -- can ride along on a /click
-- line. It has to be spelled that way rather than as a /use; see the Effect
-- section for both reasons.
--
-- A toy that is nobody's passenger has a name of its own, ttoy<id>. It works in
-- any macro at all and is held back by nothing, combat included. See the Toy
-- section, which shares no state with the Effect one and is deliberately its
-- own thing rather than a setting on it.
--
-- For the lines this addon has nothing to do with -- a plain /use or /cast that
-- is going to fail -- /tmq mutes the client's complaint about the line under
-- it, text and voice both, for a fraction of a second, and puts everything back
-- on its own. See the Silence section.
--
-- A shapeshifted player needs one more line, and it cannot be helped from here.
-- SummonByID is not protected, but half of it quietly is: the client cancels
-- the caster's form for its own mount journal, which calls exactly the same
-- function on the same line (Blizzard_MountCollection.lua,
-- MountJournalMountButton_UseMount), and refuses to when an addon is the
-- caller. So a druid in cat form gets "You must be in humanoid form" from /mnt
-- while the very same mount still comes out of the journal. Nothing here can
-- close that gap -- CancelShapeshiftForm is protected outright, and cancelling
-- a form through the buff functions is blocked by name, precisely so that
-- insecure code cannot reach the [form] conditional. Only the macro can do it,
-- and /cancelform above the command is how, run securely under the keypress.
-- It needs no condition of its own -- out of a form it is a no-op and says
-- nothing, so it never draws the error that would stop the lines below it.
--
-- It goes at the top, above the /click lines as well as the mount, because
-- dropping the form is what lets the extra go off at all -- most of them cannot
-- be used shapeshifted either.
--
-- That has one consequence worth knowing about, and it is why the flight-form
-- rule in the Effect section is written the way it is. A form drops
-- synchronously: UPDATE_SHAPESHIFT_FORM arrives inside the /cancelform line,
-- before the next one is read, and ArmEffect runs in it. On the ground that is
-- exactly right, and the extra fires a line later. In the air it is not, since
-- leaving flight form does not put you on the ground -- you are still up there
-- and still pacified when the /click arrives.
--
-- Macro to put on the bar (no #showtooltip -- it does nothing here):
--   /cancelform
--   /click tmt140309
--   /mnt [m:cs]11111;[m:a,nmnt]22222;33333
--
-- Ids may be either spellIDs or mountIDs; GetMountFromSpell sorts it out. One
-- id is neither: 000 is a random one out of your favourites, which the client
-- spells as SummonByID(0) and puts its own button on in the mount journal.
--
--   /mnt [m:a]11111;000
--
-- The slot wears Blizzard's own art for it and the tooltip is theirs as well.

-- Blizzard's own vehicle-exit art, which is also what the dismount button
-- wears: one picture for getting off whatever you are on. The two states behind
-- it are told apart by the tooltip, not the icon.
local EXIT_ICON = 6656430

-- The client's own label on the Blizzard leave button, so it arrives localised,
-- falling back to the dismount binding -- the same sentence in fewer words -- on
-- a build that turns out not to carry it.
local EXIT_TEXT = LEAVE_VEHICLE or BINDING_NAME_DISMOUNT

-- The one id that is not an id. SummonByID takes zero to mean "a random one out
-- of my favourites" -- the same call behind Blizzard's own button in the mount
-- journal -- so it is the client's feature and not an invention here.
--
-- Every spelling of zero arrives the same way, since the digits in a macro go
-- through tonumber: 0, 00 and 000 are one number by the time anything here sees
-- them. 000 is the one worth writing and the one the README teaches, because
-- three digits line up with the ids around it and read as deliberate rather than
-- as something half-typed.
local RANDOM_ID = 0

-- Blizzard's Summon Random Favorite Mount. Held as a spell rather than as a
-- texture id so that the slot wears whatever picture they give it, and so the
-- tooltip can be theirs too, localised, without a word of it written here.
local RANDOM_SPELL = 150544

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

local MOD_LETTERS = { c = "ctrl", s = "shift", a = "alt" }

-- Whole-condition shorthands. Anything not listed here is passed through
-- untouched, so the full spelling keeps working alongside these.
local CONDITIONS = {
  mnt  = "mounted",    nmnt = "nomounted",
  f    = "flyable",    nf   = "noflyable",
  af   = "advflyable", naf  = "noadvflyable",
  fly  = "flying",     nfly = "noflying",
  sw   = "swimming",   nsw  = "noswimming",
  ["in"] = "indoors",  out  = "outdoors",
  c    = "combat",     nc   = "nocombat",
  r    = "resting",    nr   = "noresting",
}

-- Conditions that carry an argument, which is passed through untouched: sp:2
-- becomes spec:2, nsp:2 becomes nospec:2. Worth the six lines on a druid, where
-- four specialisations times advflyable/flyable/noflyable is a dozen branches
-- and spec: is written out in every one of them.
--
-- A word with a colon that is not listed here falls through to the plain-word
-- path and out the other side unchanged, so spec:2 itself still works, and so
-- does every conditional the client has that we have never heard of.
local ARG_CONDITIONS = {
  sp = "spec",
}

-- Rewrites the inside of every [...] group:
--   [m:cs]        -> [mod:ctrl,mod:shift]
--   [nmnt,af]     -> [nomounted,advflyable]
-- Modifiers are the ones carrying a colon; everything else is a plain word.
local function ExpandShorthand(args)
  return (args:gsub("%[(.-)%]", function(inner)
    local parts = {}

    for token in inner:gmatch("[^,]+") do
      local neg, letters = token:match("^(n?)m:([csa]+)$")
      if letters then
        for letter in letters:gmatch("[csa]") do
          parts[#parts + 1] = (neg == "n" and "nomod:" or "mod:") .. MOD_LETTERS[letter]
        end
      else
        -- n? matches the letter n and nothing else, so sp:2 keeps its s and
        -- nsp:2 gives up its n. An unlisted word leaves full nil and the token
        -- goes on to the plain-word path below, still whole.
        local no, word, arg = token:match("^(n?)(%a+):(.+)$")
        local full = word and ARG_CONDITIONS[word]
        if full then
          parts[#parts + 1] = (no == "n" and "no" or "") .. full .. ":" .. arg
        else
          parts[#parts + 1] = CONDITIONS[token] or token
        end
      end
    end

    return "[" .. table.concat(parts, ",") .. "]"
  end))
end

-- The one place a macro argument string turns into an id.
local function ParseArgs(args)
  local action = SecureCmdOptionParse(ExpandShorthand(args))
  return action and tonumber(action)
end

local function ResolveMountID(id)
  -- zero is not a mount and must not be looked up as one -- it is the word for
  -- a random favourite, and it has to reach SummonByID intact
  if id == RANDOM_ID then return RANDOM_ID end
  return C_MountJournal.GetMountFromSpell(id) or id
end

-- Whether the client will let this one out where you are standing, and -- for a
-- named mount -- its own localised sentence for why not. The one place that
-- question is asked, because three things hang off the answer and must not
-- disagree: the icon greys, the tooltip quotes the reason, and the command
-- declines to ask out loud.
--
-- Nil is the third answer and means the question could not be put at all, on a
-- build carrying neither call. Nil greys nothing and blocks nothing; every
-- caller treats only a flat false as a refusal, which is what makes an
-- unanswerable question harmless.
--
-- Asked of the client rather than worked out here, and that is the whole point.
-- "Indoors" and "cannot mount here" are different questions: a garrison, a cave
-- and half the buildings in a capital are all indoors and all let you mount, so
-- IsIndoors or the [indoors] conditional would grey the slot several times an
-- evening for nothing -- and a slot that lies about being dead is worse than one
-- that never greys at all.
local function UsableHere(mountID)
  -- A random favourite names no mount, and the mount call will not answer for
  -- it: GetMountUsabilityByID(0) returns nothing at all, measured. Blizzard's
  -- own spell for it does answer, and answers about the place -- false in a
  -- building that refuses mounts, true outside it, measured in both.
  --
  -- Worth knowing that this one is a proxy. It is spell usability, not the rule
  -- SummonByID itself follows, and the two could disagree somewhere neither was
  -- tried. If /mnt 000 ever goes quiet where it plainly should work, this branch
  -- is the only thing in the file that could have done it. No reason comes back
  -- either -- the spell's own tooltip carries that.
  if mountID == RANDOM_ID then
    if not C_Spell.IsSpellUsable then return nil end
    return (C_Spell.IsSpellUsable(RANDOM_SPELL))
  end

  if not C_MountJournal.GetMountUsabilityByID then return nil end
  return C_MountJournal.GetMountUsabilityByID(mountID, true)
end

-- The one question asked before anything else: are you aboard something, and
-- what gets you off it. Whatever comes back drives all three faces of the slot
-- -- the press, the icon and the tooltip -- so they cannot drift apart.
--
-- Both answers work in a fight, which is when getting off matters most.
-- Dismount and VehicleExit are the unprotected corner of an otherwise closed
-- API and an addon may simply call them; their next-door neighbour
-- CancelShapeshiftForm is protected, and the file header is where that costs
-- something.
--
-- A flight path is deliberately not here. The client locks the action bars for
-- the whole flight, so the slot cannot be pressed and nothing this returned
-- would ever run.
--
-- The vehicle is asked before the mount because the driver of a two-seater is
-- both at once, and VehicleExit puts them on the ground either way.
local function ExitAction()
  if CanExitVehicle() then return VehicleExit, EXIT_TEXT end
  if IsMounted() then return Dismount, BINDING_NAME_DISMOUNT end
end

SLASH_TINYMOUNT1 = "/mnt"
SlashCmdList["TINYMOUNT"] = function(msg)
  -- aboard something: the same key gets off, conditions are not consulted at all
  local exit = ExitAction()
  if exit then
    exit()
    return
  end

  -- No mount can be summoned in combat, and asking anyway earns the client's
  -- complaint -- which would be the one thing the slot still had to say in a
  -- fight, right after greying itself out to say the opposite. It says nothing
  -- instead, and the extras above are held back the same way.
  if InCombatLockdown() then return end

  -- `if id` and not `if id > 0`: zero is a legitimate answer here, and the one
  -- the /mnt 000 shorthand for a random favourite arrives as. Lua counts it as
  -- true, which is the only reason this line needs no special case -- and the
  -- only reason it must not grow one.
  local id = ParseArgs(msg)
  if not id then return end

  local mountID = ResolveMountID(id)

  -- The same silence the combat guard above buys, for the same reason and at no
  -- greater cost: if the client has already said this one cannot come out here,
  -- asking it anyway changes nothing except that it says so out loud -- and the
  -- slot has been grey for a while now, saying it quietly. Nothing is lost by
  -- not asking; the summon was never going to happen.
  if UsableHere(mountID) == false then return end

  C_MountJournal.SummonByID(mountID)
end

--------------------------------------------------------------------------------
-- Silence
--------------------------------------------------------------------------------

-- A macro line that is going to fail draws the client's own complaint: text in
-- UIErrorsFrame and, for most players, a voice line on top of it. The line
-- costs nothing else -- a failure stops nothing below it, only /stopmacro and a
-- condition that matches nothing end a macro early -- so what is left to object
-- to is the noise, and /tmq is how a macro says it does not want to hear it.
--
--   /tmq
--   /use item:140309
--   /cast <spell>
--
-- The toy is off the global cooldown and the spell below it goes off either
-- way; on the press where the toy is not ready, nothing is said about it.
--
-- One command and not a pair. A closing one on the next line would be read in
-- the same frame the opening one was, while UI_ERROR_MESSAGE arrives later, off
-- the event queue -- so the window would already be shut by the time the error
-- turned up. And a missing closing line, left behind by an edit, would mute the
-- client until the next reload. A window that closes itself has neither
-- failure, and needs nothing written after the line it covers.
--
-- Two halves, because the client keeps them apart:
--
--   * the text goes through UIErrorsFrame:AddMessage, so it can be dropped
--     before it is ever drawn -- the frame never sees it and nothing flickers.
--     Clearing the frame afterwards is the other way round: the message is
--     already on screen and shows for a frame before it goes, which is exactly
--     what it looks like.
--
--   * the voice has no per-message switch at all. Only the cvar, held down for
--     a fraction of a second and put back to whatever it was, so a player who
--     had turned it off keeps it off.
local SILENCE_WINDOW = 0.3

-- The namespaced pair rather than the bare globals: those are deprecated
-- aliases, and they have been going away a function at a time for several
-- expansions now.
local GetCVar, SetCVar = C_CVar.GetCVar, C_CVar.SetCVar

local silenceUntil, savedSpeech = 0, nil

local function RestoreSpeech()
  -- a second /tmq inside the window pushed the end back; come back then
  if GetTime() < silenceUntil then
    C_Timer.After(silenceUntil - GetTime(), RestoreSpeech)
    return
  end
  if savedSpeech then
    SetCVar("Sound_EnableErrorSpeech", savedSpeech)
    savedSpeech = nil
  end
end

SLASH_TINYMOUNTQUIET1 = "/tmq"
SlashCmdList["TINYMOUNTQUIET"] = function()
  if not savedSpeech then
    savedSpeech = GetCVar("Sound_EnableErrorSpeech")
    SetCVar("Sound_EnableErrorSpeech", "0")
    C_Timer.After(SILENCE_WINDOW, RestoreSpeech)
  end
  silenceUntil = GetTime() + SILENCE_WINDOW
end

-- A reload inside the window would take the timer with it and leave the setting
-- switched off until the next /tmq, so it is put back on the way out as well.
-- The event fires for a reload and a logout alike, and both are early enough:
-- cvars are written after it.
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
  if savedSpeech then SetCVar("Sound_EnableErrorSpeech", savedSpeech) end
end)

-- Everything inside the window goes, not only cooldowns: the line was written
-- by hand, so the silence was asked for on purpose and for a known reason.
local OrigAddMessage = UIErrorsFrame.AddMessage
UIErrorsFrame.AddMessage = function(self, msg, ...)
  if GetTime() < silenceUntil then return end
  return OrigAddMessage(self, msg, ...)
end

--------------------------------------------------------------------------------
-- Effect
--------------------------------------------------------------------------------

-- A macro may carry an extra alongside the mount -- an off-GCD toy, a cosmetic
-- spell -- on a /click line naming one of the buttons built here:
--
--   /click tmt140309
--   /mnt [m:cs]11111;22222
--
-- Two separate walls make that the only spelling available.
--
-- The addon cannot fire the extra itself. Everything that casts a spell or uses
-- an item -- CastSpellByID, UseToy, RunMacro -- is protected, and appears
-- nowhere in the client outside SECURE_ACTIONS in SecureTemplates.lua. The check
-- is on the caller, not the callee: a macro reaches those through the client's
-- own secure command list under a keypress, an addon never does. SummonByID
-- being open is the exception this whole file stands on, and it does not
-- generalise. A secure button is the way round it -- the player's own keypress
-- drives the click, so no addon code is on the stack when the effect goes off.
--
-- Nor can the extra go on a /use or /cast line of the macro. The client resolves
-- those itself, marks the slot a spell action -- GetActionInfo starts reporting
-- subType "spell", the proc glow turns on -- and hands the icon to C by way of
-- C_ActionBar.RegisterActionUIButton. From there the texture is repainted
-- natively, out of reach of the Update hook below, and Restyle loses the race
-- every time. /click resolves to nothing, so the macro stays inert as far as the
-- client is concerned and the icon stays ours.
--
-- The button name carries the entire configuration, which is why the addon has
-- no settings file: tm<kind><id>, kind being t for toy, s for spell, i for
-- item.

-- One letter per kind, and one spelling of a name: tm, the letter, the id.
-- Lower case throughout, because a frame name is a key in _G and a second
-- spelling would simply be a second button, missing and silent.
local EFFECT_KIND = { t = "toy", s = "spell", i = "item" }

local function ParseEffect(name)
  local letter, id = name:match("^tm(%a)(%d+)$")
  return letter and EFFECT_KIND[letter], id
end

-- Attribute value per kind. Two of the three handlers pass the digits straight
-- through: the toy handler tonumber()s what it is given, and the spell one
-- takes an id as readily as a name -- measured in game.
--
-- The spell handler used to resolve the id to a name first, on the belief that
-- it ended up in CastSpellByName and that an id would arrive there as a spell
-- nobody has. It does not, and the resolving cost more than it bought: a name
-- is ambiguous where an id never is (ranks, overrides, two spells sharing a
-- name), and it could not be produced at all until the client had the spell in
-- its cache -- which is why a spell extra could quietly fail to exist for the
-- first seconds of a session.
local EFFECT_ATTR = {
  toy   = function(id) return id end,
  spell = function(id) return id end,
  -- a bare number would be read as an inventory slot -- /use 13 is a trinket
  item  = function(id) return "item:" .. id end,
}

-- macroID -> the button names its /click lines ask for, or false when it has
-- none. A macro may carry several: each /click is a line of its own and the
-- client runs them in turn, so a macro shared across the account can name one
-- extra per character and let the unusable ones stay quiet.
local macroEffect = {}

local effects = {}

-- Riding off the global cooldown is the whole point of an extra, so a duration
-- at or under the global is not a cooldown worth disarming a button for.
local GCD = 1.5

-- Whether this character has the extra at all. A macro is shared across the
-- account, so a paladin's flavour spell rides along into a death knight's copy
-- of the same macro -- where the id still resolves, because the spell exists in
-- the database whether or not you know it. Left armed it would answer every
-- press with a complaint. Disarmed it is simply one more state the button is
-- quietly not in, and one macro can carry a line per character.
local function Have(kind, id)
  id = tonumber(id)

  if kind == "spell" then return IsPlayerSpell(id) end

  -- The toy box is account-wide, so owning a class toy says nothing about being
  -- able to use it: a death knight sees the paladin's, greyed out. PlayerHasToy
  -- answers the account half and IsToyUsable the character half -- with nil,
  -- not false, while the box is still filling in. An unanswered question
  -- disarms; the next event asks again.
  if kind == "toy" then
    return PlayerHasToy(id) and C_ToyBox.IsToyUsable(id) == true
  end

  return C_Item.GetItemCount(id) > 0
end

local function Ready(kind, id)
  local start, duration
  if kind == "spell" then
    local cd = C_Spell.GetSpellCooldown(tonumber(id))
    if not cd then return false end
    start, duration = cd.startTime, cd.duration
  else
    -- a toy is an item, and its cooldown is the item's
    start, duration = C_Item.GetItemCooldown(tonumber(id))
  end
  if not start then return false end

  return start == 0 or (duration or 0) <= GCD
end

-- Of the states that should hold the extra back, the ones no macro conditional
-- can express are applied by hand -- cooldown, and being aboard something,
-- where the press has one job and no room for a passenger.
--
-- Being pacified is deliberately not one of them, and that is a decision, not
-- an oversight. Flying pacifies you and a pacified player may use nothing at
-- all, so an extra fired from a druid's flight form draws "you can't use that
-- ability while pacified". It costs nothing but the noise: a /click that fails
-- this way does not stop the client reading the macro, and the /mnt below it
-- still summons -- measured in flight form, and worth knowing, because a /use
-- or a /cast that fails does stop it.
--
-- That was disarmed here for a while, by form id -- the only thing that could
-- see it. IsFlying() is false in flight form, C_Item.IsUsableItem is false for
-- a toy always, even in town in no form, and C_Item.GetItemSpell into
-- C_Spell.IsSpellUsable answers the same in every form. All four measured in
-- game; the form id was the only one that drew the line in the right place.
--
-- It came back out anyway, because the line is in the wrong place to begin
-- with. A form drops the instant /cancelform is read, while the client stays
-- pacified a moment longer, so disarming on the form also silences the extra
-- through the whole of that moment -- and that moment is where a working spell
-- sits on every ordinary press. Trading a loss on every press for a loss on a
-- rare one is a bad trade. The flight-form press draws its error and costs its
-- mount; everything else fires.
--
-- By hand means out of combat, and nothing is lost by that: the driver in
-- EnsureEffect has already emptied the button by the time a fight starts, and
-- it goes on working through a lockdown when SetAttribute cannot.
--
-- Every unanswered question disarms, and that is the whole safety margin here.
-- What it buys is silence, and only silence: a line that fails stops nothing
-- below it, so a toy on cooldown costs the noise of the complaint and not the
-- mount. Measured, and worth writing down, because the opposite is easy to
-- assume -- only /stopmacro and a condition that matches nothing end a macro
-- early. The extras are still kept above the mount rather than below it, for a
-- different reason: using one mid-summon cancels the cast.
--
-- name -> the value last written to that button, false for none. The cooldown
-- events at the bottom of the file arrive in bursts and mostly say the same
-- thing twice, and SetAttribute on a secure button is not free -- it walks the
-- attribute machinery whether or not the value differs -- so a write that
-- changes nothing is not made. The one place the attribute is cleared behind
-- this function's back is the UPDATE_MACROS handler, and that wipes this.
local armed = {}

local function ArmEffect(name)
  local btn = effects[name]
  if not btn or InCombatLockdown() then return end

  local kind, id = ParseEffect(name)
  if not kind then return end

  local usable = not ExitAction() and Have(kind, id) and Ready(kind, id)
  -- false rather than nil, so that disarmed is a value the table can hold and
  -- is told apart from never asked
  local value = usable and EFFECT_ATTR[kind](id) or false
  if armed[name] == value then return end

  armed[name] = value
  btn:SetAttribute(kind, value or nil)
end

-- Built on demand and out of combat: CreateFrame and SetAttribute are both
-- barred once the lockdown is up. Restyle asks again on every event it handles,
-- PLAYER_REGEN_ENABLED among them, so a macro edited mid-fight gets its button
-- as soon as the fight ends.
local function EnsureEffect(name)
  if effects[name] or InCombatLockdown() then return end

  local kind = ParseEffect(name)
  if not kind then return end

  local btn = CreateFrame("Button", name, nil, "SecureActionButtonTemplate")
  btn:Hide()
  btn:RegisterForClicks("AnyUp")
  -- /click clicks with down = false, and SecureActionButton_OnClick throws that
  -- away unless the button agrees it fires on key up. Left to itself the button
  -- asks the ActionButtonUseKeyDown cvar, which most players have on, and then
  -- nothing happens at all -- no error, just silence. The attribute outranks the
  -- cvar (SecureTemplates.lua, SecureActionButton_ShouldUseOnKeyDown).
  btn:SetAttribute("useOnKeyDown", false)
  -- Mounted and in combat both have macro conditionals behind them, so the
  -- client's own state driver can carry them -- and unlike SetAttribute it goes
  -- on working through a lockdown. An empty type is a button that does nothing
  -- whatsoever: no cast, no red line, no "not ready yet" out of the speakers.
  RegisterAttributeDriver(btn, "type", "[mounted][combat];" .. kind)
  effects[name] = btn
  ArmEffect(name)
end

--------------------------------------------------------------------------------
-- Toy
--------------------------------------------------------------------------------

-- A toy on its own, in any macro at all, with nothing above it deciding whether
-- it may go off:
--
--   /click ttoy140309
--
-- Everything in the Effect section above exists to serve a mount: an extra
-- there is held back wherever the mount is, because the press has one job and a
-- passenger that fires when the mount does not is noise. This is the other
-- thing entirely -- a toy because you want the toy -- and the two are kept
-- apart rather than made into one configurable thing, because every state
-- either of them cares about is a state the other deliberately ignores.
--
-- Hence the plainer name: ttoy, then the id. No kind letter, because there is
-- only one kind. A spell or an item wants the checks that were just thrown
-- away -- a spell you have not learned and an item you are out of both have
-- something to say, whereas a toy is either in the box or it is not.
--
-- What "no checks" buys is worth being precise about, because it is not
-- laziness. The button is written once and never touched again: type and toy
-- both set at creation, no attribute driver, no re-arming, no event of its own.
-- That is what makes it work in combat at all. SetAttribute is barred under a
-- lockdown, so anything filtered through it freezes on whatever it held when
-- the fight started -- and the failure that produces is the bad one: a toy that
-- came off cooldown mid-fight would stay dead until the fight ended, silently.
-- A button nobody touches has no such state to be wrong about.
--
-- The cost is the client's own complaint when the toy is on cooldown or is not
-- yours, and that is all it is: a /click that fails stops nothing below it. Put
-- /tmq above the line if the noise is unwelcome.
--
-- Conditionals are not our business here either. /click is the client's command
-- and it parses its own [...] before ever looking the name up, so
--
--   /click [nostealth] ttoy140309
--
-- is decided before any of this runs. Full spellings only -- the shorthand in
-- the Command section is expanded by /mnt and read by nothing else.
local MacroConsts = Constants and Constants.MacroConsts
local MAX_ACCOUNT_MACROS = (MacroConsts and MacroConsts.MAX_ACCOUNT_MACROS) or 120

-- name -> button, and name -> the id last written to it. The second table is
-- what makes a repeat scan free: SetAttribute walks the attribute machinery
-- whether or not the value differs, and the scan runs whole every time.
local toys, toyArmed = {}, {}

local function EnsureToy(name)
  -- CreateFrame and SetAttribute are both barred once the lockdown is up, so a
  -- macro written mid-fight gets its button when the fight ends instead --
  -- ScanToysAfterCombat is what comes back for it.
  if InCombatLockdown() then return end

  local id = name:match("^ttoy(%d+)$")
  if not id then return end

  local btn = toys[name]
  if not btn then
    btn = CreateFrame("Button", name, nil, "SecureActionButtonTemplate")
    btn:Hide()
    btn:RegisterForClicks("AnyUp")
    -- the same trap as in EnsureEffect: /click clicks with down = false, and
    -- without this the button asks a cvar most players have on and then does
    -- nothing at all, silently
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type", "toy")
    toys[name] = btn
  end

  if toyArmed[name] ~= id then
    toyArmed[name] = id
    -- the handler tonumber()s what it is given, so the digits go straight
    -- through (SecureTemplates.lua, SECURE_ACTIONS.toy)
    btn:SetAttribute("toy", id)
  end
end

-- Every macro the character has, account and character both, whether or not it
-- sits on a bar and whether or not it mentions /mnt. Read straight out of
-- GetMacroBody rather than through the Icon section's cache, because none of
-- this has anything to do with an icon and sharing the cache would only tie the
-- two together again.
--
-- Lazy match, so a conditional in front of the name is fine:
-- /click [combat]ttoy1
--
-- Lazy also means the name is found anywhere on the line, so a /click naming
-- somebody else's button that happens to end in ttoy<digits> would be read as
-- ours. Four letters rather than two is most of what makes that not worth
-- guarding against -- the same looseness is in the tm pattern above, where it
-- is deliberate.
local function ScanToyMacro(macroID)
  local body = GetMacroBody(macroID)
  if not body then return end

  for name in body:gmatch("/click[^\n]-(ttoy%d+)") do EnsureToy(name) end
end

-- A name edited out of every macro has to stop firing, and the frame cannot be
-- destroyed -- nothing in the client destroys a frame. Emptying it is the same
-- thing from the outside. Every button is emptied and the scan that follows
-- fills back in only the names still spelled somewhere.
--
-- In combat it cannot be done at all, since SetAttribute is barred, so it is
-- remembered instead. Skipping it outright would be the quiet kind of wrong: a
-- /click line deleted during a fight would go on firing afterwards, with the
-- macro in front of you no longer mentioning it.
local toysStale = false

local function DisarmToys()
  if InCombatLockdown() then
    toysStale = true
    return
  end

  toysStale = false
  wipe(toyArmed)
  for _, btn in pairs(toys) do btn:SetAttribute("toy", nil) end
end

-- 150 GetMacroBody calls at worst, on the events in SCAN_TOYS below and nowhere
-- else -- never on a button update, never on a modifier press.
--
-- Character macros do not follow the account ones: they start at a fixed
-- offset, so the second loop counts from MAX_ACCOUNT_MACROS rather than from
-- however many account macros happen to exist (Blizzard_MacroUI.lua,
-- MacroFrameMixin:GetMacroDataIndex).
local function ScanToys()
  if InCombatLockdown() then return end

  -- an edit the lockdown turned away, finished now
  if toysStale then DisarmToys() end

  local account, character = GetNumMacros()
  for i = 1, account or 0 do ScanToyMacro(i) end
  for i = 1, character or 0 do ScanToyMacro(MAX_ACCOUNT_MACROS + i) end
end

-- Leaving combat is emphatically not a rare event -- it is every pack in a
-- dungeon, dozens of times a run -- so it is not in SCAN_TOYS, and a full scan
-- on it would be thousands of GetMacroBody calls to find nothing new.
--
-- A fight can leave exactly one thing unfinished, and toysStale is the whole of
-- it: an edit that arrived under the lockdown, where SetAttribute was barred.
-- A new button cannot be outstanding, because the only way a macro gains a
-- /click line is by being saved, and saving one draws UPDATE_MACROS -- which
-- sets that same flag when it lands in a fight.
local function ScanToysAfterCombat()
  if toysStale then ScanToys() end
end

--------------------------------------------------------------------------------
-- Icon
--------------------------------------------------------------------------------

-- macroID -> argument string of its /mnt line, or false when it has none.
-- GetMacroBody is far too costly to run on every button update.
local macroArgs = {}

local function ArgsFor(macroID)
  if macroArgs[macroID] == nil then
    local body = GetMacroBody(macroID)
    macroArgs[macroID] = body and body:match("/mnt%s+([^\n]+)") or false
    -- lazy, so a conditional in front of the name is fine: /click [m:a]tmt1
    local names = {}
    for name in (body or ""):gmatch("/click[^\n]-(tm%a%d+)") do
      names[#names + 1] = name
    end
    macroEffect[macroID] = #names > 0 and names or false
  end
  return macroArgs[macroID] or nil
end

-- LibActionButton keeps the slot in _state_action and parks .action at 0, so
-- its fields have to be read first or every LAB button looks like slot zero.
--
-- This rule is spelled out a second time, inline, at the top of OnButtonUpdate,
-- where the call this function would cost is worth avoiding. The two have to
-- agree: if a bar library ever renames these fields, both change or neither
-- works.
local function SlotOf(btn)
  if btn._state_type then
    return btn._state_type == "action" and tonumber(btn._state_action) or nil
  end
  return btn.action
end

-- slot -> the id of one of our macros sitting in it, false for a slot holding
-- anything else. This is the hot path of the whole addon and it has to cost a
-- table read, because of who calls it and how often.
--
-- The Update hook in Attach is the reason. ActionBarButtonEventsFrame answers
-- one ACTIONBAR_SLOT_CHANGED by updating every button it knows, not the one
-- whose slot changed, and an item on a bar draws one of those every time its
-- stack moves in the bags. Measured over a dungeon: 21240 firings, and 45571
-- button updates behind them, every one of which asks this question and is
-- told no. A GetActionInfo behind it would be forty-five thousand calls into
-- the client to hear the same answer.
--
-- What makes it cacheable is the direction. Which slot a button is showing is
-- not safe to remember: a bar addon repoints that under a keypress, through a
-- secure state driver, with no event to us at all, so a cache would go stale
-- silently and freeze the icon on whatever the previous page held. What is in
-- a slot is the opposite -- it changes only through ACTIONBAR_SLOT_CHANGED and
-- UPDATE_MACROS, both of which arrive here, and paging does not touch it.
local slotMacro = {}

local function MacroForSlot(slot)
  local macroID = slotMacro[slot]
  if macroID == nil then
    local kind, id = GetActionInfo(slot)
    macroID = (kind == "macro" and ArgsFor(id) and id) or false
    slotMacro[slot] = macroID
  end
  return macroID or nil
end

-- The macro sitting in this button's slot, if it is one of ours.
local function MacroOf(btn)
  local slot = SlotOf(btn)
  if not slot then return nil end

  local macroID = MacroForSlot(slot)
  if not macroID then return nil end

  return macroID, ArgsFor(macroID)
end

-- What the macro resolves to right now, for the current modifiers and state.
-- Nil when no branch matched and the macro has no default -- an entirely
-- legitimate outcome for something like "/mnt [nomounted]12345".
-- Returns icon, usable, spellID, reason, random. Icon first because the caller
-- that runs most often wants only the first two; `random` tells the tooltip
-- which of two calls will draw the thing spellID names.
--
-- `usable` and `reason` come from UsableHere, which is where the reasoning about
-- them lives. Worth recording here only that isUsable out of GetMountInfoByID
-- looks as though it would answer the same thing for free, since that call is
-- made on this very line -- and does not. Measured in game: it stays true
-- indoors, where the mount plainly will not come out.
local function Resolve(args)
  local id = ParseArgs(args)
  if not id then return nil end

  -- A random favourite is Blizzard's own spell all the way down: the picture,
  -- the tooltip and the answer to whether it can be used here all come from it.
  -- No reason string, though -- that route does not carry one, so a grey random
  -- slot says why in the spell's tooltip rather than in a line of our own.
  if id == RANDOM_ID then
    return C_Spell.GetSpellTexture(RANDOM_SPELL), UsableHere(RANDOM_ID),
           RANDOM_SPELL, nil, true
  end

  local mountID = ResolveMountID(id)
  local _, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
  local usable, why = UsableHere(mountID)

  return icon, usable, spellID, why
end

local watched = {}

-- Both families draw an action slot through GameTooltip:SetAction -- Blizzard in
-- ActionBarActionButtonMixin:SetTooltip, LibActionButton in Action.SetTooltip.
-- Hooking the tooltip itself rather than the buttons catches every repaint,
-- including the periodic one GameTooltip_OnUpdate drives (GameTooltip.lua:457).
-- That repaint is what used to flip the tooltip back to the macro name a moment
-- after it appeared. The owner is already set by whoever called us.
local function OnTooltipSetAction(tooltip, slot)
  if tooltip:IsForbidden() then return end

  local macroID = MacroForSlot(slot)
  if not macroID then return end

  -- no nil check: MacroForSlot only ever names a macro it has already seen a
  -- /mnt line in, so this cannot come back empty
  local args = ArgsFor(macroID)

  local _, exitText = ExitAction()
  if exitText then
    tooltip:SetText(exitText)
    tooltip:Show()
    return
  end

  local _, usable, spellID, why, random = Resolve(args)
  if not spellID then return end

  -- A random favourite is a spell and not a mount, so it is drawn as one: the
  -- mount tooltip wants a mount behind the id and has none to work with here.
  if random then
    tooltip:SetSpellByID(spellID)
  else
    tooltip:SetMountBySpellID(spellID)
  end
  -- The client's own sentence for why this one will not come out here, under
  -- its own tooltip. It arrives localised, so nothing about it is written here.
  -- A refusal without a sentence behind it says nothing rather than something
  -- invented: that is a random favourite, whose route carries no reason, and
  -- whose own tooltip is already on screen above this line.
  if usable == false and why then
    tooltip:AddLine(why, 1, 0.1, 0.1, true)
  end
  tooltip:Show()
end

hooksecurefunc(GameTooltip, "SetAction", OnTooltipSetAction)

local function Restyle(btn)
  local macroID, args = MacroOf(btn)
  if not args then return end

  -- asked for again every time: the first attempt may have fallen in combat.
  -- Read out of the table rather than defaulted to an empty one -- this runs
  -- for every watched button on every modifier press, and a macro without an
  -- extra is the common case.
  local names = macroEffect[macroID]
  if names then
    for _, name in ipairs(names) do
      EnsureEffect(name)
      ArmEffect(name)
    end
  end

  local exit = ExitAction()

  local icon, usable
  if exit then
    -- getting off is never refused for where you are standing
    icon, usable = EXIT_ICON, true
  else
    icon, usable = Resolve(args)
  end
  if not icon then
    -- nothing matched: fall back to the icon picked in the macro editor, so a
    -- slot that cannot fire right now stops advertising the last mount shown
    local _, macroIcon = GetMacroInfo(macroID)
    icon = macroIcon
  end
  if not icon then return end

  btn.icon:SetTexture(icon)
  btn.icon:Show()
  -- Two reasons the slot goes grey, and they are not the same kind of reason.
  -- Combat is absolute and known for certain right here. Where you are standing
  -- is the client's call, quoted rather than guessed at -- see UsableHere.
  -- Strictly false, because nil is a question that went unanswered and a slot
  -- greyed on an unanswered question would be a slot telling lies.
  --
  -- Aboard something it stays lit either way: neither way off is protected, the
  -- key works in a fight, and no room refuses to let you dismount in it. Grey or
  -- lit the tooltip still answers, and for a named mount it carries the client's
  -- own sentence for the refusal.
  btn.icon:SetDesaturated(not exit and (InCombatLockdown() or usable == false))

  -- state changed under a resting cursor: redraw through the button so the
  -- SetAction hook above gets its turn
  if GameTooltip:GetOwner() == btn and btn.SetTooltip then
    btn:SetTooltip()
  end
end

-- The guard in front of Restyle on the one path that is not ours to throttle.
-- The client answers a single ACTIONBAR_SLOT_CHANGED by updating every button
-- it knows rather than the one whose slot changed, so this is entered some
-- forty-five thousand times a dungeon to say "not mine". Restyle saying it
-- takes four nested calls; this takes one.
--
-- So the slot is read flat here rather than through SlotOf -- the same rule
-- written out a second time on purpose, and the comment on SlotOf says so from
-- its end as well -- and the answer is one table read. Only a slot known not to
-- hold one of our macros is dropped: an unknown slot falls through to Restyle,
-- which asks the client and remembers, so a bar paging to a slot nothing has
-- looked at yet still paints.
local function OnButtonUpdate(btn)
  local slot
  if btn._state_type then
    if btn._state_type == "action" then slot = tonumber(btn._state_action) end
  else
    slot = btn.action
  end
  if slot and slotMacro[slot] ~= false then Restyle(btn) end
end

local function RestyleAll()
  for btn in pairs(watched) do Restyle(btn) end
end

local function Attach(btn)
  if watched[btn] then return end
  watched[btn] = true
  -- Blizzard family: Update is where the texture gets written
  if btn.Update then hooksecurefunc(btn, "Update", OnButtonUpdate) end
  Restyle(btn)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:RegisterEvent("UPDATE_MACROS")

-- Everything a macro conditional can key off. The icon has to be repainted
-- whenever the answer could have changed, not only when a modifier is held:
-- [mod:*]
f:RegisterEvent("MODIFIER_STATE_CHANGED")
-- [mounted] / [flyable] / [advflyable] / [indoors] / [swimming]
--
-- [swimming] is the one state in the whole language with no event behind it at
-- all, in this list or anywhere else, so a slot that branches on it is repainted
-- by whatever happens to fire next rather than by entering the water. In
-- practice that is the modifier press, which is also the moment anyone is
-- looking at the slot, so it has never been worth more than this paragraph.
--
-- The zone events below carry a second reading now: whether the client will let
-- this mount out where you are standing, which Resolve asks it directly. Walking
-- into a building announces itself as ZONE_CHANGED_INDOORS, so the slot greys on
-- the doorstep rather than on the next keypress.
f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_INDOORS")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Walking into a building is not an event. ZONE_CHANGED_INDOORS sounds like it
-- would be and is not: measured, walking in and out of a building that refuses
-- mounts left the slot on its previous colour until the next modifier press.
-- Most buildings never fire it.
--
-- What the client does announce is that the set of things you can use has
-- changed, which is the same news said differently -- it is how Blizzard's own
-- buttons know to grey themselves. The catch is that it says it constantly:
-- power, auras and half a fight drive it too.
--
-- So it is not answered with a repaint. It is answered with one question, and
-- a repaint only when the answer is not the one from last time. The question is
-- put to the random-favourite spell because that reading is about the place and
-- not about any one mount, so a single call covers every slot on the bars.
f:RegisterEvent("SPELL_UPDATE_USABLE")
local lastUsableHere
-- [combat]
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
-- [form] / [stance]
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
-- [resting]
f:RegisterEvent("PLAYER_UPDATE_RESTING")
-- [spec:N], and the [sp:N] shorthand for it. Filtered to the player for the
-- same reason the vehicle events below are: the event carries a unit, so
-- registered plainly it arrives for every member of the group and each one
-- costs a full repaint pass. Measured at one or two firings over a dungeon
-- either way, so this buys nothing in practice -- it is here because the
-- unfiltered spelling is a trap two lines above a comment warning about it.
f:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
-- Nothing in the conditional language reaches a vehicle seat either, so
-- ExitAction is re-asked off whatever announces one. The two unit events are
-- filtered to the player: they fire for every party member in a vehicle
-- otherwise, and a repaint per passenger is a repaint wasted.
f:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
f:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
f:RegisterEvent("VEHICLE_UPDATE")
-- Nothing in the conditional language expresses a cooldown, so the extra's
-- readiness is re-read off whatever announces one.
f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
f:RegisterEvent("BAG_UPDATE_COOLDOWN")
-- an item extra runs out, or the last one is picked back up
f:RegisterEvent("BAG_UPDATE_DELAYED")
-- C_ToyBox.IsToyUsable answers nil until the client has filled the toy box in,
-- and an unanswered question disarms. Nothing else here announces the moment it
-- becomes answerable, which on a freshly logged-in character is some way after
-- PLAYER_ENTERING_WORLD -- long enough to look like a toy extra that simply
-- does not work.
f:RegisterEvent("TOYS_UPDATED")

-- The four above say something about an extra and nothing at all about an icon:
-- no conditional in the language reads a cooldown, a bag or the toy box. They
-- are also the loudest events here by a wide margin -- SPELL_UPDATE_COOLDOWN
-- fires on every cast and every global -- so answering them with the repaint
-- pass at the bottom of the handler was the largest piece of work this file
-- did: measured over a dungeon at some four thousand firings, each sweeping a
-- hundred-odd action slots to ask what they held, in order to repaint nothing.
-- Around four hundred thousand questions to the client, all of them idle.
--
-- They get the short answer instead. Re-arming reads `effects`, not the buttons
-- -- nought to a handful of entries, and an empty loop for a player who uses no
-- extras at all. Note what is given up by returning early: creating a button
-- that does not exist yet, which lives in EnsureEffect on the full pass. Every
-- way a new macro can appear runs one of those -- ACTIONBAR_SLOT_CHANGED for a
-- slot, UPDATE_MACROS for an edit, PLAYER_LOGIN for a session, and
-- PLAYER_REGEN_ENABLED for anything that happened while the two of them were
-- barred from acting.
--
-- The other half of the same measurement is why PLAYER_UPDATE_RESTING and
-- PLAYER_SPECIALIZATION_CHANGED appear above. [resting] and [spec] were being
-- repainted by this storm rather than by an event of their own, quietly and by
-- accident, and would have gone stale the moment it stopped.
local ARM_ONLY = {
  SPELL_UPDATE_COOLDOWN = true,
  BAG_UPDATE_COOLDOWN   = true,
  BAG_UPDATE_DELAYED    = true,
  TOYS_UPDATED          = true,
}

-- The only moments the set of ttoy buttons can change, and the whole of what the
-- Toy section costs. None of these arrive on a button update or a keypress, and
-- a ttoy button appears nowhere else in this handler -- not in ARM_ONLY above,
-- which is the loudest thing in the file, and not in the repaint pass below.
--
--   PLAYER_LOGIN           a session
--   PLAYER_ENTERING_WORLD  the same session, asked a second time
--   UPDATE_MACROS          an edit
--
-- PLAYER_ENTERING_WORLD is belt and braces, for the same reason it wipes the
-- slot cache further down. Whether GetNumMacros can answer at PLAYER_LOGIN is
-- the client's business and not worth betting on: if it cannot, the failure is
-- a toy that silently does nothing until the next time a macro is saved.
--
-- PLAYER_REGEN_ENABLED is deliberately not in here -- see ScanToysAfterCombat,
-- which is what answers it and why the full scan would be waste.
local SCAN_TOYS = {
  PLAYER_LOGIN          = true,
  PLAYER_ENTERING_WORLD = true,
  UPDATE_MACROS         = true,
}

f:SetScript("OnEvent", function(self, event, arg1)
  if ARM_ONLY[event] then
    for name in pairs(effects) do ArmEffect(name) end
    return
  end

  -- see the registration: loud event, one cheap question, and a repaint only on
  -- an answer that has actually changed
  if event == "SPELL_UPDATE_USABLE" then
    local now
    if C_Spell.IsSpellUsable then now = (C_Spell.IsSpellUsable(RANDOM_SPELL)) end
    if now == lastUsableHere then return end
    lastUsableHere = now
  end

  -- ACTIONBAR_SLOT_CHANGED names the slot that changed, and almost none of them
  -- are ours. An item sitting on a bar draws one of these every time its stack
  -- moves in the bags, so a run that loots a lot fires thousands: measured at
  -- 9476 in a single dungeon, against 62 modifier presses in the same run, and
  -- the bag events that caused them line up one to one.
  --
  -- One question about the slot answers all of them, in place of a hundred
  -- questions about the buttons. A slot that has stopped holding our macro
  -- needs no answer at all -- Restyle only ever paints a slot it recognises and
  -- leaves every other one as its own bar addon drew it, so there is nothing to
  -- undo.
  --
  -- What this event announces is also exactly what MacroForSlot remembers, so
  -- it is the thing that has to make it forget. Slot zero is the client saying
  -- it changed everything: the cache goes wholesale and the full pass at the
  -- bottom fills it back in.
  if event == "ACTIONBAR_SLOT_CHANGED" then
    if arg1 and arg1 ~= 0 then
      slotMacro[arg1] = nil
      if not MacroForSlot(arg1) then return end

      for btn in pairs(watched) do
        if SlotOf(btn) == arg1 then Restyle(btn) end
      end
      return
    end
    wipe(slotMacro)
  end

  if event == "UPDATE_MACROS" then
    wipe(macroArgs)
    wipe(macroEffect)
    -- a body edited into or out of carrying a /mnt line changes the answer for
    -- every slot holding it, and the event does not say which macro moved
    wipe(slotMacro)

    -- Every button is emptied here and filled back in by the Restyle pass at
    -- the bottom, which reads the macros afresh. A name edited out of every
    -- macro is simply never filled back in: the frame cannot be destroyed --
    -- nothing in the client destroys a frame -- but it can be left doing
    -- nothing, which is the same thing from the outside.
    --
    -- In combat this is skipped rather than deferred. SetAttribute is barred
    -- there, and a macro edited mid-fight is rare enough that the next edit
    -- out of combat can pick it up.
    if not InCombatLockdown() then
      -- cleared behind ArmEffect's back, so what it remembers writing is no
      -- longer what the button carries. In combat neither happens, and what it
      -- remembers is still true.
      wipe(armed)
      for name, btn in pairs(effects) do
        local kind = ParseEffect(name)
        if kind then btn:SetAttribute(kind, nil) end
      end
    end

    -- the same emptying for the ttoy buttons, which the scan below fills back in
    DisarmToys()
  end

  -- Belt and braces around the one way the cache could be wrong: a slot asked
  -- about before the bars are populated answers false, and false is remembered.
  -- The client does announce the fill, but it is cheaper to distrust that once
  -- per loading screen than to debug a slot that never paints again.
  if event == "PLAYER_ENTERING_WORLD" then wipe(slotMacro) end

  if event == "PLAYER_LOGIN" then
    -- Blizzard template registers itself here, and so does every Dominos button
    ActionBarButtonEventsFrame:ForEachFrame(Attach)
    -- Dominos creates its bars when a profile loads, after PLAYER_LOGIN
    hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, btn)
      Attach(btn)
    end)

    -- Asks the client to fill the toy box in now rather than whenever someone
    -- happens to open the collection; it answers with TOYS_UPDATED. Guarded
    -- because it is not in every build -- and it is only ever an optimisation:
    -- TOYS_UPDATED arrives on its own once the client gets round to it, which
    -- is what actually arms a toy extra.
    if C_ToyBox.ForceToyBoxUpdate then
      C_ToyBox.ForceToyBoxUpdate()
    end

    -- Bartender4 and anything else on LibActionButton-1.0. Asked for at login
    -- rather than on file load, because the library may load after us.
    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if LAB then
      for btn in pairs(LAB:GetAllButtons()) do Attach(btn) end
      LAB.RegisterCallback(f, "OnButtonCreated", function(_, btn) Attach(btn) end)
      LAB.RegisterCallback(f, "OnButtonUpdate",  function(_, btn) OnButtonUpdate(btn) end)
    end
  end

  -- After the UPDATE_MACROS block above, not before it: that one empties every
  -- ttoy button and the scan is what fills them back in.
  if SCAN_TOYS[event] then
    ScanToys()
  elseif event == "PLAYER_REGEN_ENABLED" then
    ScanToysAfterCombat()
  end

  RestyleAll()

  -- Entering combat is painted twice, a frame apart, and this is the only
  -- event that needs it. The bar addon answers the same moment with its own
  -- usable pass -- ACTIONBAR_UPDATE_USABLE arrives right behind
  -- PLAYER_REGEN_DISABLED -- and that pass writes the icon's saturation
  -- without going through Update, so it lands after us and undoes the greying.
  -- Hovering the slot afterwards put it back, which is what gave this away:
  -- that does go through Update, so we came last for once.
  --
  -- Leaving combat looks right only by luck. There we and the bar addon are
  -- writing the same answer, so it does not matter who writes it second.
  --
  -- A dozen or two firings over a dungeon, against forty-five thousand button
  -- updates, so the second pass costs nothing. Deferring the first pass instead
  -- of adding a second one would be wrong: UPDATE_SHAPESHIFT_FORM has to stay
  -- synchronous (see the header), and one rule for all events is easier to keep
  -- than two.
  if event == "PLAYER_REGEN_DISABLED" then
    C_Timer.After(0, RestyleAll)
  end
end)
