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

parse_inventory() {
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

#---------------------GENERAL--------------------------
check_programs

echo "Do you want to configure an ssh key? [n/Y]"
read answer
answer=${answer:-y}

if [[ "$answer" == "y" ]]; then    
    generate_ssh_key
fi

#export_default_net
parse_inventory


#./create-infra-base.sh infra-docer
#./create-vm-from-template.sh infra-docker
#./create-vm-from-template.sh infra-monitor
#./create-vm-from-template.sh infra-ci
#./create-vm-from-template.sh infra-storage
#./create-vm-from-template.sh infra-gw
