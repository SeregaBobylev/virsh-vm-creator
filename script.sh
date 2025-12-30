#!/bin/bash
set -e

SYSTEM_FAILURE_EXIT_CODE=1

function assert {
    if [ $1 -ne 0 ]; then
        echo "Command failed: $2"
        exit $SYSTEM_FAILURE_EXIT_CODE
    fi
}

function print_help {
    cat <<EOF
Usage: $0 --name <vm_name> --network <network_name> --ssh-key <path_to_key> --template-image <file> [options]

Required:
  --name <vm_name>            Name of the VM
  --network <network_name>    Libvirt network (auto-created if missing)
  --ssh-key <path_to_key>     Root SSH public key path
  --template-image <file>     QCOW2 template image (mandatory)

Optional:
  --vcpus <N>                 Number of CPU cores (default: 2)
  --ram <MB>                  RAM in MB (default: 2048)
  --disk-dir <DIR>            Directory for VM disks (default: /data/images/disks)
  --network-base <IP>         Base IP for network (default: 192.168.100.1)
  --help                      Show this help message

Example:
  sudo $0 --name testvm --network default --ssh-key /root/.ssh/authorized_keys --template-image /data/images/debian-template.qcow2
EOF
    exit 0
}

# Show help if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    print_help
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) vm_name="$2"; shift 2 ;;
        --network) vm_network="$2"; shift 2 ;;
        --ssh-key) ssh_pub_key="$2"; shift 2 ;;
        --template-image) template_image="$2"; shift 2 ;;
        --vcpus) vm_vcpus="$2"; shift 2 ;;
        --ram) vm_ram="$2"; shift 2 ;;
        --disk-dir) vm_disk_dir="$2"; shift 2 ;;
        --network-base) network_base="$2"; shift 2 ;;
        --help|-h) print_help ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

# Validate required parameters
if [[ -z "$vm_name" || -z "$vm_network" || -z "$ssh_pub_key" || -z "$template_image" ]]; then
    echo "Error: --name, --network, --ssh-key, and --template-image are required"
    print_help
fi

if [[ ! -f "$ssh_pub_key" ]]; then
    echo "SSH key file not found: $ssh_pub_key"
    exit 1
fi

if [[ ! -f "$template_image" ]]; then
    echo "Template image not found: $template_image"
    exit 1
fi

# Set defaults
vm_vcpus="${vm_vcpus:-2}"
vm_ram="${vm_ram:-2048}"
vm_disk_dir="${vm_disk_dir:-/data/images/disks}"
network_base="${network_base:-192.168.100.1}"
vm_disk="$vm_disk_dir/$vm_name.qcow2"
virsh_path=$(which virsh)

# Ensure disk directory exists
mkdir -p "$vm_disk_dir"

# Dependencies
for pkg in qemu-utils libvirt-daemon-system libvirt-clients virt-install libguestfs-tools cloud-image-utils; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        echo "Installing $pkg..."
        apt install -y "$pkg"
        assert $? "Failed to install $pkg"
    fi
done

# Compute DHCP range
IFS='.' read -r a b c d <<< "$network_base"
dhcp_start="${a}.${b}.${c}.$((d+100))"
dhcp_end="${a}.${b}.${c}.$((d+200))"

# Create network if missing
if ! $virsh_path net-info "$vm_network" &>/dev/null; then
    echo "Creating network $vm_network..."
    cat <<EOF > ./$vm_network.xml
<network>
  <name>$vm_network</name>
  <bridge name="virbr-${vm_network}" stp="on" delay="0"/>
  <forward mode="nat"/>
  <ip address="$network_base" netmask="255.255.255.0">
    <dhcp>
      <range start="$dhcp_start" end="$dhcp_end"/>
    </dhcp>
  </ip>
</network>
EOF
    $virsh_path net-define ./$vm_network.xml
    $virsh_path net-start "$vm_network"
    $virsh_path net-autostart "$vm_network"
    echo "Network $vm_network created."
else
    echo "Network $vm_network exists, skipping."
fi

# Check if VM exists
existing_vm=$($virsh_path list --name | grep -w "$vm_name" || true)
if [[ -n "$existing_vm" ]]; then
    echo "VM $vm_name already exists, skipping creation."
    exit 0
fi

echo "Creating disk..."
qemu-img create -f qcow2 -b "$template_image" "$vm_disk" -F qcow2
assert $? "qemu-img failed"

echo "Running virt-sysprep..."
virt-sysprep -a "$vm_disk" --ssh-inject "root:file:$ssh_pub_key" --hostname "$vm_name"
assert $? "virt-sysprep failed"

echo "Creating VM..."
virt-install --name "$vm_name" --os-variant debian12 --disk "$vm_disk" --import \
    --vcpus "$vm_vcpus" --ram "$vm_ram" --network network="$vm_network" \
    --graphics none --autostart --noautoconsole
assert $? "virt-install failed"

echo "Waiting for VM to get an IP..."
vm_mac=$($virsh_path domiflist "$vm_name" | awk '/network/ {print $5}' | head -n1)
vm_ip=""
for i in $(seq 1 60); do
    vm_ip=$($virsh_path net-dhcp-leases "$vm_network" | grep -i "$vm_mac" | awk '{print $5}' | cut -d'/' -f1)
    [[ -n "$vm_ip" ]] && break
    sleep 1
done

if [[ -z "$vm_ip" ]]; then
    echo "Failed to get IP for VM $vm_name after 60 seconds."
    exit 1
fi

echo "VM $vm_name created successfully with IP: $vm_ip"
