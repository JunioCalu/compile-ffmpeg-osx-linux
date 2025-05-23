#!/bin/bash

# Cores para melhor visualização
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Verifica se o caminho foi fornecido
if [ -z "$1" ]; then
    echo -e "${RED}Erro: Forneça o caminho para o Vulkan SDK${NC}"
    echo -e "Uso: $0 /caminho/para/vulkansdk-linux-x86_64-1.4.313.0"
    exit 1
fi

SDK_PATH="$1"
CONFLICT_COUNT=0
TOTAL_COUNT=0
# Array para armazenar pacotes conflitantes (usa apenas chaves únicas)
declare -A CONFLICTING_PACKAGES

# Função para extrair nome do pacote de uma string de conflito
extract_package_name() {
    local conflict="$1"
    # Extrai o nome do pacote (parte antes dos dois pontos)
    echo "$conflict" | cut -d':' -f1
}

# Função para gerar o comando de remoção
generate_remove_command() {
    # Obtém a lista de pacotes única (sem duplicatas)
    echo "sudo apt remove --purge $(printf "%s " "${!CONFLICTING_PACKAGES[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
}

# Função para verificar conflitos por extensão
check_conflicts() {
    local type="$1"
    local pattern="$2"
    local count=0
    local conflicts=0
    local previous_size=${#CONFLICTING_PACKAGES[@]}
    
    echo -e "${BOLD}Verificando arquivos $type...${NC}"
    
    # Encontra os arquivos e verifica cada um
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            basename=$(basename "$file")
            count=$((count + 1))
            
            # Verifica se existe em algum pacote
            conflict=$(dpkg -S "$basename" 2>/dev/null)
            if [ $? -eq 0 ]; then
                echo -e "${RED}CONFLITO:${NC} $basename → $conflict"
                conflicts=$((conflicts + 1))
                
                # Extrai o nome do pacote e adiciona ao array associativo
                pkg_name=$(extract_package_name "$conflict")
                CONFLICTING_PACKAGES["$pkg_name"]=1
            fi
        fi
    done < <(find "$SDK_PATH" -type f -name "$pattern" -o -type l -name "$pattern" 2>/dev/null)
    
    echo "Total: $count arquivos, $conflicts conflitos"
    
    # Se encontramos novos conflitos, exibe o comando atualizado
    if [ ${#CONFLICTING_PACKAGES[@]} -gt $previous_size ]; then
        echo -e "${BLUE}Comando parcial de remoção:${NC}"
        generate_remove_command
    fi
    
    echo ""
    
    CONFLICT_COUNT=$((CONFLICT_COUNT + conflicts))
    TOTAL_COUNT=$((TOTAL_COUNT + count))
}

# Executa verificações por tipo de arquivo
echo -e "${BOLD}Iniciando verificação de conflitos no Vulkan SDK em:${NC} $SDK_PATH"
echo ""

check_conflicts "bibliotecas estáticas" "*.a"
check_conflicts "bibliotecas compartilhadas" "*.so*"
check_conflicts "headers" "*.h"
check_conflicts "headers C++" "*.hpp"
#check_conflicts "arquivos Python" "*.py"
#check_conflicts "arquivos JSON" "*.json"
#check_conflicts "executáveis" "*" 

# Resumo final
echo -e "${BOLD}Resumo da Verificação:${NC}"
echo -e "Total de arquivos verificados: $TOTAL_COUNT"

if [ $CONFLICT_COUNT -gt 0 ]; then
    echo -e "${RED}Conflitos encontrados: $CONFLICT_COUNT${NC}"
    
    # Ordena os pacotes para melhor legibilidade
    sorted_packages=($(printf '%s\n' "${!CONFLICTING_PACKAGES[@]}" | sort))
    
    echo ""
    echo -e "${YELLOW}Pacotes conflitantes encontrados:${NC}"
    for pkg in "${sorted_packages[@]}"; do
        echo " - $pkg"
    done
    
    echo ""
    echo -e "${BOLD}${YELLOW}AVISO: Remover estes pacotes pode afetar seu sistema!${NC}"
    echo -e "A remoção dos pacotes acima pode remover dependências importantes ou"
    echo -e "comprometer a funcionalidade de seu sistema operacional."
    
    echo ""
    echo -e "${BLUE}Comando para remover os pacotes conflitantes (use com cuidado):${NC}"
    generate_remove_command
else
    echo -e "${GREEN}Nenhum conflito encontrado!${NC}"
fi

exit $CONFLICT_COUNT
