#!/bin/bash

#ffmpeg_shared="yes"
#ffmpeg_branch="release/4.3"


while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
    optimize='n'

    opt="$1";
    shift;
    case "$opt" in
        --ffmpeg-only=* )
           compile_ffmpeg_only="${opt#*=}";;
        --libs-only=* )
           compile_libs_only="${opt#*=}";;
        --extras=* )
           compile_extras="${opt#*=}";;
        --optimize=* )
           optimize="${opt#*=}";;
        --help )
           showHelp=true;;
        *);;
   esac
done

if [[ $showHelp ]]; then
    echo "-------------------------------------------------------------"
    echo "compile with:"
    echo
    echo '--libs-only=[y/n]      # compile only libs'
    echo '--ffmpeg-only=[y/n]    # compile only ffmpeg'
    echo '--extras=[y/n]         # compile mediainfo and MP4Box'
    echo '--optimize=[y/n]       # compile system optimized version'
    echo '--help                 # show this help'

    exit 0
fi

arch=$(uname -m)
system=$(uname -s)

if [[ $arch == "arm64" ]]; then
    export CXX=$(which clang++)
fi

if [[ "$optimize" == "y" ]] || [[ "$arch" != "x86_64" ]]; then
    tune="native"
    mtune="native"
    onum=2
    cpuDetect=""
    vpxFlags=""
else
    tune="x86-64"
    mtune="generic"
    onum=2
    cpuDetect="--enable-runtime-cpudetect"
    vpxFlags="--enable-postproc --enable-vp9-postproc --enable-runtime-cpu-detect"
fi

config="build_config.txt"

if [[ ! -f "$config" ]]; then
cat <<EOF > "$config"
#--enable-decklink
#--enable-libklvanc
#--disable-ffplay
#--disable-sdl2
#--enable-libfontconfig
#--enable-libaom
#--enable-libass
#--enable-libbluray
#--enable-libfdk-aac
#--enable-libfribidi
#--enable-libfreetype
#--enable-libharfbuzz
#--enable-libmp3lame
#--enable-libopus
#--enable-libsoxr
#--enable-libsrt
#--enable-librist
#--enable-libtwolame
#--enable-libvpx
#--enable-libx264
#--enable-libx265
#--enable-libzimg
#--enable-libzmq
#--enable-nonfree
#--enable-opencl
#--enable-opengl
#--enable-libopenjpeg
#--enable-openssl
#--enable-libsvtav1
#--enable-librav1e
#--enable-libdav1d
#--enable-cuda-nvcc
#--enable-cuvid
#--enable-nvenc
#--enable-nvdec
#--enable-libnpp
#--enable-libndi_newtek
#--enable-libpulse
#--enable-vulkan
#--enable-libplacebo
#--enable-libshaderc
#--enable-libvmaf
EOF
    echo "-------------------------------------------------------------------------------"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo " edit \"$config\" and activate all libs that you need"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "-------------------------------------------------------------------------------"
    while true; do
        read -r -p "run (y/n):$ " run

        if [[ "$run" == 'y' ]]; then
            break
        elif [[ "$run" == 'n' ]]; then
            exit
        else
            echo ""
            echo "Please type 'y' or 'n'"
            echo "------------------------------------"
            echo ""
        fi
    done
fi

# --------------------------------------------------

# check system
if [[ "$system" == "Darwin" ]]; then
    osExtra="-mmacosx-version-min=11"
    osString="osx"
    cpuCount=$( sysctl hw.ncpu | awk '{ print $2 - 1 }' )
    compNasm="no"
    osLib="-liconv"
    osFlag=""
    arch="--arch=$arch"
    fpic=""
    sd="gsed"

    if [[ "$arch" == "x86_64" ]]; then
        extraLibs="-lintl"
    else
        extraLibs=""
    fi

else
    osExtra="-static-libstdc++ -static-libgcc"
    osString="nix"
    cpuCount=$( nproc | awk '{ print $1 - 1 }' )
    compNasm="yes"
    osLib=""
    #osFlag="--enable-pic"
    arch=""
    #fpic="-fPIC"
    sd="sed"
    extraLibs="-lpthread"
fi

get_options() {
    $sd -r '# remove commented text
        s/#.*//
        # delete empty lines
        /^\s*$/d
        # remove leading whitespace
        s/^\s+//
        # remove trailing whitespace
        s/\s+$//
        ' "$config" | tr -d '\r'
}

IFS=$'\n' read -d '' -r -a FFMPEG_LIBS < <(get_options)

compile="false"
buildFFmpeg="false"

EXTRA_CFLAGS="-march=$tune"
LOCALBUILDDIR="$PWD/build"
LOCALDESTDIR="$PWD/local"
export LOCALBUILDDIR LOCALDESTDIR

PKG_CONFIG_PATH="${LOCALDESTDIR}/lib/pkgconfig"
CPPFLAGS="-I${LOCALDESTDIR}/include $fpic $osExtra"
CFLAGS="-I${LOCALDESTDIR}/include $EXTRA_CFLAGS -mtune=$mtune -O$onum $osExtra $fpic"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-L${LOCALDESTDIR}/lib -pipe $osExtra"
export PKG_CONFIG_PATH CPPFLAGS CFLAGS CXXFLAGS LDFLAGS

[ -d "$LOCALBUILDDIR" ] || mkdir "$LOCALBUILDDIR"
[ -d "$LOCALDESTDIR" ] || mkdir "$LOCALDESTDIR"

do_prompt() {
    # from http://superuser.com/a/608509
    while read -r -s -e -t 0.1; do : ; done
    read -r -p "$1"
}

# get git clone, checkout, or update
do_git() {
    local gitURL="$1"
    local gitFolder="$2"
    local gitDepth="$3"
    local gitBranch="$4"
    local gitCommit="$5"
    
    echo -ne "\033]0;compile $gitFolder\007"
    
    # Se o diretório não existe, fazer clone
    if [ ! -d "$gitFolder" ]; then
        echo "Clonando $gitFolder..."
        
        # Determinar comando de clone baseado nos parâmetros
        if [[ $gitDepth == "noDepth" ]]; then
            git clone "$gitURL" "$gitFolder"
        elif [[ -n "$gitBranch" ]]; then
            git clone --depth 1 --single-branch -b "$gitBranch" "$gitURL" "$gitFolder"
        else
            git clone --depth 1 "$gitURL" "$gitFolder"
        fi
        
        compile="true"
        cd "$gitFolder" || exit
        
        # Se um commit específico foi fornecido, fazer checkout
        if [[ -n "$gitCommit" ]]; then
            echo "Fazendo checkout do commit/tag: $gitCommit"
            
            # Se foi clonado com --depth 1, pode precisar fazer fetch completo
            if [[ $gitDepth != "noDepth" ]]; then
                git fetch --unshallow origin "$gitCommit" || git fetch origin "$gitCommit"
            fi
            
            git checkout "$gitCommit"
        fi
    else
        # Diretório existe, fazer update
        cd "$gitFolder" || exit
        echo "Atualizando $gitFolder..."
        
        # Salvar o commit atual
        oldHead=$(git rev-parse HEAD)
        
        # Verificar se há mudanças locais não commitadas
        if ! git diff --quiet || ! git diff --cached --quiet; then
            echo "Aviso: Descartando mudanças locais em $gitFolder"
            git reset --hard HEAD
            git clean -fdx
        fi
        
        # Fazer fetch primeiro para ter as referências atualizadas
        git fetch origin || {
            echo "Erro ao fazer fetch de $gitFolder"
            exit 1
        }
        
        # Determinar para onde fazer checkout/pull
        if [[ -n "$gitCommit" ]]; then
            # Se especificou um commit/tag, usar ele
            echo "Fazendo checkout do commit/tag: $gitCommit"
            git checkout "$gitCommit"
        elif [[ -n "$gitBranch" ]]; then
            # Se especificou um branch, atualizar para ele
            echo "Atualizando para branch: $gitBranch"
            git checkout "$gitBranch" || git checkout -b "$gitBranch" "origin/$gitBranch"
            git reset --hard "origin/$gitBranch"
        else
            # Senão, atualizar o branch atual
            current_branch=$(git rev-parse --abbrev-ref HEAD)
            
            # Se estiver em detached HEAD, usar master/main
            if [[ "$current_branch" == "HEAD" ]]; then
                if git show-ref --verify --quiet refs/remotes/origin/main; then
                    current_branch="main"
                else
                    current_branch="master"
                fi
                git checkout "$current_branch"
            fi
            
            echo "Atualizando branch: $current_branch"
            git reset --hard "origin/$current_branch" || {
                echo "Erro: Branch $current_branch não tem upstream configurado"
                git branch --set-upstream-to="origin/$current_branch" "$current_branch"
                git reset --hard "origin/$current_branch"
            }
        fi
        
        # Verificar se houve mudanças
        newHead=$(git rev-parse HEAD)
        if [[ "$oldHead" != "$newHead" ]]; then
            compile="true"
            echo "Repositório atualizado: ${oldHead:0:7} -> ${newHead:0:7}"
        else
            echo "Repositório já está atualizado"
        fi
    fi
    
    # Mostrar informações do estado atual
    echo "Estado atual de $gitFolder:"
    echo "  Branch/Tag: $(git describe --always --tags 2>/dev/null || git rev-parse --abbrev-ref HEAD)"
    echo "  Commit: $(git rev-parse --short HEAD)"
}

# get svn checkout, or update
do_svn() {
    local svnURL="$1"
    local svnFolder="$2"
    echo -ne "\033]0;compile $svnFolder\007"
    if [ ! -d "$svnFolder" ]; then
        svn checkout "$svnURL" "$svnFolder"
        compile="true"
        cd "$svnFolder" || exit
    else
        cd "$svnFolder" || exit
        oldRevision=$(svnversion)
        svn update
        newRevision=$(svnversion)

        if [[ "$oldRevision" != "$newRevision" ]]; then
            compile="true"
        fi
    fi
}

