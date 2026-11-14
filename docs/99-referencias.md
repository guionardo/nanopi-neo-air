# 99 — Referências

## Fonte primária

- [Wiki oficial — NanoPi NEO Air](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_NEO_Air)
  — especificações, pinagem, downloads, changelog. **Última revisão consultada: 30/03/2026.**
- [Download de imagens e ferramentas](http://download.friendlyelec.com/NanoPiNEOAir)
  — `01_Official images`, `05_Tools`, `sources`.

## Documentação relacionada da FriendlyElec

- [EFlasher](https://wiki.friendlyelec.com/wiki/index.php/EFlasher) — detalhes do instalador
- [npi-config](https://wiki.friendlyelec.com/wiki/index.php/Npi-config) — utilitário de configuração
- [Use NetworkManager to configure network settings](https://wiki.friendlyelec.com/wiki/index.php/Use_NetworkManager_to_configure_network_settings)
- [Building U-boot and Linux for H5/H3/H2+](https://wiki.friendlyelec.com/wiki/index.php/Building_U-boot_and_Linux_for_H5/H3/H2%2B)
- [How to make your own SD-bootable ROM](https://wiki.friendlyelec.com/wiki/index.php/How_to_make_your_own_SD-bootable_ROM)
- [How to use overlayfs on Linux](https://wiki.friendlyelec.com/wiki/index.php/How_to_use_overlayfs_on_Linux) — rootfs somente-leitura
- [WiringNP — GPIO com C](https://wiki.friendlyelec.com/wiki/index.php/WiringNP:_NanoPi_NEO/NEO2/Air_GPIO_Programming_with_C)
- [RPi.GPIO — GPIO com Python](https://wiki.friendlyelec.com/wiki/index.php/RPi.GPIO_:_NanoPi_NEO/NEO2/Air_GPIO_Programming_with_Python)
- [Linux FAQ](https://wiki.friendlyelec.com/wiki/index.php/Linux_FAQ) · [Ubuntu FAQ](https://wiki.friendlyelec.com/wiki/index.php/Ubuntu_FAQ)

## Hardware

- [Schematic V1.1 (1708), PDF](https://wiki.friendlyelec.com/wiki/images/7/70/Schematic_NanoPi-NEO-Air-V1.1_1708.pdf)
- [Schematic V1.0 (1608), PDF](https://wiki.friendlyelec.com/wiki/images/9/98/NanoPi-NEO-Air-1608-Schematic.pdf)
- [Datasheet Allwinner H3 V1.2](https://wiki.friendlyelec.com/wiki/images/4/4b/Allwinner_H3_Datasheet_V1.2.pdf)
- [Dimensões V1.1 (DXF, .rar)](https://wiki.friendlyelec.com/wiki/index.php/File:Dimensional-NanoPi_NEO_Air-V1.1-1708.rar)
- [Case 3D V1.0 (Thingiverse)](https://www.thingiverse.com/thing:1998968)

## Display LCD Nokia 5110 / PCD8544

- [MakerHero — Conheça o Display Nokia 5110](https://www.makerhero.com/blog/conheca-o-display-nokia-5110/)
  — tutorial em PT-BR (Arduino): pinagem, contraste, bitmap e fontes.
  **Consultado em 14/11/2026.** Notas de adaptação em [14-display-lcd.md](14-display-lcd.md#notas-de-tutoriais-makerhero-20261114).
- [Datasheet PCD8544](https://www.sparkfun.com/datasheets/LCD/Monochrome/Nokia5110.pdf)
  — comandos, temporização (máx. 4 MHz) e mapa de endereços.
- [Adafruit_PCD8544](https://github.com/adafruit/Adafruit-PCD8544-Nokia-5110-LCD-library)
  — referência de sequência de inicialização e escala de contraste.
- [luma.lcd](https://github.com/rm-hull/luma.lcd) — driver Python (Pillow) para Linux
- [pcd8544designer](https://pcd8544designer.web.app/) — desenha telas 84x48 e
  exporta o vetor MSB-first

## Repositórios

- [friendlyarm/WiringNP](https://github.com/friendlyarm/WiringNP)
- [friendlyarm/RPi.GPIO_NP](https://github.com/friendlyarm/RPi.GPIO_NP)
- [friendlyarm/linux (branch sunxi-4.14.y)](https://github.com/friendlyarm/linux/tree/sunxi-4.14.y)
- [friendlyarm/h3_lichee](https://github.com/friendlyarm/h3_lichee) — BSP legado 3.4
- [friendlyarm/QtE-Demo](https://github.com/friendlyarm/QtE-Demo)

## Ferramentas

- [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — grava `.img.gz` sem descompactar
- [balenaEtcher](https://etcher.balena.io/)
- [DietPi para NanoPi](https://dietpi.com/docs/hardware/#nanopi-series-friendlyarm) — alternativa de SO
- [openwrt opkg](https://openwrt.org/docs/guide-user/additional-software/opkg)

## Comunidade

- [Fórum FriendlyARM (inglês)](http://www.friendlyarm.net)
- [Fórum arm9home (chinês)](http://www.arm9home.net)
- [GitHub FriendlyARM](https://github.com/friendlyarm)

## Notas sobre as fontes

| Observação | Detalhe |
| --- | --- |
| A wiki mistura versões de hardware | V1.0 e V1.1 têm LEDs de cores diferentes |
| Alguns links de download mudam | os nomes de imagem têm data (`YYYYMMDD`); sempre liste o diretório |
| Documentação de eMMC é rasa | o procedimento do eflasher é descrito em poucas linhas; este repositório detalha o que a wiki omite |
| Changelog da wiki | 30/03/2026 corrigiu boot lento do `systemd-random-seed`; 12/01/2026 atualizou Debian Core para 13 |
