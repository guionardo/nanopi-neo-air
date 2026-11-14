# 08 — GPIO e barramentos

Como acionar e ler pinos com segurança. A pinagem completa está em
[00-hardware.md](00-hardware.md).

## Regras que valem antes de qualquer código

| Regra | Consequência de ignorar |
| --- | --- |
| GPIO é **3.3 V** | 5 V queima o pino ou o SoC |
| Máx. **~5 mA** por pino | acionar relé/motor direto queima o driver interno |
| Sem proteção contra inversão | ligar carga indutiva sem diodo = pino morto |
| Pino de boot pode ser crítico | usar GPIO errado no boot pode impedir o sistema de subir |

Cargas reais (relé, solenoide, LED de potência, motor) → **módulo driver**
(relé com optoacoplador, ULN2803, MOSFET). O GPIO manda sinal; o driver manda
corrente.

## Habilitar os barramentos

```bash
sudo npi-config
```

`Interfacing Options` → habilitar `I2C`, `SPI`, `Serial` (UART de aplicação),
`PWM` conforme necessidade. Reinicie depois.

> `Serial` aqui é a UART1/UART2 dos headers — **não** desative a UART0 do console
> de debug, ou você perde o acesso de recuperação.

Confirmação após reboot:

```bash
ls /dev/i2c-* /dev/spidev* /dev/ttyS* 2>/dev/null
lsmod | grep -E 'i2c|spi|pwm'
```

## Método 1 — sysfs (sem instalar nada)

Suficiente para teste e para scripts simples. Use o **número Linux gpio**
(coluna `Linux gpio` da pinagem), não o número do pino físico.

Exemplo: piscar o pino 7 (GPIOG11 = gpio **203**):

```bash
GPIO=203

echo $GPIO | sudo tee /sys/class/gpio/export
echo out    | sudo tee /sys/class/gpio/gpio$GPIO/direction
echo 1      | sudo tee /sys/class/gpio/gpio$GPIO/value
sleep 1
echo 0      | sudo tee /sys/class/gpio/gpio$GPIO/value
echo $GPIO | sudo tee /sys/class/gpio/unexport
```

Ler uma entrada (ex.: pino 12, GPIOA6 = gpio **6**):

```bash
echo 6 | sudo tee /sys/class/gpio/export
echo in | sudo tee /sys/class/gpio/gpio6/direction
cat /sys/class/gpio/gpio6/value
```

Ver todos os GPIOs exportados:

```bash
ls /sys/class/gpio/
cat /sys/kernel/debug/gpio        # mapa completo (root)
```

Limitações: sysfs é considerado legado, sem interrupções nem PWM, e não trata
pull-up/pull-down. Para aplicação, use uma biblioteca.

## Método 2 — WiringNP (C, equivalente ao WiringPi)

```bash
sudo apt install -y git build-essential
git clone https://github.com/friendlyarm/WiringNP
cd WiringNP
chmod 755 build
./build
```

Teste:

```bash
gpio -v
gpio readall        # tabela de pinos com estado atual
```

Uso em C:

```c
#include <wiringPi.h>

int main(void) {
    wiringPiSetup();          // numeração wiringPi
    pinMode(7, OUTPUT);       // pino físico 7
    for (;;) {
        digitalWrite(7, HIGH);
        delay(500);
        digitalWrite(7, LOW);
        delay(500);
    }
}
```

Compilar:

```bash
gcc -o blink blink.c -lwiringPi
./blink            # precisa de root
```