# get curl download
do_curl() {
    local url="$1"
    local archive="$2"
    local dirName="$3"
    local extracted_dir=""
    
    if [[ -z $archive ]]; then
        # remove arguments and filepath
        archive=${url%%\?*}
        archive=${archive##*/}
    fi

    echo "Baixando $archive de $url..."
    local -r response_code=$(curl --retry 20 --retry-max-time 5 -L -k -f -w "%{response_code}" -o "$archive" "$url")

    if [[ $response_code = "200" || $response_code = "226" ]]; then
        echo "Download concluído com sucesso."
        
        case "$archive" in
            *.tar.gz|*.tar.bz2|*.tar.xz)
                # Determina o diretório extraído usando apenas o conteúdo do arquivo
                echo "Analisando o conteúdo do arquivo $archive..."
                
                # Método simplificado: pegar primeira entrada e extrair o diretório raiz
                local first_entry=$(tar -tf "$archive" | head -1 | cut -d'/' -f1)
                
                # Remove arquivos antigos já extraídos
                if [[ -e "$first_entry" ]]; then
                    echo "Removendo arquivos antigos extraídos: $first_entry"
                    rm -vrf "$first_entry"
                fi 
                
                if [[ -z "$first_entry" ]]; then
                    echo "ERRO: Não foi possível ler o conteúdo do arquivo $archive."
                    exit
                fi
                
                extracted_dir="$first_entry"
                echo "Diretório detectado no arquivo: $extracted_dir"
                
                # Extrai o arquivo
                echo "Extraindo $archive..."
                if tar -xf "$archive"; then
                    echo "Extração concluída com sucesso."
                else
                    echo "ERRO: Falha ao extrair $archive. Abortando operação."
                    exit
                fi
                
                # Se um nome de diretório específico foi solicitado
                if [[ -n "$extracted_dir" && -n "$dirName" && "$extracted_dir" != "$dirName" ]]; then
                    echo "Renomeando diretório extraído de $extracted_dir para $dirName"
                    
                    # Verificar se o diretório extraído realmente existe
                    if [[ ! -d "$extracted_dir" ]]; then
                        echo "ERRO: O diretório extraído $extracted_dir não foi encontrado!"
                        exit
                    fi
                    
                    # Verifica se o diretório de destino já existe
                    if [[ -e "$dirName" ]]; then
                        echo "Removendo diretório de destino existente: $dirName"
                        rm -rf "$dirName"
                    fi
                    
                    # Renomeia o diretório
                    if mv "$extracted_dir" "$dirName"; then
                        extracted_dir="$dirName"
                    else
                        echo "ERRO: Falha ao renomear $extracted_dir para $dirName"
                        exit
                    fi
                fi
                
                # Navega para o diretório extraído, se existir
                if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                    echo "Navegando para $extracted_dir"
                    cd "$extracted_dir" || { echo "ERRO: Não foi possível navegar para $extracted_dir"; exit; }
                else
                    echo "Permanecendo no diretório atual (os arquivos foram extraídos aqui)"
                fi
            ;;
            *.zip)
                # Determina o diretório usando o conteúdo do arquivo ZIP
                echo "Analisando o conteúdo do arquivo $archive..."
                
                # Método simplificado: extrai o diretório raiz do primeiro arquivo
                local first_entry=$(unzip -l "$archive" | sed -n '4p' | awk '{print $4}' | cut -d'/' -f1)
                
                # Se o primeiro arquivo não tiver diretório (estiver na raiz)
                if [[ -z "$first_entry" || "$first_entry" == *.* ]]; then
                    # Tenta verificar se todas as entradas estão na mesma pasta
                    first_entry=$(unzip -l "$archive" | sed '1,3d' | head -n -2 | awk '{print $4}' | grep "/" | cut -d'/' -f1 | sort -u | head -1)
                fi
                
                if [[ -z "$first_entry" ]]; then
                    echo "AVISO: Os arquivos parecem estar na raiz do ZIP, sem diretório comum."
                    extracted_dir=""
                else
                    # Remove arquivos antigos já extraídos
                    if [[ -e "$first_entry" ]]; then
                        echo "Removendo arquivos antigos extraídos: $first_entry"
                        rm -vrf "$first_entry"
                    fi
                    
                    extracted_dir="$first_entry"
                fi
                
                echo "Diretório detectado no arquivo ZIP: $extracted_dir"
                
                # Extrai o arquivo
                echo "Extraindo $archive..."
                if unzip -q "$archive"; then
                    echo "Extração concluída com sucesso."
                    rm "$archive"
                else
                    echo "ERRO: Falha ao extrair $archive. Abortando operação."
                    exit
                fi
                
                # Renomeia se necessário
                if [[ -n "$extracted_dir" && -n "$dirName" && "$extracted_dir" != "$dirName" ]]; then
                    echo "Renomeando diretório extraído de $extracted_dir para $dirName"
                    
                    if [[ ! -d "$extracted_dir" ]]; then
                        echo "ERRO: O diretório extraído $extracted_dir não foi encontrado!"
                        exit
                    fi
                    
                    if [[ -e "$dirName" ]]; then
                        rm -rf "$dirName"
                    fi
                    
                    if mv "$extracted_dir" "$dirName"; then
                        extracted_dir="$dirName"
                    else
                        echo "ERRO: Falha ao renomear $extracted_dir para $dirName"
                        exit
                    fi
                fi
                
                # Navega para o diretório
                if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
                    echo "Navegando para $extracted_dir"
                    cd "$extracted_dir" || { echo "ERRO: Não foi possível navegar para $extracted_dir"; exit; }
                else
                    echo "Permanecendo no diretório atual (os arquivos foram extraídos aqui)"
                fi
            ;;
            *.7z)
                # Determina o diretório usando o conteúdo do arquivo 7z
                echo "Analisando o conteúdo do arquivo $archive..."
                
                # Método simplificado para extrair o diretório raiz do primeiro item 
                local first_entry=$(7z l "$archive" | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -1 | awk '{print $NF}' | cut -d'/' -f1)
                
                # Se não encontrou nada ou o que encontrou parece ser um arquivo, tenta mais métodos
                if [[ -z "$first_entry" || "$first_entry" == *.* ]]; then
                    # Procura por todos os caminhos e extrai o prefixo comum
                    first_entry=$(7z l "$archive" | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" | grep "/" | awk '{print $NF}' | cut -d'/' -f1 | sort -u | head -1)
                fi
                
                # Se ainda não encontrou, procura por diretórios explícitos
                if [[ -z "$first_entry" ]]; then
                    first_entry=$(7z l "$archive" | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" | grep "D...." | head -1 | awk '{print $NF}')
                fi
                
                if [[ -z "$first_entry" ]]; then
                    echo "AVISO: Não foi possível detectar o diretório dentro do arquivo 7z."
                    # Usamos o nome base do arquivo como fallback
                    first_entry=$(expr "$archive" : '\(.*\)\.\(7z\)$')
                else
                    # Remove arquivos antigos já extraídos
                    if [[ -e "$first_entry" ]]; then
                        echo "Removendo arquivos antigos extraídos: $first_entry"
                        rm -vrf "$first_entry"
                    fi
                fi
                
                extracted_dir="$first_entry"
                echo "Diretório detectado no arquivo 7z: $extracted_dir"
                
                # Para 7z, sempre usamos o parâmetro -o para especificar o diretório de saída
                local output_dir="${dirName:-$extracted_dir}"
                if [[ -z "$output_dir" ]]; then
                    # Se ainda não temos um diretório de saída, usamos o nome base do arquivo
                    output_dir=$(expr "$archive" : '\(.*\)\.\(7z\)$')
                fi
                
                # Certifique-se de que temos um diretório de saída
                if [[ -z "$output_dir" ]]; then
                    echo "ERRO: Não foi possível determinar o diretório de saída para $archive."
                    exit
                fi
                
                # Remove diretório existente, se houver
                if [[ -e "$output_dir" ]]; then
                    echo "Removendo diretório existente: $output_dir"
                    rm -rf "$output_dir"
                fi
                
                # Extrai o arquivo
                echo "Extraindo $archive para $output_dir..."
                if 7z x -o"$output_dir" "$archive"; then
                    echo "Extração concluída com sucesso."
                    rm "$archive"
                    
                    # Navega para o diretório de saída
                    echo "Navegando para $output_dir"
                    cd "$output_dir" || { echo "ERRO: Não foi possível navegar para $output_dir"; exit; }
                else
                    echo "ERRO: Falha ao extrair $archive. Abortando operação."
                    exit
                fi
            ;;
        esac
        
        # Confirma o diretório atual
        current_dir=$(pwd)
        echo "Diretório atual: $current_dir"
        
    elif [[ $response_code -gt 400 ]]; then
        echo "Erro $response_code ao baixar $url"
        echo "Tente novamente mais tarde ou pressione <Enter> para continuar"
        do_prompt "se você tiver certeza de que nada depende disso."
    else
        echo "Código de resposta desconhecido: $response_code"
    fi
}

# check if compiled file exist
do_checkIfExist() {
    local packetName="$1"
    local fileName="$2"
    local fileExtension=${fileName##*.}
    if [[ "$fileExtension" != "a" ]]; then
        if [ -f "$LOCALDESTDIR/$fileName" ]; then
            echo -
            echo -------------------------------------------------
            echo "build $packetName done..."
            echo -------------------------------------------------
            echo -
            compile="false"
        else
            echo -------------------------------------------------
            echo "Build $packetName failed..."
            echo "Delete the source folder under '$LOCALBUILDDIR' and start again,"
            echo "or if you know there is no dependences hit enter for continue it."
            read -r -p ""
            sleep 5
        fi
    else
        if [ -f "$LOCALDESTDIR/lib/$fileName" ]; then
            echo -
            echo -------------------------------------------------
            echo "build $packetName done..."
            echo -------------------------------------------------
            echo -
            compile="false"
        else
            echo -------------------------------------------------
            echo "build $packetName failed..."
            echo "delete the source folder under '$LOCALBUILDDIR' and start again,"
            echo "or if you know there is no dependences hit enter for continue it"
            read -r -p ""
            sleep 5
        fi
    fi
}

buildLibs() {

    cd "$LOCALBUILDDIR" || exit

    if [[ "$system" == "Darwin" ]] || [[ "$system" == "Linux" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libuuid.a" ]; then
            echo -------------------------------------------------
            echo "uuid-1.6.2 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile uuid 64Bit\007"

            do_curl "https://www.mirrorservice.org/sites/ftp.ossp.org/pkg/lib/uuid/uuid-1.6.2.tar.gz"

            ./configure --prefix="$LOCALDESTDIR" --disable-shared

            make -j "$cpuCount"
            make install

            do_checkIfExist uuid-1.6.2 libuuid.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libz.a" ]; then
        echo -------------------------------------------------
        echo "zlib-1.3.1 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libz 64Bit\007"

        do_curl "https://zlib.net/zlib-1.3.1.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --static

        make -j "$cpuCount"
        make install

        do_checkIfExist zlib-1.3.1 libz.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libiconv.a" ]; then
        echo -------------------------------------------------
        echo "libiconv-1.18 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libiconv 64Bit\007"

        do_curl "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        do_checkIfExist libiconv-1.18 libiconv.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libbz2.a" ]; then
        echo -------------------------------------------------
        echo "bzip2-1.0.8 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile bzip2 64Bit\007"

        do_curl "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz"

        if [[ "$system" == "Darwin" ]]; then
            $sd -ri "s/^CFLAGS=-Wall/^CFLAGS=-Wall $osExtra/g" Makefile
        fi

        make install PREFIX="$LOCALDESTDIR"

        do_checkIfExist bzip2-1.0.8 libbz2.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/liblzma.a" ]; then
        echo -------------------------------------------------
        echo "xz-5.8.1 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile xz 64Bit\007"

        do_curl "https://downloads.sourceforge.net/project/lzmautils/xz-5.8.1.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        do_checkIfExist xz-5.8.1 liblzma.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libunwind.a" ]; then
        echo -------------------------------------------------
        echo "libunwind-1.8.1 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libunwind 64Bit\007"

        do_curl "https://github.com/libunwind/libunwind/releases/download/v1.8.1/libunwind-1.8.1.tar.gz"

        # Configurar com opções semelhantes ao PKGBUILD
        ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static

        make -j "$cpuCount"
        make install

        # Remover arquivos desnecessários como no PKGBUILD original
        rm -rf "$LOCALDESTDIR/libexec/libunwind" 2>/dev/null || true

        do_checkIfExist libunwind-1.8.1 libunwind.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-gmp" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libgmp.a" ]; then
            echo -------------------------------------------------
            echo "GMP-6.3.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile GMP 64Bit\007"

            do_curl "https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz"

            # Patch para GCC 15, se necessário
            #if [ -f "../../patches/gmp-gcc-15.patch" ]; then
            #    git apply -p1 < ../../patches/gmp-gcc-15.patch
            #fi
            
            # Reconstruir os arquivos autoconf
            autoreconf -vif
            
            # Configurar com opções estáticas
            ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --enable-cxx

            make -j "$cpuCount"
            make install

            do_checkIfExist gmp-6.3.0 libgmp.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libpng.a" ]; then
        echo -------------------------------------------------
        echo "libpng-1.6.48 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libpng 64Bit\007"

        do_curl "http://prdownloads.sourceforge.net/libpng/libpng-1.6.48.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        do_checkIfExist libpng-1.6.48 libpng.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfontconfig" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libexpat.a" ]; then
            echo -------------------------------------------------
            echo "expat-2.7.1 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile expat 64Bit\007"

            do_curl "https://github.com/libexpat/libexpat/releases/download/R_2_7_1/expat-2.7.1.tar.bz2"

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --without-docbook

            make -j "$cpuCount"
            make install

            do_checkIfExist expat-2.7.1 libexpat.a
        fi

        cd "$LOCALBUILDDIR" || exit

        if [ -f "$LOCALDESTDIR/lib/libfreetype.a" ]; then
            echo -------------------------------------------------
            echo "freetype-2.13.3 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile freetype\007"

            do_curl "https://sourceforge.net/projects/freetype/files/freetype2/2.13.3/freetype-2.13.3.tar.gz"

            ./configure --prefix="$LOCALDESTDIR" --disable-shared --with-harfbuzz=no
            make -j "$cpuCount"
            make install

            do_checkIfExist freetype-2.13.3 libfreetype.a

            $sd -ri "s/(Libs\:.*)/\1 -lpng16 -lbz2 -lz/g" "$LOCALDESTDIR/lib/pkgconfig/freetype2.pc"
        fi

        cd "$LOCALBUILDDIR" || exit

        if [ -f "$LOCALDESTDIR/lib/libfontconfig.a" ]; then
            echo -------------------------------------------------
            echo "fontconfig-2.15.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile fontconfig\007"

            # Usar repositório Git com tag específica
            do_git "https://gitlab.freedesktop.org/fontconfig/fontconfig.git" fontconfig-git "noDepth" "" "2.15.0"

            if [[ $compile == "true" ]]; then
                # Limpar build anterior se existir
                rm -rf build
                mkdir build
                cd build

                # Configurar com Meson para compilação estática
                meson setup --default-library=static \
                            --prefix="$LOCALDESTDIR" \
                            --libdir="$LOCALDESTDIR/lib" \
                            -Ddefault-hinting=slight \
                            -Ddefault-sub-pixel-rendering=rgb \
                            -Ddoc-html=disabled \
                            -Ddoc-pdf=disabled \
                            -Ddoc-txt=disabled \
                            -Dtests=disabled \
                            ..
                
                $sd -i 's/-pthread/-pthread -lm/g' build.ninja

                # Compilar
                meson compile

                # Instalar
                meson install

                cd ..

                # Verificar se foi compilado corretamente
                do_checkIfExist fontconfig-git libfontconfig.a

                # Atualizar pkg-config para incluir dependências necessárias
                $sd -ri "s/(Libs\:.*)/\1 -lpng16 -lbz2 -lxml2 -lz -lstdc++ $osLib -llzma -lm -lexpat -luuid/g" "$LOCALDESTDIR/lib/pkgconfig/fontconfig.pc"
            else
                echo -------------------------------------------------
                echo "fontconfig is already up to date"
                echo -------------------------------------------------
            fi
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfreetype" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libfontconfig.a" ]; then
            echo -------------------------------------------------
            echo "fontconfig-2.15.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile fontconfig\007"

            # Usar repositório Git com tag específica
            do_git "https://gitlab.freedesktop.org/fontconfig/fontconfig.git" fontconfig-git "noDepth" "" "2.15.0"

            if [[ $compile == "true" ]]; then
                # Limpar build anterior se existir
                rm -rf build
                mkdir build
                cd build

                # Configurar com Meson para compilação estática
                meson setup --default-library=static \
                            --prefix="$LOCALDESTDIR" \
                            --libdir="$LOCALDESTDIR/lib" \
                            -Ddefault-hinting=slight \
                            -Ddefault-sub-pixel-rendering=rgb \
                            -Ddoc-html=disabled \
                            -Ddoc-pdf=disabled \
                            -Ddoc-txt=disabled \
                            -Dtests=disabled \
                            ..
                
                $sd -i 's/-pthread/-pthread -lm/g' build.ninja

                # Compilar
                meson compile

                # Instalar
                meson install

                cd ..

                # Verificar se foi compilado corretamente
                do_checkIfExist fontconfig-git libfontconfig.a

                # Atualizar pkg-config para incluir dependências necessárias
                $sd -ri "s/(Libs\:.*)/\1 -lpng16 -lbz2 -lxml2 -lz -lstdc++ $osLib -llzma -lm -lexpat -luuid/g" "$LOCALDESTDIR/lib/pkgconfig/fontconfig.pc"
            else
                echo -------------------------------------------------
                echo "fontconfig is already up to date"
                echo -------------------------------------------------
            fi
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfribidi" ]] || [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libass" ]]; then
        do_git "https://github.com/fribidi/fribidi.git" fribidi-git

        if [[ $compile == "true" ]]; then
            rm -rf build
            mkdir build
            cd build

            meson setup -Ddocs=false -Dbin=false -Dtests=false --default-library=static .. --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib"
            ninja
            ninja install

            if [[ ! -f "$LOCALDESTDIR/lib/pkgconfig/fribidi.pc" ]]; then
                cp fribidi.pc "$LOCALDESTDIR/lib/pkgconfig/"
            fi

            do_checkIfExist fribidi-git libfribidi.a

        else
            echo -------------------------------------------------
            echo "fribidi is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libharfbuzz" ]] ||
       [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libzmq" ]] ||
       [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfreetype" ]] ||
       [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfontconfig" ]]; then

        do_git "https://github.com/harfbuzz/harfbuzz.git" harfbuzz-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build

            meson setup --default-library=static --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" ..

            ninja
            ninja install

            do_checkIfExist harfbuzz-git libharfbuzz.a

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++/g" "$LOCALDESTDIR/lib/pkgconfig/harfbuzz.pc"
        else
            echo -------------------------------------------------
            echo "harfbuzz is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libxml2.a" ]; then
        echo -------------------------------------------------
        echo "libxml2-2.14.3 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libxml2\007"

        do_curl "https://codeload.github.com/GNOME/libxml2/tar.gz/refs/tags/v2.14.3" "libxml2-2.14.3.tar.gz"

        if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

        ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --with-iconv=no --with-python=no

        make -j "$cpuCount"
        make install

        do_checkIfExist libxml2-2.14.3 libxml2.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libzimg" ]]; then
        do_git "https://github.com/sekrit-twc/zimg.git" zimg-git

        if [[ $compile == "true" ]]; then
            if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

            git submodule update --init --recursive
            env CFLAGS="-fPIC $CFLAGS" CXXFLAGS="-fPIC $CXXFLAGS" ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --enable-static

            make -j "$cpuCount"
            make install

            do_checkIfExist zimg-git libzimg.a

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++/g" "$LOCALDESTDIR/lib/pkgconfig/zimg.pc"
        else
            echo -------------------------------------------------
            echo "zimg is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libzmq" ]]; then
        EXTRA_CFLAGS="$EXTRA_CFLAGS -DZMG_STATIC"

        do_git "https://github.com/zeromq/libzmq.git" libzmq-git

        if [[ $compile == "true" ]]; then
            if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-static --disable-shared

            make -j "$cpuCount"
            make install

            do_checkIfExist libzmq-git libzmq.a

        else
            echo -------------------------------------------------
            echo "libzmq is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libopenjpeg" ]]; then

        do_git "https://github.com/uclouvain/openjpeg.git" libopenjpeg-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build

            cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_BINDIR="bin" -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_INSTALL_INCLUDEDIR="include"

            make -j "$cpuCount"
            make install

            do_checkIfExist libopenjpeg-git libopenjp2.a

        else
            echo -------------------------------------------------
            echo "libopenjpeg is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libwebp" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libwebp.a" ]; then
            echo -------------------------------------------------
            echo "libwebp-1.5.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile libwebp 64Bit\007"
            do_curl "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.5.0.tar.gz"

            # Aplicar patch se necessário
            #if [ -f "../../patches/0001-cmake-Install-anim-utils.patch" ]; then
            #   git apply -p1 -i ../../patches/0001-cmake-Install-anim-utils.patch
            #fi

            # Configurar com CMake para build estático
            mkdir -p build
            cd build || exit
            
            # Adicionar flags para compilação estática
            CFLAGS="$CFLAGS -DNDEBUG" CXXFLAGS="$CXXFLAGS -DNDEBUG" \
            cmake -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" \
                -DBUILD_SHARED_LIBS=OFF \
                -DWEBP_BUILD_EXTRAS=OFF \
                -DWEBP_BUILD_VWEBP=OFF \
                -DWEBP_BUILD_CWEBP=ON \
                -DWEBP_BUILD_DWEBP=ON \
                -DWEBP_BUILD_GIF2WEBP=ON \
                -DWEBP_BUILD_IMG2WEBP=ON \
                -DCMAKE_BUILD_TYPE=Release \
                ..

            make -j "$cpuCount"
            make install
            
            cd ..

            do_checkIfExist libwebp-1.5.0 libwebp.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-openssl" ]] || [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsrt" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libssl.a" ]; then
            echo -------------------------------------------------
            echo "openssl-1.1.1w is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile openssl 64Bit\007"

            if [[ "$system" == "Darwin" ]]; then
                target="darwin64-x86_64-cc"
            else
                target="linux-x86_64"
            fi

            # Atualizar para versão 1.1.1w
            do_curl "https://www.openssl.org/source/openssl-1.1.1w.tar.gz"

            # Aplicar patch se necessário
            # Se você tem o patch ca-dir.patch, descomente as linhas abaixo
            # echo "Aplicando patch ca-dir..."

            #if [ -f "../../patches/ca-dir.patch" ]; then
            #    git apply -p1 < ../../patches/ca-dir.patch
            #fi

            # Configurar com opções específicas para compilação estática e otimizações
            ./Configure --prefix="$LOCALDESTDIR" \
                    --openssldir="$LOCALDESTDIR/ssl" \
                    --libdir="$LOCALDESTDIR/lib" \
                    no-shared \
                    no-ssl3-method \
                    enable-camellia \
                    enable-idea \
                    enable-mdc2 \
                    enable-rfc3779 \
                    enable-ec_nistp_64_gcc_128 \
                    -mtune=$mtune $osExtra \
                    $target

            # Compilar
            make depend all
            make install_sw

            # Instalar licença
            mkdir -p "$LOCALDESTDIR/share/licenses/openssl"
            cp LICENSE "$LOCALDESTDIR/share/licenses/openssl/"

            # Verificar instalação
            do_checkIfExist openssl-1.1.1w libssl.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsrt" ]]; then
        do_git "https://github.com/Haivision/srt.git" srt-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build || exit

            cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DENABLE_SHARED:BOOLEAN=OFF -DUSE_STATIC_LIBSTDCXX:BOOLEAN=ON -DENABLE_CXX11:BOOLEAN=OFF -DCMAKE_INSTALL_BINDIR="bin" -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_INSTALL_INCLUDEDIR="include"

            make -j "$cpuCount"
            make install

            do_checkIfExist srt-git libsrt.a

            if [[ "$system" == "Darwin" ]]; then
                extra=""
            else
                extra="-lpthread -ldl"
            fi

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++ -lcrypto -lz $extra/g" "$LOCALDESTDIR/lib/pkgconfig/srt.pc"
        else
            echo -------------------------------------------------
            echo "srt is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-librist" ]]; then
        do_git "https://code.videolan.org/rist/librist.git" librist-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build || exit

            meson setup --default-library=static --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" ..

            ninja
            ninja install

            do_checkIfExist librist-git librist.a
        else
            echo -------------------------------------------------
            echo "librist is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libvmaf" ]]; then
        do_git "https://github.com/Netflix/vmaf.git" vmaf-git

        if [[ $compile == "true" ]]; then
            cd libvmaf
            mkdir build
            cd build || exit

            meson setup --default-library=static -Denable_avx512=true -Dbuilt_in_models=true --buildtype release --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" ..

            ninja
            ninja install

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++/g" "$LOCALDESTDIR/lib/pkgconfig/libvmaf.pc"

            do_checkIfExist vmaf-git libvmaf.a
        else
            echo -------------------------------------------------
            echo "vmaf is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-librtmp" ]]; then
        # Use rtmpdump v2.4 (c28f1bab7822de97353849e7787b59e50bbb1428 como commit específico)  
        do_git "https://git.ffmpeg.org/rtmpdump" rtmpdump-git "noDepth" "" "c28f1bab7822de97353849e7787b59e50bbb1428"
        #do_git "https://git.ffmpeg.org/rtmpdump" rtmpdump-git

        if [[ $compile == "true" ]]; then
            # Aplicar os cherry-picks necessários
            git cherry-pick -n eea470fa5f9a5481a36dedd257549595ef7480d6
            git cherry-pick -n 8e3064207fa7535baad07fd06b65630ec8b31a08
            git cherry-pick -n 7340f6dbc6b3c8e552baab2e5a891c2de75cddcc

            # Patch for OpenSSL 1.1 compatibility and Debian patch's for rtmpdump v2.4
            # Taken from https://github.com/JudgeZarbi/RTMPDump-OpenSSL-1.1
            # https://raw.githubusercontent.com/Homebrew/formula-patches/85fa66a9/rtmpdump/openssl-1.1.diff
            # Lista de patches a aplicar
            patches=(
                "rtmpdump_2.4_openssl-1.1.diff"
                "01_unbreak_makefile.diff"
                "02_gnutls_requires.private.diff"
            )

            # Aplicar cada patch se existir
            for patch in "${patches[@]}"; do
                if [ "$patch" = "rtmpdump_2.4_openssl-1.1.diff" ]; then
                    flag="-p0"
                else
                    flag="-p1"
                fi
                git apply $flag < "../../patches/$patch"
            done

            # Modificar o Makefile para usar GNUTLS em vez de OpenSSL
            # $sd -i 's/^CRYPTO=OPENSSL/#CRYPTO=OPENSSL/' Makefile librtmp/Makefile
            # $sd -i 's/#CRYPTO=GNUTLS/CRYPTO=GNUTLS/' Makefile librtmp/Makefile

            # Modificar para compilação estática apenas
            $sd -i 's/SHARED=yes/SHARED=no/' librtmp/Makefile
            
            # Compilar com as flags apropriadas
            make -j "$cpuCount" SYS=posix prefix="$LOCALDESTDIR" XCFLAGS="$CFLAGS" XLDFLAGS="$LDFLAGS" 
            make -j "$cpuCount" SYS=posix prefix="$LOCALDESTDIR" XCFLAGS="$CFLAGS" XLDFLAGS="$LDFLAGS" install

            do_checkIfExist rtmpdump-git librtmp.a
        else
            echo -------------------------------------------------
            echo "rtmpdump is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libSDL2.a" ]; then
        echo -------------------------------------------------
        echo "SDL2-2.32.6 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile SDL2\007"

        # Baixar SDL2
        do_curl "https://github.com/libsdl-org/SDL/releases/download/release-2.32.6/SDL2-2.32.6.tar.gz"
        
        # Ajustar CFLAGS para incluir opções necessárias
        ORIG_CFLAGS="$CFLAGS"
        CFLAGS+=" -ffat-lto-objects"
        
        # Criar e entrar no diretório de build
        mkdir -p build
        cd build || exit
        
        # Configurar para compilação estática usando CMake
        # Observe a inversão do SDL_STATIC para ON
        cmake -G Ninja \
            -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" \
            -DCMAKE_BUILD_TYPE=Release \
            -DSDL_STATIC=ON \
            -DSDL_SHARED=OFF \
            -DSDL_RPATH=OFF \
            -DSDL_HIDAPI=ON \
            -DSDL_PIPEWIRE=OFF \
            -DSDL_WAYLAND=OFF \
            ..
        
        # Compilar
        cmake --build .
        
        # Instalar
        cmake --install .
        
        # Restaurar CFLAGS original
        CFLAGS="$ORIG_CFLAGS"
        
        cd ..
        
        # Corrigir o arquivo de configuração do CMake, se necessário
        if [ -f "$LOCALDESTDIR/lib/cmake/SDL2/SDL2Targets-noconfig.cmake" ]; then
            $sd -i "s/libSDL2\.a/libSDL2main.a/g" "$LOCALDESTDIR/lib/cmake/SDL2/SDL2Targets-noconfig.cmake"
        fi
        
        # Copiar o arquivo de licença
        if [ ! -d "$LOCALDESTDIR/share/licenses/sdl2" ]; then
            mkdir -p "$LOCALDESTDIR/share/licenses/sdl2"
        fi
        cp LICENSE.txt "$LOCALDESTDIR/share/licenses/sdl2/LICENSE"
        
        do_checkIfExist SDL2-2.32.6 libSDL2.a
    fi

    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile global tools and libs done..."
    echo
    echo "-------------------------------------------------------------------------------"

    cd "$LOCALBUILDDIR" || exit
    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile audio libs"
    echo
    echo "-------------------------------------------------------------------------------"

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libmp3lame" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libmp3lame.a" ]; then
            echo -------------------------------------------------
            echo "lame-3.100 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile lame\007"

            do_curl "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz" lame-3.100.tar.gz

            ./configure --prefix="$LOCALDESTDIR" --enable-expopt=full --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist lame-3.100 libmp3lame.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libtwolame" ]]; then
        EXTRA_CFLAGS="$EXTRA_CFLAGS -DLIBTWOLAME_STATIC"
        if [ -f "$LOCALDESTDIR/lib/libtwolame.a" ]; then
            echo -------------------------------------------------
            echo "twolame-0.4.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile twolame 64Bit\007"

            do_curl "https://sourceforge.net/projects/twolame/files/twolame/0.4.0/twolame-0.4.0.tar.gz/download" twolame-0.4.0.tar.gz

            ./configure --prefix="$LOCALDESTDIR" --disable-shared CPPFLAGS="$CPPFLAGS -DLIBTWOLAME_STATIC"

            make -j "$cpuCount"
            make install

            do_checkIfExist twolame-0.4.0 libtwolame.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfdk-aac" ]]; then
        do_git "https://github.com/mstorsjo/fdk-aac" fdk-aac-git

        if [[ $compile == "true" ]]; then
            if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist fdk-aac-git libfdk-aac.a
        else
            echo -------------------------------------------------
            echo "fdk-aac is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsoxr" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libsoxr.a" ]; then
            echo -------------------------------------------------
            echo "soxr-0.1.3 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile soxr-0.1.1\007"

            do_curl "https://downloads.sourceforge.net/project/soxr/soxr-0.1.3-Source.tar.xz"

            mkdir build
            cd build || exit



            cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 -DBUILD_SHARED_LIBS:bool=off -DBUILD_TESTS:BOOL=OFF -DWITH_OPENMP:BOOL=OFF -DUNIX:BOOL=on -Wno-dev

            make -j "$cpuCount"
            make install

            do_checkIfExist soxr-0.1.3-Source libsoxr.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libopus" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libopus.a" ]; then
            echo -------------------------------------------------
            echo "opus-1.5.2 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile opus\007"

            do_curl "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.5.2.tar.gz"

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --enable-static --disable-doc

            make -j "$cpuCount"
            make install

            do_checkIfExist opus-1.5.2 libopus.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libogg.a" ]; then
        echo -------------------------------------------------
        echo "libogg-1.3.5 is already compiled"
        echo -------------------------------------------------
    else
        # Usar o Git para obter o código (como no PKGBUILD)
        do_git "https://github.com/xiph/ogg.git" ogg-git "noDepth" "" "v1.3.5"

        if [[ $compile == "true" ]]; then

            echo -ne "\033]0;compile libogg 64Bit\007"
            
            # Configurar com CMake para build estático
            mkdir -p build
            cd build || exit
            
            cmake -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" \
                -DBUILD_SHARED_LIBS=OFF \
                -DCMAKE_BUILD_TYPE=Release \
                ..

            make -j "$cpuCount"
            make install
            
            # Instalar arquivos adicionais
            if [ ! -d "$LOCALDESTDIR/share/aclocal" ]; then
                mkdir -p "$LOCALDESTDIR/share/aclocal"
            fi
            cp ../ogg.m4 "$LOCALDESTDIR/share/aclocal/" || true
            
            cd ..

            do_checkIfExist ogg-git libogg.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libvorbis" ]]; then
        # Usar o Git para obter o código (como no PKGBUILD)
        do_git "https://github.com/xiph/vorbis.git" vorbis-git "noDepth" "" "0c55fa38933fd4bdb7db7c298b27e7bf2f2c5e98"

        if [[ $compile == "true" ]]; then
            echo -ne "\033]0;compile libvorbis 64Bit\007"
            
            # Gerar arquivos de build
            ./autogen.sh
            
            # Configurar para build estático
            ./configure --prefix="$LOCALDESTDIR" \
                        --disable-shared \
                        --enable-static \
                        --with-ogg="$LOCALDESTDIR"
            
            make -j "$cpuCount"
            make install

            do_checkIfExist vorbis-git libvorbis.a
        else
            echo -------------------------------------------------
            echo "libvorbis-1.3.7 is already compiled"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libspeex" ]]; then
        # Usar o commit específico do Speex 1.2.1
        do_git "https://gitlab.xiph.org/xiph/speex.git" speex-git "noDepth" "" "5dceaaf3e23ee7fd17c80cb5f02a838fd6c18e01"

        if [[ $compile == "true" ]]; then
            echo -ne "\033]0;compile speex\007"
            
            # Limpar versão anterior, se existir
            if [ -f "$LOCALDESTDIR/lib/libspeex.a" ]; then
                make distclean || true
            fi
            
            # Executar autogen.sh para preparar os scripts de configuração
            ./autogen.sh
            
            # Configurar para compilação estática, invertendo as opções do PKGBUILD original
            ./configure --prefix="$LOCALDESTDIR" \
                    --enable-static \
                    --disable-shared \
                    --disable-binaries \
                    --disable-oggtest
            
            # Compilar
            make -j "$cpuCount"
            
            # Instalar
            make install
            
            # Verificar se foi compilado corretamente
            do_checkIfExist speex-git libspeex.a
            
            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "speex is already up to date"
            echo -------------------------------------------------
        fi
    fi

    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile audio libs done..."
    echo
    echo "-------------------------------------------------------------------------------"

    cd "$LOCALBUILDDIR" || exit
    sleep 3
    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile video libs"
    echo
    echo "-------------------------------------------------------------------------------"

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsvtav1" ]]; then
        do_git "https://gitlab.com/AOMediaCodec/SVT-AV1.git" libsvtav1-git "noDepth" "" "v1.7.0"

        if [[ $compile == "true" ]]; then
            cd Build

            rm -rf *

            cmake .. -G"Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_BINDIR="bin" -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_INSTALL_INCLUDEDIR="include"

            make -j "$cpuCount"
            make install

            do_checkIfExist libsvtav1-git libSvtAv1Enc.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libsvtav1-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libdav1d" ]]; then
        do_git "https://code.videolan.org/videolan/dav1d.git" libdav1d-git

        if [[ $compile == "true" ]]; then
            rm -rf build
            mkdir build
            cd build

            meson setup -Denable_tools=false -Denable_tests=false --default-library=static .. --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib"
            ninja
            ninja install

            do_checkIfExist libdav1d-git libdav1d.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libdav1d-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libaom" ]]; then
        do_git "https://aomedia.googlesource.com/aom" libaom-git

        if [[ $compile == "true" ]]; then
            if [ -d "aom_build" ]; then
                cd aom_build
                make uninstall

                rm -rf *
            else
                mkdir aom_build
                cd aom_build
            fi

            cmake -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DBUILD_SHARED_LIBS=0 -DENABLE_NASM=on -DAOM_EXTRA_C_FLAGS="-mtune=$mtune $osExtra" -DAOM_EXTRA_CXX_FLAGS="-mtune=$mtune $osExtra" ../

            make -j "$cpuCount"
            make install

            cp -R $LOCALDESTDIR/lib64/* $LOCALDESTDIR/lib/

            do_checkIfExist libaom-git libaom.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libvaom is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libvpx" ]]; then
        do_git "https://github.com/webmproject/libvpx.git" libvpx-git noDepth

        if [[ $compile == "true" ]]; then
            if [ -d "$LOCALDESTDIR/include/vpx" ]; then
                rm -rf "$LOCALDESTDIR/include/vpx"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/vpx.pc"
                rm -f "$LOCALDESTDIR/lib/libvpx.a"
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --disable-unit-tests --disable-docs $vpxFlags $osFlag

            make -j "$cpuCount"
            make install

            do_checkIfExist libvpx-git libvpx.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libvpx-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libbluray" ]]; then
        do_git "https://code.videolan.org/videolan/libbluray" libbluray-git

        if [[ $compile == "true" ]]; then

            if [[ ! -f "configure" ]]; then
                git submodule update --init
                autoreconf -fiv
            else
                make uninstall
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --disable-examples --disable-bdjava-jar --disable-doxygen-doc --disable-doxygen-dot --without-fontconfig --without-freetype LIBXML2_LIBS="-L$LOCALDESTDIR/lib -lxml2" LIBXML2_CFLAGS="-I$LOCALDESTDIR/include/libxml2 -DLIBXML_STATIC"

            make -j "$cpuCount"
            make install

            do_checkIfExist libbluray-git libbluray.a

            $sd -ri "s/(Libs\:.*)/\1 -lxml2 -lstdc++ -lz $osLib -llzma -lm -ldl/g" "$LOCALDESTDIR/lib/pkgconfig/libbluray.pc"
        else
            echo -------------------------------------------------
            echo "libbluray-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libass" ]]; then
        do_git "https://github.com/libass/libass.git" libass-git

        if [[ $compile == "true" ]]; then
            if [ -f "$LOCALDESTDIR/lib/libass.a" ]; then
                make uninstall
                make clean
            fi

            if [[ ! -f "configure" ]]; then
                ./autogen.sh
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --disable-harfbuzz FRIBIDI_LIBS="-L$LOCALDESTDIR/lib" FRIBIDI_CFLAGS="-I$LOCALDESTDIR/include/fribidi"

            make -j "$cpuCount"
            make install

            $sd -i 's/-lass -lm/-lass -lfribidi -lm/' "$LOCALDESTDIR/lib/pkgconfig/libass.pc"

            do_checkIfExist libass-git libass.a
            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libass is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-decklink" ]]; then
        if [ -f "$LOCALDESTDIR/include/DeckLinkAPI.h" ]; then
            echo -------------------------------------------------
            echo "DeckLinkAPI is already in place"
            echo -------------------------------------------------
        else
            cd "$LOCALDESTDIR/include" || exit

            cp ../../headers/decklink-${osString}/* .

            if [[ $osString == "osx" ]]; then
                $sd -i '' "s/void    InitDeckLinkAPI (void)/static void    InitDeckLinkAPI (void)/" DeckLinkAPIDispatch.cpp
                $sd -i '' "s/bool        IsDeckLinkAPIPresent (void)/static bool        IsDeckLinkAPIPresent (void)/" DeckLinkAPIDispatch.cpp
                $sd -i '' "s/void InitBMDStreamingAPI(void)/static void InitBMDStreamingAPI(void)/" DeckLinkAPIDispatch.cpp
            fi
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libndi_newtek" ]]; then
        if [ -f "$LOCALDESTDIR/include/Processing.NDI.Lib.h" ]; then
            echo -------------------------------------------------
            echo "NDI headers are already in place"
            echo -------------------------------------------------
        else

            cd "$LOCALDESTDIR/include" || exit

            cp ../../headers/ndi-${osString}/* .
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libklvanc" ]]; then
        do_git "https://github.com/stoth68000/libklvanc.git" libklvanc-git noDepth

        if [[ $compile == "true" ]]; then
            if [ -f "$LOCALDESTDIR/lib/libklvanc.a" ]; then
                make distclean
            fi

            ./autogen.sh --build

            ./configure --prefix=$LOCALDESTDIR --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist libklvanc-git libklvanc.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libklvanc-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libx264" ]]; then
        do_git "https://code.videolan.org/videolan/x264" x264-git noDepth

        if [[ $compile == "true" ]]; then
            echo -ne "\033]0;compile x264-git\007"

            if [ -f "$LOCALDESTDIR/lib/libx264.a" ]; then
                rm -f "$LOCALDESTDIR/include/x264.h $LOCALDESTDIR/include/x264_config.h $LOCALDESTDIR/lib/libx264.a"
                rm -f "$LOCALDESTDIR/bin/x264 $LOCALDESTDIR/lib/pkgconfig/x264.pc"
            fi

            if [ -f "libx264.a" ]; then
                make distclean
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-static --disable-shared $osFlag

            make -j "$cpuCount"
            make install

            do_checkIfExist x264-git libx264.a
            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "x264 is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libx265" ]]; then
        do_git "https://bitbucket.org/multicoreware/x265_git.git" x265-git noDepth

        if [[ $compile == "true" ]]; then
            cd build || exit
            rm -rf ./*
            rm -f "$LOCALDESTDIR/bin/x265"
            rm -f "$LOCALDESTDIR/include/x265.h"
            rm -f "$LOCALDESTDIR/include/x265_config.h"
            rm -f "$LOCALDESTDIR/lib/libx265.a"
            rm -f "$LOCALDESTDIR/lib/pkgconfig/x265.pc"

            cmake ../source -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DENABLE_SHARED:BOOLEAN=OFF -DSTATIC_LINK_CRT:BOOL=ON -DENABLE_CLI:BOOL=OFF -DCMAKE_CXX_FLAGS_RELEASE:STRING="-O3 -DNDEBUG $CXXFLAGS"

            make -j "$cpuCount"
            make install

            do_checkIfExist x265-git libx265.a

            if [[ "$system" == "Darwin" ]]; then
                extra="-lc++"
            else
                extra="-lstdc++ -lpthread -ldl"
            fi

            $sd -ri "s/(Libs\:.*)/\1 $extra/g" "$LOCALDESTDIR/lib/pkgconfig/x265.pc"

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "x265 is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libxvid" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libxvidcore.a" ]; then
            echo -------------------------------------------------
            echo "xvidcore-1.3.7 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile xvidcore 64Bit\007"
            do_curl "https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz" "xvidcore-1.3.7.tar.gz" "xvidcore-1.3.7"
        
            # xvidcore tem uma estrutura de diretório específica
            cd build/generic || exit

            # Aplicar todas as modificações em uma única passada
            $sd -i '
                # Remover SHARED_LIB da regra all
                s/all: info $(STATIC_LIB) $(SHARED_LIB)/all: info $(STATIC_LIB)/
                
                # Limpar a regra install
                /^install:/s/$(BUILD_DIR)\/$(SHARED_LIB)//
                s/^install: \$(BUILD_DIR)\/\$(STATIC_LIB).*$/install: $(BUILD_DIR)\/$(STATIC_LIB)/
                
                # Remover seção de instalação da biblioteca compartilhada
                /ifeq ($(SHARED_EXTENSION),dll)/,/^endif/d
                
                # Remover regra de build da biblioteca compartilhada
                /^$(SHARED_LIB):/,/^$/d
            ' Makefile
            
            # Configuração estática
            ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static

            make -j "$cpuCount"
            make install

            do_checkIfExist xvidcore-1.3.7 libxvidcore.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-librav1e" ]]; then
        do_git "https://github.com/xiph/rav1e.git" rav1e-git noDepth

        if [[ $compile == "true" ]]; then
            export RUSTFLAGS="-C target-cpu=native"
            target=""

            if [[ $system == "Linux" ]]; then
                target="--target=x86_64-unknown-linux-musl"
            fi

	        sed -i 's/^version = 4$/version = 3/' Cargo.lock
            
            cargo cinstall --release $target --jobs "$cpuCount" --prefix=$LOCALDESTDIR --libdir=$LOCALDESTDIR/lib --includedir=$LOCALDESTDIR/include --library-type=staticlib --crt-static

            do_checkIfExist rav1e-git librav1e.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "rav1e-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-nvenc" ]]; then
        #do_git "https://git.videolan.org/git/ffmpeg/nv-codec-headers" nv-codec-headers-git
        #nv-codec-headers n12.2.72.0 for ffmpeg > 5.1
        #do_git "https://git.videolan.org/git/ffmpeg/nv-codec-headers" nv-codec-headers-git "noDepth" "" "157becbf51c8b813425572b75c06c370bd43d8fd"
        #nv-codec-headers n11.1.5.3 for ffmpeg <= 5.1
        do_git "https://git.videolan.org/git/ffmpeg/nv-codec-headers" nv-codec-headers-git "noDepth" "" "2c961f06047c31da56d9e1557ea395f3fef20277"

        if [[ $compile == "true" ]]; then
            make -j "$cpuCount"
            make install  PREFIX="$LOCALDESTDIR"
        else
            echo -------------------------------------------------
            echo "nv-codec-headers-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-vulkan" ]] || [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libplacebo" ]]; then
        if [[ ! -f $LOCALDESTDIR/include/vulkan/vulkan.h ]]; then
            #do_curl https://sdk.lunarg.com/sdk/download/1.3.280.1/linux/vulkansdk-linux-x86_64-1.3.280.1.tar.xz vulkansdk-linux-x86_64-1.3.280.1.tar.xz "1.3.280.1"
            #rsync --remove-source-files -auv x86_64/include $LOCALDESTDIR/include/
            #rsync --remove-source-files -auv x86_64/lib $LOCALDESTDIR/lib/
            do_curl https://sdk.lunarg.com/sdk/download/1.4.313.0/linux/vulkansdk-linux-x86_64-1.4.313.0.tar.xz vulkansdk-linux-x86_64-1.4.313.0.tar.xz "1.4.313.0"
            rsync --remove-source-files -auv x86_64/ $LOCALDESTDIR/
            #cd 1.4.313.0
            #rsync -av x86_64/ $LOCALDESTDIR/
            #echo
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libplacebo" ]]; then

        #libplacebo v7.349.0 estável
        do_git "https://code.videolan.org/videolan/libplacebo" libplacebo-git "noDepth" "" "9c4b6bbd7a1e223ffdd61affc4e5d463d42d4345"
        #libplacebo v6.338.2 estável
        #do_git "https://code.videolan.org/videolan/libplacebo" libplacebo-git "noDepth" "" "25ff836306a30e303ea524d1e276a51f2866e7f0"
        #libplacebo v4.208.0 estável
        #do_git "https://code.videolan.org/videolan/libplacebo" libplacebo-git "noDepth" "" "v4.208.0"

        git submodule update --init --recursive --depth=1 --filter=blob:none

        if [[ $compile == "true" ]]; then
            # Aplicar patch para corrigir problemas de vinculação com glslang 15.0.0 para libplacebo v7.349.0
            # Se você tiver o patch, descomente a linha abaixo
            #Patch for v7.349.0
            git apply ../../patches/fix_glslang_linking.patch
            #Patch for v6.338.2
            #git apply ../../patches/0001-meson-don-t-hard-require-glslang-internal-dependenci.patch
            #Patch for v7.349.0
            #git apply ../../patches/0001-meson-add-glslang-lib-for-15.0.0-linking.patch
            #Patch for v4.208.0
            #git apply ../../patches/0001-glsl-glslang-move-resources-declaration-to-C-file.patch
            #Patch for v4.208.0
            #git apply ../../patches/glslang_deps_for_libplacebo_v4.208.0.patch
            
            # Corrigir o define de exportação para compilação estática
            sed -i 's/DPL_EXPORT/DPL_STATIC/' src/meson.build
            
            rm -rf build
            mkdir build
            cd build

            # Adicionar flags de cabeçalho do glslang como no PKGBUILD
            export CXXFLAGS="$CXXFLAGS -I/usr/include/glslang"

            # Configuração baseada no PKGBUILD do Arch Linux
            meson setup --prefix="$LOCALDESTDIR" \
                --buildtype=release \
                --default-library=static \
                -Dvulkan=enabled \
                -Dglslang=enabled \
                -Dshaderc=enabled \
                -Dlcms=enabled \
                -Dd3d11=disabled \
                -Dlibdovi=disabled \
                -Ddemos=false \
                -Dtests=false \
                -Dbench=false \
                -Dfuzz=false \
                -Dvulkan-registry="$LOCALDESTDIR/share/vulkan/registry/vk.xml" \
                --libdir="$LOCALDESTDIR/lib" \
                ..

            ninja -j$(nproc)
            ninja install

            # SOLUÇÃO CRÍTICA: Adicionar a biblioteca C++ às dependências privadas no pkg-config
            echo "Libs.private: -lstdc++" >> "$LOCALDESTDIR/lib/pkgconfig/libplacebo.pc"

            do_checkIfExist libplacebo-git libplacebo.a
        else
            echo -------------------------------------------------
            echo "nv-codec-headers-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-vapoursynth" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libvapoursynth.a" ]; then
            echo -------------------------------------------------
            echo "vapoursynth is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile vapoursynth\007"

            do_git "https://github.com/vapoursynth/vapoursynth.git" libvapoursynth-git

            if [[ ! -f "configure" ]]; then
                ./autogen.sh
            fi
            
            env CFLAGS="-fPIC $CFLAGS" CXXFLAGS="-fPIC $CXXFLAGS" ./configure --prefix="$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" --enable-static --disable-shared

            make -j "$cpuCount"
            make install

            do_checkIfExist libvapoursynth-git libvapoursynth.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-avisynth" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libavisynth.a" ]; then
            echo -------------------------------------------------
            echo "AviSynthPlus is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile AviSynthPlus\007"

            do_curl "https://github.com/AviSynth/AviSynthPlus/archive/v3.7.3/avisynthplus-3.7.3.tar.gz" AviSynthPlus-3.7.3.tar.gz

            # Criar diretório de build se não existir
            if [[ ! -d "build" ]]; then
                mkdir build
            fi

            # Configurar o cmake com as opções fornecidas
            cmake -B build -S "." \
                -G 'Unix Makefiles' \
                -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" \
                -DCMAKE_INSTALL_LIBDIR="$LOCALDESTDIR/lib" \
                -DBUILD_SHARED_LIBS=OFF \
                -DCMAKE_BUILD_TYPE:STRING='None' \
                -Wno-dev

            # Compilar e instalar o AviSynthPlus
            cmake --build build --parallel "$cpuCount"
            cmake --install build --prefix "$LOCALDESTDIR"

            # Verificar se o binário foi gerado
            do_checkIfExist AviSynthPlus-3.7.3 libavisynth.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libtheora" ]]; then
        # Usar a tag 1.2.0 do repositório git
        do_git "https://github.com/xiph/theora.git" libtheora-git "noDepth" "" "v1.2.0"

        if [[ $compile == "true" ]]; then
            echo -ne "\033]0;compile libtheora\007"
            
            # Limpar compilação anterior, se existir
            if [ -f "$LOCALDESTDIR/lib/libtheora.a" ]; then
                make distclean || true
            fi
            
            # Executar autoreconf para preparar os scripts de configuração
            autoreconf -fi
            
            # Configurar para compilação estática
            ./configure --prefix="$LOCALDESTDIR" \
                    --disable-shared \
                    --enable-static \
                    --disable-examples \
                    --disable-oggtest \
                    --disable-vorbistest \
                    --disable-sdltest
            
            # Compilar
            make -j "$cpuCount"
            
            # Instalar
            make install
            
            # Verificar se foi compilado corretamente
            do_checkIfExist libtheora-git libtheora.a
            
            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libtheora is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-frei0r" ]]; then
        # Usar a tag v2.3.3 do repositório git
        do_git "https://github.com/dyne/frei0r.git" frei0r-git "noDepth" "" "v2.3.3"

        if [[ $compile == "true" ]]; then
            echo -ne "\033]0;compile frei0r plugins\007"
            
            # Criar e limpar diretório de build
            rm -rf build
            mkdir -p build
            cd build || exit
            
            # Configurar para compilação estática usando CMake
            cmake .. \
                -G Ninja \
                -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" \
                -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_SHARED_LIBS=OFF \
                -DCMAKE_POSITION_INDEPENDENT_CODE=OFF \
                -DCMAKE_FIND_LIBRARY_SUFFIXES=".a" \
                -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS} -static" \
                -DCMAKE_SHARED_LINKER_FLAGS="" \
                -DCMAKE_MODULE_LINKER_FLAGS="" \
                -DCMAKE_C_FLAGS="${CFLAGS} -ffunction-sections -fdata-sections" \
                -DCMAKE_CXX_FLAGS="${CXXFLAGS} -ffunction-sections -fdata-sections"
            
            # Compilar
            cmake --build .
            
            # Instalar
            cmake --install .
            
            cd ..
            
            # Verificar se foi compilado corretamente (vamos verificar um dos plugins principais)
            if [ -d "$LOCALDESTDIR/lib/frei0r-1" ]; then
                echo -
                echo -------------------------------------------------
                echo "build frei0r-plugins done..."
                echo -------------------------------------------------
                echo -
            else
                echo -------------------------------------------------
                echo "Build frei0r-plugins failed..."
                echo "Delete the source folder under '$LOCALBUILDDIR' and start again,"
                echo "or if you know there is no dependences hit enter for continue it."
                read -r -p ""
                sleep 5
            fi
        else
            echo -------------------------------------------------
            echo "frei0r-plugins is already up to date"
            echo -------------------------------------------------
        fi
    fi
}

remove_conflicting_libs() {
    BASE_DIR=$LOCALDESTDIR

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
        "$BASE_DIR/lib/libglslang.so.15.3.0"
        "$BASE_DIR/lib/libglslang-default-resource-limits.so.15"
        "$BASE_DIR/lib/libglslang.so.15"
        "$BASE_DIR/lib/libglslang-default-resource-limits.so.15.3.0"
        "$BASE_DIR/lib/cmake/glslang"
        "$BASE_DIR/lib/cmake/glslang/glslang-config-version.cmake"
        "$BASE_DIR/lib/cmake/glslang/glslang-config.cmake"
        "$BASE_DIR/lib/cmake/glslang/glslang-targets-release.cmake"
        "$BASE_DIR/lib/cmake/glslang/glslang-targets.cmake"
        "$BASE_DIR/lib/libglslang-default-resource-limits.a"
        "$BASE_DIR/lib/libglslang-default-resource-limits.so"
        "$BASE_DIR/lib/libslang-glslang.so"
        "$BASE_DIR/lib/libglslang.a"
        "$BASE_DIR/lib/libglslang.so"
        "$BASE_DIR/bin/glslangValidator"
        "$BASE_DIR/bin/glslang"
        "$BASE_DIR/include/glslang"
        "$BASE_DIR/include/glslang/Include/glslang_c_shader_types.h"
        "$BASE_DIR/include/glslang/Include/glslang_c_interface.h"
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

}

buildFfmpeg() {
    cd "$LOCALBUILDDIR" || exit
    echo "-------------------------------------------------------------------------------"
    echo "compile ffmpeg"
    echo "-------------------------------------------------------------------------------"

    #ffmpeg 7.1.1
    #do_git "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg-7.1" "noDepth" "" "a1328e68877e12ab5a6e5d92a84aefa566783ea5"
    #ffmpeg 5.1.6
    #do_git "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg-5.1" "noDepth" "" "38c3847bed52de65dcd27bd7eeed86d1bc7eb440"
    #ffmpeg 5.1.4 best stable
    #do_git "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg-5.1" "noDepth" "" "80e7806be7f10c038bef2e71905e91af174c28e9"
    #ffmpeg 5.1.6 best stable
    #do_git "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg-5.1" "noDepth" "" "38c3847bed52de65dcd27bd7eeed86d1bc7eb440"
    #ffmpeg 5.1 development release stable
    do_git "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg-5.1" "noDepth" "" "release/5.1"

    #ffmpeg 6.1.1 for ffprobe
    #do_git "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg-6.1" "noDepth" "" "6f4048827982a8f48f71f551a6e1ed2362816eec"
 

    if [[ $compile == "true" ]] || [[ $buildFFmpeg == "true" ]] || [[ ! -f "$LOCALDESTDIR/bin/ffmpeg" ]] && [[ ! -f "$LOCALDESTDIR/bin/ffmpeg_shared/bin/ffmpeg" ]]; then
        if [[ "$ffmpeg_shared" == "yes" ]]; then
            rm -rf "$LOCALDESTDIR/bin/ffmpeg_shared"
            static_share="--enable-shared"
            pkg_extra=""
            prefix_extra="$LOCALDESTDIR/bin/ffmpeg_shared"
            mkdir "$prefix_extra"
        else
            static_share="--disable-shared"
            pkg_extra="--pkg-config-flags=--static"
            prefix_extra="$LOCALDESTDIR"

            if [ -f "$LOCALDESTDIR/lib/libavcodec.a" ]; then
                rm -rf "$LOCALDESTDIR/include/libavutil"
                rm -rf "$LOCALDESTDIR/include/libavcodec"
                rm -rf "$LOCALDESTDIR/include/libpostproc"
                rm -rf "$LOCALDESTDIR/include/libswresample"
                rm -rf "$LOCALDESTDIR/include/libswscale"
                rm -rf "$LOCALDESTDIR/include/libavdevice"
                rm -rf "$LOCALDESTDIR/include/libavfilter"
                rm -rf "$LOCALDESTDIR/include/libavformat"
                rm -f "$LOCALDESTDIR/lib/libavutil.a"
                rm -f "$LOCALDESTDIR/lib/libswresample.a"
                rm -f "$LOCALDESTDIR/lib/libswscale.a"
                rm -f "$LOCALDESTDIR/lib/libavcodec.a"
                rm -f "$LOCALDESTDIR/lib/libavdevice.a"
                rm -f "$LOCALDESTDIR/lib/libavfilter.a"
                rm -f "$LOCALDESTDIR/lib/libavformat.a"
                rm -f "$LOCALDESTDIR/lib/libpostproc.a"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavcodec.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavutil.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libpostproc.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libswresample.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libswscale.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavdevice.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavfilter.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavformat.pc"
            fi
        fi

        remove_conflicting_libs

        if [ -f "ffbuild/config.mak" ]; then
            # make uninstall
            make distclean
        fi

        #git cherry-pick -n bcfbf2bac8f9eeeedc407b40596f5c7aaa0d5b47
        #git cherry-pick -n d0facac679faf45d3356dff2e2cb382580d7a521
        #git apply ../../patches/fix_build_with_texinfo-7.2.patch
        git apply ../../patches/vf_libplacebo_ffmpeg_5.1.6.patch
        git apply ../../patches/0001_configure_support_static_libnpp_for_ffmpeg_5.1.6_cuda_toolkit_12.9.patch
        
        if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libndi_newtek" ]]; then
            git apply ../../patches/revert-libndi_newtek.patch
            cp ../../patches/libndi/libavdevice/libndi_newtek_* libavdevice/
        fi

        EXTRA_CFLAGS=$(echo $EXTRA_CFLAGS | sed "s/-march=generic //")
        if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libplacebo" ]]; then
            EXTRA_LD="-Wl,--copy-dt-needed-entries"
        fi

        if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-nvenc" ]]; then
            export PATH="/usr/local/cuda/bin:$PATH"
            export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"
            EXTRA_CFLAGS="$EXTRA_CFLAGS -I/usr/local/cuda/include"
            EXTRA_LD="$EXTRA_LD -L/usr/local/cuda/lib64"
        fi

        STATIC_FLAGS="-static-libgcc -static-libstdc++"

        ./configure $arch --prefix="$prefix_extra" --disable-debug "$static_share" $disable_ffplay \
        --disable-doc --enable-gpl --enable-version3 \
        $cpuDetect --enable-avfilter --enable-zlib "${FFMPEG_LIBS[@]}" \
        $osFlag --extra-libs="-lm -liconv $extraLibs" --extra-cflags="$EXTRA_CFLAGS" $pkg_extra --extra-ldflags="$STATIC_FLAGS $EXTRA_LD"

        #$sd -ri "s/--prefix=[^ ]* //g" config.h
        #$sd -ri "s/ --extra-libs='.*'//g" config.h
        #$sd -ri "s/ --pkg-config-flags=--static//g" config.h
        #$sd -ri "s/ --extra-cflags=[a-zA-Z_'-]*//g" config.h
        #$sd -ri "s/ --extra-ldflags=[a-zA-Z_'-,]*//g" config.h

        make -j "$cpuCount"
        make install

        if [[ -z "$ffmpeg_shared" ]]; then
            do_checkIfExist ffmpeg-git libavcodec.a
        else
            do_checkIfExist ffmpeg-git "bin/ffmpeg_shared/bin/ffmpeg"
        fi

        if [[ -n "$libzmq" ]]; then
            cd tools
            gcc -o $LOCALDESTDIR/bin/zmqsend zmqsend.c -I.. `pkg-config --libs --cflags libzmq libavutil` -DZMG_STATIC -lstdc++
        fi

        # when you copy the shared libs to /usr/local/lib
        # run "sudo ldconfig"

    else
        echo -------------------------------------------------
        echo "ffmpeg is already up to date"
        echo -------------------------------------------------
    fi
}

