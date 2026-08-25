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
-- Macro to put on the bar (no #showtooltip -- it does nothing here):
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

  local id = ParseArgs(msg)
  if id then
    C_MountJournal.SummonByID(ResolveMountID(id))
  end
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

f:SetScript("OnEvent", function(self, event)
  if event == "UPDATE_MACROS" then
    wipe(macroArgs)
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
