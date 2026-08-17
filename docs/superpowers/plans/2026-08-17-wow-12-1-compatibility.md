# WoW 12.1 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Ez-OBRotation v3.3 for Retail 12.1 with supported Action Bar APIs, correct bars 5-7 binding resolution, and verified packaging.

**Architecture:** Keep the single-file add-on architecture and its existing Assisted Combat detection loop. Add a Python/Lupa behavioral harness that loads the real Lua file in a stubbed WoW environment, make only the confirmed compatibility edits, and use BigWigs Packager's `.pkgmeta` support to keep development files out of the release archive.

**Tech Stack:** World of Warcraft Lua, TOC metadata, Python 3.12 `unittest`, Lupa 2.8, BigWigsMods/packager v2, GitHub Actions, CurseForge, and Wago.

## Global Constraints

- Target Retail Interface is exactly `120100`.
- Release version and tag are exactly `3.3` and `v3.3`.
- User-facing release text is exactly `Updated for 12.1 team` with no additional prose.
- Preserve existing Blizzard, Bartender4, ElvUI, glow, settings, saved-variable, and polling behavior except for the confirmed API and slot-map fixes.
- Do not replace the 30 ms ticker, rewrite glow ownership, or adopt restricted aura/cooldown inputs.
- Development documentation, tests, and Python dependencies must not appear in the packaged add-on.
- Do not publish if any test, package check, GitHub deployment, CurseForge check, or Wago check fails.

---

### Task 1: Supported Action Bar API and 12.1 slot mappings

**Files:**
- Create: `requirements-dev.txt`
- Create: `tests/test_wow_121_compatibility.py`
- Modify: `Ez-OBRotation.lua:55-65`
- Modify: `Ez-OBRotation.lua:77,90,118,148`
- Modify: `Ez-OBRotation.lua:421-478`

**Interfaces:**
- Consumes: WoW global environment with `C_ActionBar.HasAction`, `C_ActionBar.FindSpellActionButtons`, Blizzard action slots, and global action-button frame names.
- Produces: `GetBindCommand(slot)` mappings for Blizzard bars 1-7 and Assisted Combat scans that ignore nonexistent `MultiBar8Button` frames.

- [ ] **Step 1: Add the development dependency pin**

Create `requirements-dev.txt` with:

```text
lupa==2.8
```

- [ ] **Step 2: Write the failing behavioral tests**

Create `tests/test_wow_121_compatibility.py` with:

