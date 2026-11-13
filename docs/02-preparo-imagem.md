# 02 — Download e verificação da imagem

## Qual imagem escolher

A FriendlyElec publica dois tipos de imagem para o mesmo SO. A diferença está no
sufixo do nome do arquivo:

| Sufixo | Serve para | Uso neste projeto |
| --- | --- | --- |
| `h3-sd-...` | Boot e operação **a partir do microSD** | Teste inicial / validação de hardware |
| `h3-eflasher-...` | **Gravar** o SO no eMMC | Instalação definitiva (etapa 05) |

Ou seja: `sd` = sistema; `eflasher` = instalador. Você precisa dos dois, em
momentos diferentes.

## Versões disponíveis para a NEO Air

> **Atenção:** em 2026 o endereço `download.friendlyelec.com/NanoPiNEOAir` passou a
> redirecionar para o portal da FriendlyElec. As imagens agora ficam em um Google
> Drive público — ver [Baixando](#baixando).

| Imagem | Base | Kernel | Observação |
| --- | --- | --- | --- |
| `h3-sd-ubuntu-noble-core-4.14-armhf-20260330.img.gz` | Ubuntu Core 24.04 | 4.14 | **Mais recente** — é a que está na eMMC da placa |
| `h3-sd-friendlycore-jammy-4.14-armhf-20250402.img.gz` | Ubuntu Core 22.04 | 4.14 | FriendlyCore clássico |
| `h3-sd-friendlycore-focal-kernel4.14-armhf-20250402.img.gz` | Ubuntu Core 20.04 | 4.14 | Alternativa conservadora |
| `h3-sd-debian-trixie-core-4.14-armhf-20260330.img.gz` | Debian 13 | 4.14 | Boa opção se a aplicação é Debian |
| `h3-sd-friendlywrt-4.14-armhf-20210512.img.gz` | OpenWrt 19.07.1 | 4.14 | Só se o papel for roteador |
| `h3-sd-debian-jessie-*` | Debian 8 desktop | 3.4 ou 4.14 | **Evitar** — desatualizado |

### Por que kernel 4.14 e não 3.4

A wiki é explícita: o kernel 3.4 vem do BSP da Allwinner, tem VPU/GPU acelerados
por hardware, **mas gera calor e tem mais superfície de ataque**. O 4.14 é
mainline, estável e frio. Sem necessidade de decodificação de vídeo por hardware,
4.14 é a escolha certa — e é a única combinação que a FriendlyElec mantém
atualizada (Dezembro/2023: FriendlyCore 22.04).

### Por que armhf e não arm64

O H3 é Cortex-A7: **ARMv7, 32 bits**. Não existe imagem arm64 oficial. Isso
implica:

- limite de ~3 GB de espaço de endereçamento por processo (irrelevante com 512 MB);
- Docker funciona, mas só com imagens `arm32v7`;
- pacotes `.deb` precisam ser `armhf`.

## Baixando

### Onde as imagens estão

O endereço histórico `http://download.friendlyelec.com/NanoPiNEOAir` hoje
responde com redirecionamento para o portal da empresa. As imagens oficiais estão
em um **Google Drive público**:

- pasta: <https://drive.google.com/drive/folders/1ZvaUcfgR_uFoupmtFFnTzBH4cQqweE-E>
- espelho citado no portal: <https://pan.baidu.com/s/1P0j1crgmyN2tANK1936NYA>

Estrutura relevante da pasta:

```
01_Official images/
  01_SD card images/          imagens h3-sd-*        (sistema no cartão)
  02_SD-to-eMMC images/       imagens h3-eflasher-*  (instalador p/ eMMC)
  03_Partition image files/   .tgz com imagens de partição + latest.json
02_Third party images/        DietPi, Android, ROMs de acessórios
04_SDK and toolchain/         ambiente de compilação
```

### Pelo navegador

1. Abra a pasta, entre em `01_Official images` → `01_SD card images`.
2. Baixe o `.img.gz` desejado **e** o `sha256sum.txt` da mesma pasta.

### Pela linha de comando (recomendado)

O Drive não permite `curl` em arquivo direto de forma confiável; use `gdown`
(fora do sistema, em um venv, para não sujar o Python do host):

```bash
python3 -m venv /tmp/venv
/tmp/venv/bin/pip install -q gdown

# listar a pasta (não baixa nada)
/tmp/venv/bin/gdown --folder \
  "https://drive.google.com/drive/folders/1ZvaUcfgR_uFoupmtFFnTzBH4cQqweE-E" \
  --skip-download

# baixar um arquivo pelo ID (o ID aparece na listagem)
/tmp/venv/bin/gdown <ID> -O h3-sd-ubuntu-noble-core-4.14-armhf-20260330.img.gz -c
```

`-c` retoma download interrompido. Para o checksum:

```bash
/tmp/venv/bin/gdown <ID_DO_sha256sum.txt> -O sha256sum.txt
grep 'ubuntu-noble-core' sha256sum.txt | sha256sum -c -
# h3-sd-ubuntu-noble-core-4.14-armhf-20260330.img.gz: OK
```

### Verificação — obrigatória

O `sha256sum.txt` oficial é a referência. Confira **as duas** coisas:

```bash
gzip -t h3-sd-*.img.gz && echo "gzip OK"     # arquivo não truncado
sha256sum -c sha256sum.txt --ignore-missing  # confere o hash oficial
```

Guarde o `sha256sum.txt` junto da imagem. Sem ele, "verificar" vira só um teste
de gzip — que detecta truncamento, mas não substituição/corrupção silenciosa.

## Registro de versão

Anote no [11-decisoes.md](11-decisoes.md):

- nome completo do arquivo baixado;
- data do download;
- SHA-256.

Isso é o que permite reproduzir o setup meses depois, quando a FriendlyElec já
tiver publicado outras imagens.

## Descompactar ou não?

- `dd` precisa do `.img` puro → descompacte.
- `Raspberry Pi Imager`, `Etcher` e o script deste repo aceitam `.gz` direto.
- Guarde o `.gz` (menor) e descompacte só na hora de gravar.

```bash
gunzip -k h3-sd-friendlycore-jammy-4.14-armhf-*.img.gz   # -k mantém o .gz
```
