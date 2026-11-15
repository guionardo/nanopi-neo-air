---
title: 'NanoPi NEO Air: de placa teimosa a host headless'
description: 'Como coloquei um NanoPi NEO Air para bootar sozinho pela eMMC, subir Wi-Fi com o NVRAM certo e ficar acessível por SSH — sem monitor, sem Ethernet e com um adaptador serial que não cooperava.'
date: 2026-11-15
slug: nanopi-neo-air-host-headless
tags: [nanopi, allwinner-h3, debian, emmc, linux, embarcados, wifi]
draft: true
lang: pt
translationKey: nanopi-neo-air-host-headless
# Quando as fotos estiverem em public/images/nanopi-neo-air-host-headless/,
# descomente as duas linhas abaixo (o caminho é relativo a public/).
# heroImage: /images/nanopi-neo-air-host-headless/header.jpg
# heroImageAlt: 'NanoPi NEO Air sobre a bancada, com cartão SD e adaptador serial ao lado.'
---

> **Resumo:** uma placa sem HDMI, sem Ethernet e com um sistema desconhecido na
> eMMC. O que destravou o projeto não foi um comando esperto, foi uma decisão de
> arquitetura: **eMMC é o sistema final, cartão SD é o canal de recuperação**. A
> partir dela, tudo virou reprovisionável pela rede — inclusive o Wi-Fi, que só
> funcionou depois de trocar um único arquivo de NVRAM que o próprio fabricante
> distribui errado.

<!-- FOTO (header): a placa em cima da bancada, com o cartão SD e o adaptador
     serial ao lado — é a imagem de abertura do post.
     arquivo: public/images/nanopi-neo-air-host-headless/header.jpg
     proporção: 1600×900 (16:9)
     legenda: "NanoPi NEO Air: 40 × 40 mm, sem HDMI e sem Ethernet."
     markdown: ![NanoPi NEO Air sobre a bancada](/images/nanopi-neo-air-host-headless/header.jpg)
-->

## O problema

O NanoPi NEO Air é uma plaquinha atraente: Allwinner H3 (quatro Cortex-A7),
512 MB de RAM, 8 GB de eMMC, Wi-Fi e Bluetooth no AP6212, tudo em 40 × 40 mm. O
preço dessa miniaturização é que **não existe HDMI nem Ethernet**. O acesso de
emergência clássico é o console serial — e o adaptador PL2303 da minha bancada
travava no meio do boot, ou nem abria a porta.

A eMMC veio com um sistema que eu não conhecia, em loop de reset. Sem vídeo, sem
rede e com serial instável, qualquer tentativa de "consertar" era um chute: eu
não tinha como ver o que estava acontecendo.

A primeira mudança de postura foi parar de tentar consertar o desconhecido.
**Sistema novo, em vez de sistema consertado.**

## A decisão que destravou tudo

Duas regras simples, que valem para qualquer SBC sem vídeo:

1. **A eMMC é o sistema final.** É onde o sistema mora, boota sozinho e é o que
   você vai operar no dia a dia.
2. **O cartão SD é o canal de recuperação.** Ele sobe um sistema completo, monta
   a eMMC e permite consertá-la pela rede — inclusive quando o sistema da eMMC
   não boota mais.

Isso resolve o problema de ovo e galinha do provisionamento. Em vez de "gravar o
cartão, copiar para a eMMC, tirar o cartão, descobrir que faltou algo, recomeçar",
o cartão passa a ser um **ambiente de manutenção**: você entra nele por SSH e
monta a eMMC como um diretório qualquer.

Com o cartão no ar, a eMMC vira `mmcblk1`; sem o cartão, ela vira `mmcblk0`. Parece
detalhe, mas é a origem de metade dos erros de script nessa placa — e o `boot.cmd`
do sistema gravado espera exatamente `root=/dev/mmcblk0p2`.

## Gravar a eMMC sem GUI

O instalador da FriendlyElec (eflasher) é feito para ser usado com monitor e
teclado. Sem eles, o caminho é chamar o script de flash do próprio payload, que
aceita a imagem como argumento e escreve na eMMC com verificação.

