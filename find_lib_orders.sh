#!/bin/bash

# Script para descobrir a ordem correta das bibliotecas para linkar shaderc
# Uso: ./find_library_order.sh /caminho/para/LOCALDESTDIR

set -e

LOCALDESTDIR="${1:-/ffmpeg-build/local}"
BUILD_DIR="${2:-/ffmpeg-build/build/shaderc-2023.8/build}"

echo "=========================================="
echo "DESCOBRINDO ORDEM DAS BIBLIOTECAS"
echo "=========================================="
echo "LOCALDESTDIR: $LOCALDESTDIR"
echo "BUILD_DIR: $BUILD_DIR"
echo

# Função para verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verificar ferramentas necessárias
echo "=== Verificando ferramentas ==="
for tool in nm objdump ar; do
    if command_exists "$tool"; then
        echo "✅ $tool"
    else
        echo "❌ $tool (necessário)"
        exit 1
    fi
done
echo

# 1. DESCOBRIR BIBLIOTECAS DISPONÍVEIS
echo "=== 1. DESCOBRINDO BIBLIOTECAS DISPONÍVEIS ==="
LIB_DIR="$LOCALDESTDIR/lib"

if [ ! -d "$LIB_DIR" ]; then
    echo "❌ Diretório não encontrado: $LIB_DIR"
    exit 1
fi

# Encontrar todas as bibliotecas .a relacionadas
GLSLANG_LIBS=($(find "$LIB_DIR" -name "*.a" | grep -E "(glslang|SPIRV)" | sort))
OTHER_LIBS=($(find "$LIB_DIR" -name "*.a" | grep -vE "(glslang|SPIRV)" | head -10))

echo "Bibliotecas glslang/SPIRV encontradas:"
for lib in "${GLSLANG_LIBS[@]}"; do
    echo "  $(basename "$lib")"
done

echo
echo "Outras bibliotecas:"
for lib in "${OTHER_LIBS[@]}"; do
    echo "  $(basename "$lib")"
done
echo

# 2. ANALISAR DEPENDÊNCIAS
echo "=== 2. ANALISANDO DEPENDÊNCIAS ==="

# Função para extrair símbolos indefinidos
get_undefined_symbols() {
    local lib="$1"
    nm "$lib" 2>/dev/null | grep "U " | awk '{print $2}' | sort | uniq || true
}

# Função para extrair símbolos definidos
get_defined_symbols() {
    local lib="$1"
    nm "$lib" 2>/dev/null | grep -E "^[0-9a-fA-F]+ [TDRBW] " | awk '{print $3}' | sort | uniq || true
}

# Criar arquivo temporário para análise
ANALYSIS_FILE="/tmp/lib_analysis.txt"
> "$ANALYSIS_FILE"

echo "Analisando dependências das bibliotecas..."
for lib in "${GLSLANG_LIBS[@]}"; do
    libname=$(basename "$lib")
    echo "📚 Analisando $libname"
    
    echo "=== $libname ===" >> "$ANALYSIS_FILE"
    echo "UNDEFINED:" >> "$ANALYSIS_FILE"
    get_undefined_symbols "$lib" >> "$ANALYSIS_FILE"
    echo "DEFINED:" >> "$ANALYSIS_FILE"
    get_defined_symbols "$lib" >> "$ANALYSIS_FILE"
    echo >> "$ANALYSIS_FILE"
done

# 3. CONSTRUIR MAPA DE DEPENDÊNCIAS
echo
echo "=== 3. CONSTRUINDO MAPA DE DEPENDÊNCIAS ==="

declare -A lib_dependencies
declare -A lib_provides

for lib in "${GLSLANG_LIBS[@]}"; do
    libname=$(basename "$lib" .a)
    
    # Símbolos que esta biblioteca precisa
    undefined=$(get_undefined_symbols "$lib")
    
    # Símbolos que esta biblioteca fornece
    defined=$(get_defined_symbols "$lib")
    
    lib_dependencies["$libname"]="$undefined"
    lib_provides["$libname"]="$defined"
done

# Mostrar dependências críticas
echo "Dependências críticas encontradas:"
for lib in "${!lib_dependencies[@]}"; do
    undefined="${lib_dependencies[$lib]}"
    if [[ -n "$undefined" ]]; then
        echo "📦 $lib precisa de:"
        echo "$undefined" | grep -E "glslang::|SPIRV" | head -5 | sed 's/^/    /'
    fi
done
echo

# 4. TESTAR ORDENS DE LINKAGEM
echo "=== 4. TESTANDO ORDENS DE LINKAGEM ==="

# Objeto de teste (do shaderc)
TEST_OBJ="$BUILD_DIR/glslc/CMakeFiles/glslc_exe.dir/src/main.cc.o"
SHADERC_LIBS="$BUILD_DIR/glslc/libglslc.a $BUILD_DIR/libshaderc_util/libshaderc_util.a $BUILD_DIR/libshaderc/libshaderc.a"

if [ ! -f "$TEST_OBJ" ]; then
    echo "❌ Objeto de teste não encontrado: $TEST_OBJ"
    echo "Execute o ninja primeiro para gerar os objetos"
    exit 1
fi

