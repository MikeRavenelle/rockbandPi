"""Minimal /dev/uhid client (linux/uhid.h) for creating virtual HID devices."""

import errno
import os
import struct

UHID_DESTROY = 1
UHID_START = 2
UHID_STOP = 3
UHID_OPEN = 4
UHID_CLOSE = 5
UHID_OUTPUT = 6
UHID_GET_REPORT = 9
UHID_GET_REPORT_REPLY = 10
UHID_CREATE2 = 11
UHID_INPUT2 = 12
UHID_SET_REPORT = 13
UHID_SET_REPORT_REPLY = 14

UHID_DATA_MAX = 4096
# sizeof(struct uhid_event): u32 type + largest union member (uhid_create2_req)
UHID_EVENT_SIZE = 4 + 128 + 64 + 64 + 2 + 2 + 4 * 4 + UHID_DATA_MAX

BUS_USB = 0x03
BUS_I2C = 0x18

_CREATE2 = struct.Struct('<I128s64s64sHHIIII4096s')
_INPUT2 = struct.Struct('<IH4096s')
_GET_REPORT_REPLY = struct.Struct('<IIHH4096s')
_SET_REPORT_REPLY = struct.Struct('<IIH')


class UHIDDevice:
    def __init__(self, name, vendor, product, version, descriptor,
                 phys='', uniq='', bus=BUS_USB):
        if len(descriptor) > UHID_DATA_MAX:
            raise ValueError('report descriptor too large')
        self.name = name
        self.fd = os.open('/dev/uhid', os.O_RDWR | os.O_CLOEXEC | os.O_NONBLOCK)
        try:
            self._write(_CREATE2.pack(
                UHID_CREATE2, name.encode()[:127], phys.encode()[:63], uniq.encode()[:63],
                len(descriptor), bus, vendor, product, version, 0, descriptor))
        except OSError:
            os.close(self.fd)
            raise

    def _write(self, data):
        os.write(self.fd, data)

    def send(self, report: bytes):
        try:
            self._write(_INPUT2.pack(UHID_INPUT2, len(report), report))
        except BlockingIOError:
            pass  # kernel queue full; the next report supersedes this one

    def handle_events(self):
        """Drain kernel requests. Feature-report requests get a plain reply so
        drivers probing the device never stall."""
        while True:
            try:
                ev = os.read(self.fd, UHID_EVENT_SIZE)
            except BlockingIOError:
                return
            if len(ev) < 4:
                return
            (ev_type,) = struct.unpack_from('<I', ev)
            if ev_type == UHID_GET_REPORT:
                (req_id,) = struct.unpack_from('<I', ev, 4)
                self._write(_GET_REPORT_REPLY.pack(
                    UHID_GET_REPORT_REPLY, req_id, errno.EIO, 0, b''))
            elif ev_type == UHID_SET_REPORT:
                (req_id,) = struct.unpack_from('<I', ev, 4)
                self._write(_SET_REPORT_REPLY.pack(UHID_SET_REPORT_REPLY, req_id, 0))
            # START/STOP/OPEN/CLOSE/OUTPUT (rumble, LEDs) need no action

    def close(self):
        if self.fd is None:
            return
        try:
            self._write(struct.pack('<I', UHID_DESTROY))
        except OSError:
            pass
        os.close(self.fd)
        self.fd = None

    def fileno(self):
        return self.fd
