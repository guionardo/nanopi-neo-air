# 14 — Display LCD Nokia 5110 (PCD8544 84x48)

Ligação elétrica e teste do display que vai mostrar CPU, memória, uptime e IP
([B-001 no backlog](13-backlog.md#b-001--display-lcd-nokia-5110-84x48)).

Este documento é a parte **física**; o conteúdo da tela e o daemon ficam no
backlog até o hardware estar validado.

## O que já está pronto no sistema

Verificado na placa em 2026-11-14:

```text
$ ls -l /dev/spidev0.0
crw------- 1 root root 153, 0 /dev/spidev0.0

$ cat /sys/class/spi_master/spi0/device/modalias
of:NspiT<NULL>Callwinner,sun8i-h3-spi

$ cat /sys/bus/spi/devices/spi0.0/of_node/compatible
nanopi,spidev
```

| Item | Estado |
| --- | --- |
| Controlador SPI0 | habilitado no DTB (`1c68000.spi`), `status = "okay"` |
| Pinos do barramento | `PC0` (MOSI), `PC1` (MISO), `PC2` (CLK) já em função `spi0` |
| Dispositivo | `spidev0.0` criado no boot, `compatible = nanopi,spidev` |
| Módulo de kernel | `spidev` compilado dentro do kernel (não aparece no `lsmod`) |
| `python3` | 3.11, **sem** o pacote `spidev` — o teste usa `ioctl` via `fcntl` |
| Compilador | não é necessário — o teste usa só a biblioteca padrão |

O `pitft@0` do DTB (um ST7789V de 2,8") está **`status = "disabled"`**, então não
disputa o barramento. Não há framebuffer de display (`/dev/fb0` é o do console,
do próprio driver de vídeo do SoC).

## Pinagem do módulo

O breakout do PCD8544 tem 8 pinos. Os nomes variam um pouco entre fabricantes;
os equivalentes estão na primeira coluna.

| Módulo | Alias comum | Pino GPIO1 | Função na placa | GPIO Linux |
| --- | --- | --- | --- | --- |
| `VCC` | `VDD`, `3V3` | **1** (ou 17) | `SYS_3.3V` | — |
| `GND` | `GND` | **6** (ou 9, 14, 20) | `GND` | — |
| `SCLK` | `CLK`, `SCK` | **23** | `SPI0_CLK` | `PC2` = 66 |
| `DIN` | `MOSI`, `DN`, `SDA` | **19** | `SPI0_MOSI` | `PC0` = 64 |
| `CS` | `SCE`, `CE` | **24** | `SPI0_CS` | `PC3` = 67 |
| `DC` | `D/C`, `A0` | **16** | `UART1_RTS` | `PG8` = 200 |
| `RST` | `RES`, `RST` | **18** | `UART1_CTS` | `PG9` = 201 |
| `LED` | `BL`, `LED+` | **7** | `GPIOG11` (via transistor) | `PG11` = 203 |

### Por que esses pinos e não os "óbvios"

- **`DC` e `RST` não podem ir nos pinos 11/22.** Esses são `PA0`/`PA1`, e o
  device tree entrega os dois para o **UART2** (`1c28800.serial` já está com a
  função `uart2` travada neles). Exportá-los como GPIO quebra a serial.
- **`PA6` (pino 12) está reservado pelo próprio SPI0.** O DTB declara
  `cs-gpios` com duas entradas — `PC3` e `PA6` — e deixa `PA6` como saída em
  nível baixo, pensando no `pitft` desabilitado. Funciona como GPIO, mas é
  território de outro driver: melhor não usar.
- **`PG8`/`PG9` (pinos 16/18) estão livres.** O UART1 está ativo só em `PG6`/`PG7`
  (pinos 8/10); os pinos de *flow control* não são usados. Confirmado com
  `export` + `direction out` + `value` nos três GPIOs, bem como `PG11`.

## Mapa do header com o display ligado

```text
        GPIO1 (24 pinos)                    módulo PCD8544
  1  3V3  ───────────────────────────────  VCC
  2  5V   (não usar)
  3  I2C0_SDA
  4  5V   (não usar)
  5  I2C0_SCL
  6  GND  ───────────────────────────────  GND
  7  PG11 ──[transistor]─────────────────  LED (backlight, opcional)
  8  UART1_TX (livre)
  9  GND
 10  UART1_RX (livre)
 11  UART2_TX ← ocupado pela serial
 12  PA6     ← reservado pelo SPI0 (pitft)
 13  UART2_RTS ← ocupado pela serial
 14  GND
 15  UART2_CTS ← ocupado pela serial
 16  PG8  ───────────────────────────────  DC
 17  3V3  (alternativa para VCC)
 18  PG9  ───────────────────────────────  RST
 19  PC0  ───────────────────────────────  DIN (MOSI)
 20  GND
 21  PC1  (MISO — o PCD8544 não transmite, fica vazio)
 22  UART2_RX ← ocupado pela serial
 23  PC2  ───────────────────────────────  SCLK
 24  PC3  ───────────────────────────────  CS
```

O módulo é **write-only**: o pino `MISO` (pino 21) fica sem ligação. Aproveite
para deixá-lo fora do conector — 7 fios bastam (8 se usar o backlight em GPIO).

## A armadilha do CS (leia antes de soldar)

Aqui o kernel **não** aciona o chip select. Isso é contraintuitivo e custa uma
tarde de depuração se não for levado em conta:

```text
$ grep PC3 /sys/kernel/debug/pinctrl/*/pinmux-pins
pin 67 (PC3): 1c68000.spi (GPIO UNCLAIMED) function gpio_out group PC3
```

Três coisas ao mesmo tempo:

1. `PC3` está em função **`gpio_out`**, não em `spi0` — o hardware não toggla o CS.
2. `(GPIO UNCLAIMED)` — nenhum driver tomou o GPIO, sobra para o userspace.
3. O nível de repouso é **alto** (CS desacionado): com o buffer do módulo
   ignorando tudo, a tela fica em branco e parece "display queimado".

O driver SPI do Allwinner nesse kernel 4.14 ignora `cs-gpios`; o vendor resolveu
isso no `fbtft`, que não está habilitado. Então há duas saídas:

| Opção | Como | Quando usar |
| --- | --- | --- |
| **A. CS no pino 24, controlado por software** | `gpio 67` para baixo antes do byte, para cima depois | padrão; permite outro device no barramento no futuro |
| **B. CS aterrado** | jumper do pino 24 para `GND` (pino 20) | teste de bancada; é um único escravo, write-only, não há conflito |

O script de teste aceita as duas (`--cs 67` ou `--cs-gnd`).

## Cuidados elétricos

| Risco | Regra |
| --- | --- |
| Alimentação | `VCC` **só** em `SYS_3.3V` (pino 1 ou 17). 5 V queima o módulo nu |
| Módulo com level shifter | alguns breakouts têm shifted logic e pedem 5 V no `VCC`; nesse caso os sinais continuam 3,3 V — **confira a serigrafia antes** |
| Backlight | o `LED` vai ao 3,3 V **por resistor** (220–330 Ω) ou por transistor; não ligue direto num GPIO (limite ~20 mA/pino no H3) |
| Corrente total | lógica ~10 mA + backlight ~15 mA: folgado no regulador da placa |
| Velocidade SPI | o `spidev0.0` está configurado para 10 MHz; o **PCD8544 aceita no máximo 4 MHz** — o driver deve pedir 1–4 MHz na transferência |
| Fios | até ~30 cm sem problema nessa velocidade; mantenha longe da antena do AP6212 e confira o RSSI depois de montar |

Sequência de conferência com multímetro, **antes** de energizar:

1. continuidade pino a pino do cabo (sem curtos entre vizinhos);
2. `VCC` do módulo contra `GND`: sem continuidade;
3. com a placa ligada: 3,3 V entre `VCC` e `GND` do módulo;
4. só então conecte `SCLK`/`DIN`/`CS`/`DC`/`RST`.

## Teste de fumaça

O script [`scripts/pcd8544-smoke-test.py`](../scripts/pcd8544-smoke-test.py)
inicializa o controlador e desenha padrões de teste — serve para provar a fiação
antes de existir qualquer daemon. Ele não instala nada: fala com `/dev/spidev0.0`
por `ioctl` da biblioteca padrão.

```bash
# na placa, com o display ligado
python3 /root/pcd8544-smoke-test.py --cs 67

# se o CS estiver aterrado
python3 /root/pcd8544-smoke-test.py --cs-gnd

# ajustar contraste (0x80–0xFF) e velocidade
python3 /root/pcd8544-smoke-test.py --contrast 0xC8 --speed 2000000
```

O script pinta, em sequência: tudo preto, tudo branco, xadrez, metades e
moldura com diagonal. Se aparecerem os cinco padrões, a fiação está correta.

### Evidência de que o barramento funciona

Rodado na placa **sem o display ligado**, só para provar que o `/dev/spidev0.0`
aceita as transferências e que os GPIOs respondem:

```text
$ python3 /root/pcd8544-smoke-test.py --delay 0.2
SPI /dev/spidev0.0 @ 4000000 Hz · DC=200 RST=201 CS=67 · contraste=0xBF
  -> tudo preto
  -> tudo branco
  -> xadrez
  -> metades
  -> moldura + diagonal
fim. Se os 5 padrões apareceram, a fiação está correta.

$ cat /sys/bus/spi/devices/spi0.0/statistics/bytes_tx   # 0 -> 2536
$ cat /sys/bus/spi/devices/spi0.0/statistics/errors     # 0
```

2536 bytes = 5 quadros de 504 B + 6 comandos de init + 2 comandos de endereço
por quadro. Nenhum erro do controlador.

### Se não aparecer nada

| Sintoma | Causa provável |
| --- | --- |
| Tela totalmente branca (backlight aceso, sem pixels) | `RST` errado ou `CS` não acionado (ver seção acima) |
| Nada, nem backlight | `VCC`/`GND` invertidos ou cabo solto |
| Metade da tela acesa, outra apagada | `DC` invertido com `RST` |
| Padrões "fantasma"/fracos | contraste muito baixo: `--contrast 0xD0` |
| Tudo preto | contraste alto demais ou tensão baixa na fonte |
| Troca de padrão aparece deslocada em colunas | `SCLK` e `DIN` trocados |

Depois de validar, o próximo passo é o coletor de status (`/run/nanopi-status.json`)
e o renderizador descritos em [B-001](13-backlog.md#b-001--display-lcd-nokia-5110-84x48).

## Pendências desta etapa

- [ ] confirmar a variante do breakout (3,3 V puro ou com level shifter/5 V)
- [ ] decidir CS por software (pino 24) ou aterrado
- [ ] decidir backlight fixo ou com transistor em `PG11`
- [ ] rodar o teste de fumaça e registrar o resultado no log de bordo
- [ ] medir o RSSI do Wi-Fi depois de montar o display
