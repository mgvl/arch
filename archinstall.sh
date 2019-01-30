!/bin/bash
encoding: utf-8
## https://github.com/mgvl/archlinux.git

# # CONFIGURE ESTAS VARIÁVEIS
# # VEJA TAMBÉM A FUNÇÃO install_packages PARA VER O QUE É REALMENTE INSTALADO

# Drive para instalar.
DRIVE='/dev/sda'

# Hostname da máquina instalada.
HOSTNAME='Metalhost'

# Criptografar tudo (exceto / boot). Deixe em branco para desativar.
ENCRYPT_DRIVE='TRUE'

# Senha para criptografar o disco (deixe em branco para ser solicitado).
DRIVE_PASSPHRASE=''

# Senha de root (deixe em branco para ser avisado).
ROOT_PASSWORD=''

# Usuário principal para criar (por padrão, adicionado ao grupo wheel e outros).
USER_NAME='maibe'

# A senha do usuário principal (deixe em branco para ser solicitado).
USER_PASSWORD=''

# System timezone.
TIMEZONE='America/Sao_Paulo'

# Ter / tmp em um tmpfs ou não. Deixe em branco para desativar.
# Só deixe isso em branco nos sistemas com pouca RAM.
TMP_ON_TMPFS='TRUE'

KEYMAP='pt_BR'
# KEYMAP

# Escolha seu driver de vídeo
# Para Intel
VIDEO_DRIVER="i915"
# Para nVidia
#VIDEO_DRIVER="nouveau"
# Para ATI
#VIDEO_DRIVER="radeon"
# Para generic 
#VIDEO_DRIVER="vesa"

# Dispositivo sem fio, deixe em branco para não usar a rede sem fio e use o DHCP.
WIRELESS_DEVICE="wlp12s0b1"



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

