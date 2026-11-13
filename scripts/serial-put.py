#!/usr/bin/env python3
"""Copia um arquivo pequeno do host para a placa pelo console serial.

Sem rede, a unica via e o console. O arquivo e enviado em base64 (linhas de 76
caracteres) via `echo ... >>` e decodificado na placa com `base64 -d`.

Uso:
  ./serial-put.py --local scripts/unsparse.sh --remote /tmp/u.sh --run "bash /tmp/u.sh --help"

Requisitos na placa: `base64` (coreutils) disponivel no rootfs usado.
"""
import argparse
import base64
import os
import re
import select
import termios
import time


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", required=True)
    ap.add_argument("--remote", required=True,
                    help="caminho do arquivo .b64 DENTRO do chroot (ex.: /tmp/u.b64)")
    ap.add_argument("--prefix", default="/newroot",
                    help="prefixo do rootfs no shell externo (padrao /newroot)")
    ap.add_argument("--run", default=None, help="comando a executar depois")
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--prompt-timeout", type=float, default=6.0)
    args = ap.parse_args()

    data = open(args.local, "rb").read()
    b64 = base64.b64encode(data).decode()
    lines = [b64[i:i + 76] for i in range(0, len(b64), 76)]

    fd = open_port(args.port)
    buf = bytearray()

    def send(cmd, wait):
        os.write(fd, cmd.encode() + b"\r")
        end = time.time() + wait
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.15)
            if r:
                try:
                    chunk = os.read(fd, 65536)
                except BlockingIOError:
                    continue
                if chunk:
                    buf.extend(chunk)
                    if re.search(rb"\n?\[[^\]]*\]# ?$", bytes(buf).rstrip()):
                        return
        # segue para o proximo mesmo sem prompt

    outer = args.prefix.rstrip("/") + args.remote
    print(f"enviando {len(lines)} linhas base64 para {outer}...", flush=True)
    for i, line in enumerate(lines):
        op = ">" if i == 0 else ">>"
        send(f"echo '{line}' {op} {outer}", args.prompt_timeout)

    out = args.remote[:-4]
    send(f"chroot {args.prefix} /bin/bash -c 'base64 -d {args.remote} > "
         f"{out}; wc -c {out}'", 15)

    if args.run:
        print(f"executando: {args.run}", flush=True)
        send(f"chroot {args.prefix} /bin/bash -c {args.run!r}", 40)

    print(bytes(buf).replace(b"\x00", b"").decode("utf-8", "replace")[-3000:])
    os.close(fd)


if __name__ == "__main__":
    main()
