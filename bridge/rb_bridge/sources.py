"""Physical controllers (evdev) and how each maps onto a virtual instrument.

YARG on Linux ignores evdev devices entirely (HIDrogen removes every "Linux"
interface device) and only reads hidraw plus Xbox 360 wireless receivers via
libusb. Controllers driven by kernel drivers that expose evdev only (xpad for
wired Xbox 360 hardware, xone for Xbox One/Series hardware) are therefore read
here and re-exposed as HID instruments that YARG recognises.
"""

import logging
import os

from evdev import ecodes as e

from . import reports as r
from .uhid import BUS_I2C, UHIDDevice

log = logging.getLogger(__name__)

# Linux names Xbox X/Y as BTN_X/BTN_Y, which alias BTN_NORTH/BTN_WEST even though
# the physical X button is on the west side. Use the raw names to avoid confusion.
XBOX_A, XBOX_B, XBOX_X, XBOX_Y = e.BTN_A, e.BTN_B, e.BTN_X, e.BTN_Y

XUSB_SUBTYPE_DRUMS = 0x08
XUSB_SUBTYPE_GUITARS = (0x06, 0x07, 0x0B)


# --- sysfs helpers -----------------------------------------------------------

def _sysfs_input_dir(path):
    """/dev/input/eventN -> real sysfs directory of the parent inputM node."""
    event = os.path.basename(path)
    return os.path.dirname(os.path.realpath(f'/sys/class/input/{event}'))


def _ancestors(d):
    while d and d != '/':
        yield d
        d = os.path.dirname(d)


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def driver_name(path):
    for d in _ancestors(_sysfs_input_dir(path)):
        link = os.path.join(d, 'driver')
        if os.path.islink(link):
            return os.path.basename(os.readlink(link))
    return None


def is_virtual(path):
    real = _sysfs_input_dir(path)
    return '/devices/virtual/' in real


def xusb_info(path):
    """(interface protocol, XUSB subtype) for an xpad device, from the raw USB
    descriptors. Protocol 0x01 is wired, 0x81 a wireless receiver. The subtype
    is byte 4 of the 0x21 class descriptor ([MS-XUSBI] 2.2.4.5)."""
    protocol = None
    for d in _ancestors(_sysfs_input_dir(path)):
        if protocol is None and os.path.exists(os.path.join(d, 'bInterfaceProtocol')):
            protocol = int(_read(os.path.join(d, 'bInterfaceProtocol')) or '0', 16)
        desc_path = os.path.join(d, 'descriptors')
        if os.path.exists(desc_path) and os.path.exists(os.path.join(d, 'idVendor')):
            with open(desc_path, 'rb') as f:
                return protocol, parse_xusb_subtype(f.read())
    return protocol, None


def parse_xusb_subtype(raw: bytes):
    i = raw[0] if raw else 0  # skip the device descriptor
    in_xusb_intf = False
    while i + 1 < len(raw):
        length, dtype = raw[i], raw[i + 1]
        if length < 2:
            break
        if dtype == 0x04 and i + 7 < len(raw):  # interface
            in_xusb_intf = raw[i + 5] == 0xFF and raw[i + 6] == 0x5D
        elif dtype == 0x21 and in_xusb_intf and length > 4:
            return raw[i + 4]
        i += length
    return None


# --- base --------------------------------------------------------------------

class Source:
    """One physical controller feeding one virtual HID device."""

    kind = 'controller'

    def __init__(self, dev, uhid):
        self.dev = dev
        self.uhid = uhid
        self.keys = set(dev.active_keys())
        self.absinfo = dict(dev.capabilities(absinfo=True).get(e.EV_ABS, []))
        self.abs = {code: info.value for code, info in self.absinfo.items()}

    def feed(self, event):
        if event.type == e.EV_KEY:
            if event.value:
                self.keys.add(event.code)
            else:
                self.keys.discard(event.code)
        elif event.type == e.EV_ABS:
            self.abs[event.code] = event.value
        elif event.type == e.EV_SYN and event.code == e.SYN_REPORT:
            self.uhid.send(self.report())

    def report(self) -> bytes:
        raise NotImplementedError

    def norm(self, code, default=0.0):
        """Axis value scaled to 0..1 using the device's own range."""
        info = self.absinfo.get(code)
        if info is None or info.max == info.min:
            return default
        return (self.abs.get(code, info.min) - info.min) / (info.max - info.min)

    def dpad(self):
        """D-pad as (x, y), from hat axes or xpad's d-pad-as-buttons mode."""
        x = self.abs.get(e.ABS_HAT0X, 0)
        y = self.abs.get(e.ABS_HAT0Y, 0)
        k = self.keys
        x = x or (e.BTN_TRIGGER_HAPPY2 in k) - (e.BTN_TRIGGER_HAPPY1 in k)
        y = y or (e.BTN_TRIGGER_HAPPY4 in k) - (e.BTN_TRIGGER_HAPPY3 in k)
        return x, y

    def close(self):
        self.uhid.close()
        try:
            self.dev.ungrab()
        except OSError:
            pass
        self.dev.close()


