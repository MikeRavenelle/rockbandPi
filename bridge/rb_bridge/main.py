"""rb-bridge daemon: watch evdev controllers and mirror them as HID instruments."""

import argparse
import configparser
import errno
import logging
import selectors
import signal
import time
from dataclasses import dataclass

import evdev

from . import reports
from .sources import classify

log = logging.getLogger('rb-bridge')

RESCAN_SECONDS = 1.0


@dataclass
class Config:
    drum_mode: str = 'ps3'                     # 'ps3' or 'santroller'
    santroller_drum_rev: int = reports.SANTROLLER_RB_DRUMS_REV
    gamepads: bool = True


def load_config(path):
    cfg = Config()
    parser = configparser.ConfigParser()
    if not parser.read(path):
        return cfg
    cfg.drum_mode = parser.get('drums', 'mode', fallback=cfg.drum_mode).strip().lower()
    cfg.santroller_drum_rev = int(parser.get('drums', 'santroller_revision',
                                             fallback=hex(cfg.santroller_drum_rev)), 0)
    cfg.gamepads = parser.getboolean('gamepads', 'enabled', fallback=cfg.gamepads)
    if cfg.drum_mode not in ('ps3', 'santroller'):
        log.warning('unknown drums.mode %r, using ps3', cfg.drum_mode)
        cfg.drum_mode = 'ps3'
    return cfg


class Bridge:
    def __init__(self, config):
        self.config = config
        self.sel = selectors.DefaultSelector()
        self.sources = {}       # evdev path -> Source
        self.ignored = set()    # evdev paths seen and not bridged
        self.running = True

    def scan(self):
        present = set(evdev.list_devices())
        for path in list(self.sources):
            if path not in present:
                self.remove(path, 'unplugged')
        self.ignored &= present
        for path in present - set(self.sources) - self.ignored:
            self.add(path)

    def add(self, path):
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            return  # still being set up by udev; retry next scan
        try:
            source = classify(dev, self.config)
        except OSError as exc:
            log.warning('%s (%s): cannot create virtual device: %s', path, dev.name, exc)
            dev.close()
            return
        if source is None:
            self.ignored.add(path)
            dev.close()
            return
        try:
            dev.grab()  # keep raw events away from anything else
        except OSError:
            pass
        self.sources[path] = source
        self.sel.register(dev.fd, selectors.EVENT_READ, ('evdev', path))
        self.sel.register(source.uhid.fileno(), selectors.EVENT_READ, ('uhid', path))
        log.info('%s (%s) -> virtual %s', path, dev.name, source.kind)

    def remove(self, path, reason):
        source = self.sources.pop(path, None)
        if source is None:
            return
        for fd in (source.dev.fd, source.uhid.fileno()):
            try:
                self.sel.unregister(fd)
            except (KeyError, ValueError):
                pass
        source.close()
        log.info('%s removed (%s)', path, reason)

    def run(self):
        next_scan = 0.0
        while self.running:
            now = time.monotonic()
            if now >= next_scan:
                self.scan()
                next_scan = now + RESCAN_SECONDS
            for key, _ in self.sel.select(timeout=max(0.0, next_scan - time.monotonic())):
                kind, path = key.data
                source = self.sources.get(path)
                if source is None:
                    continue
                try:
                    if kind == 'evdev':
                        for event in source.dev.read():
                            source.feed(event)
                    else:
                        source.uhid.handle_events()
                except BlockingIOError:
                    pass
                except OSError as exc:
                    if exc.errno in (errno.ENODEV, errno.EBADF):
                        self.remove(path, 'disconnected')
                    else:
                        log.exception('%s: read error', path)
                        self.remove(path, 'error')
        for path in list(self.sources):
            self.remove(path, 'shutdown')

    def stop(self, *_):
        self.running = False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default='/etc/rockband-kiosk/bridge.conf')
    parser.add_argument('-v', '--verbose', action='store_true')
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format='%(levelname)s %(message)s')

    config = load_config(args.config)
    log.info('drums=%s (santroller rev 0x%04x) gamepads=%s',
             config.drum_mode, config.santroller_drum_rev, config.gamepads)
    bridge = Bridge(config)
    signal.signal(signal.SIGTERM, bridge.stop)
    signal.signal(signal.SIGINT, bridge.stop)
    bridge.run()


if __name__ == '__main__':
    main()
