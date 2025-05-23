#!/bin/bash

# Função para mostrar o help
show_help() {
    echo "Uso: $0 [OPÇÕES] [caminho_entrada] [caminho_ffprobe]"
    echo
    echo "Analisa arquivos de mídia usando ffprobe."
    echo
    echo "Parâmetros:"
    echo "  caminho_entrada   Arquivo ou diretório para análise"
    echo "                    (padrão: /var/lib/ffplayout/tv-media/1/)"
    echo "  caminho_ffprobe   Caminho para o executável ffprobe"
    echo "                    (padrão: /usr/local/bin/ffprobe)"
    echo
    echo "Opções:"
    echo "  -h, --help       Mostra esta mensagem de ajuda"
    echo
    echo "Exemplos:"
    echo "  $0                           # Analisa todos os arquivos do diretório padrão"
    echo "  $0 video.mkv                 # Analisa um arquivo específico"
    echo "  $0 /path/to/videos/          # Analisa todos os arquivos do diretório"
    echo "  $0 video.mp4 /usr/bin/ffprobe  # Usa ffprobe específico"
    echo
    echo "O script tentará analisar qualquer arquivo como mídia, independente da extensão."
    echo "Arquivos que não são mídia válida serão identificados durante a análise."
}

# Definir o diretório padrão
default_dir="/var/lib/ffplayout/tv-media/1/"

# Verificar se foi solicitada ajuda
for arg in "$@"; do
    case $arg in
        -h|--help)
            show_help
            exit 0
            ;;
    esac
done

# Definir o primeiro argumento como input (pode ser arquivo ou diretório)
input_path="${1:-$default_dir}"

# Definir o caminho do ffprobe (segundo argumento opcional)
ffprobe_path="${2:-/usr/local/bin/ffprobe_6.1.1_minimal}"

# Capturar a versão do ffprobe
ffmpeg_version=$("$ffprobe_path" -version | head -n 1)

# Exibir a versão usada
echo "Usado ffprobe version: ${ffmpeg_version}"

# Função para analisar um único arquivo
analyze_file() {
    local file="$1"
    echo "Analisando: $(basename "$file")"
    # Tenta analisar o arquivo com ffprobe e verifica o código de retorno
    if "$ffprobe_path" -v error -show_format -show_streams -print_format json -i "$file" 2>/dev/null; then
        echo "----------------------------------------"
    else
        echo "Aviso: '$file' não é um arquivo de mídia válido ou está corrompido"
        echo "----------------------------------------"
    fi
}

# Verificar se o ffprobe existe e é executável
if [ ! -x "$ffprobe_path" ]; then
    echo "Erro: ffprobe não encontrado ou não é executável em '$ffprobe_path'"
    echo "Use '$0 --help' para mais informações"
    exit 1
fi

# Verificar se o caminho de entrada existe
if [ ! -e "$input_path" ]; then
    echo "Erro: O caminho '$input_path' não existe"
    echo "Use '$0 --help' para mais informações"
    exit 1
fi

# Se for um arquivo, analisa diretamente
if [ -f "$input_path" ]; then
    analyze_file "$input_path"
    exit 0
fi

# Se for um diretório, processa todos os arquivos
if [ -d "$input_path" ]; then
    # Adicionar barra no final do diretório se não existir
    [[ "${input_path}" != */ ]] && input_path="${input_path}/"
    
    # Listar todos os arquivos regulares do diretório
    shopt -s nullglob
    files=("${input_path}"*)
    
    # Verificar se encontrou algum arquivo
    if [ ${#files[@]} -eq 0 ]; then
        echo "Nenhum arquivo encontrado em $input_path"
        exit 1
    fi

    # Iterar sobre todos os arquivos encontrados
    for file in "${files[@]}"; do
        # Ignora diretórios
        if [ -f "$file" ]; then
            analyze_file "$file"
        fi
    done
    exit 0
fi

# Se chegou aqui, o caminho não é nem arquivo nem diretório
echo "Erro: O caminho fornecido não é um arquivo nem um diretório válido"
echo "Use '$0 --help' para mais informações"
exit 1
