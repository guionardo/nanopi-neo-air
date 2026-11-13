# 00 — Hardware e pinagem

Referência offline do que a placa oferece. Serve para tirar dúvidas sem depender
da wiki (que é a fonte primária: [wiki: NanoPi NEO Air](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_NEO_Air)).

## Especificações

| Item | Valor |
| --- | --- |
| CPU | Allwinner H3, quad-core Cortex-A7 até 1.2 GHz |
| RAM | 512 MB DDR3 (16 bits) |
| Armazenamento | 8 GB eMMC + 1 slot microSD |
| Wi-Fi | 802.11 b/g/n (chip AP6212) |
| Bluetooth | 4.0 dual mode (mesmo AP6212) |
| Câmera | DVP, conector FPC 24 pinos, passo 0.5 mm (YUV422) |
| USB | 1x microUSB (OTG + alimentação) + 2x USB via header de 12 pinos |
| Serial de debug | Header 4 pinos, passo 2.54 mm (UART0) |
| GPIO1 | Header 24 pinos 2.54 mm (UART, SPI, I2C, GPIO) |
| GPIO2 | Header 12 pinos 2.54 mm (USB x2, IR, SPDIF, I2S) |
| Áudio | Header 4 pinos (line-out L/R, mic N/P) |
| Alimentação | DC 5 V / 2 A via microUSB |
| PCB | 40 x 40 mm, 6 camadas |
| Temperatura de operação | -20 °C a 70 °C |
| Peso | 7.5 g (sem headers) |

### O que a placa NÃO tem

Isso muda o procedimento de instalação e deve ser levado a sério:

- **Sem HDMI / saída de vídeo** → não há monitor para "ver o boot".
- **Sem Ethernet** → a rede é exclusivamente Wi-Fi (ou USB-Ethernet pelo header
  de 12 pinos).
- **Sem RTC com bateria** → relógio acerta via NTP; sem rede, a hora começa errada.
- **Sem botão de reset** → recuperação é por energia ou novo cartão SD.

Consequência prática: **console serial é o único acesso confiável no primeiro boot.**
Se você não tiver o adaptador USB-TTL, o primeiro boot é uma aposta às cegas.

## Identificar a versão da placa

V1.0 e V1.1 são funcionalmente equivalentes, mas os **LEDs mudam de cor** — o que
importa na hora de diagnosticar boot pelo pisca-pisca.

| Versão | LED PWR | LED STAT |
| --- | --- | --- |
| V1.0 | Verde | Azul |
| V1.1 | Vermelho | Verde |

Outras diferenças: na V1.1 o slot do cartão foi deslocado ~1 mm na direção do
AP6212 e o header de áudio passou a ter 4 furos de 2.54 mm (na V1.0 são 4 pads).

**Como saber qual é a sua:** olhe a serigrafia na parte de baixo da PCB ou
compare as cores dos LEDs ao energizar. Anote a versão em
[11-decisoes.md](11-decisoes.md) — afeta a escolha de gabinete impresso em 3D.

## Mapa de pinos

### GPIO1 — header 24 pinos

Compatível com o header de 40 pinos do Raspberry Pi (subset de 24).

| Pino | Nome | Linux gpio | Pino | Nome | Linux gpio |
| --- | --- | --- | --- | --- | --- |
| 1 | SYS_3.3V | — | 2 | VDD_5V | — |
| 3 | I2C0_SDA / GPIOA12 | — | 4 | VDD_5V | — |
| 5 | I2C0_SCL / GPIOA11 | — | 6 | GND | — |
| 7 | GPIOG11 | 203 | 8 | UART1_TX / GPIOG6 | 198 |
| 9 | GND | — | 10 | UART1_RX / GPIOG7 | 199 |
| 11 | UART2_TX / GPIOA0 | 0 | 12 | GPIOA6 | 6 |
| 13 | UART2_RTS / GPIOA2 | 2 | 14 | GND | — |
| 15 | UART2_CTS / GPIOA3 | 3 | 16 | UART1_RTS / GPIOG8 | 200 |
| 17 | SYS_3.3V | — | 18 | UART1_CTS / GPIOG9 | 201 |
| 19 | SPI0_MOSI / GPIOC0 | 64 | 20 | GND | — |
| 21 | SPI0_MISO / GPIOC1 | 65 | 22 | UART2_RX / GPIOA1 | 1 |
| 23 | SPI0_CLK / GPIOC2 | 66 | 24 | SPI0_CS / GPIOC3 | 67 |

> Os pinos de I2C0 (3 e 5) aparecem sem número de gpio na wiki: são usados pelo
> driver de I2C (`/dev/i2c-0`), não como GPIO genérico. Mesma lógica para SPI0.

### GPIO2 — header 12 pinos (USB / I2S / IR)

