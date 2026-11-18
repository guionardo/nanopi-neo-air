#!/usr/bin/env python3
"""Teste de fumaça do OLED I2C (SSD1306 / SH1106) na NanoPi NEO Air.

Desenha padrões de teste para provar a fiação antes de existir qualquer daemon.
Não instala nada: fala com /dev/i2c-0 por ioctl (biblioteca padrão).

Ligação no header 2x12 (I2C0):

    OLED VCC -> pino 1  (SYS_3.3V)
    OLED GND -> pino 6  (GND)
    OLED SDA -> pino 3  (I2C0_SDA / PA12)
    OLED SCL -> pino 5  (I2C0_SCL / PA11)

Uso (como root):

    python3 ssd1306-smoke-test.py                  # SSD1306 128x64 em 0x3C
    python3 ssd1306-smoke-test.py --addr 0x3D      # módulo com endereço 0x3D
    python3 ssd1306-smoke-test.py --height 32      # painel 128x32
    python3 ssd1306-smoke-test.py --controller sh1106
    python3 ssd1306-smoke-test.py --hold           # para no último padrão
    python3 ssd1306-smoke-test.py --soak 600       # redesenha por 10 minutos

Observação: sem display plugado o barramento fica sem pull-ups, as linhas
flutuam e o i2cdetect trava. É normal — o módulo OLED traz os resistores.
"""

import argparse
import fcntl
import os
import sys
import time

I2C_SLAVE = 0x0703                      # include/uapi/linux/i2c-dev.h
DEFAULT_BUS = "/dev/i2c-0"
CHUNK = 64                              # bytes de dados por transferência


# --------------------------------------------------------------------------- #
# Barramento I2C cru (ioctl + write, sem smbus)
# --------------------------------------------------------------------------- #
def bus_open(dev, addr):
    try:
        fd = os.open(dev, os.O_RDWR)
    except OSError as exc:
        sys.exit("nao consegui abrir %s: %s" % (dev, exc.strerror))
    try:
        fcntl.ioctl(fd, I2C_SLAVE, addr)
    except OSError as exc:
        os.close(fd)
        sys.exit("endereco 0x%02X nao respondeu em %s: %s"
                 % (addr, dev, exc.strerror))
    return fd


