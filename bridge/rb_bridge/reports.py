"""HID report descriptors and report encoders for the virtual instruments.

Each virtual device copies a real instrument that YARG (via PlasticBand) supports
natively over hidraw on Linux:

- Rock Band guitar  -> Santroller HID RB guitar   (1209:2882, revision 0x0400)
- Rock Band drums   -> PS3 Rock Band drum kit      (12BA:0210), or optionally a
                       Santroller HID RB drum kit, which also carries velocity
- Gamepad           -> DualShock 4                 (054C:05C4)

Report layouts come from the PlasticBand docs and from the PlasticBand-Unity
v0.9.0 state structs that YARG v0.15.0 ships with.
"""

from dataclasses import dataclass, field

# --- Device identities -------------------------------------------------------

SANTROLLER_VID, SANTROLLER_PID = 0x1209, 0x2882
SANTROLLER_RB_GUITAR_REV = 0x0400
# PlasticBand-Unity v0.9.0 registers its Santroller 4-lane kit under device type
# 0x05 (the docs say 0x06), and the first registered layout wins the tie with the
# 5-lane kit. Override with drums.santroller_revision in bridge.conf if that changes.
SANTROLLER_RB_DRUMS_REV = 0x0500

PS3_RB_DRUMS_VID, PS3_RB_DRUMS_PID = 0x12BA, 0x0210
PS3_RB_DRUMS_REV = 0x0200

DS4_VID, DS4_PID = 0x054C, 0x05C4
DS4_REV = 0x0100

# --- D-pad -------------------------------------------------------------------

HAT_NEUTRAL = 8
_HAT = {
    (0, -1): 0, (1, -1): 1, (1, 0): 2, (1, 1): 3,
    (0, 1): 4, (-1, 1): 5, (-1, 0): 6, (-1, -1): 7, (0, 0): HAT_NEUTRAL,
}


def _sign(v):
    return (v > 0) - (v < 0)


def hat(x, y):
    """D-pad direction to a HID hat value. y < 0 is up."""
    return _HAT[(_sign(x), _sign(y))]


def clamp_byte(v):
    return max(0, min(255, int(v)))


# --- Descriptors -------------------------------------------------------------

# 13 buttons + hat + whammy/pickup/tilt, report ID 1, 7 data bytes + 1 pad byte
SANTROLLER_GUITAR_DESCRIPTOR = bytes([
    0x05, 0x01,        # Usage Page (Generic Desktop)
    0x09, 0x05,        # Usage (Game Pad)
    0xA1, 0x01,        # Collection (Application)
    0x85, 0x01,        #   Report ID (1)
    0x15, 0x00, 0x25, 0x01, 0x35, 0x00, 0x45, 0x01,
    0x75, 0x01, 0x95, 0x0D,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0D,
    0x81, 0x02,        #   Input: 13 buttons
    0x95, 0x03, 0x81, 0x01,  # 3 bits padding
    0x05, 0x01,
    0x25, 0x07, 0x46, 0x3B, 0x01, 0x75, 0x04, 0x95, 0x01, 0x65, 0x14,
    0x09, 0x39, 0x81, 0x42,  # Hat switch (null state)
    0x65, 0x00, 0x95, 0x01, 0x81, 0x01,  # 4 bits padding
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x46, 0xFF, 0x00,
    0x75, 0x08, 0x95, 0x03,
    0x09, 0x32, 0x09, 0x35, 0x09, 0x33,
    0x81, 0x02,        #   Input: whammy (Z), pickup (Rz), tilt (Rx)
    0x95, 0x01, 0x81, 0x01,  # 1 byte padding
    0xC0,
])

# Santroller drums: 11 buttons + hat + 7 velocity bytes, report ID 1
SANTROLLER_DRUMS_DESCRIPTOR = bytes([
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01,
    0x85, 0x01,
    0x15, 0x00, 0x25, 0x01, 0x35, 0x00, 0x45, 0x01,
    0x75, 0x01, 0x95, 0x10,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x10,
    0x81, 0x02,        #   Input: 16 button bits
    0x05, 0x01,
    0x25, 0x07, 0x46, 0x3B, 0x01, 0x75, 0x04, 0x95, 0x01, 0x65, 0x14,
    0x09, 0x39, 0x81, 0x42,
    0x65, 0x00, 0x95, 0x01, 0x81, 0x01,
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x46, 0xFF, 0x00,
    0x06, 0x00, 0xFF, 0x09, 0x20,
    0x75, 0x08, 0x95, 0x07,
    0x81, 0x02,        #   Input: 7 velocity bytes (vendor)
    0xC0,
])