O resultado da gravação, no meu caso:

```text
FLASH_DONE verify=ok
```

Essa linha é o contrato: se `verify` não for `ok`, não vale seguir. Depois dela,
a placa boota **sem o cartão** — e é isso que precisa ser testado antes de
qualquer configuração: desligar, remover o cartão, ligar, esperar o LED e ver se
ela aparece na rede.

<!-- VÍDEO: o boot com o cartão no lugar — LED verde piscando e o log do
     eflasher correndo na tela do terminal (gravação de tela ou celular
     apontado para a placa).
     arquivo: public/videos/nanopi-neo-air-host-headless/boot-emmc.mp4
     duração: 15–25 s, sem áudio ou com áudio removido
     legenda: "Primeiro boot: o cartão grava a eMMC e a placa desliga sozinha."
     html:
       <video controls preload="metadata" playsinline
              src="/videos/nanopi-neo-air-host-headless/boot-emmc.mp4"></video>
-->

## O Wi-Fi que não subia

Aqui está o achado que mais custou tempo — e o mais divertido de contar.

O kernel da FriendlyElec (4.14) usa o `brcmfmac` para o BCM43430 do AP6212. O
driver precisa de dois arquivos em `/lib/firmware/brcm/`:

- `brcmfmac43430-sdio.bin` — o firmware;
- `brcmfmac43430-sdio.txt` — o **NVRAM**: calibração de rádio específica do módulo.

O `linux-firmware` do Debian traz um NVRAM de BCM43430 "genérico", que na verdade
é do módulo AW-NB197SM (o do Raspberry Pi Zero W). O driver aceita, o chip
inicializa no SDIO, o `wlan0` aparece... e o rádio **não varre**. O log fica num
loop:

```text
wpa_supplicant: wlan0: Failed to initiate sched scan
dhclient: No DHCPOFFERS received
```

Nenhum `Trying to associate`. Não era senha, não era SSID, não era driver: era
calibração.

A diferença entre os dois arquivos é pequena e decisiva:

| Parâmetro | NVRAM genérico (RPi) | NVRAM do AP6212 | Efeito |
| --- | --- | --- | --- |
| `xtalfreq` | 37400 | **26000** | sintetizador na referência errada: o rádio não varre |
| `boardrev` | 0x1202 | **0x1101** | layout de PA diferente |

Um único valor (`xtalfreq`) separa um rádio mudo de um rádio funcional. Com o
NVRAM correto do AP6212, o resultado foi imediato:

```text
$ iw dev wlan0 link
Connected to aa:bb:cc:dd:ee:01 (on wlan0)
        SSID: minha-rede
        freq: 2432
        signal: -31 dBm
        rx bitrate: 72.2 MBit/s
```

<!-- FOTO (captura de tela): o terminal com `iw dev wlan0 link` e o sinal
     verde, para o leitor ver que é saída real e não exemplo inventado.
     arquivo: public/images/nanopi-neo-air-host-headless/iw-link.png
     legenda: "O rádio associado: -31 dBm, 72 Mbit/s."
     markdown: ![Saída do iw dev wlan0 link](/images/nanopi-neo-air-host-headless/iw-link.png)
-->

### A parte que ninguém acredita

O **próprio payload da eMMC** da FriendlyElec entrega o NVRAM errado. Os arquivos
em `/lib/firmware/brcm/` são symlinks para `/lib/firmware/ap6212/`, e o
`nvram_ap6212.txt` de lá é o mesmo genérico do `linux-firmware` — mesmos valores
de `pa2ga0`, `maxp2ga0` e `papdmode` de outro módulo.

Ou seja: "usar o firmware do fabricante" não é garantia de nada. O que funcionou
foi extrair o NVRAM certo da imagem oficial do AP6212 e **versionar o arquivo no
repositório**, com procedência e um script que o extrai de novo se preciso. Um
binário de 925 bytes que decide se a placa tem rede.

### Dois detalhes menores, mas que mordem

- **SSID é case-sensitive.** Perdi tempo com uma rede chamada `minha-rede` digitada
  como `minha-rede`... e depois como `MinhaRede`. O `wpa_supplicant` não reclama: ele
  simplesmente nunca encontra o AP.