| Pino | Nome | Descrição |
| --- | --- | --- |
| 1 | VDD_5V | Saída 5 V |
| 2 | USB-DP2 | USB2 D+ |
| 3 | USB-DM2 | USB2 D- |
| 4 | USB-DP3 | USB3 D+ |
| 5 | USB-DM3 | USB3 D- |
| 6 | GPIOL11 / IR-RX | GPIO ou receptor IR |
| 7 | SPDIF-OUT / GPIOA17 | GPIO ou saída SPDIF |
| 8 | PCM0_SYNC / I2S0_LRC | Clock de sincronismo I2S/PCM |
| 9 | PCM0_CLK / I2S0_BCK | Bit clock I2S/PCM |
| 10 | PCM0_DOUT / I2S0_SDOUT | Saída serial I2S/PCM |
| 11 | PCM0_DIN / I2S0_SDIN | Entrada serial I2S/PCM |
| 12 | GND | 0 V |

Os dois pares USB 2/3 permitem soldar um conector USB-A ou usar um adaptador
USB-Ethernet/USB-storage — é a saída para ter rede cabeada na NEO Air.

### UART0 — header de debug (4 pinos)

| Pino | Nome | Uso no console |
| --- | --- | --- |
| 1 | GND | **conectar** |
| 2 | VDD_5V | não conectar (alimenta a placa) |
| 3 | UART_TXD0 / GPIOA4 | TX da placa → RX do adaptador |
| 4 | UART_RXD0 / GPIOA5 / PWM0 | RX da placa ← TX do adaptador |

Parâmetros: **115200 8N1, sem flow control**. Nível **3.3 V** (nunca 5 V).

### Áudio — header 4 pinos

| Pino | Nome | Descrição |
| --- | --- | --- |
| 1 | LL | Line-out esquerdo |
| 2 | LR | Line-out direito |
| 3 | MICN | Microfone negativo |
| 4 | MICP | Microfone positivo |

### Câmera DVP — FPC 24 pinos

| Pino | Sinal | Pino | Sinal |
| --- | --- | --- | --- |
| 1, 2 | SYS_3.3V | 11 | VSYNC |
| 3 | I2C2_SCL | 12 | HREF/HSYNC |
| 4 | I2C2_SDA | 14 | PCLK |
| 5 | GPIOE15 | 16–23 | Data bit7–bit0 |
| 6 | GPIOE14 | 24 | GND |
| 7, 9, 13, 15 | GND | 10 | NC |
| 8 | MCLK | | |

## Limites elétricos — leia antes de ligar qualquer coisa

| Grandeza | Limite | Observação |
| --- | --- | --- |
| Tensão dos GPIOs | **3.3 V** | 5 V no pino queima o SoC. Sem tolerância. |
| Corrente por pino | **~5 mA** | Não aciona relé, LED de potência ou motor direto. |
| Entrada de alimentação | 4.7 V – 5.6 V | Via microUSB ou pinos VDD_5V |
| Corrente da fonte | **2 A** | Abaixo disso: brownout em picos de Wi-Fi |

Regras práticas:

- Para cargas (relé, LED de potência, motor) use **driver**: transistor/MOSFET,
  módulo relé com optoacoplador ou ULN2803. O GPIO só manda sinal.
- Se alimentar por um dos pinos VDD_5V, garanta que o microUSB não esteja
  alimentando ao mesmo tempo por outra fonte com tensão diferente.
- Nada de divisor resistivo "para ler 12 V" no GPIO sem conferir a tensão
  resultante — meça antes de conectar.

## Consumo e térmica (referência)

Sem números medidos ainda. O H3 em kernel 4.14 mainline roda frio justamente
porque não usa VPU/GPU; a wiki recomenda esse kernel por isso. Meça e registre em
[09-manutencao.md](09-manutencao.md) quando tiver a placa em operação:

```bash
# temperatura e frequência por core
cpu_freq
```

## Recursos de hardware

- [Schematic V1.1 (1708)](https://wiki.friendlyelec.com/wiki/images/7/70/Schematic_NanoPi-NEO-Air-V1.1_1708.pdf)
- [Schematic V1.0 (1608)](https://wiki.friendlyelec.com/wiki/images/9/98/NanoPi-NEO-Air-1608-Schematic.pdf)
- [Datasheet Allwinner H3 V1.2](https://wiki.friendlyelec.com/wiki/images/4/4b/Allwinner_H3_Datasheet_V1.2.pdf)
- [Dimensões V1.1 (dxf, rar)](https://wiki.friendlyelec.com/wiki/index.php/File:Dimensional-NanoPi_NEO_Air-V1.1-1708.rar)
- [Case 3D V1.0 (Thingiverse)](https://www.thingiverse.com/thing:1998968)
