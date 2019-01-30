!/bin/bash
encoding: utf-8
## https://github.com/mgvl/archlinux.git

# # CONFIGURE ESTAS VARIÁVEIS
# # VEJA TAMBÉM A FUNÇÃO install_packages PARA VER O QUE É REALMENTE INSTALADO

# Drive para instalar.
DRIVE='/dev/sda'

# Criptografar tudo (exceto / boot). Deixe em branco para desativar.
ENCRYPT_DRIVE='TRUE'

# Senha para criptografar o disco (deixe em branco para ser solicitado).
DRIVE_PASSPHRASE=''

# Senha de root (deixe em branco para ser avisado).
ROOT_PASSWORD=''


setup() {
    local boot_dev="$DRIVE"1
    local lvm_dev="$DRIVE"2

    echo 'Criando partições'
    partition_drive "$DRIVE"

    if [ -n "$ENCRYPT_DRIVE" ]
    then
        local lvm_part="/dev/mapper/lvm"

        if [ -z "$DRIVE_PASSPHRASE" ]
        then
            echo 'Digite uma frase secreta para criptografar o disco: '
            stty -echo
            read DRIVE_PASSPHRASE
            stty echo
        fi

        echo 'Partição criptografada'
        encrypt_drive "$lvm_dev" "$DRIVE_PASSPHRASE" lvm

    else
        local lvm_part="$lvm_dev"
    fi

    echo 'Configurando o LVM'
    setup_lvm "$lvm_part" vg00

    echo 'Formatando sistemas de arquivos'
    format_filesystems "$boot_dev"

    echo 'Montando sistemas de arquivos'
    mount_filesystems "$boot_dev"

    echo 'Instalando o sistema básico'
    install_base

    echo 'Chroot no sistema instalado para continuar a configuração ...'
    cp $0 /mnt/setup.sh
    arch-chroot /mnt ./setup.sh chroot

    if [ -f /mnt/setup.sh ]
    then
        echo 'ERRO: Algo falhou dentro do chroot, não desmontando sistemas de arquivos para que você possa investigar.'
        echo 'Certifique-se de desmontar tudo antes de tentar executar este script novamente.'
    else
        echo 'Desmontando sistemas de arquivos'
        unmount_filesystems
        echo 'Feito! Reiniciar sistema.'
    fi
}


partition_drive() {
    local dev="$1"; shift

    # 100 MB / partição de boot, tudo mais sob o LVM
    parted -s "$dev" \
        mklabel msdos \
        mkpart primary ext2 1 100M \
        mkpart primary ext2 100M 100% \
        set 1 boot on \
        set 2 LVM on
}

encrypt_drive() {
    local dev="$1"; shift
    local passphrase="$1"; shift
    local name="$1"; shift

    echo -en "$passphrase" | cryptsetup -c aes-xts-plain -y -s 512 luksFormat "$dev"
    echo -en "$passphrase" | cryptsetup luksOpen "$dev" lvm
}

setup_lvm() {
    local partition="$1"; shift
    local volgroup="$1"; shift

    pvcreate "$partition"
    vgcreate "$volgroup" "$partition"

    #  Crie uma partição swap de 1GB
    lvcreate -C y -L1G "$volgroup" -n swap

    # Use o resto do espaço para root
    lvcreate -l '+100%FREE' "$volgroup" -n root

    # Ativar os novos volumes
    vgchange -ay
}

format_filesystems() {
    local boot_dev="$1"; shift

    mkfs.ext2 -L boot "$boot_dev"
    mkfs.ext4 -L root /dev/vg00/root
    mkswap /dev/vg00/swap
}

mount_filesystems() {
    local boot_dev="$1"; shift

    mount /dev/vg00/root /mnt
    mkdir /mnt/boot
    mount "$boot_dev" /mnt/boot
    swapon /dev/vg00/swap
}

install_base() {
    echo 'Server = http://mirrors.kernel.org/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist

    pacstrap /mnt base base-devel
    pacstrap /mnt syslinux
}

unmount_filesystems() {
    umount /mnt/boot
    umount /mnt
    swapoff /dev/vg00/swap
    vgchange -an
    if [ -n "$ENCRYPT_DRIVE" ]
    then
        cryptsetup luksClose lvm
    fi
}



set_hostname() {
    local hostname="$1"; shift

    echo "$hostname" > /etc/hostname
}

set_timezone() {
    local timezone="$1"; shift

    ln -sT "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

set_locale() {
    echo 'LANG=pt_BR.UTF-8' >> /etc/locale.conf
    echo 'FONT=Lat2-Terminus16' >> /etc/locale.conf
    echo "FONT_MAP=" >> /etc/locale.gen
    locale-gen
}

set_keymap() {
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
}

set_hosts() {
    local hostname="$1"; shift

    cat > /etc/hosts <<EOF
127.0.0.1 localhost.localdomain localhost $hostname
::1       localhost.localdomain localhost $hostname
EOF
}

set_fstab() {
    local tmp_on_tmpfs="$1"; shift
    local boot_dev="$1"; shift

    local boot_uuid=$(get_uuid "$boot_dev")

    cat > /etc/fstab <<EOF
#
# /etc/fstab: informações do sistema de arquivos estáticos
#
# <file system> <dir>    <type> <options>    <dump> <pass>
/dev/vg00/swap none swap  sw                0 0
/dev/vg00/root /    ext4  defaults,relatime 0 1
UUID=$boot_uuid /boot ext2 defaults,relatime 0 2
EOF
}

set_modules_load() {
    echo 'microcode' > /etc/modules-load.d/intel-ucode.conf
}


}

set_syslinux() {
    local lvm_dev="$1"; shift

    local lvm_uuid=$(get_uuid "$lvm_dev")

    local crypt=""
    if [ -n "$ENCRYPT_DRIVE" ]
    then
        # Load in resources
        crypt="cryptdevice=/dev/disk/by-uuid/$lvm_uuid:lvm"
    fi

    cat > /boot/syslinux/syslinux.cfg <<EOF



set_root_password() {
    local password="$1"; shift

    echo -en "$password\n$password" | passwd
}

create_user() {
    local name="$1"; shift
    local password="$1"; shift

    useradd -m -s /bin/zsh -G adm,systemd-journal,wheel,rfkill,games,network,video,audio,optical,floppy,storage,scanner,power,adbusers,wireshark "$name"
    echo -en "$password\n$password" | passwd "$name"
}

update_locate() {
    updatedb
}

get_uuid() {
    blkid -o export "$1" | grep UUID | awk -F= '{print $2}'
}

set -ex

if [ "$1" == "chroot" ]
then
    configure
else
    setup
fi
