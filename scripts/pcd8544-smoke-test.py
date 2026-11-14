#!/usr/bin/env python3
"""Teste de fumaça do LCD Nokia 5110 (PCD8544 84x48) na NanoPi NEO Air.

Desenha padrões de teste para provar a fiação antes de existir qualquer daemon.
Não instala nada: fala com /dev/spidev0.0 por ioctl (biblioteca padrão) e com os
GPIOs de DC/RST/CS por /sys/class/gpio.

Uso (como root):

    python3 pcd8544-smoke-test.py                  # CS no pino 24 (gpio 67)
    python3 pcd8544-smoke-test.py --cs-gnd         # CS aterrado
    python3 pcd8544-smoke-test.py --contrast 0xC8  # contraste mais forte
    python3 pcd8544-smoke-test.py --hold           # para no último padrão

Por que o CS é controlado à mão: neste kernel o driver sunxi-spi não aciona
`cs-gpios`; o pino PC3 fica como saída em nível alto e o display ignora tudo.
Ver docs/14-display-lcd.md.
"""

import argparse
import ctypes
import fcntl
import os
import struct
import sys
import time

WIDTH, HEIGHT = 84, 48
GPIO_DIR = "/sys/class/gpio"
SPI_DEV = "/dev/spidev0.0"

# ioctls do spidev (uapi/linux/spi/spidev.h, _IOW('k', nr, size)).
# O tamanho do ioctl de mensagem é sizeof(struct spi_ioc_transfer) * N — no
# armhf (u64 alinhado em 8) dá 32 bytes, então SPI_IOC_MESSAGE(1) = 0x40206B00.
XFER = struct.Struct("<QQIIHBBBBBB")
SPI_IOC_MESSAGE_1 = (1 << 30) | (XFER.size << 16) | (0x6B << 8) | 0
SPI_IOC_WR_MODE = 0x40016B01
SPI_IOC_WR_BITS_PER_WORD = 0x40016B03
SPI_IOC_WR_MAX_SPEED_HZ = 0x40046B04


# --------------------------------------------------------------------------- #
# GPIO por sysfs
# --------------------------------------------------------------------------- #
def gpio_out(number):
    """Exporta o GPIO e o coloca como saída (nível baixo)."""
    base = os.path.join(GPIO_DIR, "gpio%d" % number)
    if not os.path.isdir(base):
        with open(os.path.join(GPIO_DIR, "export"), "w") as f:
            f.write(str(number))
        for _ in range(50):
            if os.path.isdir(base):
                break
            time.sleep(0.01)
    with open(os.path.join(base, "direction"), "w") as f:
        f.write("out")
    with open(os.path.join(base, "value"), "w") as f:
        f.write("0")
    return number


def gpio_set(number, value):
    with open(os.path.join(GPIO_DIR, "gpio%d" % number, "value"), "w") as f:
        f.write("1" if value else "0")


# --------------------------------------------------------------------------- #
# SPI por ioctl
# --------------------------------------------------------------------------- #
class Spi:
    def __init__(self, path=SPI_DEV, speed=4000000):
        self.speed = speed
        self.fd = os.open(path, os.O_RDWR)
        fcntl.ioctl(self.fd, SPI_IOC_WR_MODE, struct.pack("B", 0))  # mode 0
        fcntl.ioctl(self.fd, SPI_IOC_WR_BITS_PER_WORD, struct.pack("B", 8))
        fcntl.ioctl(self.fd, SPI_IOC_WR_MAX_SPEED_HZ, struct.pack("I", speed))

    def write(self, data):
        data = bytes(data)
        if not data:
            return
        buf = ctypes.create_string_buffer(data, len(data))
        # tx_buf, rx_buf, len, speed_hz, delay_usecs, bits, cs_change, nbits...
        msg = XFER.pack(
            ctypes.addressof(buf), 0, len(data), self.speed, 0, 8, 0, 0, 0, 0, 0,
        )
        fcntl.ioctl(self.fd, SPI_IOC_MESSAGE_1, ctypes.create_string_buffer(msg, len(msg)))

    def close(self):
        os.close(self.fd)