# --------------------------------------------------------------------------- #
# Framebuffers de teste (1 bit por pixel, 8 pixels por byte, em "pages")
# --------------------------------------------------------------------------- #
def fb_blank(value=0x00, width=128, height=64):
    return bytearray([value] * (width * (height // 8)))


def fb_checker(width=128, height=64):
    fb = fb_blank(0x00, width, height)
    for page in range(height // 8):
        for x in range(width):
            byte = 0
            for bit in range(8):
                y = page * 8 + bit
                if ((x // 4) + (y // 4)) % 2 == 0:      # xadrez de 4x4
                    byte |= 1 << bit
            fb[page * width + x] = byte
    return fb


def fb_halves(width=128, height=64):
    fb = fb_blank(0x00, width, height)
    for page in range(height // 8):
        for x in range(width // 2):
            fb[page * width + x] = 0xFF
    return fb


def fb_border(width=128, height=64):
    fb = fb_blank(0x00, width, height)
    pages = height // 8
    for x in range(width):                              # topo e base
        fb[x] |= 0x01
        fb[(pages - 1) * width + x] |= 0x80
    for page in range(pages):                           # laterais
        fb[page * width] = 0xFF
        fb[page * width + width - 1] = 0xFF
    for x in range(width):                              # diagonal
        y = x * height // width
        fb[(y // 8) * width + x] |= 1 << (y % 8)
    return fb


def patterns(width, height):
    return [
        ("tudo aceso", fb_blank(0xFF, width, height)),
        ("tudo apagado", fb_blank(0x00, width, height)),
        ("xadrez", fb_checker(width, height)),
        ("metades", fb_halves(width, height)),
        ("moldura + diagonal", fb_border(width, height)),
    ]


# --------------------------------------------------------------------------- #
# Controlador
# --------------------------------------------------------------------------- #
class OLED:
    def __init__(self, fd, width=128, height=64, controller="ssd1306"):
        self.fd = fd
        self.width = width
        self.height = height
        self.controller = controller
        self.col_offset = 2 if controller == "sh1106" else 0

    # -- primitivas ---------------------------------------------------------
    def _cmd(self, *cmds):
        os.write(self.fd, bytes([0x00]) + bytes(cmds))   # Co=0, D/C#=0

    def _data(self, payload):
        for off in range(0, len(payload), CHUNK):
            os.write(self.fd, bytes([0x40]) + bytes(payload[off:off + CHUNK]))

    # -- API ----------------------------------------------------------------
    def init(self):
        com_pins = 0x12 if self.height == 64 else 0x02

        if self.controller == "sh1106":
            # SH1106 não tem charge pump nem memory-mode; escrita é page mode
            # e a coluna 0 do painel começa no offset 2.
            seq = [0xAE,                       # display off
                   0xA1, 0xC8,                 # remap + COM scan dec
                   0xDA, com_pins,             # COM pins
                   0x81, 0xCF,                 # contraste
                   0xD9, 0x22, 0xDB, 0x35,     # pre-charge / VCOMH
                   0xA4, 0xA6, 0x2E, 0xAF]     # RAM, normal, scroll off, on
        else:
            seq = [0xAE,                       # display off
                   0xD5, 0x80,                 # clock div
                   0xA8, self.height - 1,      # multiplex
                   0xD3, 0x00,                 # display offset
                   0x40,                       # start line 0
                   0x8D, 0x14,                 # charge pump on
                   0x20, 0x00,                 # memory mode: horizontal
                   0xA1, 0xC8,                 # remap + COM scan dec
                   0xDA, com_pins,             # COM pins
                   0x81, 0xCF,                 # contraste
                   0xD9, 0xF1,                 # pre-charge
                   0xDB, 0x40,                 # VCOMH
                   0xA4, 0xA6, 0x2E, 0xAF]     # RAM, normal, scroll off, on
        self._cmd(*seq)

    def show(self, fb):
        pages = self.height // 8
        for page in range(pages):
            self._cmd(0xB0 + page,                # página
                      0x00 + (self.col_offset & 0x0F),   # coluna baixa
                      0x10 + (self.col_offset >> 4))     # coluna alta
            self._data(fb[page * self.width:(page + 1) * self.width])

    def all_on(self):
        self._cmd(0xA5)                           # toda a RAM em 1
        self._cmd(0xAF)

    def normal(self):
        self._cmd(0xA4)                           # volta a seguir a RAM

    def sleep(self):
        self._cmd(0xAE)

    def wake(self):
        self._cmd(0xAF)


# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Teste de fumaça de OLED I2C.")
    ap.add_argument("--bus", default=DEFAULT_BUS)
    ap.add_argument("--addr", default="0x3C")
    ap.add_argument("--height", type=int, default=64, choices=(32, 64))
    ap.add_argument("--controller", default="ssd1306",
                    choices=("ssd1306", "sh1106"))
    ap.add_argument("--delay", type=float, default=2.5,
                    help="segundos por padrão")
    ap.add_argument("--hold", action="store_true", help="para no último padrão")
    ap.add_argument("--soak", type=float, default=0, metavar="SEG",
                    help="redesenha um padrão por N segundos")
    ap.add_argument("--pattern", default="moldura",
                    help="padrão do --soak (prefixo do nome)")
    ap.add_argument("--all-on", type=float, default=0, metavar="SEG",
                    help="teste do controlador: tudo aceso por N segundos")
    ap.add_argument("--variants", action="store_true",
                    help="testa SSD1306/SH1106 x 128x32/128x64 com tudo aceso")
    args = ap.parse_args()

    addr = int(args.addr, 0)
    fd = bus_open(args.bus, addr)

    if args.variants:
        variants = [
            ("ssd1306", 64, 0xCF),
            ("ssd1306", 64, 0xFF),
            ("sh1106", 64, 0xCF),
            ("ssd1306", 32, 0xCF),
            ("sh1106", 32, 0xCF),
        ]
        for i, (ctrl, height, contrast) in enumerate(variants, 1):
            print("[%d/%d] %s 128x%d contraste 0x%02X -> tudo aceso 4 s"
                  % (i, len(variants), ctrl.upper(), height, contrast), flush=True)
            oled = OLED(fd, 128, height, ctrl)
            oled.init()
            oled._cmd(0x81, contrast)
            oled.all_on()
            time.sleep(4)
            oled.normal()
            oled.sleep()
            time.sleep(0.5)
        print("fim das variantes.", flush=True)
        os.close(fd)
        return

    oled = OLED(fd, 128, args.height, args.controller)
    print("%s @ %s 0x%02X · 128x%d"
          % (args.controller.upper(), args.bus, addr, args.height), flush=True)

    oled.init()
    oled.show(fb_blank(0x00, 128, args.height))
    time.sleep(0.1)

    for name, fb in patterns(128, args.height):
        print("  -> %s" % name, flush=True)
        oled.show(fb)
        time.sleep(args.delay)

    if args.all_on > 0:
        print("teste do controlador: tudo aceso por %.0f s" % args.all_on,
              flush=True)
        oled.all_on()
        time.sleep(args.all_on)
        oled.normal()
        print("  -> modo normal de volta", flush=True)

    if args.soak > 0:
        chosen = [(n, f) for n, f in patterns(128, args.height)
                  if n.startswith(args.pattern)]
        name, fb = (chosen or patterns(128, args.height)[-1:])[0]
        print('soak: redesenhando "%s" por %.0f s (Ctrl+C para sair)'
              % (name, args.soak), flush=True)
        end = time.time() + args.soak
        while time.time() < end:
            oled.show(fb)
            time.sleep(0.05)

    if args.hold:
        oled.show(patterns(128, args.height)[-1][1])

    print("fim. Se os 5 padrões apareceram, a fiação está correta.", flush=True)
    os.close(fd)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
