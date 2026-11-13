# NanoPi NEO Air — Setup do Controlador

Documentação do processo de preparação de um **NanoPi NEO Air** (Allwinner H3,
512 MB RAM, 8 GB eMMC, Wi-Fi/BT AP6212) para uso como controlador.

O foco inicial é **colocar o hardware em um estado conhecido e reproduzível**:
gravar o SO, configurar acesso, validar periféricos e registrar tudo para que o
processo possa ser repetido ou auditado depois.

## Estado atual

| Item | Situação |
| --- | --- |
| Hardware | Em mãos, eMMC virgem |
| SO alvo | FriendlyCore (Ubuntu Core) — kernel 4.14, armhf |
| Papel do controlador | **A definir** (ver [docs/11-decisoes.md](docs/11-decisoes.md)) |
| Documentação | Em construção |

## Por onde começar

Se é a primeira vez com a placa, leia na ordem:

1. [Hardware e pinagem](docs/00-hardware.md) — o que a placa tem (e o que não tem)
2. [Lista de materiais](docs/01-materiais.md) — o que precisa estar na mesa
3. [Download e verificação da imagem](docs/02-preparo-imagem.md)
4. [Gravação do cartão microSD](docs/03-gravacao-sd.md)
5. [Primeiro boot e acesso](docs/04-primeiro-boot.md)
6. [Gravar o SO no eMMC](docs/05-gravacao-emmc.md)

Depois disso: [configuração base](docs/06-configuracao-base.md),
[rede](docs/07-rede.md), [GPIO](docs/08-gpio.md).

Índice completo em **[docs/README.md](docs/README.md)**.

## Avisos rápidos

- A NEO Air **não tem HDMI nem Ethernet**. O acesso de emergência é o
  **console serial** (115200 8N1) — tenha um adaptador USB-TTL 3.3 V antes de começar.
- Fonte **5 V / 2 A** no microUSB não é sugestão: subtensão causa boot instável
  e corrupção de sistema de arquivos.
- eMMC virgem: a placa **só dá boot pelo microSD** até você rodar o `eflasher`.
- Documentação oficial: <https://wiki.friendlyelec.com/wiki/index.php/NanoPi_NEO_Air>

## Estrutura do repositório

```
README.md              visão geral e ponto de entrada
docs/                  documentação do processo (índice em docs/README.md)
scripts/flash-sd.sh    gravador de imagem para microSD (Linux, com validações)
```
