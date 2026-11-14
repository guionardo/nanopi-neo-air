# 12 — Log de bordo

Registro cronológico do que foi **realmente observado** na placa, com evidências.
Diferente dos outros documentos (que descrevem o procedimento), aqui fica o que
aconteceu — inclusive o que deu errado.

Formato: data · o que foi feito · o que foi observado · conclusão.

---

## Sessão 1 — 2026-11-13 · primeira conexão serial

### Bancada

| Item | Valor |
| --- | --- |
| Adaptador serial | Prolific PL2303 (USB ID `067b:2303`) |
| Porta no host | `/dev/ttyUSB0` |
| Permissão | usuário no grupo `dialout` (OK) |
| Baud | 115200 8N1, sem flow control |
| Ferramenta | [`scripts/serial-console.py`](../scripts/serial-console.py) |

### Achado 1 — a eMMC **não** está virgem

O pressuposto inicial ("eMMC virgem, só dá boot por SD") estava **errado**.
A placa inicia sozinha e o U-Boot reporta:

```
U-Boot SPL 2017.11 (Jun 15 2021 - 10:49:36)
DRAM: 512 MiB(408MHz)
Trying to boot from MMC2
Boot device: emmc
```

Ou seja: já existe um sistema na eMMC, gravado em algum momento anterior.

### Achado 2 — loop de reset a cada ~4,5 s

O boot avança até o initramfs e reinicia, sem mensagem de erro:

```
[    3.704462] Freeing unused kernel memory: 2048K
Loading, please wait...
Starting systemd-udevd version 255.4-1ubuntu8.2
                                                     <-- reset aqui
U-Boot SPL 2017.11 ...
```

- Não há `Kernel panic`, nem `Oops`, nem `reboot: ...`.
- O reset acontece **~0,2 s depois** de o `systemd-udevd` iniciar, dentro do
  initramfs (o rootfs nunca chega a ser montado).
- Ciclo completo: ~4,5 s de parede.

### Achado 3 — ambiente do U-Boot corrompido

Entrando no prompt (`Hit any key to stop autoboot` → `=>`):

```
*** Warning - bad CRC, using default environment
```

Consequências: `bootcmd` é o padrão (`fatload mmc 0:1 ${scriptaddr} boot.scr;
source ${scriptaddr}`) e `bootargs` **não existe** no ambiente — tudo vem do
`boot.scr` da partição 1.

### Inventário da eMMC (via U-Boot)

```
SUNXI SD/MMC: 1          -> controlador do cartão SD
SUNXI SD/MMC: 0 (eMMC)   -> eMMC

Partição  Início    Setores     Tamanho   Tipo
1         49152     81920       40 MiB    FAT  (boot)
2         131072    2883584      1,37 GiB  ext4 (rootfs)
3         3014656   12255232     5,85 GiB  ext4 (overlayfs /data)
```

Conteúdo da partição 1:

```
boot_cmd/  overlays/  uEnv.txt  boot.cmd  boot.scr
zImage (5,9 MB)   rootfs.cpio.gz (7,5 MB)
sun8i-h3-nanopi-neo-air.dtb  + dtbs de outras placas H3
```

`uEnv.txt` (variáveis relevantes):

```
kernel=zImage
ramdisk=rootfs.cpio.gz
kernel_addr=0x46000000
ramdisk_addr=0x47000000
dtb_addr=0x48000000
debug_port=ttyS0,115200
fsck.repair=yes
overlay: uart0/1/2, i2c0/1/2, spi0, pwm0, ir, tft28... (todos desabilitados)
```

`bootargs` gerado pelo `boot.cmd`:

```
console=ttyS0,115200 earlyprintk
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait fsck.repair=yes
panic=10 fbcon=map:0 overlayfs data=/dev/mmcblk0p3 pmdown_time=3600000
```

### Achado 4 — o sistema na eMMC não é um FriendlyCore padrão

- Kernel: **4.14.111** (armhf).
- Userland: **Ubuntu 24.04** — `systemd-udevd version 255.4-1ubuntu8.2`.
  O FriendlyCore publicado para H3 é baseado em 20.04/22.04. Ou seja, a imagem é
  mais nova que a documentação da wiki, ou foi montada/modificada à mão.

### Testes feitos para isolar a causa do reset

| Teste | Comando | Resultado |
| --- | --- | --- |
| Boot normal | (autoboot) | reset em ~3,9 s de kernel, durante udev do initramfs |
| Boot com `init=/bin/sh` | `bootz ... init=/bin/sh` | **idêntico** — o initramfs reinicia antes de `run-init`, então o argumento não chega a valer |
| Boot **sem initrd** | `bootz 0x46000000 - 0x48000000` | **não reinicia** em 35 s; para em `Waiting for root device /dev/mmcblk0p2...` |

