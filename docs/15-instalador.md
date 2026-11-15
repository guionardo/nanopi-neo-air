# 15 — Instalador de ponta a ponta (`install.sh`)

Um comando para levar uma NanoPi NEO Air nova de "placa com eMMC
desconhecida" até "host headless acessível por SSH", usando só um computador
Linux com leitor de cartão SD. Sem monitor, sem teclado e sem adaptador serial
na placa.

O `install.sh` não substitui os documentos [03](03-gravacao-sd.md),
[04](04-primeiro-boot.md), [05](05-gravacao-emmc.md) e [07](07-rede.md): ele
executa o mesmo caminho, com as validações que a bancada mostrou serem
necessárias.

## O que é preciso

| Item | Detalhe |
| --- | --- |
| Computador | Linux (x86_64 ou arm64), bash 4+ |
| Ferramentas | `dd`, `mount`, `findmnt`, `lsblk`, `sha256sum`, `ssh`, `ssh-keygen` e `curl` ou `wget` |
| Leitor de cartão | microSD de **16 GB ou mais** para o eflasher trixie (~14 GB); o bookworm cabia em 8 GB |
| Imagem | eflasher da FriendlyElec (`h3-eflasher-*.img.gz`) — **não** a imagem `sd` |
| Placa | NanoPi NEO Air com eMMC; fonte 5 V/2 A |

O alvo atual é **Debian 13 (trixie)**, payload
`h3-eflasher-debian-trixie-core-4.14-armhf-20260330.img.gz`
(sha256 `7e2943e4…c2fd1`, ver [D-008](11-decisoes.md)). O instalador não depende
da distro: ele lê do cartão qual payload usar.

Se faltar alguma ferramenta do pacote base, o script tenta instalar via
`apt`/`dnf`/`pacman`. Para não deixar o script mexer no sistema, use
`--skip-deps` e instale à mão.

> **Por que a imagem `eflasher` e não a `sd`?** É o eflasher que carrega o
> payload da eMMC (`boot.img`, `rootfs.img` e `userdata.img`), dentro de um
> diretório cujo nome vem do `autoStart` do `eflasher.conf` (por exemplo
> `/mnt/debian-trixie-core`). O instalador arma um serviço que grava esse
> payload sem GUI, lendo também os offsets do `partmap.txt`. A imagem `sd` sobe
> um sistema no cartão, mas não tem o que gravar na eMMC.

## Uso

```bash
./install.sh check            # ambiente, dependências, imagem e cartão
./install.sh card             # grava o cartão e injeta a configuração
./install.sh net              # encontra a placa, grava a eMMC e provisiona
./install.sh verify           # confere o sistema que subiu da eMMC
./install.sh all              # card + net (com pausa para trocar o cartão)
```

Opções:

| Opção | Efeito |
| --- | --- |
| `--config ARQUIVO` | usa outro `install.conf` |
| `--yes` | não pede confirmação (use com cuidado) |
| `--skip-deps` | não tenta instalar dependências |
| `--dry-run` | mostra o que faria, sem escrever no cartão |

## Configuração

Na primeira execução o script pergunta o que falta e grava `install.conf` com
permissão `600`. O arquivo contém a senha do Wi-Fi e está no `.gitignore`.

| Variável | Obrigatória | Descrição |
| --- | --- | --- |
| `SSID` | sim | nome da rede (diferencia maiúsculas de minúsculas) |
| `PSK` | sim | senha WPA2 (8+ caracteres) |
| `HOSTNAME_NEW` | não | hostname da placa (padrão `nanopi`) |
| `IMAGE` | sim | caminho local ou URL da imagem eflasher |
| `IMAGE_SHA256` | recomendado | checksum; sem ele o script avisa que não verificou |
| `SD_DEV` | sim | disco inteiro do cartão (ex.: `/dev/sdb`) |
| `WIFI_MAC` | não | MAC fixo (`02:xx:…`) para o roteador manter o lease |
| `SSH_KEY` | não | chave privada usada no acesso (padrão `~/.ssh/id_ed25519`) |
| `BOARD_IP` | não | pula a descoberta automática e usa este IP |

Variáveis de ambiente com o mesmo nome também funcionam
(`BOARD_IP=192.168.1.50 ./install.sh verify`).

## Fases

### `check`

Não escreve nada. Confere dependências, resolve a imagem (baixa e valida o
gzip/checksum), valida SSID/senha/hostname/MAC e inspeciona o cartão.

### `card` (destrutivo)

1. grava a imagem com [`scripts/flash-sd.sh`](../scripts/flash-sd.sh)
   (`dd` + `sync` + verificação do ponto de montagem);
