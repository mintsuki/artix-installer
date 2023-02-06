#!/bin/bash

set -e

### Warnings ###

echo "Before running the script, create a boot, a root, and (optionally) a home partition."
echo "The root and boot partitions are MANDATORY for the script to work."
echo ""
echo "You do not need to mount them, just remember which ones they are."
echo ""
echo "Enter to continue, CTRL-C to abort..."
read

# Use dhcpcd instead of connmand

echo "Please wait, moving from connmand to dhcpcd..."
sv stop connmand
sleep 5
ln -s /etc/runit/sv/dhcpcd /var/run/runit/service/ || true
sleep 10

while true; do
    printf "Keyboard layout (eg. us): "
    read Q_KEYMAP
    if [ -z "$Q_KEYMAP" ]; then
        continue
    fi
    break
    loadkeys $Q_KEYMAP
done

### DNS ###

printf "Use manual DNS servers? [y/N]: "
read Q_SETUP_CUSTOM_DNS
if [ "$Q_SETUP_CUSTOM_DNS" = "y" ]; then
    echo "nohook resolv.conf" >> /etc/dhcpcd.conf
    rm /etc/resolv.conf &> /dev/null || true
    while true; do
        printf "Add custom nameserver IP (enter for done): "
        read Q_NEW_NAMESERVER_IP
        if [ -z "$Q_NEW_NAMESERVER_IP" ]; then
            sv restart dhcpcd
            break
        fi
        echo "nameserver $Q_NEW_NAMESERVER_IP" >> /etc/resolv.conf
    done
fi

### WiFi ###

cat >/etc/wpa_supplicant/wpa_supplicant.conf <<EOF
# Default configuration file for wpa_supplicant.conf(5).

ctrl_interface=/run/wpa_supplicant
ctrl_interface_group=wheel
eapol_version=1
ap_scan=1
fast_reauth=1
update_config=1

# Add here your networks.
EOF

ln -s /usr/share/dhcpcd/hooks/10-wpa_supplicant /usr/lib/dhcpcd/dhcpcd-hooks/ &> /dev/null || true

while true; do
    printf "WiFi region? (eg: US): "
    read Q_WIFI_REGION
    if [ -z "$Q_WIFI_REGION" ]; then
        continue
    fi
    mkdir -p /etc/conf.d
    echo "WIRELESS_REGDOM=\"${Q_WIFI_REGION}\"" > /etc/conf.d/wireless-regdom
    break
done

printf "Use WiFi? [y/N]: "
read Q_SETUP_CUSTOM_WIFI
if [ "$Q_SETUP_CUSTOM_WIFI" = "y" ]; then
    rfkill unblock all || true
    ip link show
    printf "Select the WiFi interface to use: "
    read Q_DEFAULT_WIFI_INTERFACE
    cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-"$Q_DEFAULT_WIFI_INTERFACE".conf
    ip link set up "$Q_DEFAULT_WIFI_INTERFACE"
    printf "Network SSID: "
    read Q_WIFI_NETWORK_SSID
    printf "Network passphrase: "
    read Q_WIFI_NETWORK_PASSPHRASE
    wpa_passphrase "$Q_WIFI_NETWORK_SSID" "$Q_WIFI_NETWORK_PASSPHRASE" >> /etc/wpa_supplicant/wpa_supplicant-"$Q_DEFAULT_WIFI_INTERFACE".conf
    sv restart dhcpcd
    echo "Waiting for network connectivity..."
    while [ -z "$(ip r | grep default | cut -d ' ' -f 3)" ]; do sleep 0.1; done
    unset Q_WIFI_NETWORK_SSID
    unset Q_WIFI_NETWORK_PASSPHRASE
fi

pacman-key --populate artix
while ! pacman -Sy --noconfirm; do
    true
done

while ! pacman -S artix-keyring --noconfirm; do
    true
done

pacman-key --populate artix

while ! pacman -Sy --noconfirm; do
    true
done

