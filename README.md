# mbrcli — Interpretador de MBR

`mbrcli` é um interpretador de MBR (*Master Boot Record*) escrito em **Zig v0.16.0**. Ele lê os primeiros 512 bytes de uma imagem binária de disco, interpreta a tabela de partições e apresenta um relatório legível no terminal.

O programa é **somente de leitura**: não modifica a imagem, não escreve partições e não abre dispositivos de bloco reais. A interpretação dos campos do MBR é feita diretamente sobre os bytes, sem `fdisk`, `parted`, `lsblk`, bibliotecas externas ou bibliotecas C.

## Objetivo

Demonstrar, na prática, os conceitos de:

- estrutura e finalidade do MBR;
- leitura de dados binários por offsets e tamanhos de campo;
- inteiros de 32 bits em little-endian;
- endereçamento CHS versus LBA;
- validação de entradas de partição e diagnóstico de inconsistências;
- testes automatizados e documentação técnica.

## Estrutura do projeto

```text
.
├── build.zig
├── build.zig.zon
├── README.md
├── mise.toml
├── fixtures/
│   ├── teste-assinatura-invalida.img
│   └── ...
├── src/
│   ├── main.zig        # CLI
│   ├── reader.zig      # leitura somente dos 512 bytes e validação do arquivo
│   ├── mbr.zig         # decodificação dos campos do MBR
│   ├── partition.zig   # cálculos de setores/bytes/MiB e intervalos
│   ├── validation.zig  # classificação de boot flag, estendida e GPT
│   └── report.zig      # formatação do relatório
├── tests.zig           # agrega os arquivos de teste
└── tests/
    ├── helpers.zig
    ├── mbr_test.zig
    ├── partition_test.zig
    ├── validation_test.zig
    ├── report_test.zig
    └── fixtures_test.zig
```

## Compilação

```bash
zig build
```

O executável é gerado em:

```text
zig-out/bin/mbrcli
```

Para compilar em modo de release:

```bash
zig build -Doptimize=ReleaseSafe
```

## Execução

```bash
./zig-out/bin/mbrcli caminho/para/disco.img
```

Ou, usando o passo de execução do build:

```bash
zig build run -- fixtures/teste-mbr-particao.img
```

Sem argumentos, o programa exibe a mensagem de uso e retorna código de saída `1`:

```text
Uso: mbrcli <caminho/para/disco.img>
```

## Códigos de saída

- `0`: arquivo lido e relatório emitido. O relatório pode conter avisos ou erros de consistência de partições; nesse caso a análise ainda foi concluída.
- `1`: uso incorreto, arquivo inexistente, sem permissão, não regular, menor que 512 bytes ou com assinatura MBR inválida.

## Testes

```bash
zig build test
```

Para ver o resumo dos testes:

```bash
zig build test --summary all
```

Os testes usam apenas imagens em `fixtures/`, sem depender de dispositivos físicos.

## Exemplos de saída

### Imagem válida com uma partição

Comando:

```bash
./zig-out/bin/mbrcli fixtures/teste-mbr-particao.img
```

Saída:

```text
MBR Inspector
Arquivo: fixtures/teste-mbr-particao.img
Assinatura: válida (55 AA)
Identificador do disco: 0x00000000
Capacidade da imagem: 1048576 bytes (1.00 MiB)

Partição 1
  Inicializável: não
  Flag de boot: 0x00
  Tipo: 0x83 (Linux)
  LBA inicial: 1
  Setores: 100
  Offset inicial: 512 bytes
  Tamanho: 51200 bytes (0.05 MiB)
  LBA final: 100
  Offset final: 51711 bytes

Partição 2: vazia
Partição 3: vazia
Partição 4: vazia
```

### Identificador do disco em little-endian

```text
$ ./zig-out/bin/mbrcli fixtures/teste-mbr-id.img
MBR Inspector
Arquivo: fixtures/teste-mbr-id.img
Assinatura: válida (55 AA)
Identificador do disco: 0x12345678
...
```

### Assinatura inválida

```text
$ ./zig-out/bin/mbrcli fixtures/teste-assinatura-invalida.img
Erro: assinatura MBR inválida em 'fixtures/teste-assinatura-invalida.img'; esperado 55 AA nos offsets 510-511.
$ echo $?
1
```

### Arquivo truncado

```text
$ ./zig-out/bin/mbrcli fixtures/teste-pequeno.img
Erro: 'fixtures/teste-pequeno.img' tem menos de 512 bytes; não contém um MBR completo.
$ echo $?
1
```

### Flag de boot inesperada

Trecho de saída para `fixtures/teste-boot-flag.img`:

```text
Partição 1
  Inicializável: flag inválida
  Flag de boot: 0x81
  Tipo: 0x83 (Linux)
  ...
  AVISO: flag de boot inesperada (0x81); valores válidos: 0x00 e 0x80.
```

### Partição além do fim da imagem

Trecho de saída para `fixtures/teste-mbr-limites.img`:

```text
Partição 1
  ...
  Offset inicial: 512 bytes
  Tamanho: 51200 bytes (0.05 MiB)
  LBA final: 100
  Offset final: 51711 bytes
  ERRO: partição ultrapassa o fim da imagem (imagem com 10 setores).
```

### Partições sobrepostas

Trecho de saída para `fixtures/teste-mbr-sobreposicao.img`:

```text
AVISO: partições 1 e 2 se sobrepõem (LBAs 1..100 e 50..149).
```

