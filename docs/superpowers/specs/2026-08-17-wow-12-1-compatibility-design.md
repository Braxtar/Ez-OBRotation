# WoW 12.1 Compatibility Release Design

## Goal

Publish Ez-OBRotation v3.3 for World of Warcraft Retail 12.1 while fixing the smallest set of confirmed compatibility defects and avoiding unrelated combat-path refactoring.

## Evidence and target

- Target client: Retail 12.1.0, Interface `120100`.
- Current Blizzard UI snapshot checked: 12.1.0.69323, dated 2026-08-17.
- The 12.1 aura refactor does not affect Ez-OBRotation because the add-on does not read aura APIs.
- `C_AssistedCombat.GetRotationSpells`, `C_ActionBar.FindSpellActionButtons`, `C_Spell.GetSpellName`, `AssistedCombatRotationFrame`, and `AssistedCombatHighlightFrame` remain present in the checked 12.1 UI source.
- The bare global `HasAction` exists only through Blizzard's optional deprecated Action Bar compatibility layer; `C_ActionBar.HasAction` is the supported API.
- Blizzard bars 5, 6, and 7 use action pages 13, 14, and 15, corresponding to slots 145-156, 157-168, and 169-180. There is no default Blizzard `MultiBar8` in the checked 12.1 Action Bar UI.

## Approved implementation

1. Update `Ez-OBRotation.toc` from Interface `120005` to `120100` and version `3.2` to `3.3`.
2. Replace all four bare `HasAction` calls with `C_ActionBar.HasAction` so the add-on works when deprecated fallbacks are disabled.
3. Correct `GetBindCommand` mappings:
   - `145-156` -> `MULTIACTIONBAR5BUTTON1-12`
   - `157-168` -> `MULTIACTIONBAR6BUTTON1-12`
   - `169-180` -> `MULTIACTIONBAR7BUTTON1-12`
4. Remove the nonexistent Blizzard `MultiBar8Button` prefix from both Assisted Combat button scans and remove its slot mapping.
5. Preserve all other Blizzard, Bartender4, ElvUI, glow, settings, saved-variable, and polling behavior.
6. Keep process documentation and test tooling out of the distributable add-on archive.

## Runtime flow

On login, the add-on creates its settings UI and begins its existing Assisted Combat button detection. When the key cache is built or a suggested spell must be resolved, it queries `C_ActionBar.HasAction`, reads the action, maps the returned slot to the correct binding command, and renders the abbreviated key on the active Assisted Combat button. Binding, slot, shapeshift, and bonus-bar events continue to invalidate the cache as before.

## Failure handling and boundaries

- Unsupported or unmapped action slots continue to return no binding instead of raising an error.
- Missing fonts continue to fall back to Blizzard's default font.
- The release does not replace the 30 ms polling loop, rewrite glow ownership, or change the ElvUI fallback because those changes would widen runtime and taint risk beyond a compatibility release.
- Static and harness validation can establish syntax, API use, mapping behavior, and package contents. It cannot prove every in-combat interaction with every third-party action-bar configuration; the release claim is scoped accordingly.

## Validation

- Run a Lua 5.1-compatible syntax check on `Ez-OBRotation.lua`.
- Run a behavioral harness with bare `HasAction` absent and `C_ActionBar.HasAction` available.
- Verify binding resolution for the main bar and Blizzard bars 1-7, including slots 145, 156, 157, 168, 169, and 180.
- Confirm no `MultiBar8Button` or bare `HasAction(` production references remain.
- Run `git diff --check` and repository integrity checks.
- Build or emulate the release archive and confirm its root folder, TOC metadata, Lua/fonts/image payload, and exclusion of development-only files.
- Publish GitHub release `v3.3`, wait for the existing deployment workflow to succeed, then verify that CurseForge and Wago expose the 12.1 release.

## Release text

Use exactly this release message, without additional prose:

`Updated for 12.1 team`
