# 01 — Lista de materiais

Checklist do que precisa estar na bancada **antes** de começar. Marcar o que já
está em mãos evita descobrir no meio do processo que falta o adaptador serial.

## Hardware — essencial

| Item | Especificação | Por que | Tenho? |
| --- | --- | --- | --- |
| NanoPi NEO Air | V1.0 ou V1.1, 512 MB / 8 GB eMMC | A placa | ☐ |
| Fonte 5 V / 2 A | MicroUSB, cabo curto e grosso | Subtensão = boot instável e rootfs corrompido | ☐ |
| microSD | **Classe 10, ≥ 8 GB**, SDHC | Mínimo para o SO; eflasher exige ≥ 4 GB | ☐ |
| Adaptador USB-TTL | **3.3 V**, baseado em CP2102/CH340/FT232 | Único acesso no primeiro boot (sem HDMI) | ☐ |
| Jumpers fêmea-fêmea | 4x, 2.54 mm | Ligar o adaptador serial no header UART0 | ☐ |
| PC com Linux | Ubuntu/Debian (ou qualquer distro com `dd`) | Gravar o cartão | ☐ |
| Leitor de cartão microSD | USB ou interno | Gravar/validar | ☐ |

### Alternativas ao PC Linux

A wiki oficial documenta apenas Windows (`win32diskimager`). Funciona, mas:

- **Windows**: use [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
  ou o `win32diskimager` oficial. O `Pi Imager` aceita `.img.gz` direto e evita
  descompactar.
- **macOS**: `dd` com `rdisk` (`/dev/rdiskN`) é bem mais rápido que `diskN`.
- **Linux**: `dd` ou o script [`scripts/flash-sd.sh`](../scripts/flash-sd.sh)
  deste repositório, que valida device e desmontagem antes de escrever.

## Hardware — recomendado

| Item | Por que |
| --- | --- |
| Dissipador pequeno (15x15 mm) ou case com ventilação | H3 esquenta sob carga contínua; barato e evita throttling |
| Antena Wi-Fi (U.FL/IPEX) | A NEO Air tem conector U.FL; sem antena o alcance cai muito — **verifique se a sua veio com antena** |
| Case impresso em 3D | Proteção mecânica; arquivos por versão (V1.0/V1.1) |
| Etiqueta + caneta | Anotar MAC, IP, versão e data de gravação na placa |
| Hub USB com alimentação | Se for usar os 2x USB do header GPIO2 |
| Cabo microUSB **de dados** | Para OTG/fastboot; muitos cabos são só carga |

### Sobre a antena

O AP6212 usa antena externa via U.FL. Placa sem antena conectada = Wi-Fi
funciona a curtíssima distância (e às vezes nem associa). Se a sua não veio com
antena, compre uma de 2.4 GHz com cabo IPEX — é o item que mais gente esquece.

## Software — baixar antes

| Item | Onde |
| --- | --- |
| Imagem `sd` do FriendlyCore | <http://download.friendlyelec.com/NanoPiNEOAir> → `01_Official images` |
| Imagem `eflasher` | mesma pasta, arquivo `h3-eflasher-*` |
| `win32diskimager` (só Windows) | mesma URL → `05_Tools` |
| Cliente serial | `minicom`, `picocom`, `screen` ou PuTTY |

Detalhes de escolha de versão em [02-preparo-imagem.md](02-preparo-imagem.md).

## Ferramentas de bancada úteis

```bash
# cliente serial (escolha um)
sudo apt install picocom        # simples: picocom -b 115200 /dev/ttyUSB0
sudo apt install minicom        # menu: minicom -D /dev/ttyUSB0 -b 115200
```

Para inspecionar o cartão antes/depois da gravação:

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
sudo fdisk -l /dev/sdX
```

## Ordem de conferência antes do primeiro boot

1. Fonte é realmente 5 V e ≥ 2 A? (leia a etiqueta, não confie na memória)
2. Cartão é Classe 10 e ≥ 8 GB?
3. Adaptador serial está em **3.3 V**? (jumper de tensão conferido)
4. Antena Wi-Fi conectada?
5. A placa está sobre superfície **não condutiva**? (a parte de baixo tem contatos)
