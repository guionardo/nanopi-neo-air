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

Diretório oficial: <http://download.friendlyelec.com/NanoPiNEOAir> → `01_Official images`

| Imagem | Base | Kernel | Observação |
| --- | --- | --- | --- |
| `h3-sd-friendlycore-jammy-4.14-armhf-YYYYMMDD.img.gz` | Ubuntu Core 22.04 | 4.14 | **Escolhida** — mais recente, enxuta, sem X |
| `h3-sd-friendlycore-focal-4.14-armhf-...` | Ubuntu Core 20.04 | 4.14 | Alternativa estável |
| `h3-sd-friendlycore-xenial-4.14-armhf-...` | Ubuntu Core 16.04 | 4.14 | Antiga; só por compatibilidade |
| `h3-sd-debian-trixie-core-4.14-armhf-...` | Debian 13 | 4.14 | Boa opção se a aplicação é Debian |
| `h3-sd-friendlywrt-4.14-armhf-...` | OpenWrt 19.07.1 | 4.14 | Só se o papel for roteador |
| `h3-sd-debian-jessie-3.4-armhf-...` | Debian 8 desktop | 3.4 | **Evitar** — Allwinner BSP, esquenta e é antigo |

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

```bash
mkdir -p ~/nanopi/images && cd ~/nanopi/images

# ajuste a data para a versão mais recente listada no diretório
BASE=http://download.friendlyelec.com/NanoPiNEOAir

# 1) listar o que existe (se o servidor permitir indexação)
curl -s "$BASE/" | grep -oE 'h3-[a-z0-9.-]+\.img\.gz' | sort -u
```

Se a listagem não abrir no `curl`, baixe pelo navegador e mova para a pasta.
Nomes de arquivo têm a data no final (`YYYYMMDD`) — escolha a mais recente da
linha `jammy`.

Download direto (exemplo — **substitua a data**):

```bash
curl -LO "$BASE/01_Official%20images/h3-sd-friendlycore-jammy-4.14-armhf-20240101.img.gz"
```

> O caminho com espaço (`01_Official images`) pode vir codificado como `%20`.
> Se der 404, copie o link real do navegador.

## Verificando a integridade

O servidor da FriendlyElec não publica checksums de forma consistente. Duas
camadas de proteção, da melhor para a pior:

### 1. Teste do gzip (detecta download truncado/corrompido)

```bash
gzip -t h3-sd-friendlycore-jammy-4.14-armhf-*.img.gz && echo "OK: arquivo íntegro"
```

Isso valida o CRC interno do gzip. **É a verificação mínima obrigatória.**

### 2. SHA-256 registrado manualmente

```bash
sha256sum h3-sd-friendlycore-jammy-4.14-armhf-*.img.gz | tee SHA256SUMS.txt
```

Guarde o `SHA256SUMS.txt` junto da imagem. Na próxima vez que for gravar, você
compara — se mudou sem você trocar o arquivo, algo aconteceu.

### 3. Conferir o que veio dentro (sem descompactar tudo)

```bash
# tamanho descompactado e nome interno
gzip -l h3-sd-*.img.gz
```

Tamanho descompactado típico: **1 a 4 GB**. Se aparecer algo como 100 MB, o
arquivo está errado (provavelmente é o eflasher ou um download parcial).

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