Interpretação do último teste: sem o initramfs, o módulo do controlador MMC não é
carregado, então eMMC/Wi-Fi nunca são energizados — e a placa fica estável.
O reset está correlacionado com o **coldplug do udev**, que é exatamente o momento
em que eMMC e Wi-Fi passam a consumir corrente.

### Hipóteses (em ordem de probabilidade)

1. **Fonte 5 V insuficiente** — brownout no pico de corrente do eMMC/Wi-Fi.
   Encaixa com: estável no prompt do U-Boot e sem initrd; reset no coldplug.
2. **Imagem da eMMC gravada incompletamente** — o `bad CRC` do ambiente U-Boot é
   típico de escrita interrompida; um `eflasher` que falhou no meio produz
   exatamente esse estado.
3. Driver/módulo com falha silenciosa no 4.14 (menos provável: normalmente
   imprime oops; não há oops).

### Como o prompt do U-Boot foi obtido

Autoboot tem 2 s. Segurar qualquer tecla nesse intervalo:

```bash
# com o script do repositório
python3 scripts/serial-console.py --listen 5 --send ' '
```

### Comandos de recuperação usados

```text
printenv                          # ambiente (estava padrão, bad CRC)
mmc list                          # 1 = SD, 0 = eMMC
part list mmc 0                   # partições da eMMC
fatls mmc 0:1                     # arquivos da partição de boot
fatload mmc 0 0x43100000 boot.cmd # ler o script de boot
md.b 0x43100000 0x57e             # dump hex para inspecionar o boot.cmd
```

> Atenção: no ambiente padrão **não existem** `kernel_addr`, `ramdisk_addr` nem
> `dtb_addr` (eles vêm do `uEnv.txt`). Para bootar manualmente é preciso usar os
> valores literais `0x46000000` / `0x47000000` / `0x48000000`.

### Estado ao final da sessão 1

- Placa parada em `Waiting for root device` (requer power-cycle para sair).
- Nenhuma alteração foi gravada na eMMC (só leitura e boot em RAM).

---

## Sessão 2 — 2026-11-13 · causa do loop identificada

### Achado 5 — a placa estava com **duas fontes** ligadas ao mesmo tempo

Configuração encontrada: alimentação pelo pino **VDD_5V do adaptador serial** (que
entrega pouquíssima corrente) **e** um carregador de celular no microUSB.

Isso explica todo o comportamento observado:

| Observação | Explicação |
| --- | --- |
| Estável no prompt do U-Boot (minutos) | carga baixa, eMMC/Wi-Fi desligados |
| Estável sem initrd (35 s) | driver MMC não carrega, eMMC não é energizada |
| Reset ~0,3 s após o udev iniciar | coldplug energiza eMMC + Wi-Fi → pico de corrente → brownout |
| Sem `panic`/`oops` no log | não é software: o SoC é reiniciado por subtensão |

O adaptador PL2303 não é fonte: alimentar a placa por ele funciona até a carga
subir, e então o sistema reinicia em loop.

### Achado 6 — a imagem da eMMC é oficial (Ubuntu Noble Core)

A pasta oficial de downloads foi mapeada e o sistema da eMMC corresponde a:

```
h3-eflasher-ubuntu-noble-core-4.14-armhf-20260330.img.gz
```

Ou seja: o `systemd 255.4-1ubuntu8.2` observado é **Ubuntu Core 24.04**, coerente
com a imagem mais recente publicada para H3. O `bad CRC` no ambiente do U-Boot é
comportamento normal quando a variável de ambiente nunca foi salva (imagem
gravada "crua" não tem env válido) — **não** indica corrupção por si só.

Isso **rebaixa** a hipótese 2 da sessão 1 (imagem corrompida). A hipótese 1
(fonte) passa a ser a única consistente com as evidências.

### Achado 7 — o endereço oficial de download mudou