configure() {
    local boot_dev="$DRIVE"1
    local lvm_dev="$DRIVE"2

    echo 'Instalando pacotes adicionais'
    install_packages

    #echo 'Instalando yay'
    #install_yay

    #echo 'Instalando pacotes AUR'
    #install_aur_packages

    #echo 'Limpando tarballs do pacote'
    #clean_packages

    #echo 'Atualizando o banco de dados pkgfile'
    #update_pkgfile

    echo 'Configurando hostname'
    set_hostname "$HOSTNAME"

    echo 'Definição do fuso horário'
    set_timezone "$TIMEZONE"

    echo 'Definir local'
    set_locale

    echo 'Configurando o mapa de teclado do console'
    set_keymap

    echo 'Configurando arquivo hosts'
    set_hosts "$HOSTNAME"

    echo 'Definindo fstab'
    set_fstab "$TMP_ON_TMPFS" "$boot_dev"

    echo 'Configurando módulos iniciais para carregar'
    set_modules_load

    echo 'Configurando o ramdisk inicial'
    set_initcpio

    echo 'Configurando daemons iniciais'
    set_daemons "$TMP_ON_TMPFS"

    echo ' Configurando o carregador de inicialização'
    set_syslinux "$lvm_dev"

    echo 'Configurando o sudo'
    set_sudoers

    echo 'Configurando o slim'
    set_slim

    if [ -n "$WIRELESS_DEVICE" ]
    then
        echo 'Configurando o netcfg'
        set_netcfg
    fi

    if [ -z "$ROOT_PASSWORD" ]
    then
        echo 'Digite a senha de root:'
        stty -echo
        read ROOT_PASSWORD
        stty echo
    fi
    echo 'Definir senha de rootd'
    set_root_password "$ROOT_PASSWORD"

    if [ -z "$USER_PASSWORD" ]
    then
        echo "Digite a senha para o usuário $USER_NAME"
        stty -echo
        read USER_PASSWORD
        stty echo
    fi
    echo 'Criando usuário inicialr'
    create_user "$USER_NAME" "$USER_PASSWORD"

    echo 'Construindo banco de dados de localização'
    update_locate

    rm /setup.sh
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

#install_packages() {
#  #  local packages=''
#
#    #  Utilidades gerais / bibliotecas
#    packages+=' alsa-utils aspell-en chromium cpupower gvim mlocate net-tools ntp openssh p7zip pkgfile powertop python python2 rfkill rsync sudo unrar unzip wget zip systemd-sysvcompat zsh grml-zsh-config'
#
#    # Pacotes de desenvolvimento
#    packages+=' apache-ant cmake gdb git maven mercurial subversion tcpdump valgrind wireshark-gtk'
#
#    # Netcfg
#    if [ -n "$WIRELESS_DEVICE" ]
#    then
#       packages+=' netcfg ifplugd dialog wireless_tools wpa_actiond wpa_supplicant'
#    fi
#
#    # Java 
#    packages+=' icedtea-web-java7 jdk7-openjdk jre7-openjdk'
#
#    # Libreoffice
#    #packages+=' libreoffice-calc libreoffice-en-US libreoffice-gnome libreoffice-impress libreoffice-writer hunspell-en hyphen-en mythes-en'
#
#    # Programas Misc
#    packages+=' mplayer pidgin vlc xscreensaver gparted dosfstools ntfsprogs'
#
    # Xserver
    packages+=' xorg-apps xorg-server xorg-xinit xterm'
#
#    # Slim gerenciador de login
#    packages+=' slim archlinux-themes-slim'
#
#    # Fontes
#    packages+=' ttf-dejavu ttf-liberation'
#
    # Processadores Intel
    packages+=' intel-ucode'
#
    # Para laptops
    packages+=' xf86-input-synaptics'
#
#    # Pacotes extras para o tablet tc4200
#    # packages + = 'ipw2200-fw xf86-input-wacom'
#
    if [ "$VIDEO_DRIVER" = "i915" ]
    then
        packages+=' xf86-video-intel libva-intel-driver'
    elif [ "$VIDEO_DRIVER" = "nouveau" ]
    then
        packages+=' xf86-video-nouveau'
    elif [ "$VIDEO_DRIVER" = "radeon" ]
    then
        packages+=' xf86-video-ati'
    elif [ "$VIDEO_DRIVER" = "vesa" ]
    then
        packages+=' xf86-video-vesa'
    fi

#    pacman -Sy --noconfirm $packages
#}

#install_yay() {
#    git clone https://aur.archlinux.org/yay.git
#    cd yay
#    makepkg -si
#    
#}

#install_aur_packages() {
#    mkdir /foo
#    export TMPDIR=/foo
#    yay -S --noconfirm chromium
#    unset TMPDIR
#    rm -rf /foo
#}

#clean_packages() {
#    yes | pacman -Scc
#}

#update_pkgfile() {
#    pkgfile -u
#}

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

set_initcpio() {
    local vid

    if [ "$VIDEO_DRIVER" = "i915" ]
    then
        vid='i915'
    elif [ "$VIDEO_DRIVER" = "nouveau" ]
    then
        vid='nouveau'
    elif [ "$VIDEO_DRIVER" = "radeon" ]
    then
        vid='radeon'
    fi

    local encrypt=""
    if [ -n "$ENCRYPT_DRIVE" ]
    then
        encrypt="encrypt"
    fi


    # Definir MÓDULOS com o seu driver de vídeo
    cat > /etc/mkinitcpio.conf <<EOF
# vim:set ft=sh
# MODULES
# Os seguintes módulos são carregados antes de qualquer gancho de inicialização
# corre. Usuários avançados podem desejar especificar todos os módulos do sistema
# neste array. Por exemplo:
#     MODULES="piix ide_disk reiserfs"
MODULES="ext4 $vid"
# BINÁRIOS
# Esta configuração inclui quaisquer binários adicionais que um determinado usuário
# deseje na imagem do CPIO. Isso é executado por último, então pode ser usado para
# substituir os binários reais incluídos por um determinado gancho
# BINARIES são analisados ​​por dependência, portanto, você pode ignorar com segurança as bibliotecas
BINARIES=""
# ARQUIVOS
# Essa configuração é semelhante a BINÁRIOS acima, no entanto, os arquivos são adicionados
# como está e não é analisado de qualquer forma. Isso é útil para arquivos de configuração.
# Alguns usuários podem querer incluir o modprobe.conf para opções customizadas do módulo
# igual a:
#    FILES="/etc/modprobe.d/modprobe.conf"
FILES=""
# HOOKS
# Esta é a configuração mais importante neste arquivo. Os HOOKS controlam o
# módulos e scripts adicionados à imagem e o que acontece no momento da inicialização.
# O pedido é importante e é recomendável que você não altere o
# ordem em que os HOOKS são adicionados. Execute 'mkinitcpio -H <nome do gancho>' para
# ajuda em um determinado gancho.
# 'base' é _requirida_ a menos que você saiba exatamente o que está fazendo.
# 'udev' é _requirido_ para carregar automaticamente os módulos
# 'filesystems' é _required_ a menos que você especifique seus módulos fs em MODULES
# Exemplos:
## Esta configuração especifica todos os módulos na configuração MODULES acima.
## Não é necessário invadir, lvm2 ou raiz criptografada.
# HOOKS = "base"
#
## Esta configuração irá auto-detectar todos os módulos do seu sistema e deve
## funciona como um padrão sensato
# HOOKS = "base udev autodetect pata scsi sistemas de arquivos sata"
#
## Isto é idêntico ao acima, exceto que o antigo subsistema ide é
## usado para dispositivos IDE em vez do novo subsistema pata.
# HOOKS = "base de sistemas de arquivos sata autodetect ide scsi sata"
#
## Esta configuração irá gerar uma imagem 'completa' que suporta a maioria dos sistemas.
## Nenhuma autodetecção é feita.
# HOOKS = "base de dados udev pata scsi sata sistemas de arquivos usb"
#
## Essa configuração monta um array pata mdadm com um FS raiz criptografado.
## Nota: Veja 'mkinitcpio -H mdadm' para mais informações sobre dispositivos raid.
# HOOKS = "base do udev pata mdadm criptografar os sistemas de arquivos"
#
## Essa configuração carrega um grupo de volume lvm2 em um dispositivo usb.
# HOOKS = "base de sistemas de arquivos udev usb lvm2"
#
## NOTA: Se você tem / usr em uma partição separada, você deve incluir o
# Ganchos # usr, fsck e shutdown.
HOOKS="base udev autodetect modconf block keymap keyboard $encrypt lvm2 resume filesystems fsck"
# COMPRESSÃO
# Use isso para compactar a imagem do initramfs. Por padrão, a compactação gzip
# é usado. Use 'cat' para criar uma imagem não compactada.
#COMPRESSION="gzip"
#COMPRESSION="bzip2"
#COMPRESSION="lzma"
#COMPRESSION="xz"
#COMPRESSION="lzop"
# COMPRESSION_OPTIONS
# Additional options for the compressor
#COMPRESSION_OPTIONS=""
EOF

    mkinitcpio -p linux
}

set_daemons() {
    local tmp_on_tmpfs="$1"; shift

    systemctl enable cronie.service cpupower.service ntpd.service slim.service

    if [ -n "$WIRELESS_DEVICE" ]
    then
        systemctl enable net-auto-wired.service net-auto-wireless.service
    else
        systemctl enable dhcpcd@enp9s0.service
    fi

    if [ -z "$tmp_on_tmpfs" ]
    then
        systemctl mask tmp.mount
    fi
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
# Config file for Syslinux -
# /boot/syslinux/syslinux.cfg
#
# Módulos Comboot:
# * menu.c32 - fornece um menu de texto
# * vesamenu.c32 - fornece um menu gráfico
# * chain.c32 - MBRs chainload, setores de boot de partição, bootloaders do Windows
# * hdt.c32 - ferramenta de detecção de hardware
# * reboot.c32 - reinicia o sistema
# * poweroff.com - desligue o sistema
#
# Para usar: Copie os arquivos respectivos de / usr / lib / syslinux para / boot / syslinux.
# Se / usr e / boot estiverem no mesmo sistema de arquivos, crie um link simbólico para os arquivos
# de copiá-los.
#
# Se você não usar um menu, um prompt 'boot:' será mostrado eo sistema
# inicializa automaticamente após 5 segundos.
#
# Por favor, reveja o wiki: https://wiki.archlinux.org/index.php/Syslinux
# O wiki fornece mais exemplos de configuração
DEFAULT arch
PROMPT 0        # Defina como 1 se quiser sempre exibir o prompt boot: 
TIMEOUT 50
# Você pode criar keymaps syslinux com a ferramenta keytab-lilo
#KBDMAP de.ktl

#  Configuração do Menu
# Either menu.c32 or vesamenu32.c32 must be copied to /boot/syslinux 
UI menu.c32
#UI vesamenu.c32
# Refer to http://syslinux.zytor.com/wiki/index.php/Doc/menu
MENU TITLE Arch Linux
#MENU BACKGROUND splash.png
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

# seções de inicialização seguir
#
# DICA: Se você quiser um framebuffer de 1024x768, adicione "vga = 773" à sua linha de kernel.
#
# - *
LABEL arch
	MENU LABEL Arch Linux
	LINUX ../vmlinuz-linux
	APPEND root=/dev/vg00/root ro $crypt resume=/dev/vg00/swap quiet
	INITRD ../initramfs-linux.img
LABEL archfallback
	MENU LABEL Arch Linux Fallback
	LINUX ../vmlinuz-linux
	APPEND root=/dev/vg00/root ro $crypt resume=/dev/vg00/swap
	INITRD ../initramfs-linux-fallback.img
LABEL hdt
        MENU LABEL HDT (Hardware Detection Tool)
        COM32 hdt.c32
LABEL reboot
        MENU LABEL Reboot
        COM32 reboot.c32
LABEL off
        MENU LABEL Power Off
        COMBOOT poweroff.com
EOF

    syslinux-install_update -iam
}

set_sudoers() {
    cat > /etc/sudoers <<EOF
## sudoers file.
##
## This file MUST be edited with the 'visudo' command as root.
## Failure to use 'visudo' may result in syntax or file permission errors
## that prevent sudo from running.
##
## See the sudoers man page for the details on how to write a sudoers file.
##
##
## Host alias specification
##
## Groups of machines. These may include host names (optionally with wildcards),
## IP addresses, network numbers or netgroups.
# Host_Alias	WEBSERVERS = www1, www2, www3
##
## User alias specification
##
## Groups of users.  These may consist of user names, uids, Unix groups,
## or netgroups.
# User_Alias	ADMINS = millert, dowdy, mikef
##
## Cmnd alias specification
##
## Groups of commands.  Often used to group related commands together.
# Cmnd_Alias	PROCESSES = /usr/bin/nice, /bin/kill, /usr/bin/renice, \
# 			    /usr/bin/pkill, /usr/bin/top
##
## Defaults specification
##
## You may wish to keep some of the following environment variables
## when running commands via sudo.
##
## Locale settings
# Defaults env_keep += "LANG LANGUAGE LINGUAS LC_* _XKB_CHARSET"
##
## Run X applications through sudo; HOME is used to find the
## .Xauthority file.  Note that other programs use HOME to find   
## configuration files and this may lead to privilege escalation!
# Defaults env_keep += "HOME"
##
## X11 resource path settings
# Defaults env_keep += "XAPPLRESDIR XFILESEARCHPATH XUSERFILESEARCHPATH"
##
## Desktop path settings
# Defaults env_keep += "QTDIR KDEDIR"
##
## Allow sudo-run commands to inherit the callers' ConsoleKit session
# Defaults env_keep += "XDG_SESSION_COOKIE"
##
## Uncomment to enable special input methods.  Care should be taken as
## this may allow users to subvert the command being run via sudo.
# Defaults env_keep += "XMODIFIERS GTK_IM_MODULE QT_IM_MODULE QT_IM_SWITCHER"
##
## Uncomment to enable logging of a command's output, except for
## sudoreplay and reboot.  Use sudoreplay to play back logged sessions.
# Defaults log_output
# Defaults!/usr/bin/sudoreplay !log_output
# Defaults!/usr/local/bin/sudoreplay !log_output
# Defaults!/sbin/reboot !log_output
##
## Runas alias specification
##
##
## User privilege specification
##
root ALL=(ALL) ALL
## Uncomment to allow members of group wheel to execute any command
%wheel ALL=(ALL) ALL
## Same thing without a password
# %wheel ALL=(ALL) NOPASSWD: ALL
## Uncomment to allow members of group sudo to execute any command
# %sudo ALL=(ALL) ALL
## Uncomment to allow any user to run sudo if they know the password
## of the user they are running the command as (root by default).
# Defaults targetpw  # Ask for the password of the target user
# ALL ALL=(ALL) ALL  # WARNING: only use this together with 'Defaults targetpw'
%rfkill ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
%network ALL=(ALL) NOPASSWD: /usr/bin/netcfg, /usr/bin/wifi-menu
## Read drop-in files from /etc/sudoers.d
## (the '#' here does not indicate a comment)
#includedir /etc/sudoers.d
EOF

    chmod 440 /etc/sudoers
}

set_slim() {
    cat > /etc/slim.conf <<EOF
# Path, X server and arguments (if needed)
# Note: -xauth $authfile is automatically appended
default_path        /bin:/usr/bin:/usr/local/bin
default_xserver     /usr/bin/X
xserver_arguments -nolisten tcp vt07
# Commands for halt, login, etc.
halt_cmd            /sbin/poweroff
reboot_cmd          /sbin/reboot
console_cmd         /usr/bin/xterm -C -fg white -bg black +sb -T "Console login" -e /bin/sh -c "/bin/cat /etc/issue; exec /bin/login"
suspend_cmd         /usr/bin/systemctl hybrid-sleep
# Full path to the xauth binary
xauth_path         /usr/bin/xauth 
# Xauth file for server
authfile           /var/run/slim.auth
# Activate numlock when slim starts. Valid values: on|off
# numlock             on
# Hide the mouse cursor (note: does not work with some WMs).
# Valid values: true|false
# hidecursor          false
# This command is executed after a succesful login.
# you can place the %session and %theme variables
# to handle launching of specific commands in .xinitrc
# depending of chosen session and slim theme
#
# NOTE: if your system does not have bash you need
# to adjust the command according to your preferred shell,
# i.e. for freebsd use:
# login_cmd           exec /bin/sh - ~/.xinitrc %session
# login_cmd           exec /bin/bash -login ~/.xinitrc %session
login_cmd           exec /bin/zsh -l ~/.xinitrc %session
# Commands executed when starting and exiting a session.
# They can be used for registering a X11 session with
# sessreg. You can use the %user variable
#
# sessionstart_cmd	some command
# sessionstop_cmd	some command
# Start in daemon mode. Valid values: yes | no
# Note that this can be overriden by the command line
# options "-d" and "-nodaemon"
# daemon	yes
# Available sessions (first one is the default).
# The current chosen session name is replaced in the login_cmd
# above, so your login command can handle different sessions.
# see the xinitrc.sample file shipped with slim sources
sessions            foo
# Executed when pressing F11 (requires imagemagick)
#screenshot_cmd      import -window root /slim.png
# welcome message. Available variables: %host, %domain
welcome_msg         %host
# Session message. Prepended to the session name when pressing F1
# session_msg         Session: 
# shutdown / reboot messages
shutdown_msg       The system is shutting down...
reboot_msg         The system is rebooting...
# default user, leave blank or remove this line
# for avoid pre-loading the username.
#default_user        simone
# Focus the password field on start when default_user is set
# Set to "yes" to enable this feature
#focus_password      no
# Automatically login the default user (without entering
# the password. Set to "yes" to enable this feature
#auto_login          no
# current theme, use comma separated list to specify a set to 
# randomly choose from
#current_theme       default
current_theme       archlinux-simplyblack
# Lock file
lockfile            /run/lock/slim.lock
# Log file
logfile             /var/log/slim.log
EOF
}

set_netcfg() {
    cat > /etc/network.d/wired <<EOF
CONNECTION='ethernet'
DESCRIPTION='Ethernet with DHCP'
INTERFACE='enp9s0'
IP='dhcp'
EOF

    chmod 600 /etc/network.d/wired

    cat > /etc/conf.d/netcfg <<EOF
# Habilite esses perfis do netcfg no momento da inicialização.
# - prefixar uma entrada com um '@' para colocar em segundo plano sua inicialização
# - definido como 'last' para restaurar os perfis em execução no último desligamento
# - definido como 'menu' para apresentar um menu (requer o pacote de diálogo)
# Perfis de rede são encontrados em /etc/network.d
NETWORKS=()
# Especifique o nome da sua interface com fio para net-auto-wired
WIRED_INTERFACE="wlp12s0b1"
# Especifique o nome da sua interface sem fio para net-auto-wireless
WIRELESS_INTERFACE="$WIRELESS_DEVICE"
# Matriz de perfis que podem ser iniciados pelo net-auto-wireless.
# Quando não especificado, todos os perfis sem fio são considerados.
#AUTO_PROFILES=("profile1" "profile2")
EOF
}

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