- **O driver ignora o MAC do NVRAM.** Mesmo com `macaddr` no arquivo, o `wlan0`
  subia com um MAC diferente a cada boot. A solução foi fixar no NetworkManager,
  que troca o endereço antes de associar:

```ini
[wifi]
ssid=minha-rede
mode=infrastructure
# 2 = desligado. Precisa ficar em [wifi]: em [connection] o NM ignora e o
# rádio fica em power-save (latência de ~60 ms em vez de ~17 ms).
powersave=2
cloned-mac-address=02:00:00:00:00:01
```

O comentário acima não é decorativo. Na primeira versão eu tinha posto
`wifi.powersave=2` na seção `[connection]`. O NetworkManager ignorou em silêncio,
o rádio ficou em power-save e o ping médio era **60 ms**. Movendo a chave para
`[wifi]`, caiu para ~17 ms. Mesma rede, mesmo sinal, três vezes menos latência.

## Provisionar a eMMC pela rede

Com o cartão no ar e a eMMC montada, a configuração do sistema final passou a ser
um script rodando **de fora**, sobre o rootfs da eMMC:

```text
==> sistema atual: /dev/mmcblk0p3 · rootfs da eMMC: /dev/mmcblk1p2
==> firmware instalado na eMMC: brcmfmac43430-sdio.bin / .txt
==> NVRAM confirmado: AP6212
==> perfil criado: /etc/NetworkManager/system-connections/minha-rede.nmconnection
==> sshd habilitado no boot da eMMC
```

<!-- FOTO (captura de tela): a saída do script de provisionamento rodando no
     cartão, com as linhas "NVRAM confirmado: AP6212" e "perfil criado".
     arquivo: public/images/nanopi-neo-air-host-headless/provisionamento.png
     legenda: "Provisionando a eMMC pela rede, com o cartão no ar."
     markdown: ![Saída do provisionamento da eMMC](/images/nanopi-neo-air-host-headless/provisionamento.png)
-->

Nenhum ciclo de "tirar cartão, gravar, devolver". E quando algo dá errado, o
cartão continua ali, intacto, como saída de emergência.

Um cuidado que virou padrão no script: ele **não** sincroniza senhas por padrão.
Copiar o hash de `/etc/shadow` do sistema do cartão é ótimo na instalação inicial
e péssimo depois — apagaria silenciosamente uma senha já trocada na eMMC. Agora
isso é opt-in (`SYNC_PASS=1`).

## Enxugar o sistema

Sistema que boota não é sistema pronto. Alguns ajustes que mudam o dia a dia:

| Item | Ação | Por quê |
| --- | --- | --- |
| `ModemManager` | desabilitar | não há modem; ele sonda portas seriais e atrapalha |
| `systemd-binfmt` | mascarar | o kernel do vendor não tem `binfmt_misc` e a unit falhava a cada boot |
| `bluetooth` | desabilitar | o AP6212 tem BT, mas nada usa |
| `getty@tty1` | parar + mascarar | não existe teclado/tela; o getty gastava um processo |

O `getty@tty1` rendeu uma lição: `systemctl disable --now getty@tty1` removeu o
symlink e o serviço **continuou ativo**. Em unit instanciada, foi preciso `stop`
+ `mask`. Detalhe bobo, mas se você confia só no `disable --now`, o processo fica.

Depois da limpeza, o sistema inteiro cabe em 13 serviços, 77 MB de RAM e duas
portas abertas:

```text
$ ss -tuln
tcp  0.0.0.0:22      tcp  [::]:22
udp  0.0.0.0:123     udp  127.0.0.1:123     udp  192.168.1.50:123
```

Só SSH e NTP. O resto do que a placa oferece (GPIO, SPI, câmera) fica disponível,
sem nada escutando.

## 163 pacotes sem perder o SSH

A placa estava com 163 atualizações pendentes, incluindo `libc6`, `systemd`,
`openssh` e `network-manager` — exatamente o que sustenta o acesso remoto.

