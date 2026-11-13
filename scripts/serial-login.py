#!/usr/bin/env python3
"""Login e execucao de comandos pelo console serial, dirigido por prompts.

Diferente de serial-sh.py, este script espera o prompt aparecer antes de
enviar cada coisa (evita mandar senha antes do `Password:`).

Uso:
  ./serial-login.py --user pi --pass fa --cmd "uname -a" --cmd "ls /"
"""
import argparse
import os
import re
import select
import sys
import termios
import time

ANSI = re.compile(rb"\x1b\[[0-9;?]*[a-zA-Z]")


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


class Con:
    def __init__(self, fd):
        self.fd = fd
        self.buf = bytearray()

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    chunk = os.read(self.fd, 65536)
                except BlockingIOError:
                    continue
                if chunk:
                    self.buf.extend(ANSI.sub(b"", chunk))
                    if len(self.buf) > 200_000:
                        del self.buf[:-100_000]

    def text(self, n=4000):
        return bytes(self.buf[-n:]).replace(b"\x00", b"").decode(
            "utf-8", "replace")

    def wait_for(self, pattern, timeout):
        rx = re.compile(pattern.encode() if isinstance(pattern, str) else pattern)
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.1)
            m = rx.search(bytes(self.buf))
            if m:
                return True
        return False

    def send(self, line):
        os.write(self.fd, line.encode() + b"\r")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--user", default="pi")
    ap.add_argument("--pass", dest="password", default="fa")
    ap.add_argument("--cmd", action="append", default=[])
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--wait", type=float, default=4.0,
                    help="espera por comando apos enviar")
    ap.add_argument("--no-login", action="store_true")
    args = ap.parse_args()

    fd = open_port(args.port)
    con = Con(fd)
    try:
        if not args.no_login:
            con.pump(1.0)
            if not re.search(rb"login:", bytes(con.buf)):
                con.send("")
                con.wait_for("login:", 5)
            con.send(args.user)
            if not con.wait_for("Password:", 6):
                print("nao apareceu Password:", file=sys.stderr)
                print(con.text(600), file=sys.stderr)
                return 2
            con.send(args.password)
            con.pump(3.5)
            if re.search(r"Login incorrect", con.text(2000)):
                print("LOGIN FALHOU", file=sys.stderr)
                print(con.text(800), file=sys.stderr)
                return 3
            print("LOGIN OK", file=sys.stderr)

        for cmd in args.cmd:
            con.buf.clear()
            con.send(cmd)
            con.pump(args.wait)
            print(f"### {cmd}")
            print(con.text(4000).strip())
            print()
    finally:
        os.close(fd)


if __name__ == "__main__":
    sys.exit(main())