```python
from pathlib import Path
import unittest

from lupa import LuaError, LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
ADDON_SOURCE = ROOT / "Ez-OBRotation.lua"

BOOTSTRAP = r"""
SlashCmdList = {}
__addon_frame = nil
__ticker = nil
__has_action_calls = 0

C_ActionBar = {
    HasAction = function(slot)
        __has_action_calls = __has_action_calls + 1
        return false
    end,
    FindSpellActionButtons = function(spellID)
        return {}
    end,
}

C_AssistedCombat = {
    GetRotationSpells = function()
        return {}
    end,
}

C_Spell = {
    GetSpellName = function(spellID)
        return nil
    end,
}

C_Timer = {
    NewTicker = function(interval, callback)
        __ticker = callback
        return { Cancel = function() end }
    end,
}

function wipe(target)
    for key in pairs(target) do
        target[key] = nil
    end
end

function CreateFrame()
    if __addon_frame == nil then
        local frame = {}
        function frame:RegisterEvent() end
        function frame:SetScript(scriptName, callback)
            if scriptName == "OnEvent" then
                self.__on_event = callback
            end
        end
        __addon_frame = frame
        return frame
    end
    return {}
end

function __find_upvalue(fn, wantedName)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if name == nil then
            return nil
        end
        if name == wantedName then
            return value
        end
    end
    return nil
end
"""


class AddonRuntime:
    def __init__(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(BOOTSTRAP)
        self.lua.execute(ADDON_SOURCE.read_text(encoding="utf-8"))
        self.globals = self.lua.globals()
        self.frame = self.globals["__addon_frame"]

    def upvalue(self, function, name):
        value = self.globals["__find_upvalue"](function, name)
        if value is None:
            raise AssertionError(f"Lua upvalue {name!r} was not found")
        return value


class Wow121CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.runtime = AddonRuntime()
        self.find_key_for_spell = self.runtime.upvalue(
            self.runtime.frame.StartDetective,
            "FindKeyForSpell",
        )

    def test_cache_builds_without_deprecated_has_action_global(self):
        build_hotkey_cache = self.runtime.upvalue(
            self.find_key_for_spell,
            "BuildHotkeyCache",
        )
        self.runtime.globals.HasAction = None

        try:
            build_hotkey_cache()
        except LuaError as error:
            self.fail(f"cache required deprecated HasAction global: {error}")

        self.assertEqual(180, self.runtime.globals["__has_action_calls"])

    def test_binding_commands_match_retail_12_1_action_pages(self):
        get_bind_command = self.runtime.upvalue(
            self.find_key_for_spell,
            "GetBindCommand",
        )
        expected = {
            1: "ACTIONBUTTON1",
            12: "ACTIONBUTTON12",
            25: "MULTIACTIONBAR3BUTTON1",
            36: "MULTIACTIONBAR3BUTTON12",
            37: "MULTIACTIONBAR4BUTTON1",
            48: "MULTIACTIONBAR4BUTTON12",
            49: "MULTIACTIONBAR2BUTTON1",
            60: "MULTIACTIONBAR2BUTTON12",
            61: "MULTIACTIONBAR1BUTTON1",
            72: "MULTIACTIONBAR1BUTTON12",
            145: "MULTIACTIONBAR5BUTTON1",
            156: "MULTIACTIONBAR5BUTTON12",
            157: "MULTIACTIONBAR6BUTTON1",
            168: "MULTIACTIONBAR6BUTTON12",
            169: "MULTIACTIONBAR7BUTTON1",
            180: "MULTIACTIONBAR7BUTTON12",
        }
        for slot, command in expected.items():
            with self.subTest(slot=slot):
                self.assertEqual(command, get_bind_command(slot))

        for unmapped_slot in (0, 13, 24, 73, 120, 144, 181):
            with self.subTest(unmapped_slot=unmapped_slot):
                self.assertIsNone(get_bind_command(unmapped_slot))

    def test_nonexistent_multibar8_frame_is_not_scanned(self):
        self.runtime.lua.execute(
            r"""
            __multibar8_visibility_checks = 0
            MultiBar8Button1 = {
                IsVisible = function()
                    __multibar8_visibility_checks = __multibar8_visibility_checks + 1
                    return false
                end,
            }
            """
        )

        self.runtime.frame.StartDetective(self.runtime.frame)
        self.runtime.globals["__ticker"]()

        self.assertEqual(
            0,
            self.runtime.globals["__multibar8_visibility_checks"],
        )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Create the isolated test environment**

Run:

```powershell
py -3.12 -m venv ..\ezobr-test-venv
..\ezobr-test-venv\Scripts\python.exe -m pip install -r requirements-dev.txt
```

Expected: Lupa 2.8 installs successfully outside the repository.

- [ ] **Step 4: Run the tests and verify the expected failures**

Run:

```powershell
..\ezobr-test-venv\Scripts\python.exe -m unittest tests.test_wow_121_compatibility -v
```

Expected: three failures caused by the bare `HasAction` call, obsolete bars 5-8 slot ranges, and `MultiBar8Button` scanning.

- [ ] **Step 5: Implement the minimum Lua compatibility patch**

In `GetBindCommand`, replace the last four mappings with:

```lua
    if slot >= 145 and slot <= 156 then return "MULTIACTIONBAR5BUTTON"..(slot-144) end
    if slot >= 157 and slot <= 168 then return "MULTIACTIONBAR6BUTTON"..(slot-156) end
    if slot >= 169 and slot <= 180 then return "MULTIACTIONBAR7BUTTON"..(slot-168) end
```

Replace each production call of:

```lua
HasAction(slot)
```

or:

```lua
HasAction(btn.action)
```

with the corresponding supported call:

```lua
C_ActionBar.HasAction(slot)
```

or:

```lua
C_ActionBar.HasAction(btn.action)
```

Remove this entry from both `barPrefixes` tables inside `StartDetective`:

```lua
            "MultiBar8Button",
