from mw_harness.emulator import Buttons, InputScript


def test_parse_and_lookup():
    s = InputScript.parse("300-303:START 420:A+B")
    assert s.buttons_at(299) == []
    assert s.buttons_at(300) == ["START"] and s.buttons_at(303) == ["START"]
    assert s.buttons_at(420) == ["A", "B"]


def test_button_mask_order():
    m = Buttons.mask("A+START")
    assert m.tolist() == [0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
