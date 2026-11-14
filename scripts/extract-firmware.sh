#!/usr/bin/env bash
#
# extract-firmware.sh — extrai o NVRAM do AP6212 de uma imagem .img.gz da
# FriendlyElec, sem descompactar a imagem inteira.
#
# A imagem H3 tem ~7,8 GB descompactada. O NVRAM é um arquivo texto de ~1 KB
# dentro do ext4 do rootfs. Como o ext4 grava arquivos pequenos em blocos
# contíguos, o texto aparece literal no stream e pode ser localizado com grep
# no zcat — daí extraímos só a janela em volta.
#
# Uso:
#   ./scripts/extract-firmware.sh images/h3-sd-ubuntu-noble-core-4.14-armhf-20260330.img.gz
#   ./scripts/extract-firmware.sh imagem.img.gz firmware/brcmfmac43430-sdio.txt
#
# Saída padrão: firmware/brcmfmac43430-sdio.txt

set -uo pipefail

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

IMG=${1:-}
OUT=${2:-firmware/brcmfmac43430-sdio.txt}
[[ -f $IMG ]] || die "uso: $0 <imagem.img.gz> [destino.txt]"
[[ $IMG == *.gz ]] || die "esperava um .img.gz (a imagem precisa ser compressed)"

for c in zcat python3; do
  command -v "$c" >/dev/null || die "falta o comando: $c"
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

info "passo 1/2: localizando os blocos de NVRAM no stream (leva ~2 min)"
zcat "$IMG" | python3 -c '
import sys

marcadores = [b"#AP6212_NVRAM", b"# NVRAM file"]
buf = bytearray()
base = 0
vistos = set()
KEEP = 2 << 20

while True:
    chunk = sys.stdin.buffer.read(1 << 20)
    if not chunk:
        break
    buf += chunk
    for m in marcadores:
        i = 0
        while True:
            p = buf.find(m, i)
            if p < 0:
                break
            pos = base + p
            if pos not in vistos:
                vistos.add(pos)
                print(f"{pos} {m.decode()}", flush=True)
            i = p + 1
    if len(buf) > KEEP:
        drop = len(buf) - KEEP
        del buf[:drop]
        base += drop
' > "$TMP/offsets.txt" || die "falha ao varrer a imagem"

cat "$TMP/offsets.txt"
info "blocos encontrados: $(wc -l < "$TMP/offsets.txt")"

# preferencia: o bloco do AP6212
OFF=$(awk '/#AP6212_NVRAM/ {print $1; exit}' "$TMP/offsets.txt")
if [[ -z $OFF ]]; then
  OFF=$(awk '/# NVRAM file/ {print $1; exit}' "$TMP/offsets.txt")
fi
[[ -n $OFF ]] || die "nenhum NVRAM encontrado na imagem"

info "passo 2/2: extraindo 8 KiB a partir do offset $OFF"
zcat "$IMG" | tail -c +"$OFF" | head -c 8192 > "$TMP/janela.bin"

python3 - "$TMP/janela.bin" "$OUT" <<'PY'
import sys

janela, destino = sys.argv[1], sys.argv[2]
d = open(janela, "rb").read()

# o bloco pode comecar no offset exato; normaliza caso venha 1-2 bytes antes
i = min((p for p in (d.find(b"#AP6212_NVRAM"), d.find(b"# NVRAM file")) if p >= 0),
        default=-1)
if i < 0:
    sys.exit("erro: marcador sumiu da janela (offset instavel?)")

txt = d[i:]
fim = txt.find(b"\x00")
if fim > 0:
    txt = txt[:fim]
txt = txt.replace(b"\r\n", b"\n")
open(destino, "wb").write(txt)
print(f"gravado {destino}: {len(txt)} bytes, {txt.count(b'=')} pares chave=valor")
PY

info "conteúdo:"
head -12 "$OUT"