while true; do
    printf "Username: "
    read Q_USERNAME
    if [ -z "$Q_USERNAME" ]; then
        continue
    fi
    break
done

while true; do
    printf "User password: "
    read -s Q_USER_PASSWD
    if [ -z "$Q_USER_PASSWD" ]; then
        continue
    fi
    printf "User password (again): "
    read -s Q_USER_PASSWD_1
    if ! [ "$Q_USER_PASSWD" = "$Q_USER_PASSWD_1" ]; then
        echo "Passwords do not match."
    else
        break
    fi
done

printf "\nUse sudo without password? [y/N]: "
read Q_SUDONOPASSWD

while true; do
    printf "Hostname: "
    read Q_HOSTNAME
    if [ -z "$Q_HOSTNAME" ]; then
        continue
    fi
    break
done
while true; do
    printf "Timezone (eg. Europe/London): "
    read Q_TIMEZONE
    if [ -z "$Q_TIMEZONE" ]; then
        continue
    fi
    break
done
while true; do
    printf "Locale (eg. en_US): "
    read Q_LOCALE
    if [ -z "$Q_LOCALE" ]; then
        continue
    fi
    break
done

### Partitions ###

lsblk
while true; do
    printf "Boot partition device (full path eg. /dev/sda1): "
    read Q_BOOT_DEVICE
    if [ -z "$Q_BOOT_DEVICE" ]; then
        continue
    fi
    break
done
while true; do
    printf "Root partition device (full path eg. /dev/sda2): "
    read Q_ROOT_DEVICE
    if [ -z "$Q_ROOT_DEVICE" ]; then
        continue
    fi
    break
done

printf "Home partition device (full path eg. /dev/sda3, empty for none): "
read Q_HOME_DEVICE
if ! [ -z "$Q_HOME_DEVICE" ]; then
    printf "Format home partition? (not formatting preserves old data, MUST format for a first run, if the partition is unformatted) [y/N]: "
    read Q_FORMAT_HOME
fi

while true; do
    printf "Bootloader device (full path OF THE BASE DEVICE eg. /dev/sda): "
    read Q_BOOTLOAD_DEVICE
    if [ -z "$Q_BOOTLOAD_DEVICE" ]; then
        continue
    fi
    break
done

printf "Enable encryption? [y/N]: "
read Q_ENCRYPT

if [ "$Q_ENCRYPT" = "y" ]; then
    while true; do
        printf "Encryption passphrase: "
        read -s Q_CRYPT_PASS
        if [ -z "$Q_CRYPT_PASS" ]; then
            continue
        fi
        printf "Encryption passphrase (again): "
        read -s Q_CRYPT_PASS_1
        if ! [ "$Q_CRYPT_PASS" = "$Q_CRYPT_PASS_1" ]; then
            echo "Passwords do not match."
        else
            break
        fi
    done
    printf "$Q_CRYPT_PASS" | cryptsetup -y -v luksFormat "$Q_ROOT_DEVICE"
    printf "$Q_CRYPT_PASS" | cryptsetup open "$Q_ROOT_DEVICE" cryptroot
    Q_ROOT_DEVICE_X=/dev/mapper/cryptroot
    if ! [ -z "$Q_HOME_DEVICE" ]; then
        if [ "$Q_FORMAT_HOME" = "y" ]; then
            printf "$Q_CRYPT_PASS" | cryptsetup -y -v luksFormat "$Q_HOME_DEVICE"
        fi
        printf "$Q_CRYPT_PASS" | cryptsetup open "$Q_HOME_DEVICE" crypthome
        Q_HOME_DEVICE_X=/dev/mapper/crypthome
    fi
else
    Q_ROOT_DEVICE_X="$Q_ROOT_DEVICE"
    if ! [ -z "$Q_HOME_DEVICE" ]; then
        Q_HOME_DEVICE_X="$Q_HOME_DEVICE"
    fi
fi

