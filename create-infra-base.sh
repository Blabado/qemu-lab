#!/usr/bin/env bash
echo "FUUUUUUUCKKKKK"
#-------------NAMES---------------------
ADMINNAME="sys_admin"
VM_NAME="$1"

#-------------DIRECTORIES----------------
BASE_DIR="$HOME/qemu-lab"
IMAGE_DIR="$BASE_DIR/cloud-images"
DISK_DIR="$BASE_DIR/pool"
CI_DIR="$BASE_DIR/cloud-init/$VM_NAME"

#-------------FILES----------------------
SEED_ISO="$CI_DIR/seed-$VM_NAME.iso"
CLOUD_IMG="$IMAGE_DIR/jammy-server-cloudimg-amd64.img"
DISK="$DISK_DIR/${VM_NAME}.qcow2"

#-------------CONFIG--------------------
RAM="${2:-2048}"
CPU="${3:-2}"
STORAGE="${4:-10G}"

#-------------SSH------------------------
SSH_KEY_PATH_PUB="ssh_cloud/id_ed25519.pub"
SSH_KEY_PATH_PRIV="ssh_cloud/id_ed25519"

#-------------CHECKS---------------------
if [ ! -f "$SSH_KEY_PATH_PUB" ]; then
  echo "[ERROR] SSH public key not found at: $SSH_KEY_PATH_PUB"
  exit 1
fi

SSH_KEY=$(cat "$SSH_KEY_PATH_PUB")

#-------------EXECUTION------------------

echo "[1/6] Creating directories..."
mkdir -p "$IMAGE_DIR" "$DISK_DIR" "$CI_DIR"

echo "[2/6] Downloading cloud image (if not present)..."
if [ ! -f "$CLOUD_IMG" ]; then
  wget -O "$CLOUD_IMG" https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

echo "[3/6] Generating cloud-init configuration..."
cat > "$CI_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: $ADMINNAME
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - $SSH_KEY
disable_root: true
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
runcmd:
  - [ systemctl, enable, qemu-guest-agent ]
  - [ systemctl, start, qemu-guest-agent ]
EOF

cat > "$CI_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

echo "[4/6] Creating cloud-init ISO..."
mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock "$CI_DIR/user-data" "$CI_DIR/meta-data"

echo "[5/6] Creating QCOW2 disk from base image..."
qemu-img create -f qcow2 -F qcow2 -b "$CLOUD_IMG" "$DISK" "$STORAGE"

echo "[6/6] Launching virtual machine..."
virt-install \
  --connect qemu:///session \
  --name "$VM_NAME" \
  --ram "$RAM" \
  --vcpus "$CPU" \
  --os-variant ubuntu22.04 \
  --disk path="$DISK",format=qcow2 \
  --disk path="$SEED_ISO",device=cdrom \
  --network bridge=virbr0 \
  --import \
  --noautoconsole

echo "[INFO] VM '$VM_NAME' created and started."

#-------------IP ADDRESS DETECTION----------------

echo "[INFO] Getting IP address for VM '$VM_NAME'..."
for i in {1..15}; do
  VM_IP=$(virsh domifaddr --source arp "$VM_NAME" | awk '/ipv4/ {print $4}' | cut -d'/' -f1)
  if [ -n "$VM_IP" ]; then
    echo "[SUCCESS] IP address: $VM_IP"
    break
  fi
  echo "[INFO] Waiting for IP address..."
  sleep 4
done

if [ -z "${VM_IP:-}" ]; then
  echo "[ERROR] Failed to obtain IP address."
  exit 1
fi

echo "$VM_IP" >> .ip_for_ansible.txt
echo "$VM_NAME доступна по $VM_IP: ssh -i $SSH_KEY_PATH_PRIV $ADMINNAME@$VM_IP" >> result.txt

#-------------WAIT FOR SSH----------------

#echo "[INFO] Waiting for SSH to become available at $ADMINNAME@$VM_IP..."
#
#MAX_ATTEMPTS=30
#SSH_OPTS="-i $SSH_KEY_PATH_PRIV -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3"
#
#for ((i=1; i<=MAX_ATTEMPTS; i++)); do
#  ssh $SSH_OPTS "$ADMINNAME@$VM_IP" "echo ok" &>/dev/null && break
#  echo "[WAIT] Attempt $i/$MAX_ATTEMPTS: SSH still unavailable..."
#  sleep 5
#done
#
#if (( i > MAX_ATTEMPTS )); then
#  echo "[ERROR] SSH is not available after $MAX_ATTEMPTS attempts."
#  exit 1
#else
#  echo "[SUCCESS] SSH is available!"
#fi
#
#-------------WAIT FOR CLOUD-INIT----------------
#
#echo "[INFO] Waiting for cloud-init to finish..."
#
#for i in {1..20}; do
#  CLOUD_INIT_STATUS=$(ssh $SSH_OPTS "$ADMINNAME@$VM_IP" "cloud-init status --wait" 2>/dev/null || true)
#  if [[ "$CLOUD_INIT_STATUS" == *"done"* ]]; then
#    echo "[INFO] Cloud-init has completed successfully."
#    exit 0
#  fi
#  echo "[INFO] Cloud-init not finished yet..."
#  sleep 5
#done
#
#echo "[WARNING] Cloud-init did not complete in time."
