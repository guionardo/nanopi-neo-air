# NanoPi NEO Air — Setup do Controlador

Documentação do processo de preparação de um **NanoPi NEO Air** (Allwinner H3,
512 MB RAM, 8 GB eMMC, Wi-Fi/BT AP6212) para uso como controlador.

O foco inicial é **colocar o hardware em um estado conhecido e reproduzível**:
gravar o SO, configurar acesso, validar periféricos e registrar tudo para que o
processo possa ser repetido ou auditado depois.

## Estado atual

| Item | Situação |
| --- | --- |
| Hardware | Em mãos; **eMMC com Debian 12 bootando sem cartão** |
| SO | Debian 12 bookworm (payload `debian-bookworm-core`), kernel 4.14.111, armhf |
| Acesso | **SSH por Wi-Fi** em `192.168.1.50`, host `ctl-nanopi` (`root`, chave do host instalada) |
| Wi-Fi | `minha-rede`, AP6212, NVRAM do AP6212 versionado; MAC fixo `02:00:00:00:00:01` |
| Root | overlayfs: `mmcblk0p2` (1,4 GB) + `userdata` (5,8 GB) |
| Console serial | **Não confiável** (adaptador PL2303 instável); o cartão SD é o canal de recuperação |
| Papel do controlador | **A definir** (ver [docs/11-decisoes.md](docs/11-decisoes.md)) |
| Documentação | Completa; ideias futuras em [backlog](docs/13-backlog.md) |

## Por onde começar

Se é a primeira vez com a placa, leia na ordem:

1. [Log de bordo](docs/12-log-de-bordo.md) — o que já foi observado nesta placa (comece aqui)
2. [Hardware e pinagem](docs/00-hardware.md) — o que a placa tem (e o que não tem)
3. [Lista de materiais](docs/01-materiais.md) — o que precisa estar na mesa
4. [Download e verificação da imagem](docs/02-preparo-imagem.md)
5. [Gravação do cartão microSD](docs/03-gravacao-sd.md)
6. [Primeiro boot e acesso](docs/04-primeiro-boot.md)
7. [Gravar o SO no eMMC](docs/05-gravacao-emmc.md)

Depois disso: [configuração base](docs/06-configuracao-base.md),
[rede](docs/07-rede.md), [GPIO](docs/08-gpio.md).

Índice completo em **[docs/README.md](docs/README.md)**.

## Avisos rápidos

- A NEO Air **não tem HDMI nem Ethernet**. O acesso de emergência é o **cartão SD**
  (o sistema do cartão sobe, monta a eMMC e permite consertá-la pela rede).
  Console serial seria o caminho clássico, mas o adaptador PL2303 desta bancada é
  instável — ver [log de bordo](docs/12-log-de-bordo.md).
- Fonte **5 V / 2 A** no microUSB não é sugestão: subtensão causa boot instável
  e corrupção de sistema de arquivos.
- O Wi-Fi só funciona com o **NVRAM do AP6212** (`firmware/`); o arquivo genérico
  do `linux-firmware` deixa o rádio mudo. Ver [firmware/README.md](firmware/README.md).
- Documentação oficial: <https://wiki.friendlyelec.com/wiki/index.php/NanoPi_NEO_Air>

## Estrutura do repositório

```
README.md                        visão geral e ponto de entrada
docs/                            documentação do processo (índice em docs/README.md)
firmware/                        firmware + NVRAM do AP6212 (obrigatório para o Wi-Fi)
scripts/flash-sd.sh              gravador de imagem para microSD (Linux, com validações)
scripts/flash-emmc-headless.sh   grava a eMMC a partir do próprio cartão (sem GUI)
scripts/wifi-inject.sh           firmware + credenciais no rootfs do cartão
scripts/provision-emmc-wifi.sh   configura o Wi-Fi da eMMC pela rede, a partir do cartão
scripts/board-probe.sh           sonda de diagnóstico que roda no boot da placa
```