yes | mkfs.fat "$Q_BOOT_DEVICE"
yes | mkfs.ext4 "$Q_ROOT_DEVICE_X"
Q_ROOT_DEVICE_UUID=$(blkid -s UUID -o value "$Q_ROOT_DEVICE")
Q_ROOT_DEVICE_X_UUID=$(blkid -s UUID -o value "$Q_ROOT_DEVICE_X")
mount "$Q_ROOT_DEVICE_X" /mnt

if ! [ -z "$Q_HOME_DEVICE" ]; then
    if [ "$Q_FORMAT_HOME" = "y" ]; then
        yes | mkfs.ext4 "$Q_HOME_DEVICE_X"
    fi
    Q_HOME_DEVICE_UUID=$(blkid -s UUID -o value "$Q_HOME_DEVICE")
    Q_HOME_DEVICE_X_UUID=$(blkid -s UUID -o value "$Q_HOME_DEVICE_X")
    mkdir /mnt/home
    mount "$Q_HOME_DEVICE_X" /mnt/home
fi

mkdir /mnt/boot
mount "$Q_BOOT_DEVICE" /mnt/boot

### System install ###

while ! basestrap /mnt base runit elogind-runit wget; do
    true
done

fstabgen -U /mnt >>/mnt/etc/fstab

cp -rv . /mnt/artix-installer

artix-chroot /mnt <<EOF

set -e

bash /dev/stdin

set -e

export Q_USERNAME="$Q_USERNAME"
export Q_SUDONOPASSWD="$Q_SUDONOPASSWD"
export Q_BOOTLOAD_DEVICE="$Q_BOOTLOAD_DEVICE"
export Q_ROOT_DEVICE_UUID="$Q_ROOT_DEVICE_UUID"
export Q_ROOT_DEVICE_X_UUID="$Q_ROOT_DEVICE_X_UUID"
export Q_HOME_DEVICE="$Q_HOME_DEVICE"
export Q_HOME_DEVICE_UUID="$Q_HOME_DEVICE_UUID"
export Q_HOME_DEVICE_X_UUID="$Q_HOME_DEVICE_X_UUID"
export Q_ENCRYPT="$Q_ENCRYPT"
export Q_USER_PASSWD="$Q_USER_PASSWD"
export Q_HOSTNAME="$Q_HOSTNAME"
export Q_TIMEZONE="$Q_TIMEZONE"
export Q_KEYMAP="$Q_KEYMAP"
export Q_LOCALE="$Q_LOCALE"

history -c

/artix-installer/chrootside.sh

exit

EOF

rm -f /mnt/root/.bash_history
rm -rf /mnt/tmp/{.*,*} || true

ln -s /etc/runit/sv/auditd /mnt/etc/runit/runsvdir/default/
ln -s /etc/runit/sv/metalog /mnt/etc/runit/runsvdir/default/
ln -s /etc/runit/sv/dhcpcd /mnt/etc/runit/runsvdir/default/
ln -s /etc/runit/sv/ufw /mnt/etc/runit/runsvdir/default/
ln -s /etc/runit/sv/cronie /mnt/etc/runit/runsvdir/default/

if [ "$Q_SETUP_CUSTOM_DNS" = "y" ]; then
    cp -v /etc/dhcpcd.conf /mnt/etc/
fi

cp -v /etc/resolv.conf /mnt/etc/

cp -rv /etc/wpa_supplicant /mnt/etc/
ln -s /usr/share/dhcpcd/hooks/10-wpa_supplicant /mnt/usr/lib/dhcpcd/dhcpcd-hooks/ &> /dev/null || true

mkdir -p /mnt/etc/conf.d
cp -v /etc/conf.d/wireless-regdom /mnt/etc/conf.d/

sync

umount -R /mnt
if [ "$Q_ENCRYPT" = "y" ]; then
    if ! [ -z "$Q_HOME_DEVICE" ]; then
        cryptsetup close crypthome
    fi
    cryptsetup close cryptroot
fi

sync

echo ""
echo "Finished successfully!"
