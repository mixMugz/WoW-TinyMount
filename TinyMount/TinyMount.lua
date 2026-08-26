-- TinyMount/TinyMount.lua
-- Adds a /mnt slash command that summons a mount by id, and repaints any
-- action bar slot holding such a macro with the icon of the mount the currently
-- held modifiers select.
--
-- The point is macro length. A macro is capped at 255 *bytes* and Cyrillic
-- spends two per letter, so a /cast list of six localised mount names does not
-- fit. Numeric ids do, with room to spare.
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
-- While mounted the command always dismounts instead, whatever the conditions
-- say, and the slot shows the dismount icon. One key both ways.
--
-- On top of the standard conditionals there is a shorthand, because a mount
-- macro is mostly made of them:
--
--   [m:cs]     ->  [mod:ctrl,mod:shift]     c = ctrl, s = shift, a = alt
--   [nm:a]     ->  [nomod:alt]
--   [nmnt,af]  ->  [nomounted,advflyable]   see CONDITIONS below
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
-- Macro to put on the bar (no #showtooltip -- it does nothing here):
--   /click tmt140309
--   /mnt [m:cs]11111;[m:a,nmnt]22222;33333
--
-- Ids may be either spellIDs or mountIDs; GetMountFromSpell sorts it out.

local DISMOUNT_ICON = 6656430

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
        parts[#parts + 1] = CONDITIONS[token] or token
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

SLASH_TINYMOUNT1 = "/mnt"
SlashCmdList["TINYMOUNT"] = function(msg)
  -- mounted: the same key gets off, conditions are not consulted at all
  if IsMounted() then
    Dismount()
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

-- Attribute value per kind, or nil while the id cannot be turned into one yet.
local EFFECT_ATTR = {
  -- the toy handler tonumber()s what it gets, so the digits may stand as they are
  toy   = function(id) return id end,
  -- the spell handler does not: it ends up in CastSpellByName, which wants a
  -- name. An id arrives there as a spell nobody has, and casts nothing at all --
  -- no error, the same silence a missing button gives. Resolved here rather than
  -- written into the macro so that ids stay the one thing a macro ever names.
  spell = function(id)
    local info = C_Spell.GetSpellInfo(tonumber(id))
    return info and info.name
  end,
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

-- Of the three states that should hold the extra back, cooldown is the only one
-- no macro conditional can express, so it is the only one applied by hand --
-- and by hand means out of combat. Nothing is lost by that: the driver in
-- EnsureEffect has already emptied the button by the time a fight starts.
--
-- Every unanswered question disarms, and that is the whole safety margin here.
-- An extra that draws an error does not merely make a noise: the client stops
-- reading the macro at the line that failed, so a toy on cooldown would take the
-- /mnt line below it down with it and cost you the mount. The extras cannot be
-- moved below the mount to get out of the way either -- using one mid-summon
-- cancels the cast. So a press that quietly does nothing is the cheap outcome
-- and an error is the expensive one, and every guess is resolved that way.
local function ArmEffect(name)
  local btn = effects[name]
  if not btn or InCombatLockdown() then return end

  local kind, id = ParseEffect(name)
  if not kind then return end

  local usable = Have(kind, id) and Ready(kind, id)
  btn:SetAttribute(kind, usable and EFFECT_ATTR[kind](id) or nil)
end

-- Built on demand and out of combat: CreateFrame and SetAttribute are both
-- barred once the lockdown is up. Restyle asks again on every event it handles,
-- PLAYER_REGEN_ENABLED among them, so a macro edited mid-fight gets its button
-- as soon as the fight ends.
local function EnsureEffect(name)
  if effects[name] or InCombatLockdown() then return end

  local kind, id = ParseEffect(name)
  local attr = kind and EFFECT_ATTR[kind]
  if not attr then return end

  -- A spell the cache has not seen yet resolves to nothing. Returning without
  -- filling effects[name] leaves the next Restyle to try again, which is the
  -- same retry the combat check above rides on.
  if not attr(id) then return end

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

  if IsMounted() then
    tooltip:SetText(BINDING_NAME_DISMOUNT)
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

  -- asked for again every time: the first attempt may have fallen in combat
  for _, name in ipairs(macroEffect[macroID] or {}) do
    EnsureEffect(name)
    ArmEffect(name)
  end

  local icon
  if IsMounted() then
    icon = DISMOUNT_ICON
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
  -- looking live and doing nothing. Mounted it stays lit: Dismount is not
  -- protected and the key works in a fight, which is when it is wanted most.
  -- Either way the tooltip still answers.
  btn.icon:SetDesaturated(InCombatLockdown() and not IsMounted())

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
-- Nothing in the conditional language expresses a cooldown, so the extra's
-- readiness is re-read off whatever announces one.
f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
f:RegisterEvent("BAG_UPDATE_COOLDOWN")
-- an item extra runs out, or the last one is picked back up
f:RegisterEvent("BAG_UPDATE_DELAYED")

f:SetScript("OnEvent", function(self, event)
  if event == "UPDATE_MACROS" then
    wipe(macroArgs)
    wipe(macroEffect)
  end

  if event == "PLAYER_LOGIN" then
    -- Blizzard template registers itself here, and so does every Dominos button
    ActionBarButtonEventsFrame:ForEachFrame(Attach)
    -- Dominos creates its bars when a profile loads, after PLAYER_LOGIN
    hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, btn)
      Attach(btn)
    end)

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
