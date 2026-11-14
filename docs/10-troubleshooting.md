# 10 — Troubleshooting

Organizado por sintoma. Comece sempre pelas três perguntas:

1. **A fonte é 5 V / 2 A de verdade?** (maioria dos "defeitos" é fonte ou cabo)
2. **O cartão está bem gravado?** (`gzip -t`, `dd conv=fsync`, cartão Classe 10)
3. **O console serial mostra algo?** (sem isso, você está adivinhando)

## Boot

### Nada no console serial, LEDs acesos

| Causa provável | Verificação |
| --- | --- |
| Adaptador serial em 5 V | jumper de tensão do adaptador |
| TX/RX invertidos | pino 3 (TXD) → RX do adaptador; pino 4 (RXD) → TX |
| GND não conectado | pino 1 obrigatório |
| Baud errado | **115200 8N1**, sem flow control |
| Porta errada no PC | `dmesg | tail`, `ls /dev/ttyUSB*` |
| Sem permissão | `sudo usermod -aG dialout $USER` + relogin |
| Placa não está recebendo energia | LED PWR aceso? |

Teste rápido de que o adaptador está ok: faça **loopback** (junte TX e RX do
adaptador com um jumper) e digite no terminal — o texto deve voltar.

### Nada no console e LED PWR apagado

Placa sem energia. Teste:

```bash
# no PC, com um medidor USB: a placa deve puxar ~0,2 A em idle
```

- cabo microUSB só de carga? troque por um de dados;
- fonte fraca (< 2 A)? troque;
- microUSB da placa invertido/forçado? inspecione o conector.

### Para em `Hit any key to stop autoboot`

O u-boot não encontrou kernel/DTB no cartão.

1. Remova e regrave o cartão ([03](03-gravacao-sd.md)).
2. Verifique se as partições existem e o `boot` tem conteúdo:
   ```bash
   sudo mount /dev/sdX1 /mnt && ls /mnt
   ```
3. Se a árvore contém `sun50i-*` (H5) em vez de `sun8i-h3-nanopi-neo-air.dtb`,
   você baixou a imagem de outra placa.
4. Confirme que a imagem é `h3-...` (H3) e não `h5-...`.

### Para em `Uncompressing Linux...` e reinicia

Kernel incompatível ou RAM com problema. Teste outro cartão/imagem; se persistir
em qualquer imagem, é hardware.

### Boota, mas `df -h /` mostra ~1.5 GB

A expansão do rootfs não rodou.

```bash
lsblk
sudo resize2fs /dev/mmcblk0p2     # ajuste a partição
```

Se `resize2fs` reclamar que a partição é menor que o filesystem, primeiro
redimensione a partição com `fdisk`/`parted`, depois o filesystem. Alternativa
mais simples: regravar o cartão — a expansão é feita no primeiro boot.

### Boot aleatório: às vezes funciona, às vezes não

Clássico de **subtensão**. Troque a fonte antes de suspeitar do software. Também
pode ser contato do slot microSD — limpe com álcool isopropílico.

## Reset a cada ~4,5 s durante o boot (sem mensagem de erro)

Sintoma: o log chega ao initramfs, mostra `Starting systemd-udevd` e a placa
reinicia; não há `Kernel panic` nem `Oops`.

Procedimento de isolamento (detalhado em [12-log-de-bordo.md](12-log-de-bordo.md)):

1. **Confirme a fonte.** 5 V / 2 A dedicada, cabo curto. Este é o suspeito nº 1:
   o reset coincide com o momento em que eMMC e Wi-Fi começam a consumir.
2. **Interrompa o autoboot** (segure tecla nos 2 s) e observe `bad CRC, using
   default environment`. Ambiente corrompido = escrita anterior incompleta.
3. **Teste sem initrd** para ver se a placa fica estável:

   ```text
   fatload mmc 0 0x46000000 zImage
   fatload mmc 0 0x48000000 sun8i-h3-nanopi-neo-air.dtb
   setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait
   bootz 0x46000000 - 0x48000000
   ```

   Estável em `Waiting for root device` = o reset depende do coldplug (energia
   ou driver), não do rootfs em si. Reiniciando igual = problema de hardware/base.
4. **Persistindo com fonte boa:** considere a eMMC com imagem inválida. Refaça o
   eflasher ([05](05-gravacao-emmc.md)) a partir de um cartão SD.

