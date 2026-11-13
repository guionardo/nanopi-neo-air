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

