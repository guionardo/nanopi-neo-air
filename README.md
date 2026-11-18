# NanoPi NEO Air — Setup do Controlador

Documentação do processo de preparação de um **NanoPi NEO Air** (Allwinner H3,
512 MB RAM, 8 GB eMMC, Wi-Fi/BT AP6212) para uso como controlador.

O foco inicial é **colocar o hardware em um estado conhecido e reproduzível**:
gravar o SO, configurar acesso, validar periféricos e registrar tudo para que o
processo possa ser repetido ou auditado depois.

## Estado atual

| Item | Situação |
| --- | --- |
| Hardware | Em mãos; **eMMC com Debian 13 bootando sem cartão** |
| SO | Debian 13 trixie (payload `debian-trixie-core`), kernel 4.14.111, armhf |
| Acesso | **SSH por Wi-Fi** em `192.168.1.50`, host `ctl-nanopi` (`root`, chave do host instalada) |
| Wi-Fi | `minha-rede`, AP6212, NVRAM do AP6212 versionado; MAC fixo `02:00:00:00:00:01` |
| Root | overlayfs: `mmcblk0p2` (1,4 GB) + `userdata` (5,8 GB) |
| Console serial | **Não confiável** (adaptador PL2303 instável); o cartão SD é o canal de recuperação |
| Papel do controlador | **Host headless, acesso só por SSH** (D-007, ver [docs/11-decisoes.md](docs/11-decisoes.md)) |
| Instalador | `install.sh` validado de ponta a ponta (check → card → net → verify) |
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

## Instalar em uma placa nova (do zero)

Com um computador Linux e um leitor de cartão SD, o caminho inteiro — gravar o
cartão, injetar Wi-Fi + firmware + chave SSH, gravar a eMMC e provisionar o
sistema final — está em [`install.sh`](install.sh). Não precisa de monitor,
teclado nem adaptador serial na placa.

```bash
git clone https://github.com/guionardo/nanopi-neo-air.git
cd nanopi-neo-air
./install.sh check   # confere ferramentas, imagem e cartão
./install.sh card    # grava e prepara o cartão (destrutivo)
./install.sh net     # espera a placa, grava a eMMC e provisiona
./install.sh verify  # confere o sistema que subiu da eMMC
```

A primeira execução pergunta SSID, senha e hostname e grava tudo em
`install.conf` (permissão `600`, fora do git). A imagem usada é a **eflasher**
da FriendlyElec (`h3-eflasher-*`), que contém o payload da eMMC — o script não
distribui a imagem por licença. Detalhes, fases e diagnóstico em
[docs/15-instalador.md](docs/15-instalador.md).

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
install.sh                       instalador de ponta a ponta (check|card|net|verify|all)
docs/                            documentação do processo (índice em docs/README.md)
artigo/                          artigo de blog em Markdown, no formato do Astro
firmware/                        firmware + NVRAM do AP6212 (obrigatório para o Wi-Fi)
scripts/flash-sd.sh              gravador de imagem para microSD (Linux, com validações)
scripts/flash-emmc-headless.sh   grava a eMMC a partir do próprio cartão (sem GUI)
scripts/install-headless-flash.sh arma a gravação da eMMC no cartão eflasher
scripts/wifi-inject.sh           firmware + credenciais + chave SSH no rootfs do cartão
scripts/provision-emmc-wifi.sh   configura o Wi-Fi da eMMC pela rede, a partir do cartão
scripts/board-probe.sh           sonda de diagnóstico que roda no boot da placa
scripts/pcd8544-smoke-test.py    teste de fumaça do display LCD Nokia 5110 (84x48)
scripts/ssd1306-smoke-test.py    teste de fumaça do display OLED I2C (SSD1306)
scripts/i2c-bb-probe.py          sonda I2C bit-banged nos GPIOs (contorna o controlador)
```
