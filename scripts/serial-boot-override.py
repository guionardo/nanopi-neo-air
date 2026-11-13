#!/usr/bin/env python3
"""Assume o console serial no proximo boot da placa.

Fica esperando o U-Boot, interrompe o autoboot e inicia o kernel com uma
cmdline customizada. Util quando o console esta inutilizavel (ex.: loop de
getty) e nao ha botao de reset.

Uso:
  ./serial-boot-override.py --wait 300
  ./serial-boot-override.py --wait 300 --bootargs "console=ttyS0,115200 root=/dev/mmcblk0p2 rw rootwait init=/bin/sh"

Enderecos/dtb usados sao os do uEnv.txt da imagem H3 da FriendlyElec
(h3-sd-ubuntu-noble-core). Para outra imagem, revise ADDR_* e DTB.
"""
import argparse
import os
import select
import sys
import termios
import time

ADDR_KERNEL = "0x46000000"
ADDR_RAMDISK = "0x47000000"
ADDR_DTB = "0x48000000"
DTB_NAME = "sun8i-h3-nanopi-h3.dtb"  # sobrescrito por --dtb

DEFAULT_BOOTARGS = (
    "console=ttyS0,115200 earlyprintk root=/dev/mmcblk0p2 rootfstype=ext4 "
    "rw rootwait init=/bin/sh"
)


def open_port(port, baud=115200):
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    i, o, c, l, _is, _os_, cc = termios.tcgetattr(fd)
    i &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK |
           termios.ISTRIP | termios.INLCR | termios.IGNCR |
           termios.ICRNL | termios.IXON | termios.IXOFF)
    o &= ~termios.OPOST
    l &= ~(termios.ECHO | termios.ECHONL | termios.ICANON |
           termios.ISIG | termios.IEXTEN)
    c &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)
    c |= termios.CS8 | termios.CREAD | termios.CLOCAL
    c &= ~termios.CRTSCTS
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0
    b = {9600: termios.B9600, 115200: termios.B115200,
         230400: termios.B230400}[baud]
    termios.tcsetattr(fd, termios.TCSANOW, [i, o, c, l, b, b, cc])
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


class Reader:
    def __init__(self, fd):
        self.fd = fd
        self.buf = bytearray()

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.02)
            if r:
                try:
                    self.buf.extend(os.read(self.fd, 65536))
                except BlockingIOError:
                    pass
        if len(self.buf) > 400_000:       # evita crescer sem limite
            del self.buf[:-200_000]

    def seen(self, needle, window=None):
        raw = bytes(self.buf if window is None else self.buf[-window:])
        return needle in raw

    def clear(self):
        self.buf.clear()

    def tail(self, n=300):
        return bytes(self.buf[-n:]).replace(b"\x00", b"").decode(
            "utf-8", "replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--wait", type=float, default=300,
                    help="segundos aguardando o proximo boot (padrao 300)")
    ap.add_argument("--bootargs", default=DEFAULT_BOOTARGS)
    ap.add_argument("--dtb", default="sun8i-h3-nanopi-neo-air.dtb")
    ap.add_argument("--initrd", default="rootfs.cpio.gz",
                    help="nome do initrd na particao de boot (vazio = sem initrd)")
    ap.add_argument("--listen", type=float, default=25,
                    help="segundos de captura apos iniciar o boot")
    args = ap.parse_args()

    try:
        fd = open_port(args.port)
    except (FileNotFoundError, PermissionError, OSError) as exc:
        sys.exit(f"falha ao abrir {args.port}: {exc}")

    r = Reader(fd)
    print(f"aguardando boot em {args.port} por {args.wait:.0f}s "
          f"(ligue/reinicie a placa)...", flush=True)

    deadline = time.time() + args.wait
    while time.time() < deadline:
        r.pump(0.05)
        if r.seen(b"Hit any key", 2000) or r.seen(b"Hit any key"):
            print("autoboot detectado; enviando teclas", flush=True)
            for _ in range(60):
                os.write(fd, b" ")
                time.sleep(0.03)
                r.pump(0.01)
            break
        if r.seen(b"=> ") and r.seen(b"U-Boot"):
            break              # ja estava no prompt
    else:
        print("timeout: nenhum boot detectado", flush=True)
        os.close(fd)
        sys.exit(2)

    r.pump(1.5)
    if not r.seen(b"=>", 400):
        os.write(fd, b"\r")
        r.pump(1.0)

    print("prompt U-Boot assumido; carregando kernel", flush=True)
    steps = [(f"fatload mmc 0 {ADDR_KERNEL} zImage", 2.5)]
    if args.initrd:
        steps += [(f"fatload mmc 0 {ADDR_RAMDISK} {args.initrd}", 3.0),
                  ("setenv ramdisk_size ${filesize}", 0.6)]
    steps += [(f"fatload mmc 0 {ADDR_DTB} {args.dtb}", 1.5),
              (f"setenv bootargs {args.bootargs}", 0.8)]
    for cmd, wait in steps:
        os.write(fd, cmd.encode() + b"\r")
        r.pump(wait)

    if args.initrd:
        boot = (f"bootz {ADDR_KERNEL} {ADDR_RAMDISK}:${{ramdisk_size}} "
                f"{ADDR_DTB}")
    else:
        boot = f"bootz {ADDR_KERNEL} - {ADDR_DTB}"

    print(f"iniciando: {boot}", flush=True)
    r.clear()
    os.write(fd, boot.encode() + b"\r")
    r.pump(args.listen)

    print("---- saida ----", flush=True)
    print(r.tail(2500), flush=True)
    os.close(fd)


if __name__ == "__main__":
    main()