buildExtras() {
    #------------------------------------------------
    # build extra tools
    #------------------------------------------------

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/gpac/gpac.git" gpac-git noDepth
    if [[ $compile = "true"  ]] || [[ ! -f "$LOCALDESTDIR/bin/MP4Box" ]]; then
        if [ -d "$LOCALDESTDIR/include/gpac" ]; then
            rm -rf "$LOCALDESTDIR/bin/MP4Box $LOCALDESTDIR/lib/libgpac*"
            rm -rf "$LOCALDESTDIR/include/gpac"
        fi
        [[ -f config.mak ]] && make distclean
        ./configure --prefix="$LOCALDESTDIR" --static-bin --static-build --static-modules
        make -j "$cpuCount"
        make install
        do_checkIfExist gpac-git bin/MP4Box
    fi

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/MediaArea/ZenLib" libzen-git
    if [[ $compile = "true" ]] || [[ ! -f "$LOCALDESTDIR/bin/mediainfo" ]]; then
        cd Project/GNU/Library || exit
        [[ ! -f "configure" ]] && ./autogen.sh
        [[ -f libzen.pc ]] && make distclean

        if [[ -d "$LOCALDESTDIR/include/ZenLib" ]]; then
            rm -rf "$LOCALDESTDIR/include/ZenLib $LOCALDESTDIR/bin-global/libzen-config"
            rm -f "$LOCALDESTDIR/lib/libzen.{l,}a $LOCALDESTDIR/lib/pkgconfig/libzen.pc"
        fi
        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        [[ -f "$LOCALDESTDIR/bin/libzen-config" ]] && rm "$LOCALDESTDIR/bin/libzen-config"
        do_checkIfExist libzen-git libzen.a
        buildMediaInfo="true"
    fi

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/MediaArea/MediaInfoLib" libmediainfo-git
    if [[ $compile = "true" || $buildMediaInfo = "true" ]]; then
        cd Project/GNU/Library || exit
        [[ ! -f "configure" ]] && ./autogen.sh
        [[ -f libmediainfo.pc ]] && make distclean

        if [[ -d "$LOCALDESTDIR/include/MediaInfo" ]]; then
            rm -rf "$LOCALDESTDIR/include/MediaInfo{,DLL}"
            rm -f "$LOCALDESTDIR/lib/libmediainfo.{l,}a $LOCALDESTDIR/lib/pkgconfig/libmediainfo.pc"
            rm -f "$LOCALDESTDIR/bin-global/libmediainfo-config"
        fi
        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        cp libmediainfo.pc "$LOCALDESTDIR/lib/pkgconfig/"
        do_checkIfExist libmediainfo-git libmediainfo.a
        buildMediaInfo="true"
    fi

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/MediaArea/MediaInfo" mediainfo-git
    if [[ $compile = "true" || $buildMediaInfo = "true" ]]; then
        cd Project/GNU/CLI || exit
        [[ ! -f "configure" ]] && ./autogen.sh
        [[ -f config.log ]] && make distclean

        [[ -d "$LOCALDESTDIR/bin/mediainfo" ]] && rm -rf "$LOCALDESTDIR/bin/mediainfo"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-staticlibs

        make -j "$cpuCount"
        make install

        do_checkIfExist mediainfo-git bin/mediainfo
    fi
}

