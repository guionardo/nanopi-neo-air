# 13 — Backlog de funcionalidades

Ideias e funcionalidades futuras, registradas para não se perderem. Não são
compromissos de prazo — são **escopo** com o contexto técnico já levantado, para
que a decisão de implementar seja barata mais tarde.

Convenção: `B-nnn` = ideia/funcionalidade. Decisões são `D-nnn`
([11](11-decisoes.md)); observações de bancada são "Achado nn"
([12](12-log-de-bordo.md)).

| # | Funcionalidade | Status | Complexidade |
| --- | --- | --- | --- |
| B-001 | [Display de status (LCD Nokia 5110 ou OLED I2C)](#b-001--display-lcd-nokia-5110-84x48) | 🔧 em investigação | baixa/média |

---

## B-001 — Display LCD Nokia 5110 (84x48)

**Registrado em:** 2026-11-14
**Status:** 🔧 em investigação (hardware alternativo em teste)
**Origem:** pedido do usuário durante a sessão 11 do log de bordo.

**Estado em 2026-11-18.** O LCD montado na protoboard nunca acendeu, mesmo com
`CE`, `RST` e `DC` confirmados no osciloscópio e o modo de teste do controlador
(`--all-on`) sem resposta ([sessão 16](12-log-de-bordo.md)). O caminho passou a
ser um **OLED I2C (SSD1306 128x64, `0x3C`)**, que já responde no barramento mas
ainda não acende o painel — diagnóstico em
[16-display-oled.md](16-display-oled.md). A decisão de separar o display do
primeiro artigo está em [D-009](11-decisoes.md).

### Objetivo

Como a placa é um host headless acessado só por SSH, o display mostra **o que
você veria ao logar**: CPU, memória, uptime e IP. É um painel de bancada, não um
console. Pequeno, barato, ligado no header GPIO1.

### Hardware

O "Nokia 5110" é o módulo de breakout do controlador **PCD8544**: 84x48 pixels
monocromático, SPI write-only, alimentação e lógica em **3,3 V**.

| Pino do módulo | Rótulo | Placa (GPIO1) | Observação |
| --- | --- | --- | --- |
| 6 | `VCC` | pino 1 ou 17 (`SYS_3.3V`) | **nunca** no pino 2/4 (`VDD_5V`) |
| 8 | `GND` | pino 6, 9, 14 ou 20 | |
| 5 | `CLK` | pino 23 (`SPI0_CLK`, `PC2`) | |
| 4 | `DIN` | pino 19 (`SPI0_MOSI`, `PC0`) | módulo não transmite: MISO fica livre |
| 2 | `CE` (CS) | pino 24 (`SPI0_CS`, `PC3`) | o kernel **não** aciona este pino: CS por software |
| 3 | `DC` | pino 16 (`UART1_RTS`, `PG8`) | |
| 1 | `RST` | pino 18 (`UART1_CTS`, `PG9`) | |
| 7 | `LIGHT` | fechar o jumper do módulo (vem aberto) | sem fio se o backlight acender; senão 3,3 V por resistor |

Pinagem detalhada, cuidados elétricos e teste de fumaça:
[14-display-lcd.md](14-display-lcd.md).

### Hardware alternativo: OLED I2C

O caminho em teste desde a sessão 16 é um **OLED SSD1306 128x64** de 0,96" no
`I2C0` — quatro fios, dois deles de sinal, sem chip select por software:

| OLED | Placa (GPIO1) | Sinal |
| --- | --- | --- |
| `GND` | pino 6 | GND |
| `VCC` | pino 1 ou 17 | `SYS_3.3V` |
| `SDA` | pino 3 | `I2C0_SDA` / `PA12` |
| `SCL` | pino 5 | `I2C0_SCL` / `PA11` |

Endereço `0x3C` (serigrafia `0x78`/`0x7A` são os valores de 8 bits). Diagnóstico,
ferramentas e cuidados: [16-display-oled.md](16-display-oled.md).

Cuidados:

- o módulo aceita 3,3 V, mas o backlight puxa corrente; **não** alimentar o LED
  direto de um GPIO sem transistor (limite por pino do H3 é ~20 mA);
- o header UART2 (pinos 11/13/15/22) é a fonte de GPIOs livres mais conveniente —
  a serial de debug fica no header separado (UART0), então não há conflito;
- a SPI0 do header é independente do barramento MMC da eMMC: não há disputa.

### O que exibir

Escopo definido pelo usuário em 2026-11-14: **CPU, memória, uptime e IP**. Uma
tela só, sem botão e sem rotação — cabe nos 84x48:

```text
+----------------------+
| ctl-nanopi           |  hostname
| 192.168.1.50        |  IP (fonte maior: e o dado que se digita no SSH)
| CPU  12%  .:-=+=-:.  |  uso + mini-grafico das ultimas ~20 amostras
|  42C   1200MHz       |  temperatura e frequencia
| MEM  180/512M        |  memoria usada/total
| UP   3d 04h          |  uptime desde o boot
+----------------------+
```

Detalhes de implementação do conteúdo:

| Campo | Fonte | Observação |
| --- | --- | --- |
| IP | `nmcli -g IP4.ADDRESS dev show wlan0` ou `ip -4 -o addr` | se cair, mostrar `sem rede` em vez de IP velho |
| CPU | delta de `/proc/stat` entre amostras | `/proc/loadavg` é média e engana em bursts |
| Temperatura | `/sys/class/thermal/thermal_zone0/temp` | milésimos de °C |
| Frequência | `/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` | kHz |
| Memória | `MemTotal - MemAvailable` de `/proc/meminfo` | 512 MB no total |
| Uptime | `/proc/uptime` | formatar `Xd HHh` |

- atualização a cada 2 s, redesenhando **só as linhas que mudaram** (evita
  cintilação no PCD8544, que não tem buffer próprio de vídeo);
- o mini-gráfico de CPU exige um ring buffer de ~20 amostras em memória;
- opcional (barato): mostrar o **sinal Wi-Fi** em dBm na linha do IP — é o dado
  que mais ajuda a diagnosticar a rede, e o custo é ler `/proc/net/wireless`.

### Caminhos de implementação

| Caminho | Como | Prós | Contras |
| --- | --- | --- | --- |
| **A. Userspace Python** | `luma.lcd` (Pillow) + `spidev` | rápido de escrever, fontes prontas, fácil de iterar | ~30–50 MB de dependências; um processo a mais |
| **B. fbtft (framebuffer)** | overlay no device tree com `fb_pcd8544` | `/dev/fb1` vira console/framebuffer; qualquer coisa escreve | kernel 4.14 tem fbtft em staging; exige recompilar DTB/overlay |
| **C. C/WiringNP** | bit-bang ou `spidev` em C | binário mínimo, sem Python | mais código, sem fontes prontas |

Recomendação preliminar: **A** para prototipar (mede-se o valor real da
informação), e só migrar para **B** se o objetivo virar "console local" de fato.

A pinagem, os cuidados elétricos e o teste de fumaça estão em
[14-display-lcd.md](14-display-lcd.md).

### Requisitos técnicos que a implementação precisa respeitar

- não bloquear o boot: o serviço do display deve ter `After=multi-user.target` e
  falhar de forma silenciosa (`Restart=always` com limite);
- se o display sumir (SPI ocupada, módulo desconectado), o resto do sistema não
  pode ser afetado;
- leitura de dados sem `sudo` desnecessário: `systemd` pode expor via
  `/run/nanopi-status.json` escrito por um coletor, e o renderizador só lê;
- consumo: o backlight ligado 24/7 pode pesar no orçamento térmico/elétrico —
  prever desligar por horário (ex.: apagar entre 23h e 7h).

### Pendências para quando for implementar

- [x] ~~confirmar a versão do módulo LCD~~ — **3,3 V puro**, sem level shifter
      (o módulo OLED ainda não teve o LDO conferido)
- [x] sem botão e sem telas rotativas (escopo: uma tela fixa)
- [ ] medir o consumo do backlight (LCD) e o impacto em temperatura
- [ ] definir se o display é "enfeite" ou parte do diagnóstico (muda o
      investimento: fbtft + console local é bem mais trabalho)
- [ ] escolher a fonte dos dados (arquivo de status vs. ler `/sys` direto)
- [ ] decidir se o sinal Wi-Fi entra na tela (sugerido: sim)
- [x] ~~validar que o `spidev0.0` funciona no kernel 4.14 da FriendlyElec~~ —
      **já existe no DTB** (`/dev/spidev0.0`, 10 MHz, 0 erros num teste de
      2536 bytes); ver [14-display-lcd.md](14-display-lcd.md)
- [x] ~~validar o `I2C0` do header~~ — `/dev/i2c-0` em `PA11`/`PA12`, módulo
      responde em `0x3C`; ver [16-display-oled.md](16-display-oled.md)
- [ ] fazer o painel acender (5 V com conferência de nível, ou variante correta)
- [ ] validar o módulo em outra placa antes de descartá-lo
- [ ] escrever o daemon e o serviço systemd
