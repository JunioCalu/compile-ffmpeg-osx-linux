nvidia_pci_hex_id=$(lspci | grep NVIDIA | awk '{print $1}')

# Split the ID into vendor and device ID parts
pci_id_parts=(${nvidia_pci_hex_id//:/ })

# Print the vendor ID (assuming the first element in pci_id_parts)
echo "Vendor ID: ${pci_id_parts[0]}"
