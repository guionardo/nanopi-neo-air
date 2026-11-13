#!/usr/bin/env python3
"""Envia comandos em lote pelo console serial e mostra a resposta.

Feito para o shell busybox do initramfs (sem `head`, sem `id`), onde digitar
interativamente pelo terminal nao e pratico.

Uso:
  ./serial-sh.py "ls /dev/mmcblk*" "cat /proc/partitions"
  ./serial-sh.py --file comandos.txt
  ./serial-sh.py --wait 1.5 "uname -a"          # espera maior por comando

Cada linha e enviada com CR e a saida e capturada ate o proximo prompt ou
pelo tempo de --wait. Prefixo de marcador `### <cmd>` facilita a leitura.
"""
import argparse
import os
import select
import sys
import termios
import time

DEFAULT_PORT = "/dev/ttyUSB0"


def open_port(port, baud=115200):
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    i, o, c, l, _is, _os, cc = termios.tcgetattr(fd)
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


def pump(fd, seconds, sink):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except BlockingIOError:
                continue
            if chunk:
                sink.extend(chunk)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("commands", nargs="*")
    ap.add_argument("--file", help="arquivo com um comando por linha")
    ap.add_argument("--port", default=DEFAULT_PORT)
    ap.add_argument("--wait", type=float, default=1.2,
                    help="espera por comando, em segundos (padrao 1.2)")
    ap.add_argument("--settle", type=float, default=0.4,
                    help="espera inicial para o shell responder")
    args = ap.parse_args()

    cmds = list(args.commands)
    if args.file:
        with open(args.file, encoding="utf-8") as fh:
            cmds += [ln.rstrip("\n") for ln in fh
                     if ln.strip() and not ln.lstrip().startswith("#")]
    if not cmds:
        sys.exit("nada a enviar (use argumentos ou --file)")

    fd = open_port(args.port)
    sink = bytearray()
    try:
        os.write(fd, b"\r")
        pump(fd, args.settle, sink)

        for cmd in cmds:
            sink.clear()
            os.write(fd, cmd.encode() + b"\r")
            deadline = time.time() + args.wait
            # encerra antes se o prompt reaparecer no fim do buffer
            while time.time() < deadline:
                pump(fd, 0.1, sink)
                tail = bytes(sink[-80:])
                if tail.rstrip().endswith((b"#", b"$", b"#")):
                    break
            text = bytes(sink).replace(b"\x00", b"").decode(
                "utf-8", "replace")
            print(f"### {cmd}")
            print(text.strip("\r\n").replace("\x1b", "").replace("[6n", ""))
            print()
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