# --- guitars -----------------------------------------------------------------

def make_guitar_uhid(dev):
    return UHIDDevice('Santroller', r.SANTROLLER_VID, r.SANTROLLER_PID,
                      r.SANTROLLER_RB_GUITAR_REV, r.SANTROLLER_GUITAR_DESCRIPTOR,
                      phys=f'rb-bridge/{os.path.basename(dev.path)}', uniq=dev.uniq or '')


class XoneGuitar(Source):
    """Xbox One RB4 guitars (PDP Jaguar/Riffmaster, MadCatz Stratocaster) via xone.

    Frets: BTN_TRIGGER_HAPPY1-5 upper, 6-10 solo. Whammy ABS_Y, tilt ABS_Z
    (0 level .. 255 up). Pickup ABS_RX 0-4 and Riffmaster joystick
    ABS_HAT1X/ABS_HAT1Y come from patches/xone (Strat reports pickup on ABS_X 0-64).
    """

    kind = 'guitar'
    STICK_THRESHOLD = 16000

    def report(self):
        k = self.keys
        s = r.GuitarState()
        s.frets = [e.BTN_TRIGGER_HAPPY1 + i in k for i in range(5)]
        s.solo = [e.BTN_TRIGGER_HAPPY6 + i in k for i in range(5)]
        s.start, s.select, s.home = e.BTN_START in k, e.BTN_SELECT in k, e.BTN_MODE in k
        s.dpad_x, s.dpad_y = self.dpad()
        # Riffmaster joystick doubles as a menu d-pad
        jx, jy = self.abs.get(e.ABS_HAT1X, 0), self.abs.get(e.ABS_HAT1Y, 0)
        if not s.dpad_x and abs(jx) > self.STICK_THRESHOLD:
            s.dpad_x = 1 if jx > 0 else -1
        if not s.dpad_y and abs(jy) > self.STICK_THRESHOLD:
            s.dpad_y = 1 if jy > 0 else -1
        s.whammy = self.abs.get(e.ABS_Y, 0)
        s.tilt = 0x80 + self.abs.get(e.ABS_Z, 0) // 2
        if e.ABS_RX in self.absinfo:
            s.pickup = min(self.abs.get(e.ABS_RX, 0), 4)
        elif e.ABS_X in self.absinfo:
            s.pickup = min(self.abs.get(e.ABS_X, 0) // 16, 4)
        return r.santroller_guitar_report(s)


class X360Guitar(Source):
    """Wired Xbox 360 Rock Band guitars via xpad."""

    kind = 'guitar'

    def report(self):
        k = self.keys
        s = r.GuitarState()
        frets = [XBOX_A in k, XBOX_B in k, XBOX_X in k, XBOX_Y in k, e.BTN_TL in k]
        if e.BTN_THUMBL in k:   # solo flag
            s.solo = frets
        else:
            s.frets = frets
        s.start, s.select, s.home = e.BTN_START in k, e.BTN_SELECT in k, e.BTN_MODE in k
        s.dpad_x, s.dpad_y = self.dpad()
        s.whammy = int(self.norm(e.ABS_RX) * 255)
        # Tilt is right stick Y: 0 level .. 32767 up. xpad inverts Y axes.
        tilt_raw = ~self.abs.get(e.ABS_RY, -1)
        s.tilt = 0x80 + max(0, tilt_raw) * 127 // 32767
        s.pickup = min(int(self.norm(e.ABS_Z) * 5), 4)
        return r.santroller_guitar_report(s)


# --- drums -------------------------------------------------------------------

class X360Drums(Source):
    """Wired Xbox 360 Rock Band kits (incl. ION Drum Rocker) via xpad.

    Flags: A green, B red, X blue, Y yellow, RS-click pad, RB cymbal,
    LB kick 1, LS-click kick 2. Velocities on the stick axes (Y axes inverted
    by xpad).
    """

    kind = 'drums'

    def __init__(self, dev, uhid, mode):
        super().__init__(dev, uhid)
        self.mode = mode
        self.decoder = r.PadDecoder()

    def state(self):
        k = self.keys
        s = r.DrumState(
            red=XBOX_B in k, yellow=XBOX_Y in k, blue=XBOX_X in k, green=XBOX_A in k,
            pad=e.BTN_THUMBR in k, cymbal=e.BTN_TR in k,
            kick1=e.BTN_TL in k, kick2=e.BTN_THUMBL in k,
            start=e.BTN_START in k, select=e.BTN_SELECT in k, home=e.BTN_MODE in k)
        s.dpad_x, s.dpad_y = self.dpad()
        a = self.abs
        s.vel_red = r.x360_drum_velocity(a.get(e.ABS_X, 0))
        s.vel_yellow = r.x360_drum_velocity(~a.get(e.ABS_Y, -1))
        s.vel_blue = r.x360_drum_velocity(a.get(e.ABS_RX, 0))
        s.vel_green = r.x360_drum_velocity(~a.get(e.ABS_RY, -1))
        return s

    def report(self):
        s = self.state()
        if self.mode == 'santroller':
            return r.santroller_drums_report(s, self.decoder.decode(s))
        return r.ps3_drums_report(s)


def make_drums_uhid(dev, mode, santroller_rev):
    phys = f'rb-bridge/{os.path.basename(dev.path)}'
    if mode == 'santroller':
        return UHIDDevice('Santroller', r.SANTROLLER_VID, r.SANTROLLER_PID, santroller_rev,
                          r.SANTROLLER_DRUMS_DESCRIPTOR, phys=phys, uniq=dev.uniq or '')
    return UHIDDevice('Harmonix Drum Kit for PlayStation(R)3', r.PS3_RB_DRUMS_VID,
                      r.PS3_RB_DRUMS_PID, r.PS3_RB_DRUMS_REV, r.PS3_DESCRIPTOR,
                      phys=phys, uniq=dev.uniq or '')


# --- gamepads ----------------------------------------------------------------

class Gamepad(Source):
    """Xbox 360 / One / Series gamepads -> DualShock 4."""

    kind = 'gamepad'

    def __init__(self, dev, uhid):
        super().__init__(dev, uhid)
        self.encoder = r.DS4Encoder()

    def report(self):
        k = self.keys
        s = r.GamepadState(
            south=XBOX_A in k, east=XBOX_B in k, west=XBOX_X in k, north=XBOX_Y in k,
            l1=e.BTN_TL in k, r1=e.BTN_TR in k, l3=e.BTN_THUMBL in k, r3=e.BTN_THUMBR in k,
            start=e.BTN_START in k, select=e.BTN_SELECT in k, home=e.BTN_MODE in k)
        s.dpad_x, s.dpad_y = self.dpad()
        s.lx = int(self.norm(e.ABS_X, 0.5) * 255)
        s.ly = int(self.norm(e.ABS_Y, 0.5) * 255)
        s.rx = int(self.norm(e.ABS_RX, 0.5) * 255)
        s.ry = int(self.norm(e.ABS_RY, 0.5) * 255)
        s.l2 = int(self.norm(e.ABS_Z) * 255) or (255 if e.BTN_TL2 in k else 0)
        s.r2 = int(self.norm(e.ABS_RZ) * 255) or (255 if e.BTN_TR2 in k else 0)
        return self.encoder.report(s)


def make_gamepad_uhid(dev):
    # Announced on the I2C bus, not USB: the kernel lists the DualShock 4's USB
    # and Bluetooth IDs as "has a special driver", so hid-generic refuses a USB
    # one even with hid-playstation blacklisted, and no hidraw node appears.
    # hidapi (and so YARG) accepts I2C devices; the USB IDs still match
    # Unity's DualShock 4 layout.
    return UHIDDevice('Wireless Controller', r.DS4_VID, r.DS4_PID, r.DS4_REV,
                      r.DS4_DESCRIPTOR, phys=f'rb-bridge/{os.path.basename(dev.path)}',
                      uniq=dev.uniq or '', bus=BUS_I2C)


# --- classification ----------------------------------------------------------

XONE_GUITAR_DRIVERS = {'xone-gip-pdp-jaguar', 'xone-gip-madcatz-strat'}
XONE_GAMEPAD_DRIVERS = {'xone-gip-gamepad'}
XPAD_DRIVERS = {'xpad', 'xpad-noone'}


def classify(dev, config):
    """Return a Source for devices the bridge should translate, else None."""
    if is_virtual(dev.path):
        return None
    caps = dev.capabilities()
    if e.EV_KEY not in caps:
        return None

    drv = driver_name(dev.path)
    if drv in XONE_GUITAR_DRIVERS:
        return XoneGuitar(dev, make_guitar_uhid(dev))
    if drv in XONE_GAMEPAD_DRIVERS:
        return Gamepad(dev, make_gamepad_uhid(dev)) if config.gamepads else None
    if drv in XPAD_DRIVERS:
        protocol, subtype = xusb_info(dev.path)
        if protocol == 0x81:
            # Wireless receiver: YARG drives it directly over libusb
            return None
        if subtype == XUSB_SUBTYPE_DRUMS:
            return X360Drums(dev, make_drums_uhid(dev, config.drum_mode,
                                                  config.santroller_drum_rev),
                             config.drum_mode)
        if subtype in XUSB_SUBTYPE_GUITARS:
            return X360Guitar(dev, make_guitar_uhid(dev))
        return Gamepad(dev, make_gamepad_uhid(dev)) if config.gamepads else None
    return None