> Uma imagem gravada de forma incompleta pode deixar a placa em loop e ainda
> permitir leitura pelo U-Boot — o que engana quem conclui "a eMMC está boa
> porque o U-Boot lê os arquivos".

## eMMC

### eMMC não inicia (placa "morta" sem cartão)

1. Coloque o cartão `sd` de volta: se boota pelo cartão, a placa está boa e o
   problema é a eMMC.
2. Refaça o eflasher ([05](05-gravacao-emmc.md)) com **outra** imagem eflasher.
3. Se o eflasher falha no meio da escrita, a eMMC pode estar com setores ruins —
   repita e observe a mensagem exata de erro no console.
4. Se nada grava, considere usar o sistema pelo cartão permanentemente.

### O eflasher não abre o menu

```bash
# console serial, root / fa
eflasher
```

Se o comando não existir, a imagem gravada não é um eflasher (é uma imagem `sd`).
Confira o nome do arquivo baixado.

### Instalou mas continua bootando pelo cartão

O cartão está inserido. Remova e energize. Verifique também:

```bash
findmnt -no SOURCE /
```

## Rede

### `wlan0` aparece como `unmanaged`

```bash
sudo cat /etc/network/interfaces
sudo ls /etc/network/interfaces.d/
```

Remova qualquer bloco que mencione `wlan0`/`wpa-ssid`, depois:

```bash
sudo systemctl restart NetworkManager
nmcli dev status
```

### Nenhuma rede Wi-Fi encontrada

```bash
rfkill list
sudo rfkill unblock all
sudo iw dev wlan0 scan | grep SSID
```

- antena U.FL conectada? (sem antena, o alcance é de centímetros)
- a rede é 5 GHz? O AP6212 é **somente 2.4 GHz**.
- SSID oculto? conecte com `hidden yes`.

### `wlan0` existe, mas `Failed to initiate sched scan` em loop

Este é o sintoma que mais engana: a interface sobe, o `dhclient` roda e não há
`Trying to associate`. Nenhuma varredura devolve resultado, então nada de
senha/SSID tem chance de estar errado — o rádio não sintoniza.

Causa mais comum nesta placa: **NVRAM errado** em
`/lib/firmware/brcm/brcmfmac43430-sdio.txt`. O firmware `.bin` é genérico, o
`.txt` não é. Se ele veio do `linux-firmware` (Raspberry Pi/AW-NB197SM), os
parâmetros não servem para o AP6212:

| Parâmetro | RPi (errado) | AP6212 (correto) |
| --- | --- | --- |
| `xtalfreq` | 37400 | **26000** |
| `boardrev` | 0x1202 | 0x1101 |
| `pa2ga0` | `0xff65,0x195a,0xfd03` | `-168,7161,-820` |
| `maxp2ga0` | 84 | 90 |
| `papdmode` | 1 | 2 |

Confira qual está instalado:

```bash
head -1 /lib/firmware/brcm/brcmfmac43430-sdio.txt
grep -E '^(xtalfreq|boardrev)=' /lib/firmware/brcm/brcmfmac43430-sdio.txt
```

Se a primeira linha não for `#AP6212_NVRAM...`, troque — o arquivo correto está
em `firmware/` neste repositório (ver [firmware/README.md](../firmware/README.md)):

```bash
sudo ./scripts/wifi-inject.sh /dev/sdX "SSID" "SENHA" ./firmware
```

Complemento útil no `wpa_supplicant.conf` (já aplicado pelo script): forçar
varredura normal em vez de varredura agendada.

```conf
disable_scan_offload=1
ap_scan=1
```

Diagnóstico sem serial: instale a sonda no cartão e leia o resultado no PC.

```bash
sudo ./scripts/install-probe.sh /dev/sdX     # roda 45 s após o boot da placa
sudo ./scripts/diag-wifi-card.sh /dev/sdX    # imprime /root/board-probe.txt
```

### Varre a rede, vê o SSID, mas nunca associa

Se o `scan_results` lista a sua rede e o `wpa_state` fica em `SCANNING` para
sempre, o suspeito número 1 é **grafia do SSID**: SSID diferencia maiúsculas de
minúsculas. `Minha-rede` ≠ `minha-rede`.

```bash
wpa_cli -i wlan0 scan_results | awk -F'\t' '{print $NF}' | sort -u
```

Compare caractere por caractere com o `ssid=` do
`/etc/wpa_supplicant/wpa_supplicant.conf`. Depois de corrigir:

```bash
sudo wpa_cli -i wlan0 reconfigure
```

