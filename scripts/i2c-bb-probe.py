#!/usr/bin/env python3
"""Sonda I2C bit-banged nos GPIOs do header (contorna o controlador mv64xxx).

O controlador I2C do sun8i neste kernel (4.14) às vezes não completa nem o
probe de endereço ("Ctlr Error -- state: 0x2, status: 0x0"). Este script fala
I2C "na mão", piscando PA11 (SCL, header 5) e PA12 (SDA, header 3) pelo sysfs,
e serve para separar defeito do controlador de defeito do módulo.

Open-drain emulado: para nível baixo, o pino vira saída em 0; para liberar
(nível alto), o pino volta a entrada e quem puxa é o pull-up do módulo.

Requer o i2c0 desligado (o pino precisa estar livre):

    echo 1c2ac00.i2c > /sys/bus/platform/drivers/mv64xxx_i2c/unbind
    python3 i2c-bb-probe.py
    python3 i2c-bb-probe.py --scan          # varre 0x08..0x77
    echo 1c2ac00.i2c > /sys/bus/platform/drivers/mv64xxx_i2c/bind

Uso típico: só o probe. Não instala nada e não escreve no módulo.
"""

import argparse
import os
import sys
import time

GPIO = "/sys/class/gpio"
SCL, SDA = 11, 12          # PA11 = header 5, PA12 = header 3
HALF = 0.00008             # ~6 kHz; sysfs já é lento, isto só garante setup


class Pin:
    def __init__(self, num, name):
        self.num = num
        self.name = name
        self.path = os.path.join(GPIO, "gpio%d" % num)

    def claim(self):
        if not os.path.isdir(self.path):
            try:
                with open(os.path.join(GPIO, "export"), "w") as f:
                    f.write(str(self.num))
            except OSError as exc:
                sys.exit("nao consegui exportar gpio %d (%s): o i2c0 esta ligado?"
                         % (self.num, exc.strerror))
            time.sleep(0.3)
        self.release()                     # começa liberado (alto por pull-up)

    def unclaim(self):
        try:
            with open(os.path.join(GPIO, "unexport"), "w") as f:
                f.write(str(self.num))
        except OSError:
            pass

    def _write(self, name, value):
        with open(os.path.join(self.path, name), "w") as f:
            f.write(value)

    def low(self):
        self._write("direction", "out")
        self._write("value", "0")

    def release(self):
        self._write("direction", "in")

    def read(self):
        with open(os.path.join(self.path, "value")) as f:
            return int(f.read().strip())


class SoftI2C:
    def __init__(self, scl, sda):
        self.scl = scl
        self.sda = sda

    def _tick(self):
        time.sleep(HALF)

    # -- condições ---------------------------------------------------------
    def start(self):
        self.sda.release()
        self.scl.release()
        self._tick()
        self.sda.low()                     # SDA cai com SCL alto = START
        self._tick()
        self.scl.low()
        self._tick()

    def stop(self):
        self.sda.low()
        self._tick()
        self.scl.release()
        self._tick()
        self.sda.release()                 # SDA sobe com SCL alto = STOP
        self._tick()

    # -- bits --------------------------------------------------------------
    def write_bit(self, bit):
        if bit:
            self.sda.release()
        else:
            self.sda.low()
        self._tick()
        self.scl.release()                 # borda de subida
        self._tick()
        self.scl.low()                     # borda de descida
        self._tick()

    def read_bit(self):
        self.sda.release()
        self._tick()
        self.scl.release()
        self._tick()
        bit = self.sda.read()
        self.scl.low()
        self._tick()
        return bit

    def write_byte(self, byte):
        for i in range(7, -1, -1):
            self.write_bit((byte >> i) & 1)
        return self.read_bit()             # 0 = ACK

    # -- transações --------------------------------------------------------
    def probe(self, addr7):
        self.start()
        ack = self.write_byte(addr7 << 1)
        self.stop()
        return ack == 0

    def write(self, addr7, payload):
        self.start()
        if self.write_byte(addr7 << 1) != 0:
            self.stop()
            return False
        for byte in payload:
            if self.write_byte(byte) != 0:
                self.stop()
                return False
        self.stop()
        return True


def main():
    ap = argparse.ArgumentParser(description="Sonda I2C bit-banged.")
    ap.add_argument("--scan", action="store_true", help="varre 0x08..0x77")
    ap.add_argument("--addr", default="0x3C", help="endereço 7 bits a sondar")
    args = ap.parse_args()

    scl = Pin(SCL, "SCL")
    sda = Pin(SDA, "SDA")
    scl.claim()
    sda.claim()

    bus = SoftI2C(scl, sda)
    print("bit-bang: SCL=PA11 (header 5)  SDA=PA12 (header 3)", flush=True)

    ok = False
    try:
        if args.scan:
            for addr in range(0x08, 0x78):
                if bus.probe(addr):
                    print("  ACK em 0x%02X" % addr, flush=True)
                    ok = True
            if not ok:
                print("  nenhum ACK em 0x08..0x77", flush=True)
        else:
            addr = int(args.addr, 0)
            ok = bus.probe(addr)
            print("  probe 0x%02X: %s" % (addr, "ACK" if ok else "sem resposta"),
                  flush=True)
    finally:
        scl.unclaim()
        sda.unclaim()

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
