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
-- Ids may be either spellIDs or mountIDs; GetMountFromSpell sorts it out.

-- Blizzard's own vehicle-exit art, which is also what the dismount button
-- wears: one picture for getting off whatever you are on. The two states behind
-- it are told apart by the tooltip, not the icon.
local EXIT_ICON = 6656430

-- The client's own label on the Blizzard leave button, so it arrives localised,
-- falling back to the dismount binding -- the same sentence in fewer words -- on
-- a build that turns out not to carry it.
local EXIT_TEXT = LEAVE_VEHICLE or BINDING_NAME_DISMOUNT

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
  return C_MountJournal.GetMountFromSpell(id) or id
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

  local id = ParseArgs(msg)
  if id then
    C_MountJournal.SummonByID(ResolveMountID(id))
  end
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
local function ArmEffect(name)
  local btn = effects[name]
  if not btn or InCombatLockdown() then return end

  local kind, id = ParseEffect(name)
  if not kind then return end

  local usable = not ExitAction() and Have(kind, id) and Ready(kind, id)
  btn:SetAttribute(kind, usable and EFFECT_ATTR[kind](id) or nil)
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
local function SlotOf(btn)
  if btn._state_type then
    return btn._state_type == "action" and tonumber(btn._state_action) or nil
  end
  return btn.action
end

-- The macro sitting in this button's slot, if it is one of ours.
local function MacroOf(btn)
  local slot = SlotOf(btn)
  if not slot then return nil end

  local kind, macroID = GetActionInfo(slot)
  if kind ~= "macro" then return nil end

  local args = ArgsFor(macroID)
  if not args then return nil end

  return macroID, args
end

-- What the macro resolves to right now, for the current modifiers and state.
-- Nil when no branch matched and the macro has no default -- an entirely
-- legitimate outcome for something like "/mnt [nomounted]12345".
local function Resolve(args)
  local id = ParseArgs(args)
  if not id then return nil end

  local _, spellID, icon = C_MountJournal.GetMountInfoByID(ResolveMountID(id))
  return icon, spellID
end

local watched = {}

-- Both families draw an action slot through GameTooltip:SetAction -- Blizzard in
-- ActionBarActionButtonMixin:SetTooltip, LibActionButton in Action.SetTooltip.
-- Hooking the tooltip itself rather than the buttons catches every repaint,
-- including the periodic one GameTooltip_OnUpdate drives (GameTooltip.lua:457).
-- That repaint is what used to flip the tooltip back to the macro name a moment
-- after it appeared. The owner is already set by whoever called us.
hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
  if tooltip:IsForbidden() then return end

  local kind, macroID = GetActionInfo(slot)
  if kind ~= "macro" then return end

  local args = ArgsFor(macroID)
  if not args then return end

  local _, exitText = ExitAction()
  if exitText then
    tooltip:SetText(exitText)
    tooltip:Show()
    return
  end

  local _, spellID = Resolve(args)
  if not spellID then return end

  tooltip:SetMountBySpellID(spellID)
  tooltip:Show()
end)

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

  local icon
  if exit then
    icon = EXIT_ICON
  else
    icon = Resolve(args)
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
  -- No mount can be summoned in combat, so the slot says as much rather than
  -- looking live and doing nothing. Aboard something it stays lit: none of the
  -- two ways off is protected and the key works in a fight, which is when it
  -- is wanted most. Either way the tooltip still answers.
  btn.icon:SetDesaturated(InCombatLockdown() and not exit)

  -- state changed under a resting cursor: redraw through the button so the
  -- SetAction hook above gets its turn
  if GameTooltip:GetOwner() == btn and btn.SetTooltip then
    btn:SetTooltip()
  end
end

local function Attach(btn)
  if watched[btn] then return end
  watched[btn] = true
  -- Blizzard family: Update is where the texture gets written
  if btn.Update then hooksecurefunc(btn, "Update", Restyle) end
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
f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_INDOORS")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
-- [combat]
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
-- [form] / [stance]
f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
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

f:SetScript("OnEvent", function(self, event)
  if event == "UPDATE_MACROS" then
    wipe(macroArgs)
    wipe(macroEffect)

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
      for name, btn in pairs(effects) do
        local kind = ParseEffect(name)
        if kind then btn:SetAttribute(kind, nil) end
      end
    end
  end

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
      LAB.RegisterCallback(f, "OnButtonUpdate",  function(_, btn) Restyle(btn) end)
    end
  end

  for btn in pairs(watched) do Restyle(btn) end
end)
