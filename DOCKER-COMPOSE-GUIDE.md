# 🎬 FFmpeg Docker Compose Build System

Sistema completo para compilar FFmpeg em diferentes versões do Ubuntu usando Docker Compose com múltiplos modos de operação.

## 📋 Índice

- [Visão Geral](#-visão-geral)
- [Configuração Automática](#-configuração-automática)
- [Comandos Básicos](#-comandos-básicos)
- [Serviços Disponíveis](#-serviços-disponíveis)
- [Variáveis de Ambiente](#-variáveis-de-ambiente)
- [Opções de Build FFmpeg](#-opções-de-build-ffmpeg)
- [Saída Visível dos Comandos](#-saída-visível-dos-comandos)
- [Exemplos Práticos](#-exemplos-práticos)
- [Casos de Uso](#-casos-de-uso)
- [Build Args Direto](#-build-args-direto)

## 🚀 Visão Geral

Este sistema oferece diferentes modos de compilação do FFmpeg com **detecção automática do usuário**:

- **📦 Compilação normal**: Build e saída automática
- **🔧 Modo manutenção**: Acesso ao container sem build automático
- **🐚 Shell direto**: Terminal direto no container
- **🔄 Modo interativo**: Build + shell após conclusão
- **📱 Múltiplas versões Ubuntu**: 24.04, 22.04, 20.04, 18.04
- **👤 Detecção automática**: USER_ID, GROUP_ID e USERNAME do host

## ⚙️ Configuração Automática

### **Detecção Automática do Usuário**
O arquivo `.env` detecta automaticamente suas configurações:

```bash
# Detectado automaticamente:
USER_ID=$(id -u)        # Seu USER_ID atual
GROUP_ID=$(id -g)       # Seu GROUP_ID atual  
USERNAME=$(whoami)      # Seu nome de usuário
```

### **Valores Padrão (Fallback)**
Se a detecção falhar, usa valores seguros:

```bash
USER_ID=1001           # Padrão seguro
GROUP_ID=1001          # Padrão seguro
USERNAME=builduser     # Usuário padrão no container
```

## 🛠️ Comandos Básicos

### **Build com Saída Visível (Recomendado)**

```bash
# Build padrão com saída completa dos comandos RUN
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-compiler

# Modo manutenção com debug completo
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-maintenance

# Shell direto com informações de build
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-shell
```

### **Comandos Tradicionais**

```bash
# Serviço padrão (Ubuntu 24.04)
docker compose up --build ffmpeg-compiler

# Modo manutenção (debugging/verificações)
docker compose up --build ffmpeg-maintenance

# Shell direto (acesso rápido)
docker compose up --build ffmpeg-shell

# Modo interativo (build + shell)
docker compose up --build ffmpeg-interactive
```

### **Versões LTS Específicas**

```bash
# Ubuntu 22.04
docker compose up --build ffmpeg-22-04
docker compose up --build ffmpeg-22-04-maint

# Ubuntu 20.04
docker compose up --build ffmpeg-20-04
docker compose up --build ffmpeg-20-04-maint

# Ubuntu 18.04
docker compose up --build ffmpeg-18-04
docker compose up --build ffmpeg-18-04-maint
```

## 🎯 Serviços Disponíveis

| Serviço | Descrição | Modo | Shell Ativo | USER_ID Padrão |
|---------|-----------|------|-------------|----------------|
| `ffmpeg-compiler` | Build padrão | Normal | ❌ | Detectado automaticamente |
| `ffmpeg-maintenance` | Debug/manutenção | Manutenção | ✅ | Detectado automaticamente |
| `ffmpeg-shell` | Shell direto | Shell | ✅ | Detectado automaticamente |
| `ffmpeg-interactive` | Build + shell | Interativo | ✅ (pós-build) | Detectado automaticamente |
| `ffmpeg-22-04` | Ubuntu 22.04 LTS | Normal | ❌ | Detectado automaticamente |
| `ffmpeg-22-04-maint` | Ubuntu 22.04 manutenção | Manutenção | ✅ | Detectado automaticamente |
| `ffmpeg-20-04` | Ubuntu 20.04 LTS | Normal | ❌ | Detectado automaticamente |
| `ffmpeg-20-04-maint` | Ubuntu 20.04 manutenção | Manutenção | ✅ | Detectado automaticamente |
| `ffmpeg-18-04` | Ubuntu 18.04 LTS | Normal | ❌ | Detectado automaticamente |
| `ffmpeg-18-04-maint` | Ubuntu 18.04 manutenção | Manutenção | ✅ | Detectado automaticamente |

## ⚙️ Variáveis de Ambiente

### **Variáveis Principais (Atualizado)**

| Variável | Valores Padrão | Opções | Descrição |
|----------|----------------|---------|-----------|
| `UBUNTU_VERSION` | `24.04` | `24.04`, `22.04`, `20.04`, `18.04` | Versão do Ubuntu base |
| `BUILD_MODE` | `compile` | `compile`, `runtime` | Modo de operação |
| `MAINTENANCE_MODE` | `false` | `true`, `false` | Ativa modo manutenção |
| `KEEP_ALIVE` | `true` | `true`, `false` | Mantém container ativo |
| `AUTO_CLEAN` | `false` | `true`, `false` | Limpeza automática pós-build |
| `USER_ID` | **Detectado automaticamente** | `número` | ID do usuário (fallback: 1001) |
| `GROUP_ID` | **Detectado automaticamente** | `número` | ID do grupo (fallback: 1001) |
| `USERNAME` | **Detectado automaticamente** | `string` | Nome do usuário (fallback: builduser) |

### **Uso das Variáveis**

```bash
# Usar detecção automática (recomendado)
docker compose up --build ffmpeg-compiler

# Sobrescrever versão Ubuntu mantendo usuário detectado
UBUNTU_VERSION=22.04 docker compose up --build ffmpeg-compiler

# Sobrescrever usuário manualmente se necessário
USER_ID=1000 GROUP_ID=1000 USERNAME=developer docker compose up --build ffmpeg-compiler

# Múltiplas variáveis com usuário personalizado
UBUNTU_VERSION=20.04 BUILD_MODE=compile USER_ID=1000 docker compose up --build ffmpeg-compiler
```

## 🔨 Opções de Build FFmpeg

### **Tipos de Compilação Disponíveis**

| Opção | Descrição | Tempo Estimado | Uso |
|-------|-----------|----------------|-----|
| `--optimize=y` | **Padrão** - Versão otimizada | 45-90 min | Produção |
| `--libs-only=y` | Apenas bibliotecas | 30-60 min | Desenvolvimento |
| `--ffmpeg-only=y` | Apenas FFmpeg | 10-20 min | Teste rápido |
| `--extras=y` | + MediaInfo/MP4Box | +15-30 min | Ferramentas completas |

### **Configuração das Opções**

```bash
# Variável de ambiente
FFMPEG_BUILD_OPTS="--libs-only=y" docker compose up --build ffmpeg-compiler

# Exemplos de combinações
FFMPEG_BUILD_OPTS="--extras=y --optimize=y" docker compose up --build ffmpeg-compiler
FFMPEG_BUILD_OPTS="--ffmpeg-only=y" docker compose up --build ffmpeg-interactive
```

## 📺 Saída Visível dos Comandos

### **Problema Resolvido: RUN Commands Output**

**❌ Antes:**
```bash
docker compose up --build ffmpeg-compiler
# Não mostrava saída dos comandos RUN echo
```

**✅ Agora:**
```bash
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-compiler
# Mostra TODA a saída incluindo "=== BUILD INFORMATION ==="
```

### **Métodos para Ver Saída Completa**

```bash
# Método 1: Variável de ambiente (recomendado)
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-compiler

# Método 2: Build direto com Docker
docker build --progress=plain \
  --build-arg UBUNTU_VERSION=22.04 \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  --build-arg USERNAME=$(whoami) \
  -t ffmpeg-build .

# Método 3: Configuração permanente
export BUILDKIT_PROGRESS=plain
docker compose up --build ffmpeg-compiler
```

### **Informações Exibidas no Build**

Durante o build, você verá:
```
=== BUILD INFORMATION ===
Building on Ubuntu: Ubuntu 24.04.1 LTS
Ubuntu Version ID: 24.04
Build Arguments:
  BUILD_MODE=compile
  USER_ID=1001
  GROUP_ID=1001
  USERNAME=builduser
  UBUNTU_VERSION=24.04
==========================
```

## 💡 Exemplos Práticos

### **Desenvolvimento**

```bash
# Modo manutenção para debug com saída completa
BUILDKIT_PROGRESS=plain UBUNTU_VERSION=22.04 docker compose up --build ffmpeg-maintenance

# Build apenas libs para desenvolvimento
BUILDKIT_PROGRESS=plain FFMPEG_BUILD_OPTS="--libs-only=y" docker compose up --build ffmpeg-interactive

# Shell rápido para verificações (detecta seu usuário)
docker compose up --build ffmpeg-shell

# Usuário personalizado se necessário
USER_ID=1000 GROUP_ID=1000 USERNAME=developer docker compose up --build ffmpeg-shell
```

### **Produção**

```bash
# Build completo otimizado com saída visível
BUILDKIT_PROGRESS=plain UBUNTU_VERSION=24.04 FFMPEG_BUILD_OPTS="--extras=y --optimize=y" docker compose up --build ffmpeg-compiler

# Com limpeza automática e usuário específico
AUTO_CLEAN=true USER_ID=1001 docker compose up --build ffmpeg-compiler

# Background deployment
docker compose up --build -d ffmpeg-compiler
```

### **Teste e CI/CD**

```bash
# Teste rápido só FFmpeg com debug
BUILDKIT_PROGRESS=plain FFMPEG_BUILD_OPTS="--ffmpeg-only=y" docker compose up --build ffmpeg-interactive

# CI/CD com usuário específico
USER_ID=1001 GROUP_ID=1001 USERNAME=ci UBUNTU_VERSION=22.04 docker compose up --build ffmpeg-compiler

# Diferentes versões em paralelo
UBUNTU_VERSION=22.04 docker compose up --build -d ffmpeg-22-04 &
UBUNTU_VERSION=20.04 docker compose up --build -d ffmpeg-20-04 &
```

## 🎯 Casos de Uso

### **🔍 Debug de Build Falha**

```bash
# 1. Build normal falha - ver saída completa
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-compiler

# 2. Entrar em modo manutenção para investigar
BUILDKIT_PROGRESS=plain UBUNTU_VERSION=22.04 docker compose up --build ffmpeg-maintenance

# 3. Verificar usuário e permissões
echo "Seu USER_ID: $(id -u), GROUP_ID: $(id -g), USERNAME: $(whoami)"
```

### **🚀 Build para Diferentes Ambientes**

```bash
# Desenvolvimento local (detecta usuário automaticamente)
BUILDKIT_PROGRESS=plain FFMPEG_BUILD_OPTS="--libs-only=y" docker compose up --build ffmpeg-interactive

# Teste de integração com usuário específico
USER_ID=1000 GROUP_ID=1000 FFMPEG_BUILD_OPTS="--ffmpeg-only=y" docker compose up --build ffmpeg-compiler

# Produção completa
FFMPEG_BUILD_OPTS="--extras=y --optimize=y" docker compose up --build ffmpeg-compiler
```

### **🔧 Verificação de Configurações**

```bash
# Verificar detecção automática
echo "USER_ID: $(id -u)"
echo "GROUP_ID: $(id -g)" 
echo "USERNAME: $(whoami)"

# Ver configurações no .env
cat .env | grep -E "(USER_ID|GROUP_ID|USERNAME)"

# Testar com informações de debug
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-shell
```

## ⚡ Opções Avançadas

### **Compose com Detecção Automática**

```bash
# Setup automático completo (recomendado)
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-interactive

# Setup manual se necessário
BUILDKIT_PROGRESS=plain \
USER_ID=1000 \
GROUP_ID=1000 \
USERNAME=developer \
UBUNTU_VERSION=22.04 \
FFMPEG_BUILD_OPTS="--libs-only=y" \
docker compose up --build ffmpeg-interactive

# Produção otimizada com detecção automática
BUILDKIT_PROGRESS=plain \
UBUNTU_VERSION=24.04 \
FFMPEG_BUILD_OPTS="--extras=y --optimize=y" \
AUTO_CLEAN=true \
docker compose up --build ffmpeg-compiler
```

## 🏗️ Build Args Direto

### **Docker Build com Detecção Automática**

```bash
# Build básico com seu usuário detectado
docker build --progress=plain \
  --build-arg UBUNTU_VERSION=22.04 \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  --build-arg USERNAME=$(whoami) \
  -t ffmpeg-22.04 .

# Build com usuário personalizado
docker build --progress=plain \
  --build-arg UBUNTU_VERSION=20.04 \
  --build-arg BUILD_MODE=compile \
  --build-arg USER_ID=1001 \
  --build-arg GROUP_ID=1001 \
  --build-arg USERNAME=builduser \
  -t ffmpeg-custom .

# Build sem cache com debug completo
docker build --no-cache --progress=plain \
  --build-arg UBUNTU_VERSION=18.04 \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  --build-arg USERNAME=$(whoami) \
  -t ffmpeg-18.04 .
```

## 📁 Estrutura de Arquivos

```
.
├── Dockerfile              # ✅ Atualizado: USER_ID=1001, GROUP_ID=1001, USERNAME=builduser
├── docker-compose.yml      # ✅ Atualizado: USER_ID/GROUP_ID (não UID/GID), USERNAME adicionado
├── .env                    # ✅ Atualizado: Detecção automática com $(id -u), $(id -g), $(whoami)
├── build/                  # Arquivos temporários (gerado)
├── local/                  # Binários finais (gerado)
└── README.md              # Esta documentação atualizada
```

## 🔧 Troubleshooting

### **Build Falha**

```bash
# Verificar com saída completa
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-compiler

# Ver logs detalhados
docker compose logs ffmpeg-compiler

# Entrar em modo debug
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-maintenance
```

### **Problemas de Permissão**

```bash
# Verificar detecção automática
echo "Detectado: USER_ID=$(id -u), GROUP_ID=$(id -g), USERNAME=$(whoami)"

# Forçar IDs específicos se necessário
USER_ID=1000 GROUP_ID=1000 docker compose up --build ffmpeg-compiler

# Verificar ownership dos volumes
sudo chown -R $USER:$USER build/ local/
```

### **Saída dos Comandos Não Aparece**

```bash
# ✅ SOLUÇÃO: Use BUILDKIT_PROGRESS=plain
BUILDKIT_PROGRESS=plain docker compose up --build ffmpeg-compiler

# Ou configure permanentemente
export BUILDKIT_PROGRESS=plain
docker compose up --build ffmpeg-compiler

# Para docker build direto
docker build --progress=plain -t ffmpeg-build .
```

### **Container não Para**

```bash
# Forçar parada
docker compose down

# Remover containers órfãos
docker compose down --remove-orphans

# Limpeza completa
docker compose down -v --remove-orphans
```

## 📝 Notas Importantes

- **✅ Detecção Automática**: USER_ID, GROUP_ID e USERNAME são detectados automaticamente
- **✅ Valores Seguros**: Fallback para 1001:1001:builduser se detecção falhar
- **✅ Saída Visível**: Use `BUILDKIT_PROGRESS=plain` para ver comandos RUN
- **✅ Volumes Persistentes**: `build/` e `local/` são mantidos entre execuções
- **CUDA**: Volume `/usr/local/cuda` é montado automaticamente se disponível
- **Scripts**: Diretório raiz é montado como read-only para segurança
- **Timezone**: Configurado para `America/Maceio` por padrão

## 🤝 Contribuindo

1. Fork o projeto
2. Teste com diferentes USER_ID/GROUP_ID
3. Verifique compatibilidade com diferentes versões Ubuntu
4. Submeta um Pull Request

## 📄 Licença

Licenciado sob GPL-3