# Diferentes ordens para testar
declare -a ORDERS=(
    # Ordem 1: Dependências primeiro
    "libglslang-default-resource-limits.a libMachineIndependent.a libGenericCodeGen.a libOSDependent.a libglslang.a libSPIRV.a libSPIRV-Tools.a libSPIRV-Tools-opt.a"
    
    # Ordem 2: Principais primeiro
    "libglslang.a libSPIRV.a libglslang-default-resource-limits.a libMachineIndependent.a libGenericCodeGen.a libOSDependent.a libSPIRV-Tools.a libSPIRV-Tools-opt.a"
    
    # Ordem 3: SPIRV primeiro
    "libSPIRV-Tools.a libSPIRV-Tools-opt.a libSPIRV.a libglslang.a libglslang-default-resource-limits.a libMachineIndependent.a libGenericCodeGen.a libOSDependent.a"
    
    # Ordem 4: Agrupado
    "libglslang.a libglslang-default-resource-limits.a libMachineIndependent.a libGenericCodeGen.a libOSDependent.a libSPIRV.a libSPIRV-Tools.a libSPIRV-Tools-opt.a"
    
    # Ordem 5: Com possíveis bibliotecas extras
    "libglslang.a libglslang-default-resource-limits.a libMachineIndependent.a libGenericCodeGen.a libOSDependent.a libOGLCompiler.a libHLSL.a libSPIRV.a libSPIRV-Tools.a libSPIRV-Tools-opt.a libSPIRV-Tools-link.a libSPIRV-Tools-reduce.a"
)

# Função para testar uma ordem
test_link_order() {
    local order="$1"
    local test_num="$2"
    
    echo "🧪 Testando ordem $test_num:"
    echo "   $order"
    
    # Construir lista de bibliotecas com caminho completo
    local lib_args=""
    for lib in $order; do
        if [ -f "$LIB_DIR/$lib" ]; then
            lib_args="$lib_args $LIB_DIR/$lib"
        fi
    done
    
    # Tentar linkar
    local output="/tmp/test_link_$test_num"
    local cmd="g++ -o $output $TEST_OBJ $SHADERC_LIBS $lib_args -pthread -static-libstdc++ -static-libgcc"
    
    if eval "$cmd" 2>/tmp/link_error_$test_num; then
        echo "   ✅ SUCESSO!"
        echo
        echo "🎉 ORDEM ENCONTRADA:"
        echo "$order"
        echo
        echo "Comando completo que funcionou:"
        echo "$cmd"
        return 0
    else
        echo "   ❌ Falhou"
        # Mostrar alguns erros
        head -10 "/tmp/link_error_$test_num" | sed 's/^/      /'
    fi
    
    return 1
}

# Testar cada ordem
for i in "${!ORDERS[@]}"; do
    if test_link_order "${ORDERS[$i]}" "$((i+1))"; then
        break
    fi
    echo
done

# 5. ANÁLISE AVANÇADA SE NENHUMA ORDEM FUNCIONOU
echo
echo "=== 5. ANÁLISE AVANÇADA ==="

# Verificar símbolos específicos que estão faltando
echo "Procurando símbolos problemáticos..."
PROBLEM_SYMBOLS=("glslang::InitializeProcess" "glslang::TShader::TShader" "glslang::TProgram::TProgram")

for symbol in "${PROBLEM_SYMBOLS[@]}"; do
    echo "🔍 Procurando símbolo: $symbol"
    for lib in "${GLSLANG_LIBS[@]}"; do
        if nm "$lib" 2>/dev/null | grep -q "$symbol"; then
            echo "   ✅ Encontrado em: $(basename "$lib")"
        fi
    done
done

echo
echo "=== 6. RECOMENDAÇÕES ==="

# Verificar se todas as bibliotecas necessárias existem
REQUIRED_LIBS=("libglslang.a" "libSPIRV.a" "libglslang-default-resource-limits.a")
missing_libs=()

for lib in "${REQUIRED_LIBS[@]}"; do
    if [ ! -f "$LIB_DIR/$lib" ]; then
        missing_libs+=("$lib")
    fi
done

if [ ${#missing_libs[@]} -gt 0 ]; then
    echo "❌ Bibliotecas essenciais faltando:"
    for lib in "${missing_libs[@]}"; do
        echo "   $lib"
    done
    echo
    echo "💡 Recompile o glslang com todas as bibliotecas estáticas"
else
    echo "✅ Todas as bibliotecas essenciais estão presentes"
fi

echo
echo "💡 Sugestões:"
echo "1. Use -Wl,--start-group ... -Wl,--end-group para resolver dependências circulares"
echo "2. Considere usar bibliotecas compartilhadas se estáticas não funcionarem"
echo "3. Verifique se glslang foi compilado com as mesmas flags que shaderc"

# Gerar comando final recomendado
echo
echo "🎯 COMANDO RECOMENDADO PARA CMAKE:"
echo
echo 'cmake .. \'
echo '  -DCMAKE_EXE_LINKER_FLAGS="-L'$LIB_DIR' -Wl,--start-group -lglslang -lglslang-default-resource-limits -lMachineIndependent -lGenericCodeGen -lOSDependent -lSPIRV -lSPIRV-Tools -lSPIRV-Tools-opt -Wl,--end-group -pthread"'

echo
echo "Análise salva em: $ANALYSIS_FILE"
echo "Logs de erro em: /tmp/link_error_*"