`download.friendlyelec.com/NanoPiNEOAir` redireciona para o portal; as imagens
estão em um Google Drive público (ver [02](02-preparo-imagem.md#baixando)).
Existem `sha256sum.txt` oficiais — usar sempre.

### Correção aplicada

- Fio **VDD_5V removido** do adaptador serial: restaram GND (pino 1), TX (pino 3)
  e RX (pino 4).
- Alimentação passou a ser **somente** pelo microUSB, com carregador 5 V / 2 A.

### Próximos passos (da sessão 2)

1. Power-cycle com fonte única e capturar o boot completo.
2. Se subir: tentar login (`root`/`fa` nas imagens core da FriendlyElec; `pi`/`pi`
   nas com interface) e validar rede/SSH.
3. Se não subir: gravar `h3-sd-ubuntu-noble-core-...img.gz` no cartão SD e usar o
   sistema pelo cartão para diagnosticar/refazer a eMMC.
4. Registrar no [11-decisoes.md](11-decisoes.md) os dados da placa (MAC, versão).

---

## Sessão 3 — 2026-11-13 · fonte corrigida, novo obstáculo

### Resultado da correção de alimentação: **loop de reset resolvido**

Com o fio VDD_5V removido e a placa alimentada só pelo carregador, o boot
completou. Confirmação: o console passou a exibir prompt de login em vez de
reiniciar. Causa do loop fechada — era subtensão, como suspeitado.

### Achado 8 — loop de getty inutiliza o console

O console não fica utilizável: aparece um ciclo contínuo

```
username = pi
Password = pi

NanoPi-NEO-Air login: username = pi
Password = pi

NanoPi-NEO-Air login: ...
```

medições:

| Medida | Valor |
| --- | --- |
| Ocorrências de `login:` em 2 s | **25.652** |
| Bytes recebidos em 2 s | 1.333.904 |
| Taxa aparente | ~667 kB/s |

A taxa é fisicamente impossível em 115200 8N1 (máx. ~11,5 kB/s), então há também
**duplicação/entrega anômala pelo adaptador** sob fluxo contínuo (PL2303 genérico).
Fica registrado como pendência de instrumentação: para medir taxa real, usar outro
adaptador (CP2102/FT232) ou um analisador lógico.

Interpretação do loop: o `login` (ou o `agetty --autologin pi`) sai imediatamente e
é reiniciado, reimprimindo o banner (`/etc/issue`) com as credenciais sugeridas.
Consequências práticas:

- **não é possível digitar comandos** (o processo que lê o console morre antes);
- a placa provavelmente está com o restante do sistema **no ar** (o loop é local ao
  getty);
- `pi`/`pi` e `root`/`fa` não puderam ser testados por essa via.

### Achado 9 — sem SysRq neste adaptador

`tcsendbreak()` e `ioctl(TIOCSBRK)` falham com `EPIPE` no PL2303: o chip não
implementa BREAK. Logo, **não há como reiniciar a placa pelo software** — o
power-cycle é obrigatório.

### Ferramenta criada

[`scripts/serial-boot-override.py`](../scripts/serial-boot-override.py): fica
esperando o próximo boot, interrompe o autoboot e inicia o kernel com cmdline
própria (por padrão `init=/bin/sh`), liberando o console para recuperação.

---

## Sessão 4 — 2026-11-13 · causa do loop de getty: corrupção no ext4

### Como o shell de diagnóstico foi obtido

O override iniciou o kernel com `init=/bin/sh`. O initramfs ignora esse argumento
para o *init real*, mas o efeito prático foi outro: o initramfs não conseguiu
montar o rootfs e caiu no shell `(initramfs)`, que já é root. Foi o suficiente.

Estado encontrado: `rootfs` em RAM, eMMC enumerada como **`/dev/mmcblk3`**.

```text
/dev/mmcblk3     8GB 8GTF4R (MMC)
/dev/mmcblk3p1   40 MiB  FAT   (boot)
/dev/mmcblk3p2   1,4 GiB ext4  (Debian 12.4, label rootfs)
/dev/mmcblk3p3   6,1 GiB       (filesystem não reconhecido)
```

### Achado 10 — a eMMC é saudável; a corrupção é lógica

Leitura sequencial de 25 MB em p2 e em p3: `400+0 records in / 400+0 records out`,
**sem erro de I/O**. O chip responde bem; o problema é o sistema de arquivos.

### Achado 11 — p2 corrompida (causa do loop de getty)

Montada em `/mnt`, a p2 respondeu com erros do ext4:

```text
EXT4-fs error (device mmcblk3p2): ext4_find_entry:1449: inode #19135:
  comm ls: checksumming directory block 0
ls: /mnt/sbin/agetty: Bad message
ls: /mnt/usr/sbin/agetty: Bad message
```

`e2fsck -fn` (somente leitura) mostrou o tamanho do estrago:

```text
Inode 33022 is a zero-length directory.
Inode 43187 has an invalid extent node (blk 264076, lblk 0)
Directory inode 16783, block #0, offset 0: directory corrupted
e2fsck: aborted
rootfs: ********** WARNING: Filesystem still has errors **********
```

O diretório `/usr/sbin` está ilegível — e é onde vive o `agetty`. O getty morre ao
ser executado, o systemd o reinicia, e o console é inundado com o banner
(`/etc/issue`). Isso fecha a causa do **loop de getty** da sessão 3.

Origem provável da corrupção: os **brownouts repetidos** da sessão 2 (duas fontes).
Cada reset em loop acontecia com o ext4 montado `rw`; dezenas de desligamentos
sujos em poucos minutos produzem exatamente esse padrão (inodes com extent tree
inválida, diretórios com checksum quebrado).

### Achado 12 — p2 é Debian 12.4, e isso é coerente com o eflasher

```text
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
VERSION="12.4"
/etc/hostname -> FriendlyElec
/etc/fstab    -> # UNCONFIGURED FSTAB FOR BASE SYSTEM
/bin/login    -> presente;  /usr/sbin/agetty -> ilegível
```

A "mistura Ubuntu 24.04 / Debian 12" registrada na sessão 1 **não é** gravação
incompleta: o eflasher usa um initramfs Ubuntu 24.04 para instalar um payload
Debian 12. É o comportamento normal dessa imagem.

### Achado 13 — p3 não é montável (filesystem desconhecido no initramfs)

```text
mount -t ext4 /dev/mmcblk3p3 /mnt2  -> Invalid argument
mount -t auto /dev/mmcblk3p3 /mnt2  -> Invalid argument
```

`/proc/filesystems` do initramfs lista apenas ext2/3/4, vfat, overlay, nfs. A p3
provavelmente é **f2fs/btrfs/xfs** (ou está vazia). Só é possível confirmar com um
`blkid`/`file -s` de um sistema completo. Fica pendente.

### Achado 14 — o cartão SD já é um cartão eflasher pronto

O cartão do usuário (`/dev/sdc`, 58,6 GB) não estava vazio:

```text
sdc1  6,4 GiB  exFAT  "FriendlyARM"  -> eflasher.conf + debian-bookworm-core/ (1,2 GB)
sdc2  40 MiB   vfat   "BOOT"         -> zImage, rootfs.cpio.gz, dtbs, uEnv.txt, boot.scr
sdc3  850 MiB  ext4   "rootfs"
```

`eflasher.conf`:

```ini
[General]
autoStart=debian-bookworm-core
autoExit=false
disableLowFormatting=false
```

Ou seja: **basta dar boot pelo cartão e o eflasher regrava a eMMC sozinho**, sem
display (o NEO Air não tem HDMI). Não é preciso baixar nem gravar imagem nova.

Observação de bancada: o cartão não aparecia no `lsblk` porque o leitor **não havia
sido conectado** — o `lsusb` mostrava apenas o PL2303. Depois de conectado,
apareceu como `/dev/sdc`.

### Reparo tentado e por que foi descartado

`e2fsck -fy` foi executado duas vezes. Resultado:

```text
Pass 5: Checking group summary information
rootfs: 45320/90112 files (0.1% non-contiguous), 294583/360448 blocks
```

A segunda passagem saiu **limpa** — o filesystem agora é consistente. Porém o
reparo **removeu inodes** (`Inode bitmap differences: -16831 -29003 -30448 -33022
-43282`), o que pode ter apagado justamente arquivos de `/usr/sbin`. Além disso a
p3 segue inutilizável. Um sistema assim não é confiável para produção.

**Decisão:** descartar o reparo e regravar a eMMC pelo eflasher do cartão.


---

## Sessão 5 — 2026-11-13 · gravação da eMMC pelo eflasher, sem GUI

### Contexto

O cartão SD identificado na sessão 4 é um **eflasher** com o payload
`debian-bookworm-core`. A GUI (`/opt/eflasher-gui`, Qt) não funciona no NEO Air
porque a placa não tem display — e a eMMC não foi tocada (mesmas partições,
mesmo hostname).

### Achado 15 — o payload é Android sparse, não imagem crua

`rootfs.img` e `userdata.img` começam com `3a ff 26 ed` = **0xED26FF3A**, magic
do formato *Android sparse*. `dd` direto produz lixo — foi exatamente o que
aconteceu na primeira tentativa (p2 ficou sem superbloco ext4: `Bad magic number
in super-block`). O `boot.img`, por contraste, começa com `eb 3c 90 6d` e é FAT
cru — esse `dd` está correto.

`partmap.txt` define tudo:

```text
flash=mmc,0:boot0:raw:0x2000,0x17FE000:u-boot-sunxi-with-spl.bin
flash=mmc,0:boot:fat:0x1800000,0x2800000:boot.img
flash=mmc,0:rootfs:ext4:0x4000000,0x58000000:rootfs.img
flash=mmc,0:userdata:ext4:0x5C000000,0x0:userdata.img
```

Conferência importante: o U-Boot da eMMC é **byte a byte igual** ao
`u-boot-sunxi-with-spl.bin` do cartão na área de usuário (offset 0x2000) — e
**diferente** na partição `boot0` de hardware. Portanto grava-se em
`/dev/mmcblk3`, não em `mmcblk3boot0`.

### Achado 16 — ambiente sem `simg2img` e sem `python3`

Nem o host, nem o rootfs do eflasher têm `simg2img`. O rootfs do cartão também
não tem `python3`. Solução: um decodificador de sparse em **bash puro**
([`scripts/unsparse.sh`](../scripts/unsparse.sh)), que lê os cabeçalhos com
`od -j` e grava cada chunk com `dd` direto no dispositivo.

Tipos de chunk (confirmados no `rootfs.img`, 31 chunks):

| Tipo | Valor | Ação |
| --- | --- | --- |
| `CAC1` raw | 51905 | `dd` do arquivo para o destino |
| `CAC2` fill | 51906 | zerar (padrão de 4 bytes) |
| `CAC3` dont-care | 51907 | zerar |
| `CAC4` crc | 51908 | ignorar |

Soma dos chunks: 360.448 blocos × 4096 = **1.476.395.008 bytes**, exatamente o
tamanho da p2.

### Achado 17 — o SD fica instável sob leitura longa

Durante o `dd` de 1,2 GB do exFAT:

```text
sunxi-mmc 1c0f000.mmc: data error, sending stop command
mmcblk1: timed out sending r/w cmd command, card status 0x900
mmc1: Problem switching card into high-speed mode!
```

A cada ~14 s o cartão é reiniciado e renegocia velocidade. Leituras curtas
(2 MB, 40 MB) passam; leitura contínua de 1,2 GB não. Suspeitas, em ordem:
driver **exFAT out-of-tree 1.2.9** (kernel 4.14) sob I/O longo, cartão de 64 GB
de qualidade duvidosa, ou alimentação marginal durante leitura+escrita
simultâneas. Pendente de discriminar.

### Estado ao final da sessão 5

| Item | Estado |
| --- | --- |
| U-Boot na eMMC (0x2000) | ✅ gravado e idêntico ao payload |
| p1 (boot, FAT) | ✅ `boot.img` gravado |
| p2 (rootfs) | ❌ inválida — tentativa com `dd` cru; precisa do decodificador |
| p3 (userdata) | ❌ inválida pelo mesmo motivo |
| Decodificador | ✅ em `/tmp/u` no rootfs do cartão |
| Shell de trabalho | `[SD]#` (initramfs) com rootfs do cartão em `/newroot` |

### Como retomar (sem GUI)

Com o SD no slot e a placa no shell do initramfs:

```sh
# 1. montar o rootfs do cartao e o payload
mkdir -p /newroot
mount -t ext4 /dev/mmcblk1p3 /newroot
mount -t proc proc /newroot/proc
mount -t sysfs sys /newroot/sys
mount --bind /dev /newroot/dev
chroot /newroot /bin/bash -c 'modprobe exfat; mount -t exfat /dev/mmcblk1p1 /mnt'

# 2. reconstruir o decodificador (se /tmp/u sumiu)
#    scripts/serial-put.py envia o arquivo por base64

# 3. gravar (p2)
chroot /newroot /bin/bash -c \
  'bash /tmp/u /mnt/debian-bookworm-core/rootfs.img /dev/mmcblk3 67108864 31'

# 4. gravar (p3)
chroot /newroot /bin/bash -c \
  'bash /tmp/u /mnt/debian-bookworm-core/userdata.img /dev/mmcblk3 1543503872 8'

# 5. verificar
e2fsck -fn /dev/mmcblk3p2
```

> A numeração muda conforme o *boot device* do U-Boot: com o cartão no slot, o
> SD é `mmcblk1` e a eMMC é `mmcblk3`. O `boot.cmd` do eflasher ajusta isso no
> device tree com `fdt set mmc<X> boot_device <1>`.


---

## Sessão 6 — 2026-11-13 · adaptador serial perdido, auto-flash headless

### Achado 18 — o PL2303 saiu do barramento USB

Durante a gravação do `rootfs.img` o adaptador desapareceu do host: `lsusb` sem
`067b`, nenhum `/dev/ttyUSB*`, mesmo depois de reconectar em **outra porta**.

```text
Bus 001 Device 003: ID 03f0:231d HP, Inc Broadcom 2070 Bluetooth Combo
Bus 001 Device 004: ID 138a:0007 Validity Sensors, Inc. VFS451
Bus 001 Device 005: ID 04f2:b163 Chicony Electronics Co., Ltd HP Webcam
(sem 067b:2303)
```

Não é rename de device: o chip não é enumerado. Hipótese principal: proteção de
overcurrent na porta USB (histórico de VDD_5V ligado junto com o carregador,
ver sessão 2) ou adaptador morto. Sem root no host não há como resetar o hub.

### Estado da eMMC ao final da sessão 6

| Item | Estado |
| --- | --- |
| U-Boot (0x2000) | ✅ gravado, idêntico ao payload |
| p1 (boot FAT) | ✅ gravado |
| p2 (rootfs) | ⚠️ recebeu `dd` cru do sparse — inválida |
| p3 (userdata) | ⚠️ recebeu `dd` cru do sparse — inválida |

Conclusão: **a eMMC não inicia** neste estado, e sem serial não dá para
consertar pelo console. Caminho escolhido: refazer pelo cartão, com gravação
automática e sem GUI.

### Achado 19 — decodificar sparse no próprio cartão resolve o problema

O cartão do eflasher tem Debian 12 core com `bash`, `od`, `dd` e `e2fsck`, mas
sem `simg2img` e sem `python3`. O decodificador em bash
([`scripts/unsparse.sh`](../scripts/unsparse.sh)) funciona nativamente ali.

O número de chunks **não precisa ser digitado**: está no cabeçalho sparse, em
`total_chunks` (offset 20) — e `total_blks` (offset 16) permite conferir o
tamanho. Atenção: o offset 12 é `blk_sz`, não `total_blks` (erro corrigido no
teste).

### Entrega

- [`scripts/flash-emmc-headless.sh`](../scripts/flash-emmc-headless.sh) — roda no
  cartão: detecta SD (boot) e eMMC (destino) por tamanho, grava U-Boot + p1,
  expande as duas sparse, roda `e2fsck -fn`, loga em `/root/flash-emmc.log` e
  desliga.
- [`scripts/install-headless-flash.sh`](../scripts/install-headless-flash.sh) —
  roda no PC com `sudo`: instala tudo na p3 do cartão, habilita o serviço,
  desabilita a GUI e arma a execução única.
- Documentado em [05](05-gravacao-emmc.md#alternativa-sem-display-e-sem-serial--auto-flash-headless).

Nada foi executado ainda: exige o cartão no PC e uma senha de `sudo`.

---

## Sessão 7 — 2026-11-13 · o auto-flash funcionou, e a eMMC boota

### Resultado

O `flash-emmc.service` rodou no boot com o cartão e fez tudo:

```text
[14:32:15] destino: /dev/mmcblk1 (7456 MiB)
[14:32:16] gravando U-Boot em offset 0x2000
[14:32:16] gravando boot (FAT) em offset 24 MiB
[14:32:23] rootfs: 31 chunks, 360448 blocos, offset 67108864
...
[14:34:46] rootfs: gravado
[14:34:46] userdata: 8 chunks, 51200 blocos, offset 1543503872
[14:34:49] userdata: gravado
[14:34:53] p2 OK: superbloco ext4 valido e sem erros
[14:34:54] FLASH_DONE verify=ok
```

| Etapa | Resultado |
| --- | --- |
| U-Boot em `0x2000` | ✅ |
| p1 `boot.img` (FAT) | ✅ |
| p2 `rootfs.img` (31 chunks) | ✅ 1.476.395.008 bytes |
| p3 `userdata.img` (8 chunks) | ✅ 209.715.200 bytes |
| `e2fsck -fn` na p2 | ✅ sem erros |
| Tempo total | **2min39s** |

Boot seguinte, **sem cartão**: LED verde piscando (heartbeat de userspace) e a
placa desligada pelo próprio script no ciclo anterior. A eMMC inicia.

### Achado 20 — "não rodou" era a placa não ter bootado

Na primeira tentativa o cartão voltou com `ARMED` intacto e sem log, e o journal
não tinha boot novo. Conclusão correta na época: o serviço não foi invocado. Mas
a **causa** não era o systemd — era a placa não ter bootado mesmo (alimentação
pelo carregador insuficiente / cartão mal encaixado). O sintoma foi o mesmo
(vermelho aceso, verde apagado), o que engana.

Lição para o futuro: **LED verde piscando é o único sinal confiável de boot**
nesta placa sem console. Nunca interpretar `ARMED` intacto como bug do serviço
antes de confirmar o LED.

### Achado 21 — o decodificador acerta o número de chunks sozinho

O cabeçalho Android sparse traz `total_chunks` (offset 20) e `total_blks`
(offset 16). `blk_sz` fica no offset **12** — confundir os dois foi um bug real
durante o desenvolvimento. Ver
[`scripts/flash-emmc-headless.sh`](../scripts/flash-emmc-headless.sh).

---

## Sessão 8 — 2026-11-13/14 · caça ao canal de acesso

### USB gadget: não é canal

A imagem ativa `Hardware activated USB gadget` e sobe `sshd` em `0.0.0.0:22`, mas
com a placa ligada pelo micro-USB no PC **nada enumera** (`lsusb` sem dispositivo
novo, nenhum `/dev/ttyACM*`, nenhuma interface de rede). Testado com cabo de
dados. Gadget descartado como caminho.

### Wi-Fi: firmware faltando, agora injetado

O journal da sessão 4 mostrava a causa:

```text
brcmfmac mmc2:0001:1: Direct firmware load for brcm/brcmfmac43430-sdio.bin failed with error -2
brcmf_sdio_htclk: HT Avail timeout (1000000): clkctl 0x50
```

O rootfs do cartão (e o payload) não trazem o firmware do AP6212. Injetado com
[`scripts/wifi-inject.sh`](../scripts/wifi-inject.sh) a partir do `linux-firmware`
(RPi-Distro), NVRAM com `prodid=0x0726` (BCM43430). Configuração aplicada:
`wpa_supplicant.conf` (600), bloco `wlan0` DHCP em `/etc/network/interfaces`,
`wpa_supplicant.service` mascarado (brigava com o do ifupdown).

A placa **não apareceu** na rede (varredura em `192.168.1.0/24` com
[`scripts/find-board.sh`](../scripts/find-board.sh)): pendente de diagnóstico pelo
console.

### Serial: o adaptador voltou, e a fiação é o gargalo

O PL2303 reenumerou (`067b:2303`). Sintomas e o que significam:

| Sintoma | Causa |
| --- | --- |
| `0x00` contínuo a ~280 kB/s (59,6 MB em 200 s) | RX **flutuando** (fio fora do pino ou no pino errado) — o tty converte break em `0x00` |
| padrão do loopback repetido milhões de vezes (126 MB) | **TX e RX em curto**: echo do tty em anel |
| `serial-loopback.py` devolve o texto idêntico | adaptador **saudável** — o problema é só fiação |

Pinagem do header UART0 (confirmada em [00](00-hardware.md)): **1 GND, 2 VDD_5V
(nunca conectar), 3 UART_TXD0 → RX do adaptador, 4 UART_RXD0 ← TX do adaptador**.
O TX fica **do lado do 5 V**, não do GND — é o erro de ligação mais provável.

---

## Sessão 9 — 2026-11-14 · a causa do Wi-Fi: NVRAM do módulo errado

### O que a sonda do cartão mostrou

O diagnóstico offline do rootfs do cartão (`scripts/diag-wifi-card.sh`) provou
que o problema não era firmware ausente nem `rfkill`:

```text
brcmfmac ... using brcm/brcmfmac43430-sdio for chip BCM43430/1   (sem erro depois)
wlan0: Failed to initiate sched scan                             (em loop, a cada ~6 s)
DHCPDISCOVER on wlan0 ... interval 7..18                          (dhclient com a interface up)
No DHCPOFFERS received.
```

Ou seja: `wlan0` **existe**, o módulo carrega, o `dhclient` roda — mas **nenhum
`Trying to associate` aparece**. O `wpa_supplicant` nunca recebe um único
resultado de varredura. A varredura falha, não a associação.

### A causa: NVRAM de outro módulo BCM43430

O firmware do `brcmfmac` é genérico (mesmo chip), mas o arquivo
`brcmfmac43430-sdio.txt` é o **NVRAM** — e ele contém a calibração de rádio
daquele módulo específico. O que foi injetado na sessão 8 veio do
`linux-firmware` (RPi/AW-NB197SM):

```text
# NVRAM file for BCM943430WLSELG
xtalfreq=37400
boardrev=0x1202
pa2ga0=0xff65,0x195a,0xfd03
```

O NVRAM correto do AP6212 estava dentro da própria imagem FriendlyElec:

```text
#AP6212_NVRAM_V1.0.1_20160606
xtalfreq=26000
boardrev=0x1101
pa2ga0=-168,7161,-820
```

| Parâmetro | Errado (RPi) | AP6212 | Efeito |
| --- | --- | --- | --- |
| `xtalfreq` | 37400 | **26000** | referência do sintetizador errada: o rádio não sintoniza canal |
| `boardrev` | 0x1202 | 0x1101 | layout de PA diferente |
| `pa2ga0` | `0xff65,0x195a,0xfd03` | `-168,7161,-820` | curva de potência errada |
| `maxp2ga0` | 84 | 90 | teto de potência errado |
| `papdmode` | 1 | 2 | correção de potência em modo diferente |

`xtalfreq` é a explicação mais direta do quadro: o chip inicializa no SDIO
(por isso não há `Direct firmware load ... failed`), mas o sintetizador fica
referenciado em 37,4 MHz quando o cristal da placa é de 26 MHz — o rádio não
completa varredura e o driver devolve erro para todo `sched scan`.

### Como o NVRAM foi extraído

A imagem `h3-sd-ubuntu-noble-core-4.14-armhf-20260330.img.gz` tem 7,8 GB
descompactada e o `.txt` é um arquivo de 1 KB dentro do ext4. Em vez de
descompactar tudo, o script varre o `zcat` e extrai só a janela em volta do
marcador `#AP6212_NVRAM`:

```bash
./scripts/extract-firmware.sh images/h3-sd-ubuntu-noble-core-4.14-armhf-20260330.img.gz
```

Resultado versionado em [`firmware/`](../firmware/README.md):
`brcmfmac43430-sdio.txt` (AP6212) + `brcmfmac43430-sdio.bin` (linux-firmware).

### Correções aplicadas de uma vez

1. `wifi-inject.sh` passou a **sobrescrever** o firmware quando recebe a pasta
   (antes pulava com "já presente" — justamente o arquivo errado).
2. `wpa_supplicant.conf` recebeu `disable_scan_offload=1` e `ap_scan=1`:
   varredura normal em vez de `sched scan`, eliminando a mensagem de erro
   mesmo se o driver continuar implicando.
3. Nova sonda [`scripts/board-probe.sh`](../scripts/board-probe.sh), instalada
   por [`scripts/install-probe.sh`](../scripts/install-probe.sh): roda sozinha
   45 s depois do boot e grava `wlan0`, `rfkill`, `dmesg`, `wpa_cli scan_results`
   e o hash do NVRAM em `/root/board-probe.txt`. Com isso o cartão vira o canal
   de diagnóstico, sem serial.

### Achado 22 — o adaptador PL2303 está funcionalmente morto para isto

Resumo do que ficou provado na caça à serial:

| Teste | Resultado | Conclusão |
| --- | --- | --- |
| loopback (TX↔RX do adaptador) | texto volta idêntico | o chip transmite e recebe |
| RX solto | fluxo contínuo de `0x00` (~280 kB/s) | entrada flutuando / break |
| TX↔RX no header da placa | anel de `LOOPBACK-...` (126 MB) | curto ou mesma porta |
| após reenumerar para `ttyUSB1` | 4.038 bytes, 100% NUL | receptor travado |

O adaptador já caiu do barramento e reenumerou duas vezes. Enquanto não houver
um segundo adaptador (ou fiação com GND firme e pinos distintos), **a serial
não é canal** — e o cartão SD resolve o mesmo problema.

### Estado ao fim da sessão

| Item | Estado |
| --- | --- |
| eMMC gravada e bootando | ✅ |
| NVRAM correto identificado e versionado | ✅ |
| Wi-Fi com IP | ⏳ a validar no próximo boot |
| Sonda de diagnóstico instalada no cartão | ✅ |

---

## Sessão 10 — 2026-11-14 · o rádio voltou; faltava a grafia do SSID

### Resultado do NVRAM do AP6212: resolvido

Mesmo boot, mesmo cartão, só o NVRAM trocado. A sonda mostrou o rádio vivo:

```text
brcmf_c_preinit_dcmds: Firmware: BCM43430/1 wl0: Oct 22 2019 01:59:28
                       version 7.45.98.94 (r723000 CY) FWID 01-3b33decd
wlan0  02:11:22:33:44:55  (UP, NO-CARRIER)
scan_results:
  aa:bb:cc:dd:ee:01  2432  -25  [WPA2-PSK+FT/PSK-CCMP]  minha-rede
  aa:bb:cc:dd:ee:02  2432  -26  [WPA-PSK+TKIP][WPA2+CCMP+TKIP]  minha-rede-iot
  aa:bb:cc:dd:ee:03  2422  -25  UNIFIQUE115
  ...
```

Antes: zero resultados de varredura. Depois: 14 BSSIDs, o AP da casa a −25 dBm.
`xtalfreq` era mesmo a diferença entre um rádio mudo e um rádio funcional.

### Achado 23 — SSID diferencia maiúsculas de minúsculas

O `wpa_supplicant.conf` dizia `ssid="Minha-rede"`; a rede é **`minha-rede`**
(`U`, `R`, `L`, `A` maiúsculos). O `wpa_supplicant` varria, via a rede, não
casava o SSID e voltava a varrer:

```text
wpa_state=SCANNING
network id / ssid / bssid / flags
0	Minha-rede	any
```

Isso explica o histórico inteiro: nunca houve `Trying to associate`, e o
`dhclient` nunca recebeu oferta porque a interface **nunca associou** — não era
DHCP, não era senha, não era `rfkill`.

Consequência para a documentação: ao diagnosticar "não pega IP", a primeira
coisa a comparar é a lista de `scan_results` com o `ssid=` do arquivo, caractere
por caractere. Ver [10-troubleshooting.md](10-troubleshooting.md).

### Achado 24 — o MAC é aleatório a cada boot

O `macaddr` do NVRAM é o placeholder `00:90:4c:c5:12:38`; o `brcmfmac` detecta
isso e gera um MAC aleatório. No boot medido: `02:11:22:33:44:55`. Para um
headless isso é ruim: o lease muda e o IP "desaparece".

Solução adotada: `wifi-inject.sh` aceita um MAC como 5º argumento e escreve em
`macaddr=`/`il0macaddr=` do NVRAM. Usado `02:00:00:00:00:01` (localmente
administrado, "nanop" em ASCII), para criar lease estático no MikroTik.

### Como foi diagnosticado sem serial

A sonda [`scripts/board-probe.sh`](../scripts/board-probe.sh) rodou sozinha no
boot e gravou tudo em `/root/board-probe.txt`; o
[`diag-wifi-card.sh`](../scripts/diag-wifi-card.sh) montou o cartão no PC e
imprimiu o arquivo. **Zero serial, zero tentativa às cegas.** O ciclo completo é:
cartão na placa → 3 min → cartão no PC → leitura. É o canal de diagnóstico
oficial deste projeto a partir daqui.

### Estado ao fim da sessão

| Item | Estado |
| --- | --- |
| Firmware + NVRAM do AP6212 | ✅ rádio varrendo, 14 BSSIDs |
| SSID correto (`minha-rede`) | ⏳ injeção pendente |
| MAC fixo | ⏳ injeção pendente |
| IP por DHCP / SSH | ⏳ depois do boot |
