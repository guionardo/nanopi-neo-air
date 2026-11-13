#!/bin/bash
# Expande uma imagem Android sparse direto no dispositivo de destino.
# Uso: unsparse.sh <imagem-sparse> <dispositivo> <offset_bytes> <n_chunks>
set -e
IN=$1; OUT=$2; BASE=$3; N=$4; DRY=${DRY:-0}
pos=28; outblk=0
for ((i=1; i<=N; i++)); do
  vals=($(od -An -tu4 -w4 -j "$pos" -N 12 "$IN"))
  w0=${vals[0]}; cs=${vals[1]}; ts=${vals[2]}
  type=$((w0 & 65535))
  dp=$((pos + 12))
  dst=$((BASE + outblk * 4096))
  if [ "$DRY" = 1 ]; then
    echo "chunk=$i type=$type start_blk=$outblk nblk=$cs len=$ts dst=$dst"
  else
    case $type in
      51905)  # CAC1 raw
        dd if="$IN" of="$OUT" bs=4096 iflag=skip_bytes,count_bytes \
           skip="$dp" count=$((cs * 4096)) oflag=seek_bytes seek="$dst" \
           conv=notrunc status=none
        echo "chunk=$i RAW ok nblk=$cs" ;;
      51906)  # CAC2 fill (padrao de 4 bytes; tratar como zero)
        dd if=/dev/zero of="$OUT" bs=4096 count="$cs" oflag=seek_bytes \
           seek="$dst" conv=notrunc status=none
        echo "chunk=$i FILL zerado nblk=$cs" ;;
      51907)  # CAC3 dont care
        dd if=/dev/zero of="$OUT" bs=4096 count="$cs" oflag=seek_bytes \
           seek="$dst" conv=notrunc status=none
        echo "chunk=$i DONT zerado nblk=$cs" ;;
      51908)  # CAC4 crc
        echo "chunk=$i CRC ignorado" ;;
      *)
        echo "chunk=$i TIPO_DESCONHECIDO type=$type"; exit 2 ;;
    esac
  fi
  pos=$((pos + ts)); outblk=$((outblk + cs))
done
echo "UNSPARSE_DONE total_blocks=$outblk bytes=$((outblk * 4096))"
