#!/bin/bash
set -e

echo "========================================="
echo "   Antigravity OS - Arch Linux Installer "
echo "========================================="

if [ -z "$1" ]; then
    echo "Error: No target drive specified."
    echo "Usage: ./install.sh <target_drive>"
    echo "Example: ./install.sh /dev/nvme0n1"
    echo ""
    echo "Available drives:"
    lsblk -d -n -p -o NAME,SIZE,MODEL
    exit 1
fi

TARGET=$1

echo ""
echo "!!! WARNING: DATA LOSS IMMINENT !!!"
echo "This will completely WIPE the drive: $TARGET"
echo "Make sure this is NOT your Windows SSD!"
read -p "Are you absolutely sure you want to continue? [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation aborted."
    exit 0
fi

echo "==> Wiping and partitioning $TARGET..."
parted -s "$TARGET" mklabel gpt
parted -s "$TARGET" mkpart primary fat32 1MiB 513MiB
parted -s "$TARGET" set 1 esp on
parted -s "$TARGET" mkpart primary linux-swap 513MiB 8705MiB
parted -s "$TARGET" mkpart primary ext4 8705MiB 100%

# Determine partition names correctly (nvme drives use 'p' suffix for partitions)
PART_PREFIX="${TARGET}"
if [[ "$TARGET" == *nvme* ]]; then
    PART_PREFIX="${TARGET}p"
fi

echo "==> Formatting partitions..."
mkfs.fat -F32 "${PART_PREFIX}1"
mkswap "${PART_PREFIX}2"
swapon "${PART_PREFIX}2"
mkfs.ext4 -F "${PART_PREFIX}3"

echo "==> Mounting partitions..."
mount "${PART_PREFIX}3" /mnt
mkdir -p /mnt/boot/efi
mount "${PART_PREFIX}1" /mnt/boot/efi

echo "==> Installing base system and packages..."
# Read the base packages from the ISO, and fetch the heavy GUI packages directly from the internet!
pacstrap -K /mnt - < /root/packages.x86_64 base-devel linux-headers os-prober ntfs-3g neovim hyprland kitty waybar wofi sddm polkit-kde-agent nvidia-dkms nvidia-utils intel-ucode firefox gtk3 nss alsa-lib libxss xdg-utils fuse2

echo "==> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Configuring system..."

cat << 'EOF' > /mnt/root/chroot_install.sh
#!/bin/bash
set -e

echo "==> Setting timezone and locale..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "antigravity-os" > /etc/hostname

echo "==> Setting up users..."
echo "root:password" | chpasswd
useradd -m -G wheel -s /bin/bash antigravity
echo "antigravity:password" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

echo "==> Configuring NetworkManager..."
systemctl enable NetworkManager

echo "==> Configuring SDDM (Login Manager)..."
systemctl enable sddm

echo "==> Configuring GRUB & os-prober for Dual Boot..."
# Uncomment GRUB_DISABLE_OS_PROBER so it finds Windows
sed -i 's/.*GRUB_DISABLE_OS_PROBER.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
# Mount all partitions just in case ntfs-3g needs to see the Windows EFI
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=AntigravityOS
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Installing Antigravity IDE..."
mkdir -p /opt/antigravity
echo "Downloading Antigravity IDE..."
curl -L -o /tmp/antigravity.tar.gz "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"
echo "Extracting..."
tar -xzf /tmp/antigravity.tar.gz -C /opt/antigravity

# Create a desktop entry for Hyprland/Wofi to find
cat << 'DESKTOP' > /usr/share/applications/antigravity.desktop
[Desktop Entry]
Name=Antigravity IDE
Comment=AI-Powered IDE
Exec=/opt/antigravity/antigravity
Icon=utilities-terminal
Type=Application
Categories=Development;
DESKTOP

echo "==> Installation complete inside chroot!"
EOF

chmod +x /mnt/root/chroot_install.sh
arch-chroot /mnt /root/chroot_install.sh
rm /mnt/root/chroot_install.sh

echo "==> Unmounting..."
umount -R /mnt
echo "====================================================="
echo " ALL DONE! "
echo " You can now reboot and set your BIOS to boot from "
echo " the NVMe drive. GRUB will let you pick Windows or Arch!"
echo "====================================================="
