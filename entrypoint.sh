#!/bin/bash

# Entrypoint script para FFmpeg Build Container
# Suporta diferentes modos de operação

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variáveis de ambiente com valores padrão
MAINTENANCE_MODE=${MAINTENANCE_MODE:-false}
BUILD_MODE=${BUILD_MODE:-compile}
KEEP_ALIVE=${KEEP_ALIVE:-false}
AUTO_CLEAN=${AUTO_CLEAN:-false}
FFMPEG_BUILD_OPTS=${FFMPEG_BUILD_OPTS:-"--optimize=y"}

# Função para mostrar banner
show_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                    FFmpeg Build Container                 ║"
    echo "║                       $(date '+%Y-%m-%d %H:%M:%S')                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}Ubuntu Version:${NC} $(cat /etc/os-release | grep VERSION= | cut -d'"' -f2)"
    echo -e "${CYAN}Build Mode:${NC} $BUILD_MODE"
    echo -e "${CYAN}Maintenance Mode:${NC} $MAINTENANCE_MODE"
    echo -e "${CYAN}FFmpeg Build Options:${NC} $FFMPEG_BUILD_OPTS"
    echo -e "${CYAN}Working Directory:${NC} $(pwd)"
    echo ""
}

# Função para mostrar opções de build
show_build_options() {
    echo -e "${BLUE}📋 Opções de Build FFmpeg Disponíveis:${NC}"
    echo -e "${CYAN}  --libs-only=[y/n]${NC}      # Compilar apenas bibliotecas"
    echo -e "${CYAN}  --ffmpeg-only=[y/n]${NC}    # Compilar apenas FFmpeg"
    echo -e "${CYAN}  --extras=[y/n]${NC}         # Compilar MediaInfo e MP4Box"
    echo -e "${CYAN}  --optimize=[y/n]${NC}       # Compilar versão otimizada (padrão)"
    echo -e "${CYAN}  --help${NC}                 # Mostrar ajuda do script"
    echo ""
    echo -e "${YELLOW}Opções atuais:${NC} $FFMPEG_BUILD_OPTS"
    echo ""
    echo -e "${YELLOW}Exemplos de uso:${NC}"
    echo "  build-now --libs-only=y"
    echo "  build-now --ffmpeg-only=y --optimize=y"
    echo "  build-now --extras=y --optimize=n"
    echo ""
}

# Função para modo manutenção
maintenance_mode() {
    echo -e "${YELLOW}🔧 MODO MANUTENÇÃO ATIVADO${NC}"
    echo -e "${CYAN}Comandos disponíveis:${NC}"
    echo "  • build-now [opções]  - Iniciar build FFmpeg com opções"
    echo "  • build-libs          - Compilar apenas bibliotecas"
    echo "  • build-ffmpeg        - Compilar apenas FFmpeg"
    echo "  • build-extras        - Compilar MediaInfo e MP4Box"
    echo "  • build-optimized     - Compilar versão otimizada"
    echo "  • build-help          - Mostrar opções de build"
    echo "  • check-deps          - Verificar dependências"
    echo "  • clean-build         - Limpar arquivos de build"
    echo "  • system-info         - Informações do sistema"
    echo "  • exit                - Sair do container"
    echo ""
    echo -e "${GREEN}Container pronto para manutenção!${NC}"
    
    # Criar aliases úteis
    cat << EOF > /root/.bash_aliases
alias build-now='cd /ffmpeg-build && ./compile-ffmpeg.sh'
alias build-libs='cd /ffmpeg-build && ./compile-ffmpeg.sh --libs-only=y'
alias build-ffmpeg='cd /ffmpeg-build && ./compile-ffmpeg.sh --ffmpeg-only=y'
alias build-extras='cd /ffmpeg-build && ./compile-ffmpeg.sh --extras=y'
alias build-optimized='cd /ffmpeg-build && ./compile-ffmpeg.sh --optimize=y'
alias build-help='cd /ffmpeg-build && ./compile-ffmpeg.sh --help'
alias check-deps='apt list --installed | grep -E "(nasm|yasm|cmake|git|build-essential)"'
alias clean-build='rm -rf /ffmpeg-build/build/* /ffmpeg-build/local/*'
alias system-info='echo "=== System Info ===" && uname -a && echo && echo "=== Memory ===" && free -h && echo && echo "=== Disk ===" && df -h'
alias ffmpeg-version='if [ -f /ffmpeg-build/local/bin/ffmpeg ]; then /ffmpeg-build/local/bin/ffmpeg -version; else echo "FFmpeg not built yet"; fi'
alias show-logs='find /ffmpeg-build -name "*.log" -exec echo "=== {} ===" \; -exec cat {} \;'
alias build-status='echo "=== Build Status ===" && echo "FFmpeg binary:" && ls -la /ffmpeg-build/local/bin/ffmpeg 2>/dev/null || echo "Not found" && echo "Libraries:" && ls -la /ffmpeg-build/local/lib/ 2>/dev/null | head -10 || echo "Not found"'
EOF
    
    # Carregar aliases
    source /root/.bash_aliases
    
    # Mostrar opções de build disponíveis
    show_build_options
    
    # Entrar em shell interativo
    exec /bin/bash
}