O risco real não é o kernel (o da FriendlyElec vem fora do apt, então atualizar
não mexe no boot). O risco é o `systemd` reiniciar serviços no meio do
`full-upgrade` e a sessão SSH morrer com o `dpkg` pela metade.

A receita que usei:

```bash
setsid nohup sh -c 'DEBIAN_FRONTEND=noninteractive apt-get -y \
  -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  full-upgrade' > /root/pre-upgrade/upgrade.log 2>&1 < /dev/null &
```

Três detalhes que fazem diferença:

- **`setsid nohup`**: o upgrade deixa de depender da sessão. Se o SSH cair, o
  `apt` continua e você reconecta depois.
- **`--force-confold`**: sem isso o `dpkg` abre prompt de conffile, o upgrade para
  e — com a sessão morta — você fica sem saber por quê. O `confold` mantém seus
  arquivos locais.
- **backup do que é difícil de reconstruir**: antes de começar, copiei o perfil
  do NetworkManager e o `sshd_config`. Se algo fosse sobrescrito, o conserto
  seria trivial.

Resultado:

```text
EXIT=0
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
dpkg --audit: (vazio)

libc6            2.36-9+deb12u3   -> 2.36-9+deb12u14
systemd          252.19-1~deb12u1 -> 252.39-1~deb12u2
openssh-server   9.2p1-2+deb12u1  -> 9.2p1-2+deb12u10
network-manager  1.42.4-1         -> 1.42.4-1+deb12u1
kernel           4.14.111 (inalterado)
```

Depois do reboot, Wi-Fi de volta no mesmo IP, NTP sincronizado, zero unidades
falhando. O detalhe que quase virou susto: `timedatectl` responde
`NTPSynchronized=no` no primeiro minuto de boot. Não é falha — é o `ntpsec` ainda
fazendo a primeira sincronização.

## O root não é o que parece: overlayfs

Um detalhe que muda backup, `fsck` e qualquer diagnóstico de "disco cheio":

```text
$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
overlay         5.8G  2.1G  3.5G  38% /
```

O rootfs não é uma partição de 5,8 GB. O `boot.cmd` explica:

```text
root=/dev/mmcblk0p2 rootfstype=ext4 ...
setenv overlayfs data=/dev/mmcblk0p3
```

Ou seja: `mmcblk0p2` (1,4 GB) é a camada **inferior** e `mmcblk0p3` (`userdata`,
5,8 GB) é a camada **superior** gravável. O `df` mostra o conjunto. Consequências
práticas:

- não é preciso montar `userdata` em lugar nenhum — ela **é** o espaço livre;
- backup e `fsck` têm que tratar as duas partições juntas;
- um `rsync` "só da raiz" não reproduz o sistema; ele está espalhado nas duas.

## Display LCD Nokia 5110: em andamento

Com o sistema estável, o próximo passo é um painel de bancada: um LCD Nokia 5110
(PCD8544, 84×48) mostrando o que você veria ao logar — **IP, CPU, memória e
uptime**.

Duas descobertas já feitas no sistema em produção valem para quem for repetir:

**1. O kernel não aciona o chip select.** O SPI0 já vem habilitado no device tree
(`/dev/spidev0.0`, `compatible = nanopi,spidev`), mas o pino `PC3` — o CS do
header — aparece assim:

```text
pin 67 (PC3): 1c68000.spi (GPIO UNCLAIMED) function gpio_out group PC3
```

Ele está em função `gpio_out`, **não** em `spi0`, e nenhum driver o reivindicou.
O `sun6i-spi` do kernel 4.14 ignora a propriedade `cs-gpios`, e o pino fica em
nível alto: o display ignora tudo e parece queimado. Solução: acionar o CS por
software (sysfs/GPIO) ou aterrar o pino.

**2. Os pinos "óbvios" estão ocupados.** `PA0` e `PA1` (pinos 11 e 22 do header)
estão tomados pelo driver do UART2, mesmo sem getty neles. O `PA6` (pino 12) faz
parte do pinctrl do SPI0. Os GPIOs realmente livres são `PG8`, `PG9` e `PG11`.

A fiação que ficou definida:

