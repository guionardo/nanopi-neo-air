---
title: 'NanoPi NEO Air: o painel de status que quase não existiu'
description: 'IP, CPU, memória e uptime num OLED de dois fios — depois de um LCD que nunca acendeu, um barramento I2C que travava e uma troca de fios que custou a noite inteira.'
date: 2026-11-17
slug: nanopi-neo-air-display-status
tags: [nanopi, allwinner-h3, i2c, oled, ssd1306, linux, embarcados]
draft: true
lang: pt
translationKey: nanopi-neo-air-display-status
# Quando as fotos estiverem em public/images/nanopi-neo-air-display-status/,
# descomente as duas linhas abaixo (o caminho é relativo a public/).
# heroImage: /images/nanopi-neo-air-display-status/header.jpg
# heroImageAlt: 'NanoPi NEO Air com o OLED de 0,96" ligado por quatro fios.'
---

> **Resumo:** este é o segundo tempo do projeto — o host headless já está pronto
> e documentado, falta dar a ele uma cara. O painel deveria ser um LCD Nokia 5110
> no SPI; terminou num OLED de dois fios no I2C. No meio do caminho: um chip
> select que o kernel não aciona, um pino de clock que na verdade estava solto e
> um `SDA`/`SCL` trocado que fez dois módulos diferentes parecerem defeituosos.

<!-- Estrutura prevista. Escrever os blocos na ordem abaixo, no mesmo tom do
     primeiro artigo (decisão → evidência → o que morde). Onde está TODO, é
     material que só existe depois de validar o hardware. -->

## O que o painel precisa mostrar

Escopo fechado desde o início: uma tela fixa com o que você veria ao logar —
hostname, IP, uso de CPU, memória e uptime. Sem botão, sem rotação, sem menu.

O detalhe que define o resto: a placa é **headless**, então o dado mais
importante é o IP. É o que se digita para entrar.

## Por que não o LCD Nokia 5110

O módulo PCD8544 (84×48) já estava comprado e a fiação documentada. O barramento
funcionava: `spidev0.0` transmitiu 2.536 bytes com zero erros. Mesmo assim, a
tela nunca mostrou um pixel — nem no modo de teste do próprio controlador
(`--all-on`, que deveria deixar a tela inteira preta).

Três coisas que ficaram de aprendizado:

- **o kernel 4.14 do vendor não aciona o chip select.** `PC3` (pino 24) fica em
  `gpio_out`, e o `sun6i-spi` ignora `cs-gpios`. Sem CS por software, o display
  recebe bytes e descarta tudo. *TODO: confirmar se o PCD8544 está realmente
  defeituoso ou se o problema era só contato — testar em outra placa.*
- **60 Hz num pino de clock não é clock.** Um sinal de 60 Hz em `CLK` é a
  assinatura de pino flutuando (captando ruído da rede), não de SPI a 4 MHz.
- **`DC`, `RST` e `CE` certos não bastam.** Os três foram confirmados no
  osciloscópio, e a tela continuou apagada.

## O barramento I2C que travava

Trocar para um OLED I2C parecia simplificar: dois fios, endereço fixo, sem CS
por software. A primeira surpresa foi o `i2cdetect` **travar** em vez de não
achar nada.

```text
i2c i2c-0: mv64xxx: I2C bus locked, block: 1, time_left: 0
```

Traduzindo: o controlador sente `SDA` ou `SCL` presos em nível baixo e nem
começa a transação. A causa está no `pinctrl`:

```text
pin 11 (PA11): input bias disabled, output drive strength (20 mA)
pin 12 (PA12): input bias disabled, output drive strength (20 mA)
```

O I2C0 do header **não tem pull-up interno habilitado**. Quem puxa as linhas
para 3,3 V é o módulo — e, sem display plugado, o barramento fica flutuando e o
kernel o considera ocupado.

### Como medir o nível de um pino multiplexado

O primeiro reflexo foi ler o registrador de dados do SoC (`PADAT` com `devmem`),
que devolveu `0 0`. Falso: em pino multiplexado, esse registrador mostra o
último valor de **saída**, não o nível do pad.

A leitura confiável é tirar o controlador do caminho:

```bash
D=/sys/bus/platform/drivers/mv64xxx_i2c
echo 1c2ac00.i2c > $D/unbind
echo 11 > /sys/class/gpio/export && echo in > /sys/class/gpio/gpio11/direction
cat /sys/class/gpio/gpio11/value      # nível real de PA11
echo 1c2ac00.i2c > $D/bind
```

Com o display ligado, `PA11` e `PA12` deram `1` — prova de que o módulo estava
alimentado e que os fios chegavam nos pinos certos.

## Bit-bang para separar controlador de módulo

Ainda sem resposta em endereço nenhum, faltava distinguir "controlador sem
jeito" de "módulo morto". O teste decisivo foi falar I2C **na mão**, piscando os
dois GPIOs pelo sysfs — o script que ficou no repositório é
`scripts/i2c-bb-probe.py`.

Open-drain emulado em duas linhas: para nível baixo o pino vira saída em `0`;
para liberar, volta a entrada e quem puxa é o pull-up do módulo.

Resultado: nenhum ACK entre `0x08` e `0x77`. Ou seja, o controlador estava
inocente.

## O culpado era a ordem dos fios

O módulo tinha serigrafia `0x78` e `0x7A`, que são os endereços em **8 bits** —
`0x78` = `0x3C` e `0x7A` = `0x3D` em 7 bits. Varrendo os dois: nada.

O que faltava era o óbvio: **`SDA` e `SCL` trocados**. Com as duas linhas em
3,3 V (pelos pull-ups do módulo), o barramento parece saudável, a varredura
"passa" sem erro e nenhum endereço responde.

A inversão foi confirmada por um teste que dispensa contar pinos: colocar `PA11`
e `PA12` como saída com duty cycles diferentes — 25% e 75% — e ler a **média** no
multímetro (~0,8 V e ~2,5 V). Assim dá para achar o pad certo em qualquer ponto
da montagem, sem confiar na contagem do header.

Depois da troca:

```text
$ i2cdetect -y -r 0 0x3c 0x3d
30:                                    3c --
```

*TODO: e aqui entra o desfecho do painel — o módulo passou a responder no I2C
mas a tela continuou apagada. Registrar o que resolveu (charge pump, variante
SH1106 ou alimentação em 5 V com os devidos cuidados de nível).*

## O daemon de status

*TODO: `scripts/nanopi-status-oled.py` — fonte 5×7 no próprio script, leitura de
`/proc/stat`, `/proc/meminfo` e `/proc/uptime`, IP por `nmcli`, atualização a
cada 2 s. Sem dependências externas.*

*TODO: serviço systemd com `Restart=always`, `After=multi-user.target`,
falha silenciosa — o display não pode derrubar nem atrasar o boot.*

## O que eu faria diferente

- **Continuidade antes de código.** A noite inteira foi gasta em software por
  causa de dois fios invertidos.
- **Um teste que mede elétrico, não lógico.** `i2cdetect` não achar nada não diz
  se o problema é o módulo, o fio ou o controlador; o bit-bang diz.
- **Testar o modo de teste do próprio chip primeiro.** `--all-on` separa
  "controlador não recebe nada" de "recebe e não consegue acender" — a diferença
  entre olhar fiação e olhar o painel.

---

*Complementa o primeiro artigo, sobre o host headless. Fiação, código de cores e
armadilhas ficam em `docs/14-display-lcd.md` (LCD) e `docs/16-display-oled.md`
(OLED): <https://github.com/guionardo/nanopi-neo-air>.*
