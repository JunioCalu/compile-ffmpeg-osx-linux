#!/bin/bash

# Passo 1: Obter o ID do barramento PCI da placa NVIDIA
nvidia_pci_hex_id=$(lspci | grep NVIDIA | awk -F " " '{print $1}' | awk -F . '{print $1}')

# Passo 2: Dividir o ID em duas partes
pci_id_parts=($(echo "$nvidia_pci_hex_id" | awk -F: '{print $1, $2}'))

# Passo 3: Converter de hexadecimal para decimal
part1=$(echo "obase=10; ibase=16; ${pci_id_parts[0]}" | bc)
part2=$(echo "obase=10; ibase=16; ${pci_id_parts[1]}" | bc)

# Passo 4: Juntar as partes com ":"
busid="$part1:$part2"

# Exibir o resultado
echo "BusID da placa NVIDIA: $busid"
