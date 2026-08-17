from pathlib import Path
import unittest

from lupa import LuaError, LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
ADDON_SOURCE = ROOT / "Ez-OBRotation.lua"
ADDON_TOC = ROOT / "Ez-OBRotation.toc"

BOOTSTRAP = r"""
SlashCmdList = {}
print = function() end
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

    def test_ezobrdebug_does_not_scan_nonexistent_multibar8_frame(self):
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
        self.runtime.globals.SlashCmdList["EZOBRDEBUG"]()

        self.assertEqual(
            0,
            self.runtime.globals["__multibar8_visibility_checks"],
        )


class TocMetadataTests(unittest.TestCase):
    def test_retail_12_1_release_metadata(self):
        metadata = {}
        for line in ADDON_TOC.read_text(encoding="utf-8-sig").splitlines():
            if line.startswith("## ") and ":" in line:
                key, value = line[3:].split(":", 1)
                metadata[key.strip()] = value.strip()

        self.assertEqual("120100", metadata.get("Interface"))
        self.assertEqual("3.3", metadata.get("Version"))


if __name__ == "__main__":
    unittest.main()
