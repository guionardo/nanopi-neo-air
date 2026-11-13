# 03 — Gravação do microSD

Gravar a imagem `sd` no cartão. Este é o passo mais destrutivo do processo:
**todo o conteúdo do device de destino é apagado**.

## Regra de ouro: identifique o device

Antes de qualquer coisa, com o cartão **já inserido** no PC:

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,TRAN
```

Saída típica:

```
NAME        SIZE TYPE MOUNTPOINT MODEL            TRAN
nvme0n1   476.9G disk              Samsung SSD      nvme
├─nvme0n1p1 512M part /boot/efi
└─nvme0n1p2 476.4G part /
sdb        29.7G disk              USB SD Reader    usb
└─sdb1     29.7G part /media/user/BOOT
```

Aqui o cartão é `/dev/sdb` — disco inteiro, **não** `/dev/sdb1`.

Confira três vezes:

1. O tamanho bate com o cartão (29.7 G)?
2. A coluna `TRAN` é `usb`?
3. O `MODEL` é o leitor de cartão?

Se errar isso, você apaga o disco do seu computador. Não existe desfazer.

## Opção A — script do repositório (Linux, recomendado)

O script [`scripts/flash-sd.sh`](../scripts/flash-sd.sh) valida device, recusa
disco do sistema, desmonta partições e só então escreve:

```bash
sudo ./scripts/flash-sd.sh ~/nanopi/images/h3-sd-friendlycore-jammy-4.14-armhf-*.img.gz /dev/sdX
```

Ele faz, nesta ordem:

1. confere se o arquivo existe e se é `.img` ou `.img.gz`;
2. confere se `/dev/sdX` é um dispositivo de bloco e **não** contém `/` ou `/boot`;
3. desmonta todas as partições do destino;
4. descompacta em streaming e grava com `dd conv=fsync status=progress`;
5. executa `sync` e informa o resultado.

## Opção B — `dd` na mão

```bash
# desmontar (repita para cada partição montada do cartão)
sudo umount /dev/sdb1

# gravar (imagem .img.gz, descompactando em streaming)
gunzip -c h3-sd-friendlycore-jammy-4.14-armhf-*.img.gz \
  | sudo dd of=/dev/sdb bs=4M conv=fsync status=progress

# garantir que os buffers chegaram ao cartão
sync
```

Se a imagem já estiver descompactada, troque o `gunzip -c ... |` por `if=arquivo.img`.

Por que `conv=fsync` é obrigatório: sem ele o `dd` "termina" antes de os dados
saírem do cache do kernel. Você tira o cartão, o boot falha, e o cartão parece
defeituoso.

## Opção C — Windows

1. Instale [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (aceita `.gz`).
2. "Choose OS" → "Use custom" → selecione o `.img.gz`.
3. "Choose Storage" → o cartão (o Imager esconde discos internos).
4. Write. Ele verifica a escrita automaticamente.

Alternativa: `win32diskimager` (documentado pela wiki), rodando **como
administrador** — exige o `.img` descompactado.

## Opção D — macOS

```bash
diskutil list                                  # identifique o disco (ex: disk4)
diskutil unmountDisk /dev/disk4
sudo dd if=image.img of=/dev/rdisk4 bs=4m      # rdisk = mais rápido
```

## Validação depois de gravar

### 1. O cartão tem partições?

```bash
sudo partprobe /dev/sdb
lsblk /dev/sdb
```

Esperado: pelo menos uma partição FAT (boot) e uma Linux (rootfs).

```
sdb
├─sdb1   64M  part  /media/user/BOOT
└─sdb2  1.5G  part
```

### 2. Dá para ler o conteúdo do boot?

```bash
sudo mount /dev/sdb1 /mnt
ls /mnt
sudo umount /mnt
```

Esperado: `boot.scr`, `Image`, `sun8i-h3-nanopi-neo-air.dtb` (ou similar),
`kernel.img`/`uInitrd` dependendo da versão. Se a partição está vazia ou o
`mount` falha, a gravação não completou — grave de novo com outro cartão.

### 3. Desmontar com segurança antes de remover

```bash
sync
sudo udisksctl power-off -b /dev/sdb    # ou simplesmente ejetar
```

## Sinais de que o cartão é o problema

Se após gravar o boot falha (LEDs sem sequência esperada, console serial mudo):

- grave de novo com **outro** cartão Classe 10 (cartões falsificados de 128 GB
  são comuns e falham em escrita sequencial);
- teste o cartão: `sudo badblocks -wsv /dev/sdb` (destrutivo, mas conclusivo);
- cartões abaixo de Classe 10 ou com setores ruins produzem exatamente o mesmo
  sintoma de "placa queimada".

## Próximo passo

Cartão gravado e validado → [04 — Primeiro boot e acesso](04-primeiro-boot.md).