| Módulo | Header | GPIO |
| --- | --- | --- |
| `VCC` | pino 1 (3,3 V) | — |
| `GND` | pino 6 | — |
| `CLK` | pino 23 | `PC2` = 66 |
| `DIN` | pino 19 | `PC0` = 64 |
| `CE` | pino 24 | `PC3` = 67 (por software) |
| `DC` | pino 16 | `PG8` = 200 |
| `RST` | pino 18 | `PG9` = 201 |
| `LIGHT` | jumper do módulo | — |

<!-- FOTO (galeria, 2 imagens lado a lado quando publicar): o módulo PCD8544
     e o jumper do backlight; e o header da placa com os fios soldados.
     arquivos:
       public/images/nanopi-neo-air-host-headless/display-modulo.jpg
       public/images/nanopi-neo-air-host-headless/display-fiacao.jpg
     legenda: "O módulo Nokia 5110 e a fiação no header de 24 pinos."
     markdown (uma por linha):
       ![Módulo LCD Nokia 5110 com o jumper do backlight](/images/nanopi-neo-air-host-headless/display-modulo.jpg)
       ![Fiação do display no header da NanoPi](/images/nanopi-neo-air-host-headless/display-fiacao.jpg)
-->

O barramento já foi validado com um teste de fumaça que não instala nada —
`ioctl` direto no `spidev` pela biblioteca padrão do Python — e transmitiu 2536
bytes com zero erros. Falta plugar o display e ver os padrões na tela. Quando
isso acontecer, conto aqui o resultado (e a tela de status).

<!-- VÍDEO: a tela de status funcionando — IP, CPU, memória e uptime no LCD,
     com o terminal ao lado mostrando os mesmos valores. Gravar só depois de
     validar o display; até lá este bloco fica comentado.
     arquivo: public/videos/nanopi-neo-air-host-headless/display-status.mp4
     duração: 10–20 s (plano fixo, sem áudio)
     legenda: "O painel de bancada: o que você veria ao logar, sem logar."
     html:
       <video controls preload="metadata" playsinline
              src="/videos/nanopi-neo-air-host-headless/display-status.mp4"></video>
-->

## O que eu faria diferente

- **Trataria a recuperação como requisito, não como plano B.** O cartão SD como
  canal de manutenção mudou o ritmo do projeto: qualquer erro virou reversível.
- **Versionaria o NVRAM desde o primeiro dia.** Um binário de 925 bytes que não
  está no repositório é um projeto que não reproduz.
- **Documentaria as evidências, não só os passos.** Cada comando com a saída real
  (inclusive os que falharam) virou a parte mais útil da documentação depois.
  "Funcionou" não ensina nada; `FLASH_DONE verify=ok` e `Power save: off`
  ensinam.
- **Testaria o upgrade antes de precisar dele.** Descobrir que `disable --now`
  não para uma unit instanciada durante uma emergência é bem pior.

## O artefato

Tudo isso virou um repositório de documentação: decisões numeradas (`D-001`…),
log de bordo com as sessões de bancada e os "achados", backlog de ideias,
scripts de flash/provisão/sonda e o firmware do Wi-Fi versionado com procedência.
Está em <https://github.com/guionardo/nanopi-neo-air>.

E, para não deixar o processo só como leitura, o repositório tem um instalador
que faz o caminho inteiro: confere o ambiente, grava o cartão, injeta Wi-Fi +
firmware + chave SSH, arma a gravação da eMMC e provisiona o sistema final pela
rede. Do computador, tudo cabe em três comandos:

```bash
./install.sh card     # grava e prepara o cartão
./install.sh net      # espera a placa, grava a eMMC e provisiona
./install.sh verify   # confere o sistema que subiu da eMMC
```

Não é burocracia: seis meses depois, o que você vai querer saber não é *o que*
foi feito, é **por que** aquele parâmetro está naquele valor. Foi o que salvou o
`xtalfreq`.

---

*Valores de rede (SSID, IP e MAC) foram substituídos por placeholders neste
artigo. O kernel é 4.14.111, o userland é Debian 12 bookworm e a placa é uma
NanoPi NEO Air com eMMC de 8 GB.*
