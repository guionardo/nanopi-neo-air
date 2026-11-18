# 14 — Display LCD Nokia 5110 (PCD8544 84x48)

Ligação elétrica e teste do display que vai mostrar CPU, memória, uptime e IP
([B-001 no backlog](13-backlog.md#b-001--display-lcd-nokia-5110-84x48)).

Este documento é a parte **física**; o conteúdo da tela e o daemon ficam no
backlog até o hardware estar validado.

> **Situação em 2026-11-18:** o módulo montado nesta fiação **nunca acendeu**,
> mesmo com `CE`, `RST` e `DC` confirmados no osciloscópio e o modo de teste do
> controlador (`--all-on`) sem resposta ([sessão 16](12-log-de-bordo.md#sessão-16--2026-11-17--display-o-lcd-mudo-e-o-i2c-travado)).
> O caminho em teste passou a ser o **OLED I2C** ([16-display-oled.md](16-display-oled.md)).
> A fiação abaixo continua válida para quando o módulo for validado em outra
> placa.

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

Lido na serigrafia do módulo em mãos (2026-11-14), na ordem física:

```text
  1 RST   2 CE   3 DC   4 DIN   5 CLK   6 VCC   7 LIGHT   8 GND
  o o     o o    o o    o o     o o     o o     o o       o o
```

O breakout do PCD8544 tem 8 pinos. `CE` é o *chip enable* (CS) e `LIGHT` é o
ânodo do backlight; os nomes variam entre fabricantes e estão na coluna de
aliases.

| Pino | Rótulo | Alias comum | Vai para | GPIO Linux | Função na placa |
| --- | --- | --- | --- | --- | --- |
| 1 | `RST` | `RES` | **18** | `PG9` = 201 | `UART1_CTS` |
| 2 | `CE` | `CS`, `SCE` | **24** | `PC3` = 67 | `SPI0_CS` |
| 3 | `DC` | `D/C`, `A0` | **16** | `PG8` = 200 | `UART1_RTS` |
| 4 | `DIN` | `MOSI`, `DN`, `SDA` | **19** | `PC0` = 64 | `SPI0_MOSI` |
| 5 | `CLK` | `SCLK`, `SCK` | **23** | `PC2` = 66 | `SPI0_CLK` |
| 6 | `VCC` | `VDD`, `3V3` | **1** (ou 17) | — | `SYS_3.3V` |
| 7 | `LIGHT` | `LED`, `BL` | **jumper fechado** (sem fio) — ou 3,3 V via resistor | — | backlight |
| 8 | `GND` | `GND` | **6** (ou 9, 14, 20) | — | `GND` |

> A ordem física (RST primeiro, GND por último) é a mesma dos módulos
> "Nokia 5110" tradicionais. Ao conferir o cabo, use **rótulo**, não posição:
> um cabo invertido coloca `VCC` no `GND` e queima o módulo.

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
  1  3V3  ───────────────────────────────  VCC   (pino 6)
  2  5V   (não usar)
  3  I2C0_SDA
  4  5V   (não usar)
  5  I2C0_SCL
  6  GND  ───────────────────────────────  GND   (pino 8)
  7  PG11 (livre — dimmer futuro)
  8  UART1_TX (livre)
  9  GND
 10  UART1_RX (livre)
 11  UART2_TX ← ocupado pela serial
 12  PA6     ← reservado pelo SPI0 (pitft)
 13  UART2_RTS ← ocupado pela serial
 14  GND
 15  UART2_CTS ← ocupado pela serial
 16  PG8  ───────────────────────────────  DC    (pino 3)
 17  3V3  (alternativa para VCC)
 18  PG9  ───────────────────────────────  RST   (pino 1)
 19  PC0  ───────────────────────────────  DIN   (pino 4, MOSI)
 20  GND
 21  PC1  (MISO — o PCD8544 não transmite, fica vazio)
 22  UART2_RX ← ocupado pela serial
 23  PC2  ───────────────────────────────  CLK   (pino 5)
 24  PC3  ───────────────────────────────  CE    (pino 2, CS)

 extra: LIGHT (pino 7) → deixar sem fio se o jumper do backlight estiver fechado
       (senão: LIGHT ──[ R = 100 Ω ]── pino 1 ou 17, o mesmo 3,3 V do VCC)
```

O `LED` do backlight não vai para GPIO nenhum neste projeto: ele sai do mesmo
`SYS_3.3V` do `VCC`, passando por um resistor (ver "Cuidados elétricos"). Isso
deixa o `PG11` (pino 7) livre para um dimmer com transistor mais tarde, sem
remexer na fiação.

O módulo é **write-only**: o pino `MISO` (pino 21) fica sem ligação. São 7 fios
até o header (`VCC`, `GND`, `CLK`, `DIN`, `CE`, `DC`, `RST`); o `LIGHT` só entra
se o jumper do backlight estiver aberto.

## Código de cores dos fios

Padrão fixado em 2026-11-15, com o estoque da bancada (8 cores). A regra de
ouro: **vermelho é sempre alimentação e preto é sempre terra** — nunca use
vermelho para `RST` "porque é reset".

| Fio | Sinal | Pino do módulo | Pino do header | Por quê essa cor |
| --- | --- | --- | --- | --- |
| **vermelho** | `VCC` (3,3 V) | 6 | 1 | convenção universal de positivo |
| **preto** | `GND` | 8 | 6 | convenção universal de terra |
| **laranja** | `CLK` / `SCLK` | 5 | 23 | o "batimento" do barramento, cor quente |
| **amarelo** | `DIN` / `MOSI` | 4 | 19 | par de dados, vizinho do laranja |
| **verde** | `DC` / `A0` | 3 | 16 | controle de dados/comando |
| **azul** | `RST` / `RES` | 1 | 18 | cor fria para o reset |
| **branco** | `CE` / `CS` | 2 | 24 | "habilita" o chip; neutro |
| **marrom** | `LIGHT` / `BL` | 7 | 3,3 V via resistor (ou reserva) | reserva: jumper do backlight / dimmer futuro |

Regras de montagem:

- **etiquete as duas pontas** (fita ou número) antes de enfiar no header; cor
  ajuda, rótulo resolve;
- **conferência de continuidade** pino a pino com o multímetro, **antes** de
  energizar: sem curtos entre vizinhos e sem `VCC`↔`GND`;
- mantenha os fios com o **mesmo comprimento** (≤ 30 cm) e passe o par
  vermelho/preto junto; sinais longos e soltos pioram a EMI;
- afaste o chicote da **antena do AP6212** e confira o RSSI depois de fechar a
  tampa;
- o **marrom** só entra se o jumper do backlight estiver aberto e você precisar
  alimentar o `LIGHT` por fora (100 Ω em série). Com o jumper fechado, deixe-o
  desconectado — ele fica guardado para o dimmer em `PG11` (pino 7).

> O `CE` fica no **pino 24 (PC3)** com CS por software (`--cs 67`). Aterrar o
> CS (`--cs-gnd`) é aceitável numa bancada de escravo único, mas aí o branco vai
> para o `GND` (pino 20) e o barramento fica preso a esse display.

## Montagem com cabo flat (IDC)

O header `GPIO1` é **2x12** (24 pinos, 2,54 mm, pinout equivalente aos 24
primeiros pinos do Raspberry Pi). Não existe "um lado só": os 7 sinais do
display estão distribuídos nas duas fileiras.

| Fileira | Pinos usados |
| --- | --- |
| Ímpares (1, 3, … 23) | **1** (`3V3`), **19** (`DIN`), **23** (`CLK`) |
| Pares (2, 4, … 24) | **6** (`GND`), **16** (`DC`), **18** (`RST`), **24** (`CE`) |

Com IDC, a montagem fica assim:

- conector **IDC fêmea 2x12, passo 2,54 mm**, num cabo de 24 vias (1,27 mm);
- o **fio vermelho do cabo é o pino 1** (`3V3`) — confira a continuidade do
  pino 1 do conector até o pino 1 do header **antes** de plugar;
- as 17 vias que sobram incluem **5 V** (pinos 2 e 4) e **UART2** (11, 13, 15
  e 22): corte-as curtas e isole as pontas;
- o código de cores acima vale para os **fios do lado do módulo**; o cabo flat
  tem a sequência do arco-íris, então etiquete por **posição**, não por cor;
- prenda o cabo com abraçadeira ou um pingo de cola para não alavancar o
  header da placa, e mantenha-o longe da antena do AP6212.

> Identificação do pino 1 na placa: é o pad quadrado (ou o ponto na serigrafia)
> do canto. Com a placa ligada e **nada plugado**, dá para confirmar com o
> multímetro: pino 1 = 3,3 V, pino 2 = 5 V, pino 6 = `GND`. Se o pino 1 não der
> 3,3 V, o conector está invertido — não plugue o display.

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
| Backlight | feche o **jumper** do módulo primeiro; se ainda precisar de alimentação externa, use resistor (10–25 mA). Nunca ligue o backlight direto num GPIO (limite ~20 mA/pino no H3) |
| Corrente total | lógica ~10 mA + backlight ~15 mA: folgado no regulador da placa |
| Velocidade SPI | o `spidev0.0` está configurado para 10 MHz; o **PCD8544 aceita no máximo 4 MHz** — o driver deve pedir 1–4 MHz na transferência |
| Fios | até ~30 cm sem problema nessa velocidade; mantenha longe da antena do AP6212 e confira o RSSI depois de montar |

### O jumper do backlight

Este breakout tem um **jumper que vem aberto** e precisa ser fechado para o
backlight funcionar (conforme a documentação do fabricante). Fechado, os LEDs já
recebem alimentação pela placa — normalmente com resistor embutido — e o pino
`LIGHT` (7) **não precisa de fio nenhum**.

Como confirmar em 10 segundos, com o jumper fechado:

1. ligue só `VCC` (pino 6) e `GND` (pino 8), **sem** nada no `LIGHT`;
2. se o backlight acender, está resolvido: 7 fios, sem resistor externo;
3. se continuar apagado, o jumper apenas leva o `LIGHT` ao ânodo e a alimentação
   tem de vir de fora — aí siga a seção do resistor abaixo.

Se o jumper for do tipo que **não** deve ser fechado com a placa energizada
(alguns são solder jumpers), feche antes de ligar e confira com o multímetro se
`LIGHT` tem continuidade com `VCC`.

### Dimensionar o resistor do backlight (só se o jumper não bastar)

O backlight desses módulos são LEDs brancos cuja tensão direta fica muito perto
de 3,3 V — por isso "330 Ω" (receita comum na internet) deixa a tela quase
apagada: sobra pouca tensão para o resistor limitar. O caminho prático:

1. comece com **100 Ω** em série e meça a corrente com o multímetro;
2. se estiver apagado, desça para **47 Ω** ou **33 Ω**;
3. mire em **10–25 mA** no total — acima de 30 mA esquenta e não melhora a leitura;
4. vários breakouts já têm resistor embutido na placa; nesse caso o `LIGHT` pode
   ir direto ao 3,3 V (confira a presença do componente perto do pino `LIGHT`).

> Atalho de montagem (quando há resistor externo): `VCC` (pino 6) e `LIGHT`
> (pino 7) são vizinhos no módulo. O resistor pode ser soldado **direto entre os
> dois pinos**, sem fio extra — um único jumper de 3,3 V alimenta os dois.

Sequência de conferência com multímetro, **antes** de energizar:

1. continuidade pino a pino do cabo (sem curtos entre vizinhos);
2. `VCC` do módulo contra `GND`: sem continuidade;
3. com a placa ligada: 3,3 V entre `VCC` e `GND` do módulo;
4. só então conecte `SCLK`/`DIN`/`CS`/`DC`/`RST`.

## Ensaio na protoboard (antes da montagem final)

Testar a lógica com o módulo solto, o backlight por resistor externo e o CS por
software — sem soldar nada no display.

> O conector **IDC 2x12 não entra em protoboard**: as duas fileiras ficam a
> 2,54 mm e caem na canaleta central. Para o ensaio use dupont (fêmea no header
> da placa, macho na protoboard); o cabo flat fica para a montagem final.

Ligação (mesmo código de cores):

| Header | Fio | Módulo | Observação |
| --- | --- | --- | --- |
| 1 (`3V3`) | vermelho | 6 `VCC` | trilho vermelho da protoboard |
| 6 (`GND`) | preto | 8 `GND` | trilho azul |
| 23 (`PC2`) | laranja | 5 `CLK` | |
| 19 (`PC0`) | amarelo | 4 `DIN` | |
| 16 (`PG8`) | verde | 3 `DC` | |
| 18 (`PG9`) | azul | 1 `RST` | |
| 24 (`PC3`) | branco | 2 `CE` | CS por software (`--cs 67`) |
| 1 (`3V3`) | marrom | 7 `LIGHT` | com **100 Ω** em série |

Passo a passo:

1. módulo atravessando a canaleta central, um pino por linha (não deixe dois
   pinos na mesma linha de 5 furos);
2. alimente os trilhos a partir do pino 1 (3,3 V) e do pino 6 (`GND`); se a
   protoboard tiver os trilhos partidos no meio, una as metades com um jumper;
3. **100 nF** entre `VCC` e `GND` junto do módulo (seguro barato contra ruído do
   barramento em protoboard);
4. marrom: `LIGHT` → **100 Ω** → trilho de 3,3 V (não ligue o `LIGHT` direto);
5. com tudo desligado, confira continuidade pino a pino e ausência de curto
   `VCC`↔`GND`;
6. ligue só a placa, meça 3,3 V no `VCC` do módulo e veja se o backlight acende
   fraco (meça a corrente em série com o resistor: 10–25 mA);
7. só então rode o teste de fumaça.

```bash
scp scripts/pcd8544-smoke-test.py root@<IP>:/root/
ssh root@<IP> 'python3 /root/pcd8544-smoke-test.py --cs 67'
```

Não faça hot-plug: conecte e desconecte o módulo sempre com a placa desligada.

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

## Notas de tutoriais (MakerHero, 2026-11-14)

O [tutorial da MakerHero](https://www.makerhero.com/blog/conheca-o-display-nokia-5110/)
usa Arduino, mas três coisas dele são aproveitáveis aqui:

**1. Os rótulos batem com o módulo desta bancada.** A tabela do tutorial é
`RST, CE, DC, DIN, CLK, VCC, BL, GND` — mesma ordem física do nosso, com `BL` no
lugar de `LIGHT`. Serve como confirmação externa da pinagem documentada acima.

**2. Escala de contraste.** O tutorial usa `setContrast(56)` (biblioteca Adafruit,
escala 0–100). Isso corresponde ao comando `Vop` do controlador:

| Tutorial (Adafruit) | Nosso script (`--contrast`) | Resultado |
| --- | --- | --- |
| `setContrast(20)` | `--contrast 0x94` | claro, pixels fracos |
| `setContrast(56)` | `--contrast 0xB8` | médio (padrão do tutorial) |
| `setContrast(80)` | `--contrast 0xD0` | escuro |
| — | `--contrast 0xFF` | máximo; pode borrar |

O padrão do nosso script (`0xBF`) fica entre o "médio" e o "escuro".

**3. Bitmap e fontes.** O caminho do tutorial (`drawBitmap`, `setTextSize`,
`display()`) é o mesmo que o daemon vai precisar depois. Para desenhar telas de
84x48 existe uma ferramenta web dedicada:
[pcd8544designer.web.app](https://pcd8544designer.web.app/) — gera o vetor no
formato MSB-first que o PCD8544 espera.

### O que **não** copiar do tutorial

- **"PCB azul aceita 3,3 V ou 5 V"**: o PCD8544 é um componente de 3,3 V. Se o
  breakout não tiver um CI de *level shifter* (e a maioria dos azuis não tem),
  os 5 V do Arduino entram direto nos pinos de lógica. Aqui isso não é risco —
  a NanoPi só tem 3,3 V no header — mas não vale como regra geral.
- **Backlight direto num GPIO** (`digitalWrite(BLpin, HIGH)`): o AVR do Arduino
  aguenta mais corrente que o H3, e o tutorial não mostra resistor. Neste
  projeto o backlight é resolvido pelo jumper do módulo.
- O tutorial assume um único display com CE dedicado; no nosso caso o CE é
  controlado por software porque o kernel não o aciona (seção acima).

## Pendências desta etapa

- [x] ~~confirmar a variante do breakout~~ — **3,3 V puro**, sem level shifter
- [x] ~~registrar os rótulos do módulo~~ — `RST, CE, DC, DIN, CLK, VCC, LIGHT, GND`
- [x] ~~decidir backlight~~ — fixo, ligado pelo **jumper do módulo**; `PG11` fica para um dimmer futuro
- [ ] fechar o jumper do backlight e confirmar se o `LIGHT` pode ficar sem fio
- [x] ~~decidir CS~~ — por **software** no pino 24 (`--cs 67`)
- [x] ~~padronizar as cores dos fios~~ — ver "Código de cores dos fios"
- [x] ~~rodar o teste de fumaça~~ — rodado em 2026-11-17: 5 padrões e `--all-on`
      transmitidos com `errors=0`, mas **nenhum pixel** apareceu
      ([sessão 16](12-log-de-bordo.md#sessão-16--2026-11-17--display-o-lcd-mudo-e-o-i2c-travado))
- [ ] validar o módulo em outra placa antes de descartá-lo
- [ ] medir o RSSI do Wi-Fi depois de montar o display
