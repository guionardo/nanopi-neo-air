#!/usr/bin/env python3
"""Probe/console serial minimalista, sem dependencias externas.

Uso:
  ./serial-console.py                 # apenas escuta 10s
  ./serial-console.py --send 'cmd'    # envia cmd + CR e escuta 10s
  ./serial-console.py --listen 30     # escuta 30s
  ./serial-console.py --interactive   # console interativo (Ctrl-] para sair)

Porta padrao: /dev/ttyUSB0, 115200 8N1.
"""
import argparse
import os
import select
import sys
import termios
import time
import tty

DEFAULT_PORT = "/dev/ttyUSB0"
DEFAULT_BAUD = 115200

BAUDS = {
    9600: termios.B9600, 19200: termios.B19200, 38400: termios.B38400,
    57600: termios.B57600, 115200: termios.B115200, 230400: termios.B230400,
}


def open_port(port, baud):
    # O_NONBLOCK evita travar no open() esperando DCD/carrier.
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)

    iflag, oflag, cflag, lflag, ispeed, ospeed, cc = attrs
    iflag &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK |
               termios.ISTRIP | termios.INLCR | termios.IGNCR |
               termios.ICRNL | termios.IXON | termios.IXOFF)
    oflag &= ~termios.OPOST
    lflag &= ~(termios.ECHO | termios.ECHONL | termios.ICANON |
               termios.ISIG | termios.IEXTEN)
    cflag &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)
    cflag |= termios.CS8 | termios.CREAD | termios.CLOCAL
    cflag &= ~termios.CRTSCTS

    speed = BAUDS[baud]
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0

    termios.tcsetattr(fd, termios.TCSANOW,
                      [iflag, oflag, cflag, lflag, speed, speed, cc])
    termios.tcflush(fd, termios.TCIOFLUSH)  # descarta lixo anterior
    return fd


def read_for(fd, seconds, out=sys.stdout):
    deadline = time.time() + seconds
    total = 0
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], min(0.3, deadline - time.time()))
        if not r:
            continue
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            continue
        except OSError as exc:
            print(f"\n[erro de leitura: {exc}]", file=sys.stderr)
            break
        if not chunk:
            continue
        total += len(chunk)
        out.write(chunk.decode("utf-8", errors="replace"))
        out.flush()
    return total


def interactive(fd):
    print("[console serial — Ctrl-] para sair]", file=sys.stderr)
    old = termios.tcgetattr(sys.stdin.fileno())
    try:
        tty.setraw(sys.stdin.fileno())
        while True:
            r, _, _ = select.select([fd, sys.stdin], [], [], 0.3)
            if fd in r:
                data = os.read(fd, 4096)
                if data:
                    os.write(sys.stdout.fileno(), data)
            if sys.stdin in r:
                data = os.read(sys.stdin.fileno(), 1024)
                if data == b"\x1d":  # Ctrl-]
                    break
                os.write(fd, data)
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=DEFAULT_PORT)
    ap.add_argument("--baud", type=int, default=DEFAULT_BAUD, choices=BAUDS)
    ap.add_argument("--listen", type=float, default=10.0,
                    help="segundos de escuta (padrao 10)")
    ap.add_argument("--send", action="append", default=[],
                    help="linha a enviar antes de escutar (pode repetir)")
    ap.add_argument("--interactive", action="store_true")
    args = ap.parse_args()

    try:
        fd = open_port(args.port, args.baud)
    except FileNotFoundError:
        sys.exit(f"porta nao encontrada: {args.port}")
    except PermissionError:
        sys.exit(f"sem permissao em {args.port} — usuario no grupo dialout?")
    except OSError as exc:
        sys.exit(f"falha ao abrir {args.port}: {exc}")

    try:
        if args.interactive:
            interactive(fd)
            return

        for line in args.send:
            os.write(fd, line.encode() + b"\r")
            time.sleep(0.4)
        total = read_for(fd, args.listen)
        print(f"\n[recebidos {total} bytes em {args.listen:.0f}s]",
              file=sys.stderr)
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