# PS3 instrument report: no report ID, 27 bytes
PS3_DESCRIPTOR = bytes([
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01,
    0x15, 0x00, 0x25, 0x01, 0x35, 0x00, 0x45, 0x01,
    0x75, 0x01, 0x95, 0x0D,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0D,
    0x81, 0x02,        #   Input: 13 buttons
    0x95, 0x03, 0x81, 0x01,
    0x05, 0x01,
    0x25, 0x07, 0x46, 0x3B, 0x01, 0x75, 0x04, 0x95, 0x01, 0x65, 0x14,
    0x09, 0x39, 0x81, 0x42,
    0x65, 0x00, 0x95, 0x01, 0x81, 0x01,
    0x26, 0xFF, 0x00, 0x46, 0xFF, 0x00,
    0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35,
    0x75, 0x08, 0x95, 0x04,
    0x81, 0x02,        #   Input: 4 stick axes
    0x06, 0x00, 0xFF, 0x09, 0x20,
    0x75, 0x08, 0x95, 0x14,
    0x81, 0x02,        #   Input: 20 pressure/motion bytes (vendor)
    0xC0,
])

# DualShock 4 USB input report 0x01: 63 data bytes
DS4_DESCRIPTOR = bytes([
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01,
    0x85, 0x01,
    0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35,
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x04,
    0x81, 0x02,        #   Input: sticks
    0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00, 0x46, 0x3B, 0x01,
    0x65, 0x14, 0x75, 0x04, 0x95, 0x01,
    0x81, 0x42,        #   Input: hat
    0x65, 0x00,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0E, 0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x0E,
    0x81, 0x02,        #   Input: 14 buttons
    0x06, 0x00, 0xFF, 0x09, 0x20, 0x75, 0x06, 0x95, 0x01, 0x15, 0x00, 0x25, 0x3F,
    0x81, 0x02,        #   Input: 6-bit counter
    0x05, 0x01, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xFF, 0x00,
    0x75, 0x08, 0x95, 0x02,
    0x81, 0x02,        #   Input: triggers
    0x06, 0x00, 0xFF, 0x09, 0x21, 0x95, 0x36,
    0x81, 0x02,        #   Input: 54 vendor bytes (motion, touchpad...)
    0xC0,
])

# --- Guitar ------------------------------------------------------------------

# Pickup notch -> the byte a PS3/Santroller guitar reports for it
PICKUP_VALUES = (0x19, 0x4C, 0x96, 0xB2, 0xE5)


@dataclass
class GuitarState:
    frets: list = field(default_factory=lambda: [False] * 5)  # G R Y B O
    solo: list = field(default_factory=lambda: [False] * 5)
    start: bool = False
    select: bool = False
    home: bool = False
    dpad_x: int = 0
    dpad_y: int = 0            # -1 up (strum up), 1 down
    whammy: int = 0            # 0 rest .. 255 full
    pickup: int = None         # notch 0-4, or None if the guitar has no switch
    tilt: int = 0x80           # 0x80 level .. 0xFF straight up


def santroller_guitar_report(s: GuitarState) -> bytes:
    buttons = 0
    for i in range(5):
        if s.frets[i]:
            buttons |= 1 << i
        if s.solo[i]:
            buttons |= 1 << (5 + i)
    if s.select:
        buttons |= 0x0400
    if s.start:
        buttons |= 0x0800
    if s.home:
        buttons |= 0x1000
    pickup = PICKUP_VALUES[s.pickup] if s.pickup is not None else 0x7F
    return bytes([
        0x01, buttons & 0xFF, buttons >> 8,
        hat(s.dpad_x, s.dpad_y),
        clamp_byte(s.whammy), pickup, clamp_byte(s.tilt),
        0x00,
    ])


# --- Drums -------------------------------------------------------------------

RED_PAD, YELLOW_PAD, BLUE_PAD, GREEN_PAD = 'rp', 'yp', 'bp', 'gp'
YELLOW_CYM, BLUE_CYM, GREEN_CYM = 'yc', 'bc', 'gc'


@dataclass
class DrumState:
    """Rock Band drum flags as every console kit reports them."""
    red: bool = False
    yellow: bool = False
    blue: bool = False
    green: bool = False
    pad: bool = False
    cymbal: bool = False
    kick1: bool = False
    kick2: bool = False
    start: bool = False
    select: bool = False
    home: bool = False
    dpad_x: int = 0
    dpad_y: int = 0
    # Hit strength per colour, 1 (soft) .. 255 (hard), 0 if unknown
    vel_red: int = 0
    vel_yellow: int = 0
    vel_blue: int = 0
    vel_green: int = 0


