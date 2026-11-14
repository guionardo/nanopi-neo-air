# 13 — Backlog de funcionalidades

Ideias e funcionalidades futuras, registradas para não se perderem. Não são
compromissos de prazo — são **escopo** com o contexto técnico já levantado, para
que a decisão de implementar seja barata mais tarde.

Convenção: `B-nnn` = ideia/funcionalidade. Decisões são `D-nnn`
([11](11-decisoes.md)); observações de bancada são "Achado nn"
([12](12-log-de-bordo.md)).

| # | Funcionalidade | Status | Complexidade |
| --- | --- | --- | --- |
| B-001 | [Display LCD Nokia 5110 (84x48) com informações de operação](#b-001--display-lcd-nokia-5110-84x48) | 💡 ideia | baixa/média |

---

## B-001 — Display LCD Nokia 5110 (84x48)

**Registrado em:** 2026-11-14
**Status:** 💡 ideia (sem data)
**Origem:** pedido do usuário durante a sessão 11 do log de bordo.

### Objetivo

Mostrar o estado da placa sem depender de rede: um display pequeno e barato,
ligado no header GPIO1, exibindo as informações que hoje só existem via SSH.

### Hardware

O "Nokia 5110" é o módulo de breakout do controlador **PCD8544**: 84x48 pixels
monocromático, SPI write-only, alimentação e lógica em **3,3 V**.

| Módulo | Placa (GPIO1) | Observação |
| --- | --- | --- |
| `VCC` | pino 1 ou 17 (`SYS_3.3V`) | **nunca** no pino 2/4 (`VDD_5V`) |
| `GND` | pino 6, 9, 14 ou 20 | |
| `SCLK` | pino 23 (`SPI0_CLK`, GPIOC2) | |
| `DIN` (MOSI) | pino 19 (`SPI0_MOSI`, GPIOC0) | módulo não transmite: MISO fica livre |
| `CE` (CS) | pino 24 (`SPI0_CS`, GPIOC3) | ou um GPIO comum, se preferir não usar CS0 |
| `DC` | GPIO livre, ex.: pino 12 (`GPIOA6`, gpio 6) | seleciona dado/comando |
| `RST` | GPIO livre, ex.: pino 11 (`UART2_TX`, gpio 0) | |
| `LED` (backlight) | 3,3 V via resistor **ou** GPIO com transistor | se GPIO, permite PWM/dimmer |

Cuidados:

- o módulo aceita 3,3 V, mas o backlight puxa corrente; **não** alimentar o LED
  direto de um GPIO sem transistor (limite por pino do H3 é ~20 mA);
- o header UART2 (pinos 11/13/15/22) é a fonte de GPIOs livres mais conveniente —
  a serial de debug fica no header separado (UART0), então não há conflito;
- a SPI0 do header é independente do barramento MMC da eMMC: não há disputa.

### O que exibir (proposta)

Como 84x48 dá ~6 linhas de 14 caracteres em fonte 5x7, o conteúdo precisa ser
rotativo ou por "telas":

| Tela | Linha 1 | Linha 2 | Linha 3 | Linha 4 | Linha 5 | Linha 6 |
| --- | --- | --- | --- | --- | --- | --- |
| Rede | `NanoPi` | `192.168.1.50` | `minha-rede -31dBm` | `up 3d 04h` | `ld 0.28` | `sshd ok` |
| Saúde | `CPU 42C` | `freq 1200MHz` | `RAM 180/512M` | `disk 38%` | `swap 0M` | `fs ro? nao` |
| Serviço | nome do serviço | estado | porta | última falha | `.` | `.` |

Alternância automática a cada ~5 s com um botão (GPIO) para trocar de tela, ou
`systemd` + um daemon pequeno.

### Caminhos de implementação

| Caminho | Como | Prós | Contras |
| --- | --- | --- | --- |
| **A. Userspace Python** | `luma.lcd` (Pillow) + `spidev` | rápido de escrever, fontes prontas, fácil de iterar | ~30–50 MB de dependências; um processo a mais |
| **B. fbtft (framebuffer)** | overlay no device tree com `fb_pcd8544` | `/dev/fb1` vira console/framebuffer; qualquer coisa escreve | kernel 4.14 tem fbtft em staging; exige recompilar DTB/overlay |
| **C. C/WiringNP** | bit-bang ou `spidev` em C | binário mínimo, sem Python | mais código, sem fontes prontas |

Recomendação preliminar: **A** para prototipar (mede-se o valor real da
informação), e só migrar para **B** se o objetivo virar "console local" de fato.

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

- [ ] confirmar a **versão do módulo** (alguns breakouts têm regulador/level
      shifter de 5 V; nesse caso o `VCC` vai em 5 V, mas os sinais continuam 3,3 V)
- [ ] decidir entre telas rotativas ou botão físico
- [ ] medir o consumo do backlight e o impacto em temperatura
- [ ] definir se o display é "enfeite" ou parte do diagnóstico (muda o
      investimento: fbtft + console local é bem mais trabalho)
- [ ] escolher a fonte dos dados (arquivo de status vs. ler `/sys` direto)
- [ ] validar que o `spidev0.0` funciona no kernel 4.14 da FriendlyElec
      (pode exigir habilitar o overlay de SPI no `uEnv.txt`/DTB)
