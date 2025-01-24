#!/bin/bash

# Recebe os parâmetros do canal
CHANNEL_ID=""
CHANNEL_NAME=""
RTMP_DETAILS=""

# Lê os parâmetros passados ao script
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --monitor_channel=*)
      CHANNEL_ID="${1#*=}"
      shift
      ;;
    --channel_name=*)
      CHANNEL_NAME="${1#*=}"
      shift
      ;;
    --rtmp_details=*)
      RTMP_DETAILS="${1#*=}"
      shift
      ;;
    *)
      echo "Parâmetro desconhecido: $1"
      exit 1
      ;;
  esac
done

# Verifica se os parâmetros obrigatórios foram fornecidos
if [ -z "$CHANNEL_ID" ] || [ -z "$CHANNEL_NAME" ]; then
    echo "Uso: $0 --monitor_channel=<CHANNEL_ID> --channel_name=<CHANNEL_NAME> [--rtmp_details=<RTMP_DETAILS>]"
    exit 1
fi

# Define o caminho do arquivo de log específico para o canal
LOG_FILE="/tmp/ytbot_${CHANNEL_ID}.log"

# Inicia o serviço para o canal
echo "ytbot iniciado para o canal ID: $CHANNEL_ID, Nome: $CHANNEL_NAME" >> "$LOG_FILE"
if [ -n "$RTMP_DETAILS" ]; then
    echo "Detalhes RTMP: $RTMP_DETAILS" >> "$LOG_FILE"
fi

# Loop infinito para simular o serviço
while true; do
    echo "ytbot para canal $CHANNEL_NAME (ID: $CHANNEL_ID) rodando em $(date)" >> "$LOG_FILE"
    sleep 60  # Espera 60 segundos
done
