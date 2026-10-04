import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from rb_bridge import reports as r  # noqa: E402


def input_report_bits(descriptor):
    """Sum of Input item bits per report ID (minimal HID descriptor walker)."""
    sizes, report_size, report_count, report_id = {}, 0, 0, 0
    i = 0
    while i < len(descriptor):
        prefix = descriptor[i]
        size = (0, 1, 2, 4)[prefix & 0x03]
        data = int.from_bytes(descriptor[i + 1:i + 1 + size], 'little')
        tag = prefix & 0xFC
        if tag == 0x74:
            report_size = data
        elif tag == 0x94:
            report_count = data
        elif tag == 0x84:
            report_id = data
        elif tag == 0x80:  # Input
            sizes[report_id] = sizes.get(report_id, 0) + report_size * report_count
        i += 1 + size
    return sizes


def expected_len(descriptor):
    sizes = input_report_bits(descriptor)
    assert len(sizes) == 1
    (rid, bits), = sizes.items()
    assert bits % 8 == 0, bits
    return bits // 8 + (1 if rid else 0)


class DescriptorTests(unittest.TestCase):
    def test_guitar_report_matches_descriptor(self):
        self.assertEqual(len(r.santroller_guitar_report(r.GuitarState())),
                         expected_len(r.SANTROLLER_GUITAR_DESCRIPTOR))

    def test_ps3_drums_report_matches_descriptor(self):
        self.assertEqual(len(r.ps3_drums_report(r.DrumState())), 27)
        self.assertEqual(expected_len(r.PS3_DESCRIPTOR), 27)

    def test_santroller_drums_report_matches_descriptor(self):
        self.assertEqual(len(r.santroller_drums_report(r.DrumState(), set())),
                         expected_len(r.SANTROLLER_DRUMS_DESCRIPTOR))

    def test_ds4_report_matches_descriptor(self):
        self.assertEqual(len(r.DS4Encoder().report(r.GamepadState())), 64)
        self.assertEqual(expected_len(r.DS4_DESCRIPTOR), 64)

    def test_usages_are_gamepads(self):
        # HIDrogen only accepts Generic Desktop Joystick/Gamepad top-level usages
        for d in (r.SANTROLLER_GUITAR_DESCRIPTOR, r.SANTROLLER_DRUMS_DESCRIPTOR,
                  r.PS3_DESCRIPTOR, r.DS4_DESCRIPTOR):
            self.assertEqual(d[:4], bytes([0x05, 0x01, 0x09, 0x05]))


class GuitarTests(unittest.TestCase):
    def test_layout(self):
        s = r.GuitarState(frets=[True, False, False, False, True],
                          solo=[False, True, False, False, False],
                          start=True, dpad_y=1, whammy=200, pickup=2, tilt=0xF0)
        rep = r.santroller_guitar_report(s)
        self.assertEqual(rep[0], 0x01)
        self.assertEqual(rep[1] | rep[2] << 8, 0x0001 | 0x0010 | 0x0040 | 0x0800)
        self.assertEqual(rep[3], 4)          # strum down
        self.assertEqual(rep[4:7], bytes([200, 0x96, 0xF0]))

    def test_idle(self):
        rep = r.santroller_guitar_report(r.GuitarState())
        self.assertEqual(rep[3], r.HAT_NEUTRAL)
        self.assertEqual(rep[5], 0x7F)       # pickup "at rest"
        self.assertEqual(rep[6], 0x80)       # tilt level


class DrumTests(unittest.TestCase):
    def decode(self, **flags):
        return r.PadDecoder().decode(r.DrumState(**flags))

    def test_pads(self):
        self.assertEqual(self.decode(red=True, pad=True), {r.RED_PAD})

    def test_cymbals_use_dpad(self):
        self.assertEqual(self.decode(yellow=True, cymbal=True, dpad_y=-1), {r.YELLOW_CYM})
        self.assertEqual(self.decode(blue=True, cymbal=True, dpad_y=1), {r.BLUE_CYM})
        self.assertEqual(self.decode(green=True, cymbal=True), {r.GREEN_CYM})

    def test_pad_and_cymbal_different_colours(self):
        self.assertEqual(self.decode(red=True, yellow=True, pad=True, cymbal=True, dpad_y=-1),
                         {r.RED_PAD, r.YELLOW_CYM})

    def test_same_colour_pad_and_cymbal(self):
        self.assertEqual(self.decode(yellow=True, pad=True, cymbal=True, dpad_y=-1),
                         {r.YELLOW_PAD, r.YELLOW_CYM})

    def test_rb1_kit_without_flags(self):
        self.assertEqual(self.decode(blue=True), {r.BLUE_PAD})

    def test_ps3_bits(self):
        rep = r.ps3_drums_report(r.DrumState(green=True, cymbal=True, kick1=True,
                                             vel_green=255))
        self.assertEqual(rep[0] | rep[1] << 8, 0x0002 | 0x0010 | 0x0800)
        self.assertEqual(rep[13], 0x00)      # hardest hit = 0 on PS3

    def test_santroller_velocities(self):
        s = r.DrumState(yellow=True, cymbal=True, dpad_y=-1, vel_yellow=90)
        rep = r.santroller_drums_report(s, r.PadDecoder().decode(s))
        self.assertEqual(rep[4:11], bytes([0, 0, 0, 0, 0, 90, 0]))

    def test_x360_velocity(self):
        self.assertEqual(r.x360_drum_velocity(0x0000), 255)   # hardest
        self.assertEqual(r.x360_drum_velocity(0x7FFF), 1)     # softest
        self.assertEqual(r.x360_drum_velocity(-32768), 255)   # top bit ignored


class GamepadTests(unittest.TestCase):
    def test_ds4_layout(self):
        s = r.GamepadState(south=True, north=True, l1=True, start=True, home=True,
                           dpad_x=-1, lx=0, ly=255, r2=255)
        rep = r.DS4Encoder().report(s)
        self.assertEqual(rep[0], 0x01)
        self.assertEqual(rep[1:3], bytes([0, 255]))
        self.assertEqual(rep[5], 6 | 0x20 | 0x80)     # left, cross, triangle
        self.assertEqual(rep[6], 0x01 | 0x08 | 0x20)  # L1, R2 button, options
        self.assertEqual(rep[7] & 0x01, 1)
        self.assertEqual(rep[9], 255)


class XusbDescriptorTests(unittest.TestCase):
    def test_subtype_from_config_descriptor(self):
        try:
            from rb_bridge.sources import parse_xusb_subtype
        except ImportError:
            self.skipTest('python-evdev not installed')
        device = bytes([18, 1]) + bytes(16)
        config = bytes([9, 2, 0, 0, 1, 1, 0, 0x80, 0xFA])
        intf = bytes([9, 4, 0, 0, 2, 0xFF, 0x5D, 0x01, 0])
        xusb = bytes([0x11, 0x21, 0x00, 0x01, 0x08, 0x25, 0x81, 0x14, 0, 0, 0, 0,
                      0x13, 0x01, 0x08, 0, 0])
        self.assertEqual(parse_xusb_subtype(device + config + intf + xusb), 0x08)


if __name__ == '__main__':
    unittest.main()
