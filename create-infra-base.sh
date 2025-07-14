#set -e

VM_NAME="infra-base"
BASE_DIR="$HOME/qemu-lab"
IMAGE_DIR="$BASE_DIR/cloud-images"
DISK_DIR="$BASE_DIR/pool"
CI_DIR="$BASE_DIR/cloud-init/$VM_NAME"
SEED_ISO="$CI_DIR/seed-$VM_NAME.iso"
DISK="$DISK_DIR/$VM_NAME.qcow2"
CLOUD_IMG="$IMAGE_DIR/jammy-server-cloudimg-amd64.img"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519.pub"
SSH_KEY=$(cat "$SSH_KEY_PATH")

echo "[1/6] Создание директорий..."
mkdir -p "$IMAGE_DIR" "$DISK_DIR" "$CI_DIR"

echo "[2/6] Скачивание cloud-image (если нет)..."
if [ ! -f "$CLOUD_IMG" ]; then
    wget -O "$CLOUD_IMG" https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

echo "[3/6] Подготовка cloud-init файлов..."
cat > "$CI_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: sys_admin
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - $SSH_KEY
disable_root: true
package_update: true
package_upgrade: true
EOF

cat > "$CI_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

echo "[4/6] Генерация seed ISO..."
mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock \
    "$CI_DIR/user-data" "$CI_DIR/meta-data"

echo "[5/6] Создание QCOW2-диска на базе cloud image..."
qemu-img create -f qcow2 -F qcow2 -b "$CLOUD_IMG" "$DISK" 10G

echo "[6/6] Запуск virt-install..."
virt-install \
  --connect qemu:///system \
  --name "$VM_NAME" \
  --ram 2048 \
  --vcpus 2 \
  --os-variant ubuntu22.04 \
  --disk path="$DISK",format=qcow2 \
  --disk path="$SEED_ISO",device=cdrom \
  --network network=default \
  --import \
  --graphics none

echo "VM '$VM_NAME' создана и запущена!"

echo "Ожидаем получения IP-адреса..."

sleep 10  # даём немного времени на инициализацию сети

VM_IP=$(virsh domifaddr "$VM_NAME" | awk '/ipv4/ {print $4}' | cut -d'/' -f1) 

echo "$VM_IP" > .ip_for_ansible.txt

if [ -n "$VM_IP" ]; then
  echo "VM '$VM_NAME' доступна по адресу: $VM_IP" | tee Ip_list.txt
  echo "Подключение: ssh sys_admin@$VM_IP"
else
  echo "Не удалось определить IP-адрес. Проверь сеть или cloud-init."
fi


