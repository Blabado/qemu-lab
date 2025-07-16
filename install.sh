#!/usr/bin/env bash
check_programs() {
    echo "Checking required programs..."
    local programs=("qemu-nbd" "virsh" "mkisofs" "virt-install")
    local missing=()

    for program in "${programs[@]}"; do
        if ! which "$program" > /dev/null; then
            echo "$program not found"
            missing+=("$program")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Please install the missing programs: ${missing[*]}"
        exit 1
    else
        echo "All required programs are installed"
    fi
}

generate_ssh_key() {
    echo "Generating SSH keys for Ansible...."
    mkdir -p ./ssh_cloud
    cd ssh_cloud
    ssh-keygen -t ed25519 -f ./id_ed25519 -N ""
    cd ..
}

export_default_net() {
    echo "Root access is required for these commands."
    echo "sudo virsh net-define default.xml"
    echo "sudo virsh net-autostart default"
    echo "sudo virsh net-start default"
    
    sudo virsh net-define default.xml
    sudo virsh net-autostart default
    sudo virsh net-start default


}

parse_inventory_create_vm() {
    name=""
    ram=""
    vcpus=""
    storage=""

while read -r line; do
    # Удаляем пробелы по краям и пропускаем пустые строки
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$line" ]] && continue

    # Извлекаем ключ и значение
    key=$(echo "$line" | cut -d':' -f1 | tr -d ' ')
    value=$(echo "$line" | cut -d':' -f2 | tr -d ' ')

    case "$key" in
        name) name="$value" ;;
        ram) ram="$value" ;;
        vcpus) vcpus="$value" ;;
        storage)
            storage="$value"
            # После storage считаем, что запись завершена — можно вывести или сохранить
            ./create-infra-base.sh $name $ram $vcpus $storage
            ;;
    esac
done < ./inventory.txt

}
test_1() {
    echo "$1"
}
check_available_cloud-init() {

echo "[INFO] Waiting for cloud-init to finish..."

local VM_IP="$1"
local ADMINNAME="sys_admin"
local SSH_KEY_PATH_PRIV="ssh_cloud/id_ed25519"
local SSH_OPTS="-n -i $SSH_KEY_PATH_PRIV -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3"

for i in {1..20}; do
  CLOUD_INIT_STATUS=$(ssh $SSH_OPTS "$ADMINNAME@$VM_IP" "cloud-init status --wait" 2>/dev/null || true)
  if [[ "$CLOUD_INIT_STATUS" == *"done"* ]]; then
    echo "[INFO] Cloud-init has completed successfully $VM_IP."
    break
  fi
  echo "[INFO] Cloud-init not finished yet... $VM_IP"
  sleep 5
done

}

#---------------------GENERAL--------------------------
rm .ip_for_ansible.txt
rm result.txt

check_programs

echo "Do you want to configure an ssh key? [n/Y]"
read answer
answer=${answer:-y}

if [[ "$answer" == "y" ]]; then    
    generate_ssh_key
fi

echo "Set the default network environment?"
echo "It is important that the bridge is on the virbr0 network interface."
echo "Also check that the 'allow virbr0' line was in '/etc/qemu/bridge.conf'"
echo "Please [n/Y]"
read answer
answer=${answer:-y}

if [[ "$answer" == "y" ]]; then
    export_default_net
fi

parse_inventory_create_vm

while read -r ip; do
    check_available_cloud-init "$ip"
done < .ip_for_ansible.txt

echo "It's result.txt"
cat result.txt
echo "Virtual machines are ready"
