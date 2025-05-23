#!/bin/bash

# Script para remover arquivos shaderc

# Diretório base
BASE_DIR="/config/workspace/compile-ffmpeg-osx-linux/local"

# Lista de arquivos e diretórios para remover
ITEMS_TO_REMOVE=(
    "$BASE_DIR/lib/libshaderc_shared.so.1"
    "$BASE_DIR/lib/libshaderc.a"
    "$BASE_DIR/lib/libshaderc_combined.a"
    "$BASE_DIR/lib/libshaderc_util.a"
    "$BASE_DIR/lib/libshaderc_shared.so"
    "$BASE_DIR/include/shaderc/shaderc.hpp"
    "$BASE_DIR/include/shaderc/shaderc.h"
    "$BASE_DIR/include/shaderc"
)

# Função para remover arquivo/diretório
remove_item() {
    local item="$1"
    if [ -e "$item" ]; then
        echo "Removendo: $item"
        rm -rf "$item"
        if [ $? -eq 0 ]; then
            echo "✓ Removido com sucesso"
        else
            echo "✗ Erro ao remover"
        fi
    else
        echo "Não encontrado: $item"
    fi
    echo ""
}

# Verificar se script está sendo executado como root (se necessário)
if [ ! -w "$BASE_DIR" ]; then
    echo "Aviso: Pode ser necessário executar como sudo"
    echo ""
fi

# Modo dry-run (simulação)
if [ "$1" == "--dry-run" ] || [ "$1" == "-d" ]; then
    echo "=== MODO DRY-RUN (apenas mostrando o que seria removido) ==="
    echo ""
    for item in "${ITEMS_TO_REMOVE[@]}"; do
        if [ -e "$item" ]; then
            echo "Seria removido: $item"
        else
            echo "Não encontrado: $item"
        fi
    done
    echo ""
    echo "Para realmente remover, execute sem o parâmetro --dry-run"
    exit 0
fi

# Confirmar antes de remover
echo "=== Script para remover arquivos shaderc ==="
echo ""
echo "Os seguintes arquivos/diretórios serão removidos:"
echo ""
for item in "${ITEMS_TO_REMOVE[@]}"; do
    if [ -e "$item" ]; then
        echo " - $item"
    fi
done
echo ""
read -p "Deseja continuar? (y/N): " confirm

case "$confirm" in
    [Yy]|[Yy][Ee][Ss])
        echo ""
        echo "Iniciando remoção..."
        echo ""
        
        # Remover cada item
        for item in "${ITEMS_TO_REMOVE[@]}"; do
            remove_item "$item"
        done
        
        echo "=== Limpeza concluída ==="
        echo ""
        echo "Verificando se ainda existem arquivos shaderc..."
        find "$BASE_DIR" -name "*shaderc*" 2>/dev/null
        ;;
    *)
        echo "Operação cancelada."
        exit 0
        ;;
esac