### MBR protetor de GPT

Entradas `0xEE` são identificadas e recebem tratamento especial, sem interpretar a tabela GPT:

```text
Partição 1
  Tipo: 0xEE (MBR protetor de GPT)
  LBA inicial: 1
  Setores: 2047
  ...
  Observação: entrada de MBR protetor de GPT; a tabela GPT não é interpretada.
```

### Partição estendida

Entradas `0x05`, `0x0F` e `0x85` são identificadas como contêineres estendidos, sem interpretar a cadeia de EBRs:

```text
Partição 1
  Tipo: 0x0F (Partição estendida (LBA))
  ...
  Observação: partição estendida; a cadeia de EBRs não é interpretada.
```

## Decisões de implementação

- **Imports relativos:** os arquivos usam caminhos relativos (`@import("mbr.zig")` em `src/` e `@import("../src/mbr.zig")` em `tests/`). O `build.zig` declara apenas o executável (`src/main.zig`) e a raiz dos testes (`tests.zig`); não há mapeamento manual de módulos com `addModule`.
- **Leitura mínima:** o programa lê somente os 512 bytes do MBR, usando leitura posicional. O tamanho do arquivo é obtido por `stat`, sem carregar a imagem inteira.
- **Arquivo regular:** antes de abrir, o caminho é verificado com `statFile`. Diretórios, dispositivos de bloco, caracteres, FIFOs e sockets são rejeitados com a mensagem “não é um arquivo regular”. Isso evita abrir dispositivos reais.
- **Somente leitura:** o arquivo é aberto com as opções padrão de `openFile`, cujo modo é `read_only`. Não há escrita na imagem.
- **Decodificação manual:** os campos são lidos por offset e convertidos com `std.mem.readInt(..., .little)`. Nenhuma struct é reinterpretada diretamente a partir dos bytes, evitando problemas de alinhamento, padding e endianness.
- **Aritmética segura:** LBA e número de setores são convertidos para `u64` antes da multiplicação por 512, evitando overflow mesmo com valores de 32 bits elevados.
- **Entrada vazia:** uma entrada é vazia somente quando os 16 bytes são zero. Uma entrada com flag, tipo, CHS ou LBA diferente de zero e zero setores é tratada como inconsistência, não como vazia.
- **Relatório uniforme:** toda entrada não vazia exibe número, boot flag, código e nome do tipo, LBA inicial, setores, offset inicial, tamanho em bytes e MiB, LBA final e offset final. Diagnósticos vêm depois dos campos, para não esconder informações.
- **Tipos especiais:** `0xEE` é identificado como MBR protetor de GPT; `0x05`, `0x0F` e `0x85` são identificados como partições estendidas. A tabela GPT e a cadeia de EBRs não são interpretadas.
- **Sobreposição:** a comparação usa intervalos semiabertos `[início, fim)` e considera apenas partições primárias de dados (exclui estendidas, GPT protetor e entradas com tipo `0x00`).
- **Tamanho não múltiplo de 512:** se o arquivo tiver pelo menos 512 bytes, ele é aceito. Se o tamanho não for múltiplo de 512, o programa avisa e usa apenas os setores completos para as verificações de limite.
- **Erros:** mensagens de uso e erro vão para `stderr` e o programa retorna código de saída `1`.


## Cobertura dos testes (R07)

| Caso exigido | Onde está coberto |
| --- | --- |
| Conversão little-endian | `tests/mbr_test.zig`, `tests/partition_test.zig` |
| MBR válido sem partições | `tests/fixtures_test.zig` |
| Uma partição válida | `tests/mbr_test.zig`, `tests/fixtures_test.zig` |
| Quatro entradas de partição | `tests/mbr_test.zig`, `tests/fixtures_test.zig` |
| Assinatura inválida | `tests/mbr_test.zig`, `tests/fixtures_test.zig` |
| Arquivo truncado | `tests/fixtures_test.zig` |
| Flag de boot inesperada | `tests/validation_test.zig`, `tests/report_test.zig`, `tests/fixtures_test.zig` |
| Intervalos sobrepostos | `tests/partition_test.zig`, `tests/report_test.zig`, `tests/fixtures_test.zig` |
| Partição que termina além da imagem | `tests/partition_test.zig`, `tests/report_test.zig`, `tests/fixtures_test.zig` |

Além disso, `tests/report_test.zig` verifica o conteúdo do relatório: presença de MiB, offset final em bytes, campos de entradas especiais, zero setores, LBA zero, boot flag inválida e sobreposição.

## Limitações

- O programa não interpreta a cadeia de partições lógicas (EBR) nem a tabela GPT.
- Os campos CHS são lidos apenas indiretamente para detectar entrada não vazia; não são exibidos nem validados contra o LBA.
- O programa não monta partições, não interpreta sistemas de arquivos e não escreve na imagem.
- Não há suporte a tamanhos de setor diferentes de 512 bytes.

## Integrantes e contribuições

Integrantes identificados no histórico Git do repositório:

| Integrante | Contribuições verificáveis no histórico |
| --- | --- |
| Emanuelly Gomes | Implementação do interpretador, validações finais e correções |
| Gabriel Frasão | Testes, refatoração da conversão de bytes e merges/revisões de PRs |
| Cauã Mendes | Marco 1, validação da assinatura e identificação do disco; PRs |
| Stephany Franca | Testes de interpretação da tabela de partições |

As discussões, Issues e revisões detalhadas estão registradas no GitHub do projeto.