class PadDecoder:
    """Turns colour + pad/cymbal flags into individual pad and cymbal hits.

    Port of the algorithm in PlasticBand's "Deciphering Pads and Cymbals" notes,
    including the RB1 (no flags) and same-colour pad + cymbal cases.
    """

    def __init__(self):
        self.has_flags = False

    def decode(self, s: DrumState) -> set:
        red, yellow, blue, green = s.red, s.yellow, s.blue, s.green
        pad, cymbal = s.pad, s.cymbal
        up, down = s.dpad_y < 0, s.dpad_y > 0
        hits = set()

        self.has_flags |= pad or cymbal

        if pad and cymbal:
            colors = sum([red, yellow or up, blue or down, green or not (up or down)])
            if colors > 1:
                if up:
                    hits.add(YELLOW_CYM)
                    yellow = cymbal = False
                if down:
                    hits.add(BLUE_CYM)
                    blue = cymbal = False
                if not (up or down):
                    hits.add(GREEN_CYM)
                    green = cymbal = False

        if pad or (not cymbal and not self.has_flags):
            if red:
                hits.add(RED_PAD)
            if yellow:
                hits.add(YELLOW_PAD)
            if blue:
                hits.add(BLUE_PAD)
            if green:
                hits.add(GREEN_PAD)

        if cymbal:
            if yellow:
                hits.add(YELLOW_CYM)
            if blue:
                hits.add(BLUE_CYM)
            if green:
                hits.add(GREEN_CYM)

        return hits


def ps3_drums_report(s: DrumState) -> bytes:
    buttons = 0
    for flag, bit in ((s.blue, 0x0001), (s.green, 0x0002), (s.red, 0x0004),
                      (s.yellow, 0x0008), (s.kick1, 0x0010), (s.kick2, 0x0020),
                      (s.select, 0x0100), (s.start, 0x0200), (s.pad, 0x0400),
                      (s.cymbal, 0x0800), (s.home, 0x1000)):
        if flag:
            buttons |= bit

    def ps3_velocity(active, vel):
        # PS3 kits invert velocity: 0x00 hardest, 0xFF softest
        return 0xFF - clamp_byte(vel or 255) if active else 0

    report = bytearray(27)
    report[0] = buttons & 0xFF
    report[1] = buttons >> 8
    report[2] = hat(s.dpad_x, s.dpad_y)
    report[3:7] = b'\x80\x80\x80\x80'
    report[11] = ps3_velocity(s.yellow, s.vel_yellow)
    report[12] = ps3_velocity(s.red, s.vel_red)
    report[13] = ps3_velocity(s.green, s.vel_green)
    report[14] = ps3_velocity(s.blue, s.vel_blue)
    return bytes(report)


def santroller_drums_report(s: DrumState, hits: set) -> bytes:
    buttons = 0
    for flag, bit in ((s.green, 0x0001), (s.red, 0x0002), (s.blue, 0x0004),
                      (s.yellow, 0x0008), (s.pad, 0x0010), (s.cymbal, 0x0020),
                      (s.kick1, 0x0040), (s.kick2, 0x0080), (s.select, 0x0100),
                      (s.start, 0x0200), (s.home, 0x0400)):
        if flag:
            buttons |= bit

    def vel(name, v):
        return max(1, clamp_byte(v or 255)) if name in hits else 0

    return bytes([
        0x01, buttons & 0xFF, buttons >> 8,
        hat(s.dpad_x, s.dpad_y),
        vel(GREEN_PAD, s.vel_green), vel(RED_PAD, s.vel_red),
        vel(YELLOW_PAD, s.vel_yellow), vel(BLUE_PAD, s.vel_blue),
        vel(GREEN_CYM, s.vel_green), vel(YELLOW_CYM, s.vel_yellow),
        vel(BLUE_CYM, s.vel_blue),
    ])


def x360_drum_velocity(raw: int) -> int:
    """Xbox 360 drum velocity axis (inverted, top bit ignored) -> 1..255."""
    strength = 0x7FFF - (raw & 0x7FFF)
    return max(1, strength >> 7)


# --- Gamepad -----------------------------------------------------------------

@dataclass
class GamepadState:
    south: bool = False
    east: bool = False
    west: bool = False
    north: bool = False
    l1: bool = False
    r1: bool = False
    l3: bool = False
    r3: bool = False
    start: bool = False
    select: bool = False
    home: bool = False
    dpad_x: int = 0
    dpad_y: int = 0
    lx: int = 128
    ly: int = 128              # 0 up .. 255 down
    rx: int = 128
    ry: int = 128
    l2: int = 0
    r2: int = 0


class DS4Encoder:
    def __init__(self):
        self.counter = 0

    def report(self, s: GamepadState) -> bytes:
        b1 = hat(s.dpad_x, s.dpad_y)
        b1 |= (s.west << 4) | (s.south << 5) | (s.east << 6) | (s.north << 7)
        b2 = (s.l1 | (s.r1 << 1) | ((s.l2 > 25) << 2) | ((s.r2 > 25) << 3)
              | (s.select << 4) | (s.start << 5) | (s.l3 << 6) | (s.r3 << 7))
        self.counter = (self.counter + 1) & 0x3F
        b3 = s.home | (self.counter << 2)
        report = bytearray(64)
        report[0:10] = bytes([
            0x01, clamp_byte(s.lx), clamp_byte(s.ly), clamp_byte(s.rx), clamp_byte(s.ry),
            b1, b2, b3, clamp_byte(s.l2), clamp_byte(s.r2),
        ])
        return bytes(report)