stripAll() {
    echo -ne "\033]0;strip binaries\007"
    echo
    echo "-------------------------------------------------------------------------------"
    echo
    FILES=$(find "$LOCALDESTDIR/bin" -type f -mmin -600 ! \( -name '*-config' -o -name '.DS_Store' -o -name '*.conf' -o -name '*.png' -o -name '*.desktop' -o -path 'bin/ffmpeg_shared/*' -prune \))

    for f in $FILES; do
        strip "$f"
        echo "strip $f done..."
    done

    echo -ne "\033]0;deleting source folders\007"
    echo
    echo "deleting source folders..."
    echo
    #find "$LOCALBUILDDIR" -mindepth 1 -maxdepth 1 -type d ! \( -name '*-git' -o -name '*-svn' -o -name '*-hg' \) -print0 | xargs -0 rm -rf
}

if [[ "$compile_libs_only" == "y" ]]; then
    buildLibs
fi

if [[ "$compile_ffmpeg_only" == "y" ]]; then
    buildFfmpeg
fi

if [[ -z "$compile_libs_only" ]] && [[ -z "$compile_ffmpeg_only" ]] && [[ -z "$compile_extras" ]]; then
    buildLibs
    buildFfmpeg
fi

if [[ "$compile_extras" == "y" ]]; then
    buildExtras
fi

stripAll

echo -ne "\033]0;compiling done...\007"
exit 0