# Função para verificar sistema
check_system() {
    echo -e "${BLUE}🔍 Verificando sistema...${NC}"
    
    # Verificar espaço em disco
    DISK_USAGE=$(df /ffmpeg-build | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 90 ]; then
        echo -e "${RED}⚠️ Aviso: Pouco espaço em disco ($DISK_USAGE% usado)${NC}"
    fi
    
    # Verificar memória
    MEM_AVAILABLE=$(free | grep '^Mem:' | awk '{printf "%.0f", $7/$2 * 100.0}')
    if [ "$MEM_AVAILABLE" -lt 20 ]; then
        echo -e "${YELLOW}⚠️ Aviso: Pouca memória disponível ($MEM_AVAILABLE% livre)${NC}"
    fi
    
    # Verificar se scripts existem
    if [ ! -f "/ffmpeg-build/compile-ffmpeg.sh" ]; then
        echo -e "${RED}❌ Script compile-ffmpeg.sh não encontrado!${NC}"
        echo -e "${YELLOW}💡 Montou o volume corretamente?${NC}"
    fi
    
    echo -e "${GREEN}✅ Verificação do sistema concluída${NC}"
}

# Função para build
run_build() {
    echo -e "${GREEN}🔨 Iniciando build do FFmpeg...${NC}"
    
    # Verificar se script existe
    if [ ! -f "./compile-ffmpeg.sh" ]; then
        echo -e "${RED}❌ Script compile-ffmpeg.sh não encontrado no diretório atual!${NC}"
        echo -e "${YELLOW}Arquivos disponíveis:${NC}"
        ls -la
        exit 1
    fi
    
    # Preparar comando de build
    BUILD_CMD="./compile-ffmpeg.sh"
    
    # Se argumentos foram passados para esta função, usar eles
    if [ $# -gt 0 ]; then
        BUILD_ARGS="$*"
        echo -e "${CYAN}Usando argumentos passados: $BUILD_ARGS${NC}"
    else
        BUILD_ARGS="$FFMPEG_BUILD_OPTS"
        echo -e "${CYAN}Usando opções padrão: $BUILD_ARGS${NC}"
    fi
    
    # Executar build
    echo -e "${CYAN}Executando: $BUILD_CMD $BUILD_ARGS${NC}"
    if $BUILD_CMD $BUILD_ARGS; then
        echo -e "${GREEN}✅ Build concluído com sucesso!${NC}"
        
        # Mostrar informações do build
        echo -e "${BLUE}📊 Resultados do Build:${NC}"
        
        # Verificar FFmpeg
        if [ -f "./local/bin/ffmpeg" ]; then
            echo -e "${CYAN}FFmpeg versão:${NC}"
            ./local/bin/ffmpeg -version | head -3
            echo ""
            echo -e "${CYAN}Tamanho do binário FFmpeg:${NC}"
            ls -lh ./local/bin/ffmpeg
        fi
        
        # Verificar outros binários
        if [ -f "./local/bin/ffprobe" ]; then
            echo -e "${CYAN}FFprobe:${NC} $(ls -lh ./local/bin/ffprobe | awk '{print $5}')"
        fi
        
        # Verificar MediaInfo se extras foram compilados
        if [ -f "./local/bin/mediainfo" ]; then
            echo -e "${CYAN}MediaInfo:${NC} $(ls -lh ./local/bin/mediainfo | awk '{print $5}')"
        fi
        
        # Verificar MP4Box se extras foram compilados
        if [ -f "./local/bin/MP4Box" ]; then
            echo -e "${CYAN}MP4Box:${NC} $(ls -lh ./local/bin/MP4Box | awk '{print $5}')"
        fi
        
        # Verificar bibliotecas
        LIB_COUNT=$(find ./local/lib -name "*.a" 2>/dev/null | wc -l)
        if [ "$LIB_COUNT" -gt 0 ]; then
            echo -e "${CYAN}Bibliotecas estáticas:${NC} $LIB_COUNT arquivos"
        fi
        
        # Auto-limpeza se habilitada
        if [ "$AUTO_CLEAN" = "true" ]; then
            echo -e "${YELLOW}🧹 Executando limpeza automática...${NC}"
            rm -rf ./build/*
            echo -e "${GREEN}✅ Limpeza concluída${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}❌ Build falhou!${NC}"
        
        # Mostrar logs de erro se existirem
        if [ -f "./build.log" ]; then
            echo -e "${YELLOW}📋 Últimas linhas do log:${NC}"
            tail -20 ./build.log
        fi
        
        # Listar arquivos de log disponíveis
        echo -e "${YELLOW}📁 Logs disponíveis:${NC}"
        find . -name "*.log" -type f 2>/dev/null | head -5
        
        return 1
    fi
}

# Função para shell interativo pós-build
post_build_shell() {
    echo -e "${YELLOW}🔧 Entrando em modo interativo pós-build...${NC}"
    echo -e "${CYAN}Comandos úteis:${NC}"
    echo "  • ffmpeg-version  - Ver versão do FFmpeg"
    echo "  • show-logs       - Mostrar logs de build"
    echo "  • clean-build     - Limpar arquivos temporários"
    echo ""
    
    # Definir aliases
    alias ffmpeg-version='./local/bin/ffmpeg -version'
    alias show-logs='find . -name "*.log" -exec echo "=== {} ===" \; -exec cat {} \;'
    alias clean-build='rm -rf ./build/*'
    
    exec /bin/bash
}

# Função para executar builds com lifecycle completo
execute_build() {
    local description="$1"
    shift
    
    if [ "$MAINTENANCE_MODE" = "true" ]; then
        maintenance_mode
        return
    fi
    
    echo -e "${CYAN}🔨 $description...${NC}"
    if "$@"; then
        if [ "$KEEP_ALIVE" = "true" ]; then
            post_build_shell
        fi
    else
        if [ "$KEEP_ALIVE" = "true" ]; then
            echo -e "${YELLOW}🔧 $description falhou - entrando em modo debug...${NC}"
            maintenance_mode
        else
            exit 1
        fi
    fi
}

# Função para comandos que podem falhar (com lifecycle)
execute_command() {
    local description="$1"
    shift
    
    if [ "$MAINTENANCE_MODE" = "true" ]; then
        maintenance_mode
        return
    fi
    
    echo -e "${CYAN}🚀 $description: $@${NC}"
    if "$@"; then
        if [ "$KEEP_ALIVE" = "true" ]; then
            post_build_shell
        fi
    else
        if [ "$KEEP_ALIVE" = "true" ]; then
            echo -e "${YELLOW}🔧 $description falhou - entrando em modo debug...${NC}"
            maintenance_mode
        else
            exit 1
        fi
    fi
}

# Função para verificação de instalação
check_installation() {
    if [ -f "./local/bin/ffmpeg" ]; then
        echo -e "${GREEN}✅ FFmpeg encontrado:${NC}"
        ./local/bin/ffmpeg -version | head -3
        echo ""
        echo -e "${CYAN}Outros binários:${NC}"
        ls -la ./local/bin/ 2>/dev/null || echo "Diretório bin não encontrado"
    else
        echo -e "${YELLOW}FFmpeg não encontrado - execute build primeiro${NC}"
        echo -e "${CYAN}Arquivos disponíveis em local/:${NC}"
        ls -la ./local/ 2>/dev/null || echo "Diretório local não existe"
    fi
}

# Função para limpeza
clean_build_files() {
    rm -rf ./build/* ./local/*
    echo -e "${GREEN}✅ Limpeza concluída${NC}"
}

# Função principal
main() {
    show_banner
    check_system
    
    # Processar argumentos
    case "${1:-build}" in
        "maintenance"|"maint"|"debug")
            maintenance_mode
            ;;
        "build"|"compile")
            shift # Remove o primeiro argumento (build/compile)
            execute_build "Iniciando build do FFmpeg" run_build "$@"
            ;;
        "build-libs")
            execute_build "Compilando apenas bibliotecas" run_build "--libs-only=y"
            ;;
        "build-ffmpeg")
            execute_build "Compilando apenas FFmpeg" run_build "--ffmpeg-only=y"
            ;;
        "build-extras")
            execute_build "Compilando extras (MediaInfo, MP4Box)" run_build "--extras=y"
            ;;
        "build-optimized")
            execute_build "Compilando versão otimizada" run_build "--optimize=y"
            ;;
        "build-help")
            echo -e "${CYAN}🔨 Mostrando ajuda do script de build...${NC}"
            if [ -f "./compile-ffmpeg.sh" ]; then
                ./compile-ffmpeg.sh --help
            else
                echo -e "${RED}❌ Script compile-ffmpeg.sh não encontrado!${NC}"
            fi
            ;;
        "shell"|"bash")
            echo -e "${CYAN}🐚 Entrando em shell...${NC}"
            exec /bin/bash
            ;;
        "check"|"verify")
            echo -e "${BLUE}🔍 Verificando instalação...${NC}"
            check_installation
            ;;
        "clean")
            echo -e "${YELLOW}🧹 Limpando arquivos de build...${NC}"
            clean_build_files
            ;;
        "options"|"opts")
            show_build_options
            ;;
        *)
            # Comando personalizado - pode ser opções de build
            if [[ "$1" == --* ]]; then
                execute_build "Executando build com opções personalizadas" run_build "$@"
            else
                execute_command "Executando comando personalizado" "$@"
            fi
            ;;
    esac
}

# Interceptar sinais para limpeza
trap 'echo -e "\n${YELLOW}🛑 Container sendo finalizado...${NC}"; exit 0' SIGTERM SIGINT

# Executar função principal
main "$@"
