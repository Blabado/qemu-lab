#!/bin/bash

# === Настройки ===
BASE_NAME="infra-base"
NEW_NAME="$1"
ADMINNAME="sys_admin"
BASE_DIR="$HOME/qemu-lab"
IMAGE_DIR="$BASE_DIR/cloud-images"
DISK_DIR="$BASE_DIR/pool"
CI_DIR="$BASE_DIR/cloud-init/$NEW_NAME"
SEED_ISO="$CI_DIR/seed-$NEW_NAME.iso"
BASE_IMAGE="$DISK_DIR/${BASE_NAME}.qcow2"
NEW_DISK="$DISK_DIR/${NEW_NAME}.qcow2"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519.pub"
SSH_KEY=$(cat "$SSH_KEY_PATH")

if [ -z "$NEW_NAME" ]; then
  echo "Usage: $0 <new-vm-name>"
  exit 1
fi

echo "[1/6] Проверка шаблона и подготовка директорий..."
if [ ! -f "$BASE_IMAGE" ]; then
  echo "Базовый образ $BASE_IMAGE не найден!"
  exit 1
fi

mkdir -p "$CI_DIR"

echo "[2/6] Создание cloud-init конфигов..."
cat > "$CI_DIR/user-data" <<EOF
#cloud-config
hostname: $NEW_NAME
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
EOF

cat > "$CI_DIR/meta-data" <<EOF
instance-id: $NEW_NAME
local-hostname: $NEW_NAME
EOF

echo "[3/6] Генерация seed ISO..."
mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock \
    "$CI_DIR/user-data" "$CI_DIR/meta-data"

echo "[4/6] Клонирование диска..."
cp "$BASE_IMAGE" "$NEW_DISK"

echo "[5/6] Запуск новой виртуальной машины: $NEW_NAME"
virt-install \
  --connect qemu:///system \
  --name "$NEW_NAME" \
  --ram 2048 \
  --vcpus 2 \
  --os-variant ubuntu22.04 \
  --disk path="$NEW_DISK",format=qcow2 \
  --disk path="$SEED_ISO",device=cdrom \
  --network network=default \
  --import \
  --noautoconsole

echo "[6/6] Ожидание IP-адреса..."
sleep 2
for i in {1..10}; do
  VM_IP=$(virsh domifaddr "$NEW_NAME" | awk '/ipv4/ {print $4}' | cut -d'/' -f1)
  [ -n "$VM_IP" ] && break
  echo "Ожидание IP..."
  sleep 2
done

echo "$VM_IP" >> .ip_for_ansible.txt
echo "$NEW_NAME доступна по $VM_IP ssh $ADMINNAME@$VM_IP" >> result.txt

if [ -z "$VM_IP" ]; then
  echo "[ERROR] Не удалось получить IP-адрес"
  exit 1
fi

echo "[INFO] Ожидаем доступности SSH от $ADMINNAME@$VM_IP..."

MAX_ATTEMPTS=30
SSH_KEY_PATH_PRIV="$HOME/.ssh/id_ed25519"  # или укажи явно путь
SSH_CMD="ssh -i $SSH_KEY_PATH_PRIV -o StrictHostKeyChecking=no -o ConnectTimeout=3"

for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  $SSH_CMD "$ADMINNAME@$VM_IP" "echo ok" &>/dev/null && break
  echo "[WAIT] Попытка $i/$MAX_ATTEMPTS: SSH ещё недоступен..."
  sleep 5
done

if (( i > MAX_ATTEMPTS )); then
  echo "[ERROR] SSH не стал доступен после $MAX_ATTEMPTS попыток"
  exit 1
else
  echo "[SUCCESS] SSH доступен!"
fi

echo "[INFO] Проверка завершения cloud-init..."
for i in {1..20}; do
  CLOUD_INIT_DONE=$(ssh -i $SSH_KEY_PATH_PRIV "$ADMINNAME@$VM_IP" "cloud-init status --wait 2>/dev/null")
  if [[ "$CLOUD_INIT_DONE" == *"done"* ]]; then
    echo "[INFO] Cloud-init завершён ✅"
    exit
  fi
    echo "[INFO] Cloud-init ещё работает..."
    sleep 5
  done

echo "[WARNING] Не удалось дождаться завершения cloud-init"
