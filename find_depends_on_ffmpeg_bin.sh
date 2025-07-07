#!/bin/bash
FFMPEG_BIN="../local/bin/ffmpeg"

echo "🕵️  INVESTIGAÇÃO COMPLETA DE DEPENDÊNCIAS"
echo "Binário: $FFMPEG_BIN"
echo

# Função para categorizar símbolos
categorize_symbol() {
    local symbol="$1"
    case "$symbol" in
        *std::*|*_Z*|*__cxa_*) echo "libstdc++" ;;
        *sin*|*cos*|*exp*|*log*|*sqrt*|*pow*|*ceil*|*floor*|*fabs*) echo "libm" ;;
        *malloc*|*free*|*printf*|*strlen*|*memcpy*|*memset*) echo "libc" ;;
        *__gcc*|*__unwind*|*__stack*) echo "libgcc" ;;
        *_ZGV*|*mvec*) echo "libmvec" ;;
        *) echo "other" ;;
    esac
}

# Extrair todos os símbolos externos
echo "=== CATEGORIZANDO SÍMBOLOS EXTERNOS ==="
symbols=$(nm -D "$FFMPEG_BIN" 2>/dev/null | grep -E "U " | awk '{print $2}')

# Contadores
declare -A lib_count
lib_count[libstdc++]=0
lib_count[libm]=0
lib_count[libc]=0
lib_count[libgcc]=0
lib_count[libmvec]=0

# Amostras de símbolos por categoria
declare -A lib_samples
lib_samples[libstdc++]=""
lib_samples[libm]=""
lib_samples[libc]=""
lib_samples[libgcc]=""
lib_samples[libmvec]=""

# Processar símbolos
while IFS= read -r symbol; do
    category=$(categorize_symbol "$symbol")
    if [[ "$category" != "other" ]]; then
        ((lib_count[$category]++))
        if [[ ${lib_count[$category]} -le 3 ]]; then
            lib_samples[$category]+="$symbol "
        fi
    fi
done <<< "$symbols"

# Mostrar resultados
for lib in libstdc++ libm libc libgcc libmvec; do
    if [[ ${lib_count[$lib]} -gt 0 ]]; then
        echo "🔴 $lib: ${lib_count[$lib]} símbolos"
        echo "   Exemplos: ${lib_samples[$lib]}"
    else
        echo "🟢 $lib: sem símbolos detectados"
    fi
done

echo
echo "=== VERIFICANDO PKG-CONFIG DE BIBLIOTECAS LINKADAS ==="
pkg_configs=$(find ../local/lib/pkgconfig -name "*.pc" 2>/dev/null)
for pc in $pkg_configs; do
    lib_name=$(basename "$pc" .pc)
    libs_line=$(grep -E "^Libs:" "$pc" 2>/dev/null)
    if echo "$libs_line" | grep -qE "(lstdc|lm|lgcc)"; then
        echo "⚠️  $lib_name: $libs_line"
    fi
done