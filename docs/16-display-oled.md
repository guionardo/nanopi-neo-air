# 16 — Display OLED I2C (SSD1306 128x64)

Segundo caminho para o painel de status do [B-001](13-backlog.md#b-001--display-lcd-nokia-5110-84x48):
em vez do LCD Nokia 5110 no SPI, um OLED de 0,96" no **I2C0** — dois fios de
sinal, sem chip select por software e sem *shift register*.

O LCD continua documentado em [14-display-lcd.md](14-display-lcd.md); nada foi
descartado. Este documento registra a ligação, o diagnóstico e as ferramentas.

**Estado em 2026-11-18:** o módulo **responde no I2C** (ACK em `0x3C`), mas o
painel ainda não acendeu. Investigação em andamento — ver "Resultado até agora".

## Ligação

| OLED | Header (GPIO1) | Sinal |
| --- | --- | --- |
| `GND` | pino **6** (ou 9, 14, 20) | GND |
| `VCC` | pino **1** (ou 17) — `SYS_3.3V` | 3,3 V |
| `SDA` | pino **3** | `I2C0_SDA` / `PA12` |
| `SCL` | pino **5** | `I2C0_SCL` / `PA11` |

Cuidados:

- **`SDA` e `SCL` trocados não queimam nada, mas não funcionam** — e o sintoma
  engana: as duas linhas continuam em 3,3 V (pull-up do módulo), a varredura do
  `i2cdetect` "passa" sem erro e **nenhum** endereço responde. Foi a causa de
  boa parte da sessão 16.
- **Não alimentar em 5 V sem conferir os níveis.** O SSD1306 é um chip de 3,3 V;
  a maioria dos módulos aceita 5 V no `VCC` porque tem um LDO a bordo. O risco
  está nos pull-ups: se eles estiverem ligados ao `VCC` do módulo (e não à saída
  do LDO), `SDA`/`SCL` vão a 5 V em repouso, acima do máximo do `PA11`/`PA12`.
  Antes de ligar o I2C com o módulo em 5 V, meça `SDA` e `SCL` no módulo: tem que
  dar ~3,3 V.
- Módulos de **7 pinos** (`GND VCC SCL SDA RES DC CS`) normalmente vêm
  configurados para SPI; nesses, só os quatro primeiros são usados no modo I2C.

## Endereços

| Serigrafia do módulo | Endereço de 8 bits | Endereço de 7 bits (usar no Linux) |
| --- | --- | --- |
| `0x78` | escrita | `0x3C` |
| `0x7A` | escrita | `0x3D` |

O Linux sempre fala em 7 bits: `i2cdetect` mostra `3c`/`3d` e o script recebe
`--addr 0x3C`. Metade dos tutoriais mostra o valor de 8 bits — daí a confusão.

## O que o sistema já tem

Verificado na placa em 2026-11-17 (trixie, kernel 4.14.111):

```text
$ ls -l /dev/i2c-0
crw-rw---- 1 root i2c 89, 0 /dev/i2c-0
$ grep "pin 1[12] " /sys/kernel/debug/pinctrl/*/pinmux-pins
pin 11 (PA11): 1c2ac00.i2c (GPIO UNCLAIMED) function i2c0 group PA11
pin 12 (PA12): 1c2ac00.i2c (GPIO UNCLAIMED) function i2c0 group PA12
```

| Item | Estado |
| --- | --- |
| Controlador | `i2c@01c2ac00` (`mv64xxx`), `status = "okay"`, é o `/dev/i2c-0` |
| Pinos | `PA11` (SCL) e `PA12` (SDA) já em função `i2c0` |
| Ferramentas | `i2ctools` presente (`i2cdetect`, `i2cget`) |
| Python | 3.11 **sem** `smbus`, `smbus2` ou `luma.oled` — os scripts usam `ioctl` |
| Pull-up | **nenhum** interno: `pinconf` mostra `input bias disabled` nos dois pinos |
| `i2c-3` | é o DDC do HDMI (`DesignWare HDMI`) — não é header |

O barramento depende inteiramente do pull-up do módulo. Sem display plugado, as
linhas flutuam, o controlador as considera ocupadas e o `i2cdetect` **trava** com:

```text
i2c i2c-0: mv64xxx: I2C bus locked, block: 1, time_left: 0
```

Isso não é defeito — é o comportamento esperado de um barramento sem pull-up.

## Ferramentas

### `scripts/ssd1306-smoke-test.py`

Teste de fumaça que não instala nada: fala com `/dev/i2c-0` por `ioctl` e
desenha padrões direto no controlador.

```bash
python3 ssd1306-smoke-test.py                  # SSD1306 128x64 em 0x3C
python3 ssd1306-smoke-test.py --addr 0x3D      # módulo no endereço alternativo
python3 ssd1306-smoke-test.py --height 32      # painel 128x32
python3 ssd1306-smoke-test.py --controller sh1106
python3 ssd1306-smoke-test.py --all-on 15      # teste do controlador: tudo aceso
python3 ssd1306-smoke-test.py --variants       # matriz de init (ver abaixo)
```

Padrões: tudo aceso, tudo apagado, xadrez, metades e moldura + diagonal.

`--all-on` é o teste mais importante: usa o comando `0xA5` do controlador, que
acende a tela inteira **sem depender do framebuffer**. Ele separa dois mundos:

| `--all-on` | Significado |
| --- | --- |
| a tela acende | o controlador recebe comandos e o painel funciona: o problema é nos dados/contraste |
| nada acontece | o controlador não está recebendo nada, ou o painel não é excitado (charge pump/variante) |

`--variants` tenta, em sequência, `SSD1306`/`SH1106` × `128x32`/`128x64`, com
contraste `0xCF` e `0xFF`, cada uma com "tudo aceso" por 4 s.

### `scripts/i2c-bb-probe.py`

I2C bit-banged em `PA11`/`PA12` pelo sysfs. Serve para separar **defeito do
controlador** de **defeito do módulo**: se o controlador não completa nem o probe
de endereço, este script responde se o escravo está vivo.

```bash
D=/sys/bus/platform/drivers/mv64xxx_i2c
echo 1c2ac00.i2c > $D/unbind        # o pino precisa estar livre
python3 i2c-bb-probe.py             # probe em 0x3C
python3 i2c-bb-probe.py --scan      # varre 0x08..0x77
echo 1c2ac00.i2c > $D/bind
```

Ele emula open-drain alternando `direction` entre `out` (0) e `in` (liberado,
quem puxa é o pull-up do módulo). O clock fica em ~5 kHz — lento e fácil de
ver no osciloscópio.

### Ler o nível real de um pino multiplexado

`devmem` no `PADAT` do SoC **não serve**: em pino multiplexado o registrador
mostra o último valor de saída, não o nível do pad. Para medir de verdade,
tire o controlador do caminho:

```bash
D=/sys/bus/platform/drivers/mv64xxx_i2c
echo 1c2ac00.i2c > $D/unbind
echo 11 > /sys/class/gpio/export
echo in > /sys/class/gpio/gpio11/direction
cat /sys/class/gpio/gpio11/value     # 1 = linha em 3,3 V
echo 11 > /sys/class/gpio/unexport
echo 1c2ac00.i2c > $D/bind
```

### Identificar os pads sem contar pinos

Quando a contagem do header é suspeita, coloque `PA11` e `PA12` como saída com
duty cycles diferentes e leia a **média** no multímetro:

| Pino | Duty | Média esperada |
| --- | --- | --- |
| `PA11` = SCL (pino 5) | 25% | ~0,8 V |
| `PA12` = SDA (pino 3) | 75% | ~2,5 V |

Assim os dois pads se identificam em qualquer ponto da montagem. O laço completo
usado na bancada (4 s de período, 7 minutos) está na sessão 16 do
[log de bordo](12-log-de-bordo.md).

## Diagnóstico rápido

| Sintoma | Causa provável | Como confirmar |
| --- | --- | --- |
| `i2cdetect` trava | barramento sem pull-up (sem display/desligado) | `dmesg` mostra `I2C bus locked` |
| Varredura passa, nada aparece | `SDA`/`SCL` trocados, ou módulo sem alimentação | medir 3,3 V em `SDA` e `SCL` no módulo |
| `i2cget` dá `Read failed` | normal: o SSD1306 é write-only para registradores | usar `i2cdetect` para presença |
| Nenhum ACK no bit-bang | módulo não responde (fiação ou defeito) | `i2c-bb-probe.py --scan` |
| ACK em `0x3C`, tela apagada | variante (SH1106), contraste ou charge pump | `--all-on` + `--variants` |

## Resultado até agora

Confirmado na bancada (2026-11-17/18):

- `SDA`/`SCL` trocados explicavam a ausência total de ACK: com a ordem correta,
  `i2cdetect` mostrou `3c`;
- `ssd1306-smoke-test.py` rodou os 5 padrões e o `--all-on` sem erro de I2C;
- **o painel não acendeu** em nenhuma das 5 variantes de `--variants`;
- o LCD Nokia 5110 montado em paralelo também nunca acendeu, mesmo com `CE`,
  `RST` e `DC` confirmados no osciloscópio e `--all-on` sem resposta.

Próximo passo: energizar o módulo em **5 V** (medindo antes os níveis de
`SDA`/`SCL`, conforme o cuidado acima) para descartar LDO/charge pump, e testar o
módulo em outra placa (Arduino/Raspberry) antes de descartá-lo.

## Pendências

- [x] ~~confirmar que o I2C0 está habilitado no DTB~~ — `/dev/i2c-0` em `PA11`/`PA12`
- [x] ~~descobrir o endereço~~ — `0x3C` (8 bits `0x78`); alternativa `0x3D` (`0x7A`)
- [x] ~~script de teste sem dependências~~ — `ssd1306-smoke-test.py`
- [x] ~~separar defeito de controlador e de módulo~~ — `i2c-bb-probe.py`
- [ ] fazer o painel acender (5 V com verificação de nível, ou variante correta)
- [ ] validar o módulo em outra placa antes de descartar
- [ ] escrever o daemon de status e o serviço systemd (ver B-001)
