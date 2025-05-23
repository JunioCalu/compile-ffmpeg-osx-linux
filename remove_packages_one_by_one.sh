#!/bin/bash

# Verificar se o script está sendo executado com sudo
if [ "$EUID" -ne 0 ]; then 
    echo "Este script precisa ser executado com sudo"
    exec sudo "$0" "$@"
fi

# Nome do arquivo que conterá a lista de pacotes a manter
KEEP_PACKAGES_FILE="/tmp/keep-packages.txt"

# Arquivo de log para registrar resultados
LOG_FILE="/tmp/package_removal_log.txt"

# Remover arquivo de log antigo se existir
#[ -f "$LOG_FILE" ] && rm -vf "$LOG_FILE"

# Função para log que exibe na tela e salva no arquivo
log_msg() {
    echo "$@"
    echo "$@" >> "$LOG_FILE"
}

# Garantir que o arquivo de log seja criado corretamente
touch $LOG_FILE
#chmod -v 777 $LOG_FILE
if [ ! -f "$LOG_FILE" ]; then
    echo "Erro: Não foi possível criar o arquivo de log em $LOG_FILE"
    exit 1
fi

# Cria arquivo com a lista de pacotes a manter
cat > $KEEP_PACKAGES_FILE << 'EOF'
base-files
base-passwd
bash
bsdutils
coreutils
dash
debconf
debianutils
diffutils
dpkg
e2fsprogs
findutils
gcc-14-base
grep
gzip
hostname
init-system-helpers
libacl1
libattr1
libaudit-common
libaudit1
libblkid1
libbz2-1.0
libc-bin
libc6
libcap-ng0
libcap2
libcom-err2
libcrypt1
libdebconfclient0
libext2fs2t64
libgcc-s1
libgcrypt20
libgmp10
libgpg-error0
liblz4-1
liblzma5
libmd0
libmount1
libncursesw6
libpam-modules
libpam-modules-bin
libpam-runtime
libpam0g
libpcre2-8-0
libproc2-0
libselinux1
libsemanage-common
libsemanage2
libsepol2
libsmartcols1
libss2
libssl3t64
libsystemd0
libtinfo6
libudev1
libuuid1
libzstd1
login
logsave
mawk
mount
ncurses-base
ncurses-bin
passwd
perl-base
procps
sed
sensible-utils
sysvinit-utils
tar
util-linux
zlib1g
apt
gpgv
libapt-pkg6.0t64
libassuan0
libffi8
libgnutls30t64
libhogweed6t64
libidn2-0
libnettle8t64
libnpth0t64
libp11-kit0
libseccomp2
libstdc++6
libtasn1-6
libunistring5
libxxhash0
ubuntu-keyring
EOF

log_msg ""
log_msg "Executando limpeza inicial com aptitude..."
log_msg "---- Início do log de limpeza com aptitude ----"

if ! command -v aptitude >/dev/null 2>&1; then
    log_msg "O aptitude não está instalado, instalando..."
    apt update
    apt install aptitude -y
fi

# Verificar se o aptitude está instalado
if command -v aptitude >/dev/null 2>&1; then
    APTITUDE_PACKAGES=$(aptitude search '~i!~M!~prequired!~pimportant!~R~prequired!~R~R~prequired!~R~pimportant!~R~R~pimportant!busybox!grub!initramfs-tools' | awk '{print $2}')
    
    if [ -n "$APTITUDE_PACKAGES" ]; then
        log_msg "Pacotes encontrados pelo aptitude para remoção:"
        echo "$APTITUDE_PACKAGES" | tee -a $LOG_FILE
        
        # Remover pacotes encontrados pelo aptitude
        DEBIAN_FRONTEND=noninteractive aptitude purge -y $APTITUDE_PACKAGES 2>&1 | tee -a $LOG_FILE
    else
        log_msg "Nenhum pacote adicional encontrado pelo aptitude"
    fi
else
    log_msg "Aptitude não está instalado - pulando esta etapa"
fi
log_msg "---- Fim do log de limpeza com aptitude ----"