```

- [ ] **Step 6: Run the focused tests and verify green**

Run:

```powershell
..\ezobr-test-venv\Scripts\python.exe -m unittest tests.test_wow_121_compatibility -v
```

Expected: 3 tests pass with no errors.

- [ ] **Step 7: Commit the runtime compatibility task**

Run:

```powershell
git add Ez-OBRotation.lua requirements-dev.txt tests/test_wow_121_compatibility.py
git diff --cached --check
git commit -m "Fix WoW 12.1 action bar compatibility"
```

Expected: one commit containing only the Lua compatibility changes and their tests.

---

### Task 2: v3.3 metadata and release-package boundary

**Files:**
- Modify: `tests/test_wow_121_compatibility.py`
- Modify: `Ez-OBRotation.toc:1-5`
- Create: `.pkgmeta`

**Interfaces:**
- Consumes: WoW TOC loader contract and BigWigs Packager v2 `.pkgmeta` `ignore` directive.
- Produces: Retail 12.1/v3.3 metadata and a distributable tree containing only end-user add-on files.

- [ ] **Step 1: Add the failing TOC metadata test**

Add below `ADDON_SOURCE`:

```python
ADDON_TOC = ROOT / "Ez-OBRotation.toc"
```

Add this test class before the `if __name__ == "__main__"` block:

```python
class TocMetadataTests(unittest.TestCase):
    def test_retail_12_1_release_metadata(self):
        metadata = {}
        for line in ADDON_TOC.read_text(encoding="utf-8-sig").splitlines():
            if line.startswith("## ") and ":" in line:
                key, value = line[3:].split(":", 1)
                metadata[key.strip()] = value.strip()

        self.assertEqual("120100", metadata.get("Interface"))
        self.assertEqual("3.3", metadata.get("Version"))
```

- [ ] **Step 2: Run the metadata test and verify red**

Run:

```powershell
..\ezobr-test-venv\Scripts\python.exe -m unittest tests.test_wow_121_compatibility.TocMetadataTests -v
```

Expected: failure showing current values `120005` and `3.2` instead of `120100` and `3.3`.

- [ ] **Step 3: Update the TOC metadata**

Change the metadata to:

```text
## Interface: 120100
## Title: Ez-OB Rotation
## Notes: One Button Rotation with keybinds
## Author: Braxtar
## Version: 3.3
```

Keep the existing icon, saved-variable, Wago, CurseForge, blank-line, and Lua file entries unchanged.

- [ ] **Step 4: Run the metadata test and full suite**

Run:

```powershell
..\ezobr-test-venv\Scripts\python.exe -m unittest tests.test_wow_121_compatibility.TocMetadataTests -v
..\ezobr-test-venv\Scripts\python.exe -m unittest discover -s tests -v
```

Expected: the metadata test passes, then all 4 tests pass.

- [ ] **Step 5: Establish the package-content failure before adding exclusions**

Ensure the exact workflow packager is available in a sibling tools directory and run a no-upload, no-zip package build:

```powershell
if (-not (Test-Path -LiteralPath '..\bigwigs-packager-v2\.git')) {
    git clone --depth 1 --branch v2 https://github.com/BigWigsMods/packager.git ..\bigwigs-packager-v2
}
$packagerHead = git -C ..\bigwigs-packager-v2 rev-parse HEAD
if ($packagerHead -ne '6d50adb6e8517eefef63f4afb16a6518166a6b28') { throw "Unexpected BigWigs Packager v2 revision: $packagerHead" }
& 'C:\Program Files\Git\bin\bash.exe' -lc '../bigwigs-packager-v2/release.sh -d -z -r /c/Users/Vincent/Documents/Codex/2026-08-17/https-www-curseforge-com-wow-addons/work/ezobr-package-red'
```

Inspect:

```powershell
Get-ChildItem -Recurse -File ..\ezobr-package-red | Select-Object -ExpandProperty FullName
```

Expected: the package tree contains `docs`, `tests`, or `requirements-dev.txt`, demonstrating the missing release boundary.

- [ ] **Step 6: Add the package exclusions**

Create `.pkgmeta` with:

```yaml
ignore:
  - docs
  - tests
  - requirements-dev.txt
```

- [ ] **Step 7: Rebuild and verify the package boundary**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -lc '../bigwigs-packager-v2/release.sh -d -z -r /c/Users/Vincent/Documents/Codex/2026-08-17/https-www-curseforge-com-wow-addons/work/ezobr-package-green'
$packageRoot = Get-ChildItem -Directory ..\ezobr-package-green | Where-Object Name -eq 'Ez-OBRotation'
Get-ChildItem -Recurse -File -LiteralPath $packageRoot.FullName | ForEach-Object { $_.FullName.Substring($packageRoot.FullName.Length + 1) }
```

Expected package files:

```text
CHANGELOG.md
Ez-OBRotation.jpg
Ez-OBRotation.lua
Ez-OBRotation.toc
Fonts\Luciole-Bold.ttf
Fonts\Luciole-Regular.ttf
LICENSE
README.md
```

