#!/bin/bash

set -e

ln -sf /usr/share/zoneinfo/$Q_TIMEZONE /etc/localtime
hwclock --systohc

echo $Q_HOSTNAME > /etc/hostname

echo "127.0.0.1   localhost
::1         localhost
127.0.1.1   $Q_HOSTNAME.localdomain  $Q_HOSTNAME">>/etc/hosts

echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
if ! [ "$Q_LOCALE" = "en_US" ]; then
    echo "$Q_LOCALE.UTF-8 UTF-8" >>/etc/locale.gen
fi
locale-gen

echo "export LANG=\"$Q_LOCALE.UTF-8\"
export LC_COLLATE=\"C\"">/etc/locale.conf

echo "KEYMAP=$Q_KEYMAP">/etc/vconsole.conf

source /etc/locale.conf

umount /tmp || true

sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 25/g' /etc/pacman.conf
sed -i 's/#Color/Color/g' /etc/pacman.conf
sed -i 's/#VerbosePkgLists/VerbosePkgLists/g' /etc/pacman.conf

sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$(nproc)\"/g" /etc/makepkg.conf

pacman-key --populate artix

ARCH_SUPP_TMPDIR=$(mktemp -d)
cd $ARCH_SUPP_TMPDIR
wget -r -nd --no-parent -A 'artix-archlinux-support-*.pkg.tar.zst' https://universe.artixlinux.org/x86_64/
wget -r -nd --no-parent -A 'archlinux-keyring-*.pkg.tar.zst' https://universe.artixlinux.org/x86_64/
wget -r -nd --no-parent -A 'archlinux-mirrorlist-*.pkg.tar.zst' https://universe.artixlinux.org/x86_64/
pacman --needed --noconfirm -U *
cd
rm -rf $ARCH_SUPP_TMPDIR

pacman-key --populate archlinux

cat <<'EOF' >>/etc/pacman.conf
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[community]
Include = /etc/pacman.d/mirrorlist-arch
EOF

curl -s 'https://download.opensuse.org/repositories/home:/ungoogled_chromium/Arch/x86_64/home_ungoogled_chromium_Arch.key' | pacman-key -a -

cat <<'EOF' >>/etc/pacman.conf
[home_ungoogled_chromium_Arch]
SigLevel = Required TrustAll
Server = https://download.opensuse.org/repositories/home:/ungoogled_chromium/Arch/$arch
EOF

while ! pacman -Syu --noconfirm; do
    true
done

while ! pacman -S reflector --noconfirm --needed; do
    true
done

echo "Please wait, ranking mirrors..."
reflector --latest 6 --protocol https --sort rate --save /etc/pacman.d/mirrorlist-arch

while ! pacman -Syu --noconfirm; do
    true
done

mkdir -p /boot/EFI/BOOT
mkdir -p /etc/pacman.d/hooks
cat <<'EOF' >/etc/pacman.d/hooks/edk2shell.hook
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = edk2-shell

[Action]
Description = Deploying EDK2 shell after upgrade...
When = PostTransaction
Exec = /bin/cp /usr/share/edk2-shell/x64/Shell_Full.efi /boot/EFI/BOOT/
EOF

while ! pacman -S base-devel mkinitcpio linux linux-firmware linux-headers linux-api-headers intel-ucode amd-ucode python artools-base metalog metalog-runit chrony cronie cronie-runit ufw ufw-runit audit audit-runit dhcpcd dhcpcd-runit cryptsetup cryptsetup-runit pcre inetutils git nano vim vi man-db man-pages bash-completion wget wpa_supplicant neofetch ntfs-3g efibootmgr usbutils dosfstools openssh parted pv p7zip zip unzip net-tools wireless-regdb xdg-user-dirs edk2-shell dialog help2man gettext htop lm_sensors tree --noconfirm --needed; do
    true
done

mkdir -p /etc/pacman.d/hooks
cat <<'EOF' >/etc/pacman.d/hooks/mirrorupgrade.hook
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = archlinux-mirrorlist

[Action]
Description = Updating archlinux-mirrorlist with reflector and removing pacnew...
When = PostTransaction
Depends = reflector
Exec = /bin/sh -c "reflector --latest 6 --protocol https --sort rate --save /etc/pacman.d/mirrorlist-arch && rm -f /etc/pacman.d/mirrorlist-arch.pacnew"
EOF

passwd -l root

useradd -m $Q_USERNAME
printf "$Q_USER_PASSWD\n$Q_USER_PASSWD\n" | passwd $Q_USERNAME

groupadd sudo

usermod -aG wheel $Q_USERNAME
usermod -aG sudo $Q_USERNAME
usermod -aG audio $Q_USERNAME
usermod -aG video $Q_USERNAME
usermod -aG floppy $Q_USERNAME
usermod -aG optical $Q_USERNAME
usermod -aG kvm $Q_USERNAME
usermod -aG uucp $Q_USERNAME
usermod -aG games $Q_USERNAME
usermod -aG log $Q_USERNAME
usermod -aG scanner $Q_USERNAME
usermod -aG rfkill $Q_USERNAME