Segundo suspeito: senha errada — mas aí aparece `4-Way Handshake failed` ou
`pre-shared key may be incorrect` no `wpa_cli status`/log, não silêncio.

### O MAC do Wi-Fi muda a cada boot

Com o `macaddr` placeholder do NVRAM, o `brcmfmac` gera um MAC aleatório em todo
boot — o lease do roteador muda e você perde o IP de vista. Fixe um MAC
localmente administrado (primeiro octeto `02`, `06`, `0A` ou `0E`):

```bash
sudo ./scripts/wifi-inject.sh /dev/sdX "SSID" "SENHA" ./firmware 02:00:00:00:00:01
```

Depois crie um lease estático no roteador para esse MAC. Confira na placa:

```bash
cat /sys/class/net/wlan0/address
```


### Conecta mas cai a cada poucos minutos

Power-save do Wi-Fi:

```bash
sudo iwconfig wlan0 power off
# permanente:
echo -e '[connection]\nwifi.powersave = 2' | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager
```

Sinal fraco também causa isso: `iwconfig wlan0 | grep Signal` (pior que -75 dBm
é problemático).

### Tem IP mas não navega

```bash
ip route                 # existe default via <gateway>?
cat /etc/resolv.conf     # tem nameserver?
ping -c2 1.1.1.1         # IP funciona?
ping -c2 deb.debian.org  # DNS funciona?
```

IP ok + nome falha = DNS. Sem rota default = gateway.

### SSH: `Connection refused` ou `Permission denied`

```bash
# no console serial
sudo systemctl status ssh
sudo systemctl enable --now ssh
sudo npi-config     # Interfacing Options → SSH → Enable
```

`Permission denied` com chave: permissões do `~/.ssh` (700) e
`authorized_keys` (600) no usuário `pi`.

### Me tranquei fora (sem SSH, sem teclado)

Console serial. Se você desabilitou o autologin, faça login com `pi` e a senha
que definiu. Se perdeu a senha: boot pelo cartão `sd` e edite a eMMC montada, ou
refaça o eflasher (perde os dados).

## Sistema

### `apt` falha com erro de data/assinatura

Relógio errado (sem NTP):

```bash
timedatectl
sudo date -s "2026-11-13 10:00:00"
sudo apt update
```

### `Out of memory` / processos mortos pelo kernel

512 MB é pouco:

```bash
free -h
sudo dmesg | grep -i -E 'oom|killed process'
```

- reduza serviços (`systemctl disable --now bluetooth` se não usar);
- aumente swap (com moderação);
- limite memória do seu serviço no systemd: `MemoryMax=256M`.

### Temperatura acima de 80 °C

```bash
cpu_freq
cpu_freq -s 624000     # reduz clock
```

- instale dissipador;
- o kernel 3.4 esquenta muito mais — use 4.14;
- verifique se há processo em loop (`top`).

### Sistema corrompido após queda de energia

```bash
sudo fsck -f /dev/mmcblk2p2    # com o sistema desmontado (boot pelo SD)
```

Prevenção: fonte decente, `sync` antes de desligar, e backup
([09](09-manutencao.md#backup-e-restauração-da-emmc)).

### `read-only file system`

O kernel remontou o rootfs como somente leitura após erro de I/O — geralmente
eMMC/cartão com problema ou falta de energia.

```bash
dmesg | grep -i -E 'I/O error|remount'
sudo mount -o remount,rw /
```

Se repetir, o meio está degradado: faça backup e troque (cartão) ou refaça a
eMMC.

## Diagnóstico por LED (resumo)

| Observado | Interpretação |
| --- | --- |
| PWR apagado | sem energia |
| PWR aceso, STAT sempre apagado | sem boot / kernel travado antes do disco |
| STAT piscando contínuo e rápido | boot em andamento ou erro repetido |
| STAT piscando lento (heartbeat) | sistema ok |
| STAT pisca e para | kernel panic — veja o console |
| STAT aceso fixo em placa já bootada | processo travado em I/O |

## Coleta de evidências para pedir ajuda

```bash
{
  uname -a
  cat /etc/os-release
  lsblk
  df -h
  free -h
  cpu_freq
  nmcli dev status
  systemctl --failed
  dmesg -T | tail -100
} > /tmp/diagnostico.txt 2>&1
```

Guarde o log do console serial (`picocom -l`) e o `/tmp/diagnostico.txt`. Com
esses dois arquivos, qualquer problema fica diagnosticável.
