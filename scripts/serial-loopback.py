#!/usr/bin/env python3
"""Teste de loopback da serial: TX do adaptador ligado no RX dele mesmo.

Uso:
  1. Desconecte os fios do header da placa.
  2. Encoste/junte o fio TX do adaptador no fio RX do adaptador (só esses dois).
  3. ./scripts/serial-loopback.py

Se o adaptador estiver bom, o que voce enviar volta identico. Se voltar so
0x00 (ou nada), o receptor do adaptador esta morto/flutuando.
"""
import os
import select
import sys
import termios
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
PADRAO = b"LOOPBACK-PL2303-0123456789\r\n"

fd = os.open(PORT, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
i, o, c, l, _, _, cc = termios.tcgetattr(fd)
i &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK | termios.ISTRIP |
       termios.INLCR | termios.IGNCR | termios.ICRNL | termios.IXON |
       termios.IXOFF)
o &= ~termios.OPOST
l &= ~(termios.ECHO | termios.ECHONL | termios.ICANON | termios.ISIG |
       termios.IEXTEN)
c &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)
c |= termios.CS8 | termios.CREAD | termios.CLOCAL
c &= ~termios.CRTSCTS
cc[termios.VMIN] = 0
cc[termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, [i, o, c, l, termios.B115200,
                                        termios.B115200, cc])
termios.tcflush(fd, termios.TCIOFLUSH)

os.write(fd, PADRAO)
os.write(fd, PADRAO)

data = bytearray()
fim = time.time() + 3
while time.time() < fim:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            data += os.read(fd, 4096)
        except BlockingIOError:
            pass
os.close(fd)

nul = bytes(data).count(0)
limpo = bytes(data).replace(b"\x00", b"")
print(f"enviado : {len(PADRAO) * 2} bytes")
print(f"recebido: {len(data)} bytes ({nul} NULs, {len(limpo)} de texto)")
print(f"texto   : {limpo!r}")

if PADRAO in bytes(data):
    print("\nRESULTADO: adaptador OK — TX e RX funcionam.")
    print("O problema esta na fiacao ou no pino da placa.")
elif len(data) and nul == len(data):
    print("\nRESULTADO: so 0x00 — receptor do adaptador flutuando/queimado.")
    print("Sem loopback, o TX/RX do adaptador nao se comunicam: adaptador ruim.")
elif not data:
    print("\nRESULTADO: nada recebido — TX do adaptador nao sai ou RX nao le.")
else:
    print("\nRESULTADO: lixo nao-NUL — baud/ruido; adaptador parcialmente funcional.")