sed -i 's/# %sudo\tALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers

Q_KERNEL_CMDLINE_COMMON=""

if [ "$Q_ENCRYPT" = "y" ]; then
    Q_KERNEL_CMDLINE="root=UUID=$Q_ROOT_DEVICE_X_UUID rw cryptdevice=UUID=$Q_ROOT_DEVICE_UUID:cryptroot $Q_KERNEL_CMDLINE_COMMON"
    sed -i 's/block filesystems/block encrypt filesystems/g' /etc/mkinitcpio.conf

    if ! [ -z "$Q_HOME_DEVICE" ]; then
        echo "crypthome UUID=$Q_HOME_DEVICE_UUID none" >/etc/crypttab
    fi
else
    Q_KERNEL_CMDLINE="root=UUID=$Q_ROOT_DEVICE_UUID rw $Q_KERNEL_CMDLINE_COMMON"
fi

mkdir -p /etc/pacman.d/hooks

cat >/etc/pacman.d/hooks/liminedeploy.hook <<EOF
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = limine

[Action]
Description = Deploying Limine after upgrade...
When = PostTransaction
Exec = /bin/sh -c "limine-deploy $Q_BOOTLOAD_DEVICE && /bin/cp /usr/share/limine/limine.sys /boot/ && /bin/cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/"
EOF

su - $Q_USERNAME <<EOF

set -e

cd
git clone https://aur.archlinux.org/aura-bin.git
cd aura-bin
while ! makepkg -si --noconfirm; do
    true
done
cd ..
rm -rf aura-bin
sudo pacman -Qdtq | sudo pacman -Rs - --noconfirm || true

while ! sudo aura -Aax limine --noconfirm; do
    true
done
sudo pacman -Qdtq | sudo pacman -Rs - --noconfirm || true

EOF

if ! [ "$Q_SUDONOPASSWD" = "y" ]; then
    sed -i 's/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/%sudo ALL=(ALL:ALL) ALL/g' /etc/sudoers
fi

cat <<EOF >/boot/limine.cfg
TIMEOUT=5

:Artix Linux

PROTOCOL=linux
CMDLINE=$Q_KERNEL_CMDLINE
KERNEL_PATH=boot:///vmlinuz-linux
MODULE_PATH=boot:///intel-ucode.img
MODULE_PATH=boot:///amd-ucode.img
MODULE_PATH=boot:///initramfs-linux.img

:Artix Linux (fallback)

PROTOCOL=linux
CMDLINE=$Q_KERNEL_CMDLINE
KERNEL_PATH=boot:///vmlinuz-linux
MODULE_PATH=boot:///intel-ucode.img
MODULE_PATH=boot:///amd-ucode.img
MODULE_PATH=boot:///initramfs-linux-fallback.img

:UEFI shell

PROTOCOL=chainload
IMAGE_PATH=boot:///EFI/BOOT/Shell_Full.efi
EOF

cat >/etc/nanorc <<'EOF'
set nowrap
set softwrap
set historylog
set tabsize 4
set tabstospaces
include /usr/share/nano/*.nanorc
include /usr/share/nano/extra/*.nanorc
EOF

cat >/etc/chrony.conf <<'EOF'
# Use public NTP servers from the pool.ntp.org project.
pool pool.ntp.org iburst

# Record the rate at which the system clock gains/losses time.
driftfile /var/lib/chrony/drift

# Allow the system clock to be stepped in the first three updates
# if its offset is larger than 1 second.
makestep 1.0 3

# Enable kernel synchronization of the real-time clock (RTC).
rtconutc
rtcsync
EOF

pacman -Qdtq | pacman -Rs - --noconfirm || true

sed -i 's/ENABLED=no/ENABLED=yes/g' /etc/ufw/ufw.conf

cat <<'EOF' >/usr/lib/rc/sv.d/clear-tmp
#!/bin/bash

# sourcing our current rc.conf requires this to be a bash script
. /usr/lib/rc/functions

case "$1" in
    start)
        stat_busy "Starting clear-tmp"
        /bin/rm -rf /tmp/{.*,*} &>/dev/null || true
        add_daemon clear-tmp
        stat_done clear-tmp
        ;;
    *)
        echo "usage: $0 {start}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/lib/rc/sv.d/clear-tmp
ln -s /usr/lib/rc/sv.d/clear-tmp /etc/rc/sysinit/66-clear-tmp

cp /artix-installer/crontab /var/spool/cron/root
cp /artix-installer/sync-clock /usr/local/bin/
/artix-installer/sync-clock

mkinitcpio -P

mv /artix-installer /home/$Q_USERNAME/
chown -R $Q_USERNAME:$Q_USERNAME /home/$Q_USERNAME/artix-installer
su -c "cd artix-installer && ./userside.sh" - $Q_USERNAME

sync
