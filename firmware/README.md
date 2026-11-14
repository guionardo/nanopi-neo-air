# firmware/ — firmware do Wi-Fi (AP6212 / BCM43430)

Arquivos necessários para o `brcmfmac` subir o `wlan0` da NanoPi NEO Air.

| Arquivo | Origem | Tamanho |
| --- | --- | --- |
| `brcmfmac43430-sdio.bin` | `linux-firmware` (RPi-Distro), chip BCM43430/1 | 400.447 B |
| `brcmfmac43430-sdio.txt` | **NVRAM do AP6212**, extraído da imagem FriendlyElec | 925 B |

## Por que o `.txt` é crítico

O `brcmfmac` aceita qualquer NVRAM com `prodid=0x0726`, mas os parâmetros de
calibração são específicos do **módulo**. Usar o NVRAM de outro módulo BCM43430
(o do Raspberry Pi / AW-NB197SM, que é o que vem no `linux-firmware`) faz o chip
inicializar no SDIO e falhar em tudo depois:

| Parâmetro | NVRAM errado (RPi) | NVRAM do AP6212 | Efeito |
| --- | --- | --- | --- |
| `xtalfreq` | 37400 | **26000** | sintetizador na referência errada: o rádio não varre |
| `boardrev` | 0x1202 | 0x1101 | layout de PA diferente |
| `pa2ga0` | `0xff65,0x195a,0xfd03` | `-168,7161,-820` | potência/linearidade erradas |
| `maxp2ga0` | 84 | 90 | potência máxima errada |
| `papdmode` | 1 | 2 | modo de correção de potência errado |

Sintoma no log: `wpa_supplicant: wlan0: Failed to initiate sched scan` em loop,
`No DHCPOFFERS received` e **nenhum** `Trying to associate` — ou seja, o scan
nunca devolve nada.

## Como re-extrair da imagem oficial

A imagem `.img.gz` (7,8 GB descompactada) fica em `images/` e não vai para o
git. O script faz a extração em streaming, sem descompactar tudo em disco:

```bash
./scripts/extract-firmware.sh images/h3-sd-ubuntu-noble-core-4.14-armhf-*.img.gz
```

Ele localiza o bloco `#AP6212_NVRAM` no stream e grava
`firmware/brcmfmac43430-sdio.txt`. O `.bin` não é extraído: o do `linux-firmware`
é o mesmo arquivo (mesmo chip), e é o que está versionado aqui.

## Instalação no cartão

```bash
sudo ./scripts/wifi-inject.sh /dev/sdX "SSID" "SENHA" ./firmware
```

O `wifi-inject.sh` **sobrescreve** o que estiver em `/lib/firmware/brcm/` quando
uma pasta de firmware é passada (guarda `.bak`).