# --------------------------------------------------------------------------- #
# PCD8544
# --------------------------------------------------------------------------- #
class PCD8544:
    def __init__(self, spi, dc, rst, cs=None, contrast=0xBF):
        self.spi = spi
        self.dc = gpio_out(dc)
        self.rst = gpio_out(rst)
        self.cs = gpio_out(cs) if cs is not None else None
        self.contrast = contrast

    # -- primitivas ---------------------------------------------------------
    def _select(self, on):
        if self.cs is not None:
            gpio_set(self.cs, 0 if on else 1)

    def _command(self, *cmds):
        self._select(True)
        gpio_set(self.dc, 0)
        for c in cmds:
            self.spi.write([c])
        self._select(False)

    def _data(self, payload):
        self._select(True)
        gpio_set(self.dc, 1)
        self.spi.write(payload)
        self._select(False)

    # -- API ----------------------------------------------------------------
    def reset(self):
        gpio_set(self.rst, 1)
        time.sleep(0.05)
        gpio_set(self.rst, 0)
        time.sleep(0.1)
        gpio_set(self.rst, 1)
        time.sleep(0.1)

    def init(self):
        self.reset()
        self._command(
            0x21,                 # function set: modo estendido
            0x80 | (self.contrast & 0x7F),  # Vop (contraste)
            0x04,                 # temperature coefficient 0
            0x14,                 # bias 1:4
            0x20,                 # function set: modo básico
            0x0C,                 # display control: normal
        )

    def show(self, framebuffer):
        assert len(framebuffer) == WIDTH * HEIGHT // 8
        self._command(0x80, 0x40)  # X = 0, Y = 0
        self._data(framebuffer)


# --------------------------------------------------------------------------- #
# Padrões de teste
# --------------------------------------------------------------------------- #
def fb_blank(value=0x00):
    return bytearray([value] * (WIDTH * HEIGHT // 8))


def fb_checker():
    fb = fb_blank()
    for bank in range(HEIGHT // 8):
        fill = 0xAA if bank % 2 == 0 else 0x55
        for x in range(WIDTH):
            fb[bank * WIDTH + x] = fill if (x + bank) % 2 == 0 else 0xFF ^ fill
    return fb


def fb_border():
    fb = fb_blank()
    for x in range(WIDTH):                       # linhas de cima e de baixo
        fb[x] |= 0x01
        fb[(HEIGHT // 8 - 1) * WIDTH + x] |= 0x80
    for bank in range(HEIGHT // 8):              # colunas das laterais
        fb[bank * WIDTH] |= 0xFF
        fb[bank * WIDTH + WIDTH - 1] |= 0xFF
    for x in range(WIDTH):                       # diagonal
        y = x * HEIGHT // WIDTH
        fb[(y // 8) * WIDTH + x] |= 1 << (y % 8)
    return fb


def fb_halves():
    fb = fb_blank()
    for bank in range(HEIGHT // 8):
        for x in range(WIDTH // 2):
            fb[bank * WIDTH + x] = 0xFF
    return fb


PATTERNS = [
    ("tudo preto", fb_blank(0xFF)),
    ("tudo branco", fb_blank(0x00)),
    ("xadrez", fb_checker()),
    ("metades", fb_halves()),
    ("moldura + diagonal", fb_border()),
]


# --------------------------------------------------------------------------- #
def main():
    p = argparse.ArgumentParser(description="Teste de fumaça do PCD8544 84x48")
    p.add_argument("--dc", type=int, default=200, help="GPIO de DC (padrão: 200 = PG8, pino 16)")
    p.add_argument("--rst", type=int, default=201, help="GPIO de RST (padrão: 201 = PG9, pino 18)")
    p.add_argument("--cs", type=int, default=67, help="GPIO de CS (padrão: 67 = PC3, pino 24)")
    p.add_argument("--cs-gnd", action="store_true", help="CS aterrado: não controla o pino")
    p.add_argument("--contrast", type=lambda s: int(s, 0), default=0xBF, help="Vop 0x80–0xFF")
    p.add_argument("--speed", type=int, default=4000000, help="Hz (PCD8544 aceita até 4 MHz)")
    p.add_argument("--hold", action="store_true", help="para no último padrão")
    p.add_argument("--delay", type=float, default=1.5, help="segundos por padrão")
    args = p.parse_args()

    if os.geteuid() != 0:
        sys.exit("rode como root (precisa de /dev/spidev0.0 e /sys/class/gpio)")

    cs = None if args.cs_gnd else args.cs
    print("SPI %s @ %s Hz · DC=%s RST=%s CS=%s · contraste=0x%02X"
          % (SPI_DEV, args.speed, args.dc, args.rst, "aterrado" if cs is None else cs,
             args.contrast))

    spi = Spi(speed=args.speed)
    lcd = PCD8544(spi, dc=args.dc, rst=args.rst, cs=cs, contrast=args.contrast)
    try:
        lcd.init()
        for name, fb in PATTERNS:
            print("  -> %s" % name, flush=True)
            lcd.show(fb)
            time.sleep(args.delay)
        if args.hold:
            lcd.show(PATTERNS[-1][1])
            print("último padrão na tela; Ctrl+C para sair")
            while True:
                time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        spi.close()

    print("fim. Se os 5 padrões apareceram, a fiação está correta.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