Referência oficial: [wiki: WiringNP](https://wiki.friendlyelec.com/wiki/index.php/WiringNP:_NanoPi_NEO/NEO2/Air_GPIO_Programming_with_C)

## Método 3 — RPi.GPIO_NP (Python)

O FriendlyCore já traz a biblioteca portada do RPi.GPIO (imagens a partir de
jun/2017). **Não precisa instalar**:

```python
#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time

PIN = 7                      # número do PINO FÍSICO no header
GPIO.setmode(GPIO.BOARD)      # BOARD = pino físico; BCM = numeração do SoC
GPIO.setup(PIN, GPIO.OUT)

try:
    while True:
        GPIO.output(PIN, True)
        time.sleep(1)
        GPIO.output(PIN, False)
        time.sleep(1)
finally:
    GPIO.cleanup()
```

```bash
chmod +x blink.py
sudo ./blink.py
```

Se `import RPi.GPIO` falhar:

```bash
python3 -c "import RPi.GPIO as g; print(g.VERSION)"
# ausente? instale a versão da FriendlyElec:
git clone https://github.com/friendlyarm/RPi.GPIO_NP
cd RPi.GPIO_NP && sudo python3 setup.py install
```

`GPIO.BOARD` é o modo mais seguro aqui: o número é o pino impresso no header,
igual à tabela da [pinagem](00-hardware.md).

## I2C

Barramento `i2c-0` nos pinos 3 (SDA) e 5 (SCL).

```bash
sudo apt install -y i2c-tools
sudo i2cdetect -y 0
```

```
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:          -- -- -- -- -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
50: 50 -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
```

Um endereço presente (ex.: `50` = EEPROM) confirma que o dispositivo responde.

```bash
# ler um registrador de um device em 0x50
i2cget -y 0 0x50 0x00
# escrever
i2cset -y 0 0x50 0x00 0x41
```

Em Python:

```python
import smbus
bus = smbus.SMBus(0)          # i2c-0
data = bus.read_byte_data(0x50, 0x00)
```

**Pull-ups:** módulos I2C prontos trazem resistores de pull-up. Se você soldar
um chip direto no barramento, adicione 4.7 kΩ para 3.3 V em SDA e SCL.

## SPI

`spidev0.0` — MOSI pino 19, MISO pino 21, CLK pino 23, CS pino 24.

```bash
ls /dev/spidev*
# teste de loopback: junte MOSI (19) com MISO (21) com um jumper
sudo apt install -y python3-spidev
python3 - <<'PY'
import spidev
spi = spidev.SpiDev()
spi.open(0, 0)
spi.max_speed_hz = 500000
resp = spi.xfer2([0xAA, 0x55, 0x01])
print("enviado : AA 55 01")
print("recebido:", " ".join(f"{b:02X}" for b in resp))
PY
```

Se `recebido` == `enviado`, o barramento está funcionando (loopback com jumper).

## UART de aplicação (UART1 / UART2)

| UART | TX | RX | RTS | CTS |
| --- | --- | --- | --- | --- |
| UART1 | pino 8 (gpio 198) | pino 10 (gpio 199) | 16 (200) | 18 (201) |
| UART2 | pino 11 (gpio 0) | pino 22 (gpio 1) | 13 (2) | 15 (3) |

```bash
sudo systemctl stop serial-getty@ttyS1.service 2>/dev/null   # liberar se houver getty
stty -F /dev/ttyS1 115200 raw -echo
cat /dev/ttyS1 &          # escutar
echo "teste" > /dev/ttyS1 # enviar
```

Em Python:

```python
import serial
s = serial.Serial('/dev/ttyS1', 115200, timeout=1)
s.write(b'ping\n')
print(s.readline())
```

Nível 3.3 V. Para conectar a um dispositivo RS-232 (±12 V) é obrigatório um
conversor MAX3232 — ligar direto destrói o SoC.

## PWM

O pino 4 do header de debug é `PWM0` (GPIOA5), compartilhado com UART0 RX — use
só se você não precisar do console serial. Alternativas dedicadas dependem do
muxing do kernel; verifique o que está disponível:

```bash
ls /sys/class/pwm/
```

Se existir `pwmchip0`:

```bash
CHIP=/sys/class/pwm/pwmchip0
echo 0      | sudo tee $CHIP/export
echo 1000000| sudo tee $CHIP/pwm0/period     # 1 ms = 1 kHz
echo 500000 | sudo tee $CHIP/pwm0/duty_cycle # 50%
echo 1      | sudo tee $CHIP/pwm0/enable
```

## Recepção IR (header de 12 pinos, pino 6)

Desabilitado por padrão. Habilite em `npi-config` → `Advanced Options` → `IR`,
reinicie e teste:

```bash
sudo apt install -y ir-keytable
echo "+rc-5 +nec +rc-6 +jvc +sony" | sudo tee /sys/class/rc/rc0/protocols
sudo ir-keytable -t
# pressione teclas no controle; aparecem scancodes
```

## Serviço de exemplo: rodar seu script no boot

Não use `rc.local` às cegas — use uma unit systemd, que dá log e reinício:

```ini
# /etc/systemd/system/controlador.service
[Unit]
Description=Controlador NanoPi
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/controlador.py
Restart=on-failure
RestartSec=5
User=pi
# acesso a GPIO sem root:
SupplementaryGroups=gpio

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now controlador.service
systemctl status controlador.service
journalctl -u controlador.service -f
```

## Checklist de segurança elétrica

- [ ] Toda carga tem driver (transistor/relé/MOSFET), nunca direto no GPIO
- [ ] Carga indutiva (relé, motor) tem diodo de roda-livre ou driver com opto
- [ ] Nada de 5 V em pino de 3.3 V — verificado com multímetro antes de ligar
- [ ] Fonte e GND da carga e da placa têm referência comum quando há sinal entre elas
- [ ] Testei o pino com LED + resistor 1 kΩ antes de ligar a carga real
- [ ] Sei qual pino o script usa no boot e ele não é um pino de função crítica

## Próximo passo

[09 — Operação e manutenção](09-manutencao.md)

> Ideia registrada para o futuro: display LCD Nokia 5110 (84x48, PCD8544) em SPI0
> mostrando IP, sinal, temperatura e estado dos serviços — ver
> [B-001 no backlog](13-backlog.md#b-001--display-lcd-nokia-5110-84x48).
