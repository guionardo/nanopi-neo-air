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

### Estado ao final da sessão

- Placa parada em `Waiting for root device` (requer power-cycle para sair).
- Diagnóstico **pendente de confirmação da fonte de alimentação**.
- Nenhuma alteração foi gravada na eMMC (só leitura e boot em RAM).

### Próximos passos definidos

1. Confirmar/ trocar a fonte por **5 V / 2 A dedicada** e repetir o boot.
2. Se o loop persistir com fonte adequada → tratar como eMMC com imagem inválida
   e refazer o eflasher a partir de um cartão SD ([05](05-gravacao-emmc.md)).
3. Registrar no [11-decisoes.md](11-decisoes.md) os dados da placa (MAC, versão).