The package must not contain `.github`, `.pkgmeta`, `docs`, `tests`, or `requirements-dev.txt`.

- [ ] **Step 8: Commit the release metadata task**

Run:

```powershell
git add .pkgmeta Ez-OBRotation.toc tests/test_wow_121_compatibility.py
git diff --cached --check
git commit -m "Prepare Ez-OBRotation v3.3"
```

Expected: one commit containing the metadata, package exclusions, and metadata regression test.

---

### Task 3: Final verification and publication

**Files:**
- Verify: all tracked files changed since `origin/main`
- Remote write: `Braxtar/Ez-OBRotation` pull request, `main`, tag `v3.3`, GitHub release, CurseForge project `1443163`, and Wago project `kGryylKy`

**Interfaces:**
- Consumes: green local tests/package, authenticated GitHub CLI account `Braxtar`, and existing `deploy.yml` release workflow.
- Produces: merged main branch, GitHub release `v3.3`, successful deployment workflow, and visible 12.1 files on CurseForge and Wago.

- [ ] **Step 1: Run the complete pre-publication verification**

Run:

```powershell
..\ezobr-test-venv\Scripts\python.exe -m unittest discover -s tests -v
git diff --check origin/main...HEAD
git fsck --full --no-dangling
$legacyHasAction = git grep -n -E '(^|[^[:alnum:]_.])HasAction\(' -- '*.lua'
if ($LASTEXITCODE -eq 0) { throw "Deprecated HasAction call remains: $legacyHasAction" }
if ($LASTEXITCODE -ne 1) { throw "HasAction scan failed" }
$multiBar8 = git grep -n 'MultiBar8Button' -- '*.lua'
if ($LASTEXITCODE -eq 0) { throw "MultiBar8Button reference remains: $multiBar8" }
if ($LASTEXITCODE -ne 1) { throw "MultiBar8Button scan failed" }
git status -sb
git diff --stat origin/main...HEAD
```

Expected: 4 tests pass; diff and repository checks succeed; both grep commands return no matches; only the intended committed files differ from `origin/main`; the working tree is clean.

- [ ] **Step 2: Push the implementation branch and open the publication PR**

Run:

```powershell
git push -u origin agent/wow-12-1-compatibility
gh pr create --repo Braxtar/Ez-OBRotation --base main --head agent/wow-12-1-compatibility --title "Updated for 12.1 team" --body "Updated for 12.1 team"
```

Expected: a new pull request URL targeting `main`.

- [ ] **Step 3: Merge the verified change with the requested public message**

Run:

```powershell
gh pr merge --repo Braxtar/Ez-OBRotation --squash --delete-branch --subject "Updated for 12.1 team" --body ""
git switch main
git pull --ff-only origin main
```

Expected: the PR is merged, remote feature branch is deleted, and local `main` matches `origin/main`.

- [ ] **Step 4: Reverify the exact merged tree**

Run:

```powershell
..\ezobr-test-venv\Scripts\python.exe -m unittest discover -s tests -v
git diff --check HEAD^
git status -sb
```

Expected: 4 tests pass and `main` is clean and aligned with `origin/main`.

- [ ] **Step 5: Publish the GitHub release**

Run:

```powershell
gh release create v3.3 --repo Braxtar/Ez-OBRotation --target main --title "v3.3" --notes "Updated for 12.1 team"
```

Expected: a public GitHub release URL for `v3.3` whose body is exactly `Updated for 12.1 team`.

- [ ] **Step 6: Wait for the automated deployment**

Run:

```powershell
$run = gh run list --repo Braxtar/Ez-OBRotation --workflow deploy.yml --event release --limit 1 --json databaseId,headBranch,status,conclusion,url | ConvertFrom-Json
if ($run.headBranch -ne 'v3.3') { throw "Latest deploy run is not v3.3" }
gh run watch $run.databaseId --repo Braxtar/Ez-OBRotation --exit-status
```

Expected: the `v3.3` deployment run completes with conclusion `success`.

- [ ] **Step 7: Verify all public destinations**

Verify:

```text
https://github.com/Braxtar/Ez-OBRotation/releases/tag/v3.3
https://www.curseforge.com/wow/addons/ez-obrotation
https://addons.wago.io/addons/ez-obrotation
```

Expected: GitHub shows v3.3 with the exact release text; CurseForge project 1443163 and Wago project kGryylKy expose a Retail 12.1/v3.3 file. If either external catalogue is still processing after the successful workflow, poll its public project page until the new file appears; do not create a duplicate release.
