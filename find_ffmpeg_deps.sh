#!/bin/bash

# Script para identificar pacotes necessários a partir de dependências de biblioteca
# Usage: ./find_ffmpeg_deps.sh [caminho_para_binario]

# Verificar se um argumento foi fornecido
if [ $# -ne 1 ]; then
    echo "Uso: $0 <caminho_para_binario>"
    echo "Exemplo: $0 ./local/bin/ffmpeg"
    exit 1
fi

BINARY="$1"

# Verificar se o binário existe
if [ ! -f "$BINARY" ]; then
    echo "Erro: O arquivo '$BINARY' não existe."
    exit 1
fi

# Verificar se apt-file está instalado
if ! command -v apt-file &> /dev/null; then
    echo "apt-file não está instalado. Instalando..."
    sudo apt-get update
    sudo apt-get install -y apt-file
    sudo apt-file update
    echo "apt-file instalado com sucesso."
fi

echo "Executando ldd em '$BINARY'..."
LDD_OUTPUT=$(ldd "$BINARY")

if [ $? -ne 0 ]; then
    echo "Erro ao executar ldd no binário. Verifique se o arquivo é válido."
    exit 1
fi

echo "Analisando dependências de biblioteca..."

# Extrair os nomes das bibliotecas da saída do ldd
LIBS=$(echo "$LDD_OUTPUT" | grep "=>" | grep -v "linux-vdso.so" | grep -v "/lib64/ld-linux" | awk '{print $3}' | sort | uniq)

# Criar array para armazenar pacotes
declare -a PACKAGES

# Contador para progresso
TOTAL=$(echo "$LIBS" | wc -l)
CURRENT=0

echo "Encontrando pacotes para $TOTAL bibliotecas..."
echo ""

# Para cada biblioteca, encontrar o pacote correspondente
for LIB in $LIBS; do
    # Incrementar contador
    CURRENT=$((CURRENT+1))
    
    # Ignorar bibliotecas do CUDA
    #if [[ "$LIB" == *"/usr/local/cuda"* ]]; then
    #    echo "[$CURRENT/$TOTAL] Ignorando biblioteca CUDA: $LIB"
    #    continue
    #fi
    
    # Verificar se o arquivo existe
    if [ ! -f "$LIB" ]; then
        echo "[$CURRENT/$TOTAL] Biblioteca não encontrada: $LIB"
        continue
    fi
    
    # Obter o nome base da biblioteca e o diretório
    LIB_NAME=$(basename "$LIB")
    LIB_DIR=$(dirname "$LIB")
    
    # Extrair o nome base sem numeração de versão
    LIB_BASE=$(echo "$LIB_NAME" | sed -E 's/\.so\.[0-9]+(\.[0-9]+)*$/\.so/')
    
    echo -n "[$CURRENT/$TOTAL] Procurando pacote para $LIB_NAME... "
    
    # Método 1: Buscar pelo caminho exato primeiro
    PACKAGE=$(apt-file search -l "$LIB" 2>/dev/null | head -n1 | cut -d: -f1)
    
    # Método 2: Buscar pelo caminho com nome base sem numeração
    if [ -z "$PACKAGE" ]; then
        SEARCH_PATTERN="$LIB_DIR/$LIB_BASE"
        PACKAGE=$(apt-file search -l "$SEARCH_PATTERN" 2>/dev/null | head -n1 | cut -d: -f1)
    fi
    
    # Método 3: Buscar apenas pelo nome base da biblioteca sem caminho
    if [ -z "$PACKAGE" ]; then
        PACKAGE=$(apt-file search -l "$LIB_BASE" 2>/dev/null | grep -v "dev" | head -n1 | cut -d: -f1)
    fi
    
    if [ -n "$PACKAGE" ]; then
        echo "Encontrado: $PACKAGE"
        # Adicionar o pacote à lista
        if [[ ! " ${PACKAGES[@]} " =~ " ${PACKAGE} " ]]; then
            PACKAGES+=("$PACKAGE")
        fi
    else
        echo "Não encontrado"
    fi
done

echo ""
echo "Pacotes encontrados: ${#PACKAGES[@]}"

# Se nenhum pacote foi encontrado, avisar
if [ ${#PACKAGES[@]} -eq 0 ]; then
    echo "Nenhum pacote identificado. Verifique se o sistema tem os repositórios corretos habilitados."
    exit 1
fi

# Gerar comando apt-get
APT_COMMAND="sudo apt-get install -y"

for PKG in "${PACKAGES[@]}"; do
    APT_COMMAND="$APT_COMMAND $PKG"
done

echo ""
echo "======================= COMANDO APT GERADO ========================="
echo "$APT_COMMAND"
echo "=================================================================="

echo ""
echo "Você deseja executar este comando agora? (s/n)"
read -r RESPOSTA

if [[ "$RESPOSTA" == "s" ]] || [[ "$RESPOSTA" == "S" ]]; then
    echo "Executando comando apt-get..."
    eval "$APT_COMMAND"
else
    echo "Comando não executado. Você pode copiá-lo e executá-lo manualmente."
fi