2. roda [`scripts/wifi-inject.sh`](../scripts/wifi-inject.sh) para colocar no
   rootfs do cartão o firmware + NVRAM do AP6212, o perfil do NetworkManager e a
   chave SSH pública;
3. roda [`scripts/install-headless-flash.sh`](../scripts/install-headless-flash.sh)
   para armar a gravação da eMMC no primeiro boot.

Depois disso: cartão na placa, ligar, esperar ~15 min. A placa grava a eMMC,
verifica (`FLASH_DONE verify=ok`) e desliga sozinha.

### `net`

1. encontra a placa na LAN (varredura do `/24` da rota padrão, testando SSH);
2. confirma que a eMMC está visível (`/dev/mmcblk*p2`);
3. acompanha `/root/flash-emmc.log` até `FLASH_DONE verify=ok`;
4. pede para você religar a placa **ainda com o cartão**;
5. copia e roda [`scripts/provision-emmc-wifi.sh`](../scripts/provision-emmc-wifi.sh)
   na placa, que monta a eMMC e escreve: firmware/NVRAM, perfil de Wi-Fi
   (`powersave=2` em `[wifi]`, MAC fixo opcional), `sshd` habilitado, a
   `authorized_keys` copiada do cartão e o hostname;
6. desliga a placa para você tirar o cartão.

### `verify`

Entra por SSH e confere: origem do root, se o boot veio da eMMC (sem cartão, é
`mmcblk0p2`; com cartão, `/dev/mmcblk1` existe), hostname, uptime, `firstuse`,
associação Wi-Fi (SSID e sinal) e unidades systemd falhando. É leitura pura.

No trixie o root é `overlay` e o `findmnt` mostra caminhos remapeados
(`lowerdir=/root`), então a fase não procura o device nas opções: ela confere
que **não** há `mmcblk1` (cartão) e que `mmcblk0p2` existe. O sinal vem do
`nmcli` (o payload trixie não traz `iw`).

## Segurança do dispositivo

O script recusa:

- disco que contém o sistema em execução (comparação por `PKNAME`);
- disco com qualquer partição montada (lista os pontos de montagem);
- dispositivo inexistente ou partição em vez do disco inteiro;
- cartão menor que a imagem (com margem de 200 MiB).

E, sem `--yes`, exige digitar o caminho do dispositivo (`/dev/sdb`) para
confirmar a gravação. `--dry-run` mostra os três passos do `card` sem tocar no
cartão.

## Estado de validação

| Fase | Situação |
| --- | --- |
| `check` | ✅ recusa disco raiz, disco com partição montada e device inexistente; valida gzip |
| `card` | ✅ eflasher trixie gravado em cartão de 58,6 GB (14 GB em 1326 s) |
| `net` | ✅ ciclo completo: `FLASH_DONE verify=ok` → provisionamento → `poweroff` |
| `verify` | ✅ placa real em trixie: overlay, `firstuse`, Wi-Fi e 0 unidades falhando |

O caminho manual dos documentos 03–07 continua válido como referência do que o
script faz por baixo.

## Diagnóstico

| Sintoma | O que verificar |
| --- | --- |
| `SSID é obrigatório` | `install.conf` ausente ou sem `SSID`; rode `check` de novo |
| `não é dispositivo de bloco` | confira `lsblk`; use o disco inteiro, não a partição |
| `tem partições montadas` | `umount` das partições do cartão (o desktop pode montar sozinho) |
| `não achei a placa` | a placa entrou na LAN? Use `BOARD_IP=…` ou `--dry-run` para conferir a config |
| `tempo esgotado esperando a gravação` | veja `/root/flash-emmc.log` no cartão; `FLASH_FAILED` indica falha |
| `root não está na eMMC` no `verify` | o cartão ainda está no lugar; remova e ligue de novo |
| Wi-Fi não associa | SSID com maiúsculas diferentes, ou NVRAM errado (ver [10](10-troubleshooting.md)) |

## O que o script não faz

- não distribui a imagem (licença da FriendlyElec): informe `IMAGE`;
- não suporta macOS nem Windows — usa `dd`, `mount` e utilitários GNU;
- não troca a senha do root: o provisionamento **não** sincroniza
  `/etc/shadow` (seria destrutivo numa placa já usada). Em vez disso copia a
  chave do cartão e desabilita o login por senha, porque a senha do payload é
  a padrão do fabricante (`fa`, pública). Use `ALLOW_PASSWORD=1` para manter
  o login por senha ou `SYNC_PASS=1` para copiar o hash do cartão;
- não mexe no bootloader nem no kernel: eles vêm do payload do fabricante.