log_msg "$(date) - Iniciando processo de remoção de pacotes"

# Obtém lista de pacotes a serem removidos
PACKAGES_TO_REMOVE=$(dpkg-query -f '${binary:Package}\n' -W | grep -v -f $KEEP_PACKAGES_FILE)

# Exibe e registra os pacotes que serão removidos
log_msg ""
log_msg "=== PACOTES QUE SERÃO REMOVIDOS (NÃO ESTÃO NA LISTA DE PRESERVAÇÃO) ==="
echo "$PACKAGES_TO_REMOVE" | tee -a $LOG_FILE
log_msg "==================================================================="
log_msg ""

# Conta total de pacotes a remover
TOTAL_COUNT=$(echo "$PACKAGES_TO_REMOVE" | wc -l)
CURRENT=0
SUCCESS=0
FAIL=0

log_msg "Total de pacotes a remover: $TOTAL_COUNT"
log_msg ""

# Função para tratar sinais (CTRL+C)
function cleanup {
    log_msg ""
    log_msg ""
    log_msg "Interrompido pelo usuário."
    log_msg "Pacotes processados: $CURRENT de $TOTAL_COUNT"
    log_msg "Sucessos: $SUCCESS | Falhas: $FAIL"
    log_msg "$(date) - Processo interrompido pelo usuário após $CURRENT de $TOTAL_COUNT pacotes"
    exit 1
}

# Captura CTRL+C
trap cleanup SIGINT

# Remove pacotes um por um
for package in $PACKAGES_TO_REMOVE; do
    CURRENT=$((CURRENT + 1))
    
    log_msg ""
    log_msg "[$CURRENT/$TOTAL_COUNT] Removendo $package..."
    
    # Tenta remover o pacote e exibe o log na tela
    log_msg "---- Início do log de remoção para $package ----"
    DEBIAN_FRONTEND=noninteractive apt-get --yes purge "$package" 2>&1 | tee -a $LOG_FILE
    STATUS=${PIPESTATUS[0]}
    log_msg "---- Fim do log de remoção para $package ----"
    
    if [ $STATUS -eq 0 ]; then
        log_msg "RESULTADO: SUCESSO - $package foi removido"
        SUCCESS=$((SUCCESS + 1))
    else
        log_msg "RESULTADO: FALHA - Não foi possível remover $package"
        FAIL=$((FAIL + 1))
    fi
    
    # Pequena pausa para não sobrecarregar o sistema
    sleep 0.5
done

# Executa autoremove para limpar dependências órfãs
log_msg ""
log_msg "Executando autoremove para limpar pacotes órfãos..."
log_msg "---- Início do log de autoremove ----"
DEBIAN_FRONTEND=noninteractive apt-get --yes autoremove --purge 2>&1 | tee -a $LOG_FILE
log_msg "---- Fim do log de autoremove ----"

# Resumo final
log_msg ""
log_msg "Processo concluído!"
log_msg "Total de pacotes processados: $TOTAL_COUNT"
log_msg "Sucessos: $SUCCESS | Falhas: $FAIL"
log_msg "Log detalhado salvo em: $LOG_FILE"
log_msg "$(date) - Processo concluído. Sucessos: $SUCCESS | Falhas: $FAIL"

# Verificar se ainda existem pacotes não listados no sistema
REMAINING_PACKAGES=$(dpkg-query -f '${binary:Package}\n' -W | grep -v -f $KEEP_PACKAGES_FILE)
REMAINING_COUNT=$(echo "$REMAINING_PACKAGES" | grep -v "^$" | wc -l)

if [ $REMAINING_COUNT -gt 0 ]; then
    log_msg ""
    log_msg "=== ATENÇÃO: AINDA EXISTEM $REMAINING_COUNT PACOTES NÃO LISTADOS NO SISTEMA ==="
    echo "$REMAINING_PACKAGES" | grep -v "^$" | tee -a $LOG_FILE
    log_msg "==================================================================="
else
    log_msg ""
    log_msg "Todos os pacotes não listados foram removidos com sucesso!"
fi