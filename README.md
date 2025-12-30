# VM Provisioning Script

Automates creation of Debian VMs from a QCOW2 template. The script:

- Creates a VM disk from the template.
- Injects your root SSH key.
- Attaches the VM to a libvirt network (auto-created if missing).
- Waits for the VM to get an IP and prints it.

# Download Debian 12 Generic Cloud QCOW2 image (Optional)

```bash
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
```

## Clone the repository:
```bash
git clone https://github.com/SeregaBobylev/virsh-vm-creator.git
cd virsh-vm-creator
chmod +x script.sh
```

## Usage

```bash
sudo ./script.sh \
--name <vm_name> \ 
--network <network_name> \
--ssh-key <path_to_ssh_pub_key> \
--template-image <path_template>
```

## Example
```bash 
sudo ./script.sh \
--name testvm \
--network test-net \
--ssh-key /root/.ssh/authorized_keys \
--template-image /data/images/debian-template.qcow2
```
# VM Provisioning Script

This script automates creation of Debian-based VMs from a QCOW2 template with cloud-init support. It:

- Creates a VM disk from a template.
- Injects your root SSH key.
- Creates the VM and attaches it to a libvirt network (auto-created if missing).
- Waits for the VM to get an IP via DHCP and prints it.

## Parameters

Required:
- `--name <vm_name>` — VM name
- `--network <network_name>` — libvirt network (auto-created if missing)
- `--ssh-key <path_to_key>` — path to root SSH public key
- `--template-image <FILE>` — QCOW2 template (default: `/data/images/debian-template.qcow2`)

Optional:
- `--vcpus <N>` — CPU cores (default: 2)
- `--ram <MB>` — RAM in MB (default: 2048)
- `--disk-dir <DIR>` — VM disk directory (default: `/data/images/disks`)
- `--network-base <IP>` - Base IP for network (default: `192.168.100.1`)

## Example

```bash
sudo ./script.sh \
--name testvm \
--network default \
--ssh-key /root/.ssh/authorized_keys \
--template-image /data/images/debian-template.qcow2

```

```bash
sudo ./script.sh \
--name testvm \
--network test-net \
--ssh-key /root/.ssh/id_rsa.pub \
--template-image /data/images/debian-template.qcow2 \
--vcpus 4 \
--ram 4096 \
--network-base 192.168.100.1
```
