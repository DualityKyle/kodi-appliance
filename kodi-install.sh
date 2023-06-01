#!/usr/bin/env bash

welcome () {
    # Set script directory
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Check whether device supports UEFI/bluetooth
    UEFI_SUPPORT=false
    BT_SUPPORT=false
    if [[ -d /sys/firmware/efi ]]; then
        UEFI_SUPPORT=true
    fi
    if dmesg | grep -iq "bluetooth"; then
        BT_SUPPORT=true
    fi

    dialog --title "Kodi Standalone Appliance Installer" \
    --ok-label "Continue" --msgbox "Welcome to the installation \
script for your standalone Kodi appliance. You can use the ARROW \
keys and the SPACE or ENTER keys to navigate and select your \
desired options for your appliance." 12 70
}

# Check if there is an internet connection
network_check () {
    dialog --infobox "Making sure we have internet..." 3 50
    if ! nc -zw1 archlinux.org 443; then
        dialog --title "Kodi Standalone Appliance Installer" \
            --msgbox "We were unable to detect a working internet connection. \
Ensure your ethernet cable is securely plugged in. If you are connecting via \
wi-fi, use the \"iwctl\" command to connect to a wi-fi network.\n\nAfter correcting \
your connection issue, try running the installer again." 10 80
        reset;
        exit 1
    fi
}

# Gather the basics
# Set keyboard layout
set_keymap () {
    while true; do
        KEYMAP=$(dialog --title "Set Appliance Keyboard Layout" --nocancel \
        --default-item "us" --menu "Select the keyboard layout you wish to use on \
your appliance. Some common ones are listed below. If you don't see your preferred \
layout, choose \"other\".\n\nSelect keyboard layout:" 22 57 10 \
"us" "United States" \
"fr" "French" \
"de" "German" \
"gr" "Greek" \
"hu" "Hungarian" \
"it" "Italian" \
"pl" "Polish" \
"ru" "Russian" \
"es" "Spanish" \
"other" "View all available layouts" 3>&1 1>&2 2>&3)

        if [[ "$KEYMAP" = "other" ]]; then
            keymaps=()
            for layout in $(localectl list-keymaps); do
                keymaps+=("$layout" "")
            done
            KEYMAP=$(dialog --title "Set Appliance Keyboard Layout" --cancel-label "Back" \
                --menu "Select keyboard layout:" 30 60 25 "${keymaps[@]}" 3>&1 1>&2 2>&3)
            if [[ $? -eq 0 ]]; then
                break
            fi
        else
            break
        fi
    done
    dialog --infobox "Setting keyboard layout to $KEYMAP..." 3 50
    localectl set-keymap "$KEYMAP"
    loadkeys "$KEYMAP"
}

# Set locale
set_locale () {
    while true; do
        LOCALE=$(dialog --title "Set Appliance Locale" --nocancel \
        --default-item "en_US.UTF-8" --menu "Select the locale for your language \
and region. Some common locales are listed below. If yours is not listed, choose \
\"other\" to see the full list of locales.\n\nSelect locale:" 30 65 16 \
"en_US.UTF-8" "English (United States)" \
"en_CA.UTF-8" "English (Canada)" \
"en_GB.UTF-8" "English (United Kingdom)" \
"zh_CN.UTF-8" "Chinese (Simplified)" \
"fr_FR.UTF-8" "French (France)" \
"de_DE.UTF-8" "German (Germany)" \
"hi_IN.UTF-8" "Hindi (India)" \
"it_IT.UTF-8" "Italian (Italy)" \
"ja_JP.UTF-8" "Japanese (Japan)" \
"ko_KR.UTF-8" "Korean (Korea)" \
"pt_BR.UTF-8" "Portuguese (Brazil)" \
"ru_RU.UTF-8" "Russian (Russia)" \
"es_ES.UTF-8" "Spanish (Spain)" \
"sv_SE.UTF-8" "Swedish (Sweden)" \
"other" "View all available locales" 3>&1 1>&2 2>&3)

        if [[ "$LOCALE" = "other" ]]; then
            locales=()
            # Read all entries in /etc/locale.gen, removing all extra characters
            while read -r line; do
                locales+=("$line" "")
            done < <(grep -E "^#?[a-z].*UTF-8" /etc/locale.gen | sed -e 's/#//' -e 's/\s.*$//')
            LOCALE=$(dialog --title "Set Appliance Locale" --cancel-label "Back" \
                --menu "Select Locale:" 30 65 16 "${locales[@]}" 3>&1 1>&2 2>&3)
            if [[ $? -eq 0 ]]; then
                break
            fi
        else
            break
        fi
    done
}

# Set timezone
set_timezone () {
    UTC_TIME=true
    regions=()
    for region in $(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | grep -E -v '/$|posix|right' | sort); do
        regions+=("$region" "")
    done
    regions+=("other" "")

    while true; do
        TIME_ZONE=$(dialog --title "Set Appliance Time Zone" --nocancel \
            --menu "Choose your time zone.\nIf your region is not listed, \
select \"other\".\n\nSelect time zone:" 27 50 17 "${regions[@]}" 3>&1 1>&2 2>&3)

        if [[ "$TIME_ZONE" != "other" ]]; then
            zone_regions=()
            for zone_region in $(find /usr/share/zoneinfo/"${TIME_ZONE}" \
            -mindepth 1 -maxdepth 1 -printf '%f\n' | sort); do
                zone_regions+=("$zone_region" "")
            done
            SUB_ZONE=$(dialog --title "Set Appliance Time Zone" --cancel-label "Back" \
                --menu "Select time zone:" 27 50 17 "${zone_regions[@]}" 3>&1 1>&2 2>&3)
            if [[ $? -eq 0 ]]; then
                if [[ -d /usr/share/zoneinfo/"${TIME_ZONE}/${SUB_ZONE}" ]]; then
                    subzone_regions=()
                    for subzone_region in $(find /usr/share/zoneinfo/"${TIME_ZONE}/${SUB_ZONE}" \
                    -mindepth 1 -maxdepth 1 -printf '%f\n' | sort); do
                        subzone_regions+=("$subzone_region" "")
                    done
                    SUBZONE_SUBREGION=$(dialog --title "Set Appliance Time Zone" \
                        --cancel-label "Back" --menu "Select time zone:" 27 50 17 \
                        "${subzone_regions[@]}" 3>&1 1>&2 2>&3)
                    if [[ $? -eq 0 ]]; then
                        TIME_ZONE="${TIME_ZONE}/${SUB_ZONE}/${SUBZONE_SUBREGION}"
                        break
                    fi
                else
                    TIME_ZONE="${TIME_ZONE}/${SUB_ZONE}"
                    break
                fi
            fi
        else
            for other_region in $(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type f -printf '%f\n' \
            | grep -E -v '/$|iso3166.tab|leapseconds|posixrules|tzdata.zi|zone.tab|zone1970.tab' | sort); do
                other_regions+=("$other_region" "")
            done
            TIME_ZONE=$(dialog --title "Set Appliance Time Zone" --cancel-label "Back" \
                --menu "Select time zone:" 27 50 17 "${other_regions[@]}" 3>&1 1>&2 2>&3)
            if [[ $? -eq 0 ]]; then
                TIME_ZONE="${TIME_ZONE}"
                break
            fi
        fi
    done

    dialog --title "Set Appliance Clock" --nocancel \
        --yesno "Would you like to use UTC time for the system clock? If you choose \"no\", \
then local time will be used instead.\n\nIf you are not sure, the default is UTC." 8 85
    if [[ $? -ne 0 ]]; then
        UTC_TIME=false
    fi
}

set_hostname () {
    while true; do
        HOST_NAME=$(dialog --title "Set Appliance Hostname" --nocancel \
            --inputbox "Please enter the hostname for the appliance. \
            \n\nHostname:" 12 80 3>&1 1>&2 2>&3)
        
        # Ensure the hostname is valid (alphanumeric only with optional dash)
        if printf "%s" "$HOST_NAME" | grep -Eoq "^[a-zA-Z0-9-]{1,63}$" \
        && [[ "${HOST_NAME:0:1}" != "-" ]] \
        && [[ "${HOST_NAME: -1}" != "-" ]]; then
            break
        else
            dialog --title "Set Appliance Hostname" \
                --msgbox "ERROR: Invalid Hostname Format! Machine hostnames may be \
a maximum of 63 characters long and contain only alphanumeric characters or dashes. \
Hostnames must also NOT begin or end with a dash." 9 75
        fi
    done
}


#Set user info
set_userinfo () {
    while true; do
        USER_NAME=$(dialog --title "Create Appliance User" --nocancel \
            --inputbox "Please enter a username for the main account for \
your appliance. If you do not enter a username, the default user \"htpc\" \
will be used.\n\nEnter username:" 13 40 3>&1 1>&2 2>&3)
        # If the username field is blank, set to "htpc"
        if [[ "${#USER_NAME}" -eq 0 ]]; then
            USER_NAME="htpc"
            pw_match=false
            while ! $pw_match; do
                PASSWORD1=$(dialog --title "Create Appliance User" \
                --clear --stdout --nocancel --insecure \
                --passwordbox "Please enter a password for user '$USER_NAME'.\n\nPassword:" 10 70)

                if [[ -z "$PASSWORD1" ]]; then
                    dialog --title "ERROR: Empty Password" \
                    --msgbox "You are not allowed to have an empty password." 5 55
                else
                    PASSWORD2=$(dialog --title "Create Appliance User" \
                    --clear --stdout --insecure \
                    --passwordbox "Re-enter password to verify:" 8 55)
                    if [ "$PASSWORD1" != "$PASSWORD2" ]; then
                        dialog --title "ERROR: Passwords Do No Match" \
                        --msgbox "The two passwords you entered did not match." 5 55
                    else
                        USER_PW="$PASSWORD1"
                        pw_match=true
                    fi
                fi
            done            
            break
            # Check if username is valid (no symbols, 32 chars or less)
        elif printf "%s" "$USER_NAME" | grep -Eoq "^[a-z][a-z0-9-]*$" \
            && [[ "${#USER_NAME}" -lt 33 ]]; then
            # Check that entered username isn't on the reserved list
            if grep -Fxq "$USER_NAME" "$DIR"/config/reserved_usernames; then
                dialog --title "Create Appliance User" \
                --msgbox "ERROR! The username you entered ($USER_NAME) is reserved \
                for use by the system. Please select a different one." 6 70
            elif printf "%s" "$USER_NAME" | grep -w kodi; then
                dialog --title "Create Appliance User" \
                --msgbox "The \"kodi\" username is reserved for use by the \
                Kodi standalone daemon. Please select a different one." 6 70
            else
                pw_match=false
                while ! $pw_match; do
                    PASSWORD1=$(dialog --title "Create Appliance User" \
                    --clear --stdout --nocancel --insecure \
                    --passwordbox "Please enter a password for user '$USER_NAME'.\n\nPassword:" 10 70)
                    
                    if [[ -z "$PASSWORD1" ]]; then
                        dialog --title "ERROR: Empty Password" \
                        --msgbox "You are not allowed to have an empty password." 5 55
                    else
                        PASSWORD2=$(dialog --title "Create Appliance User" \
                        --clear --stdout --insecure \
                        --passwordbox "Re-enter password to verify:" 8 55)
                        if [ "$PASSWORD1" != "$PASSWORD2" ]; then
                            dialog --title "ERROR: Passwords Do No Match" \
                            --msgbox "The two passwords you entered did not match." 5 55
                        else
                            USER_PW="$PASSWORD1"
                            pw_match=true
                        fi
                    fi
                done
                FULL_NAME=$(dialog --title "Create Appliance User" --nocancel \
                    --inputbox "Please enter the real name (display name) for the \
appliance user. It is recommended to enter this information, but it may be \
left blank.\n\nEnter display name:" 15 80 3>&1 1>&2 2>&3)
                # End the main loop
                break
            fi
        else
            dialog --title "Create Appliance User" \
            --msgbox "ERROR! You entered an invalid username! Usernames must be \
all lower-case, begin with a letter, and be followed by any combination of \
alphanumeric characters or the dash symbol, and must be no more than 32 \
characters long." 9 80
        fi
    done
}

# Create a password for the root user
set_root_pw () {
    root_match=false
    while ! $root_match; do
        ROOT_PW1=$(dialog --title "Create Root Password" --clear --stdout \
        --nocancel --insecure --passwordbox "Please enter a password \
for the root account.\n\nPassword:" 10 75)

        if [[ -z "$ROOT_PW1" ]]; then
            dialog --title "Create Root Password" \
                --msgbox "ERROR! The root password may not be blank." 5 55
        else
            ROOT_PW2=$(dialog --title "Create Root Password" --clear \
            --stdout --insecure --passwordbox "Confirm password:" 8 55)            
            if [[ "$ROOT_PW1" != "$ROOT_PW2" ]]; then
                dialog --title "Create Root Password" \
                    --msgbox "ERROR! Entered passwords do not match." 5 55
            else
                ROOT_PW="$ROOT_PW1"
                root_match=true
            fi
        fi
    done
}

format_disk () {
    ENABLE_SWAP=false
    drives=()
    for drive_name in $(lsblk -dnpr -e 7,11 -o NAME); do
        drive_size=$(lsblk -dnr -o SIZE "$drive_name")
        drives+=("$drive_name" "$drive_size")
    done

    while true; do
        DISK=$(dialog --title "Appliance Disk Setup" \
        --cancel-label "Back to Main Menu" \
        --menu "Select which disk you would like to install the appliance OS \
onto. Keep in mind this will erase all data on the disk, but not until you \
confim the changes.\n\nChoose disk:" 16 55 5 "${drives[@]}" 3>&1 1>&2 2>&3)
        
        # NVMe partitions are named differently so check if disk is NVMe
        if [[ $? -eq 0 ]]; then
            PARTITION_PREFIX=""
            if [[ "$DISK" == *"nvme"* ]]; then
                PARTITION_PREFIX="p"
            fi
            
            FILE_SYSTEM=$(dialog --title "Appliance Disk Setup" --nocancel \
            --menu "Select which type of filesystem you want to use on the OS \
drive. It is recommended to use ext4 unless you have a specific reason to use a \
different filesystem.\n\nChoose filesystem:" 16 68 5 \
"ext4" "Extended filesystem v4" \
"ext3" "Extended filesystem v3" \
"ext2" "Extended filesystem v2" \
"btrfs" "B-tree filesystem" \
"xfs" "XFS filesystem" 3>&1 1>&2 2>&3)

            while true; do
            ROOTFS_LABEL=$(dialog --title "Appliance Disk Setup" --nocancel \
            --inputbox "Please a label for the root filesystem. This gives your filesystem \
a friendly name to reference, and is also used when configuring the bootloader. The label must \
begin with a letter, and may be up to 16 characters. You may use any alphanumeric characters, \
dashes, or spaces. The label must end with an alphanumeric character. If left blank, a default \
label, \"KodiBoxFS\" will be used.\n\nEnter filesystem label:" 15 80 3>&1 1>&2 2>&3)
            if [[ "${#ROOTFS_LABEL}" -eq 0 ]]; then
                ROOTFS_LABEL="KodiBoxFS"
                break
            elif printf "%s" "$ROOTFS_LABEL" | grep -Eoq "^[a-zA-Z0-9 -]{1,16}$" \
            && [[ "${ROOTFS_LABEL:0:1}" != "-" ]] \
            && [[ "${ROOTFS_LABEL: -1}" != "-" ]] \
            && [[ "${ROOTFS_LABEL:0:1}" != " " ]] \
            && [[ "${ROOTFS_LABEL: -1}" != " " ]]; then
                break
            else
                dialog --title "Appliance Disk Setup" \
                    --msgbox "ERROR! You entered an invalid filesystem label. Labels must begin with \
and end with an alphanumeric character and be 16 characters or less. Additionally, they may only contain \
dashes or spaces in addition to alphanumeric characters." 15 80
            fi
            done

            dialog --title "Appliance Disk Setup" --yesno "Do you want to create \
a swap partition on your disk?" 6 57
            if [[ $? -eq 0 ]]; then
                while true; do
                    SWAP_SIZE=$(dialog --title "Appliance Disk Setup" --inputbox "Specify \
the amount of swap space (in GiB) that you want to allocate on your disk. Only enter \
the number. For example, if you want a swap partition size of 8 GiB, then simply \
enter \"8\".\n\nEnter swap partition size:" 11 80 3>&1 1>&2 2>&3)
                    if [[ $? -eq 0 ]]; then
                        disk_size=$(lsblk -bdn -o SIZE "$DISK")
                        disk_size_gib=$((disk_size/1024/1024/1024))

                        if [[ "$SWAP_SIZE" -gt $((disk_size_gib - 4)) ]]; then
                            dialog --title "Appliance Disk Setup" \
                            --msgbox "ERROR: The amount you entered for the swap partition \
exceeds the available space on your disk. Note that the install will prevent you from \
choosing a swap size that leaves less than 4 GiB of space on disk for the OS." 10 57
                        else
                            ENABLE_SWAP=true
                            break
                        fi
                    fi
                done
            fi
            # Phrase for swap selection
            if $ENABLE_SWAP; then
                swap_info="$SWAP_SIZE GiB"
            else
                swap_info="No swap"
            fi
            dialog --title "Confirm Appliance Disk Setup" --defaultno \
                --yesno "WARNING: All data on $DISK will be lost! Make sure to review your \
selections before continuing!\n\nFilesystem type: $FILE_SYSTEM\nSwap size: $swap_info\n\nAre \
you sure you want to destroy disk data and write the changes?" 13 60
            if [[ $? -eq 0 ]]; then
                # Erase all disk data
                dialog --infobox "Erasing data on $DISK..." 3 50
                sgdisk -Z "$DISK" &> /dev/null
                wipefs -a "$DISK" &> /dev/null
                # Partition disk
                dialog --infobox "Partitioning $DISK with $FILE_SYSTEM..." 3 50
                create_partition_table
                create_filesystem
                break
            else
                main_menu
            fi
        else
            main_menu
        fi
    done
}

create_partition_table () {
    # Set GPT for UEFI or MBR for BIOS systems
    if $UEFI_SUPPORT; then
        parted -s "$DISK" mklabel gpt &> /dev/null
    else
        parted -s "$DISK" mklabel msdos &> /dev/null
    fi
    # If any errors, abort install
    if [[ $? -ne 0 ]]; then
        dialog --title "ERRORS: Cannot partition $DISK" \
            --msgbox "An error was encountered while trying to partition $DISK. \
Ensure the selected disk is not active before running the install script.\n\n If \
the error keeps occurring, reboot the device and try again." 8 80
        reset;
        exit 1
    fi
}

create_filesystem () {
    # Create EFI partition for UEFI systems
    if $UEFI; then
        BOOT_PARTITION="${DISK}${PREFIX}1"
        ROOT_PARTITION="${DISK}${PREFIX}2"
        if $ENABLE_SWAP; then
            SWAP_PARTITION="${DISK}${PREFIX}3"
            sgdisk -n 1:0:+512M -n 2:0:-"${SWAP_SIZE}G" -n 3:-"${SWAP_SIZE}G":-0  \
                -t 1:ef00 -t 2:8300 -t 3:8200 "$DISK" &> /dev/null
            mkswap "$SWAP_PARTITION" &> /dev/null
            swapon "$SWAP_PARTITION"
            e2label "${DISK}${PREFIX}2" \"${ROOTFS_LABEL}\"
        else
            sgdisk -n 1:0:+512M -n 2:0:0 -t 1:ef00 -t 2:8300 "$DISK" &> /dev/null
            e2label "${DISK}${PREFIX}2" \"${ROOTFS_LABEL}\"
        fi
        mkfs.fat -F32 "$BOOT_PARTITION" &> /dev/null
    else
        ROOT_PARTITION="${DISK}${PREFIX}1"
        if $ENABLE_SWAP; then
            SWAP_PARTITION="${DISK}${PREFIX}2"
            echo -e "n\np\n1\n\n-${SWAP_SIZE}\nn\np\n2\n\n\nt\n2\n82\nw" \
                | fdisk "$DISK" &> /dev/null
            mkswap "$SWAP_PARTITION" &> /dev/null
            swapon "$SWAP_PARTITION"
        else
            echo -e "n\np\n1\n\n\nw" | fdisk "$DISK" &> /dev/null 
        fi
    fi

    # Format root partition with selected file system
    case "$FILE_SYSTEM" in
        btrfs|xfs) mkfs."$FILE_SYSTEM" -f "$ROOT_PARTITION" &> /dev/null ;;
        *) mkfs."$FILE_SYSTEM" "$ROOT_PARTITION" &> /dev/null ;;
    esac
    # Mount root partition
    mount "$ROOT_PARTITION" /mnt
    # If UEFI, mount EFI partition
    if $UEFI_SUPPORT; then
        mkdir /mnt/boot
        mount "$BOOT_PARTITION" /mnt/boot
    fi
}

# Update mirror list with reflector for faster speeds
update_mirrors () {
    dialog --title "Update Repo Mirror List" \
        --yesno "Would you like to update the mirror list? Updating the list \
may help speed up package download speeds. It is recommended to do this for a \
quicker install experience." 8 70

    if [[ $? -eq 0 ]]; then
        dialog --infobox "Updating mirror list..." 3 50
        reflector --latest 25 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    fi
}

# Gather system-specific info from user to build package list
prepare_install () {
    SYSTEM_PACKAGES=()

    # Check for UEFI support (if UEFI we use systemd-boot, not GRUB)
    if ! $UEFI_SUPPORT; then
        SYSTEM_PACKAGES+=('grub')
    fi

    # Install filesystem tools if needed
    if [[ "$FILE_SYSTEM" = "btrfs" ]]; then
        SYSTEM_PACKAGES+=('btrfs-progs')
    elif [[ "$FILE_SYSTEM" = "xfs" ]]; then
        SYSTEM_PACKAGES+=('xfsprogs')
    fi

    # Install packages for Bluetooth support
    if $BT_SUPPORT; then
        SYSTEM_PACKAGES+=('bluez' 'bluez-utils')
    fi

    # Add Kodi packages
    SYSTEM_PACKAGES+=('kodi' 'lzo')

    # Ask for Kodi Method
    DISPLAY_MODE=$(dialog --title "Select Kodi Display Method" \
        --default-item "x11" --menu "Select which method you would like to \
use to display Kodi on the appliance. If you are unsure on this, we recommend \
using the \"X11\" option for ease of use and compatibility.\n\nSelect display \
method:" 10 50 5 \
"x11" "Xorg" \
"wayland" "Wayland kiosk-mode using cage" \
"gbm" "Not recommended" 3>&1 1>&2 2>&3)
    if [[ "$DISPLAY_MODE" = "x11" ]]; then
        SYSTEM_PACKAGES+=('xorg-server' 'xorg-xinit' 'libinput')
    elif [[ "$DISPLAY_MODE" = "wayland" ]]; then
        SYSTEM_PACKAGES+=('cage' 'libinput' 'xorg-xwayland')
    else
        SYSTEM_PACKAGES+=('libinput')
    fi

    # Add Vulkan ICD loader - Even though Kodi doesn't make use of Vulkan, we'll install 
    # it anyway as some users may want to use Kodi as their hub for gaming/emulation
    SYSTEM_PACKAGES+=('vulkan-icd-loader' 'vulkan-tools')    

    GPU_TYPE=$(dialog --title "Select Appliance GPU" \
        --menu "Select which type of graphics your appliance is equipped with. \
Please ensure you choose the proper option, as this will help ensure proper video \
performance on your appliance.\n\nChoose graphics type:" 10 50 5 \
"igpu-intel" "Intel integrated graphics" \
"igpu-amd" "AMD integrated graphics" \
"amd" "AMD Radeon dedicated graphics" \
"arc" "Intel ARC dedicated graphics" \
"nvidia" "Nvidia dedicated graphics" 3>&1 1>&2 2>&3)
    # We only need xf86-video drivers when using X11
    # If using Intel, it's actually recommended to not use xf86-video
    if [[ "$DISPLAY_MODE" = "x11" ]]; then     
        if [[ "$GPU_TYPE" = "igpu-amd" ]] || [[ "$GPU_TYPE" = "amd" ]]; then
            SYSTEM_PACKAGES+=('xf86-video-amdgpu')
        fi
    fi
    # Install required video drivers
    if [[ "$GPU_TYPE" = "igpu-intel" ]]; then
        SYSTEM_PACKAGES+=('intel-media-driver' 'libva-intel-driver' 'vulkan-intel')      
    elif [[ "$GPU_TYPE" = "igpu-amd" ]] || [[ "$GPU_TYPE" = "amd" ]]; then
        SYSTEM_PACKAGES+=('mesa' 'libva-mesa-driver' 'mesa-vdpau' 'vulkan-radeon')
    # NOTE: Intel Arc GPU's require kernel version 6.2 or higher
    elif [[ "$GPU_TYPE" = "arc" ]]; then
        SYSTEM_PACKAGES+=('intel-media-driver' 'vulkan-intel')
    elif [[ "$GPU_TYPE" = "nvidia" ]]; then
        # Get GPU PCI device ID
        gpu_pci_id=$(lspci -nn  | grep -ioP 'VGA.*NVIDIA.*\[\K[\w:]+' | sed 's/.*://')
        # Ensure to install the supported Nvidia driver
        if grep -Fq "$gpu_pci_id" "$DIR"/config/nvidia_390_pci_ids; then
            SYSTEM_PACKAGES+=('nvidia-390xx' 'nvidia-390xx-utils' 'nvidia-390xx-settings')
        # Fallback to nouveau for unsupported Nvidia cards
        elif grep -Fq "$gpu_pci_id" "$DIR"/config/nvidia_340_pci_ids; then
            SYSTEM_PACKAGES+=('xf86-video-nouveau' 'mesa')
        else
            SYSTEM_PACKAGES+=('nvidia' 'nvidia-utils' 'nvidia-settings')
        fi
    fi
}

# Actually install the system with pacstrap
install_system () {
    # Packages we will include regardless of user selections
    BASE_PACKAGES=('base' 'linux' 'linux-firmware' 'networkmanager' 'pacman-contrib' 'bash-completion' 'sudo' 'nano' 'e2fsprogs' 'neofetch' 'openssh' 'wget' 'man-db' 'man-pages' 'texinfo' 'git' 'ufw')

    while true; do
        dialog --title "Appliance Installation Review" \
        --yesno "The appliance is ready to be installed on $DISK. The following packages \
will be installed:\n\n${BASE_PACKAGES[*]} ${SYSTEM_PACKAGES[*]}\n\nProceed with installation?" 0 0
        if [[ $? -eq 0 ]]; then
            clear
            pacstrap /mnt "${BASE_PACKAGES[@]}" "${SYSTEM_PACKAGES[@]}"
            if [[ $? -eq 0 ]]; then
                SUCCESS=true
            else
                dialog --title "Installation Failure" \
                    --msgbox "The appliance has failed to installed. An error occured \
while running the \"pacstrap\" command." 7 65
                reset; exit 1
            fi
            break
        else
            dialog --title "Cancel Installation" \
                --yesno "Are you sure you want to exit to the main menu?" 5 55
            if [[ $? -eq 0 ]]; then
                main_menu
            fi
        fi
    done
}

# Do rest of things like fstab, timezone, etc.
postinstall_setup () {
    # Generate fstab
    dialog --infobox "Generating fstab file..." 3 50
    genfstab -U /mnt >> /mnt/etc/fstab

    # Set timezone and hardware clock
    dialog --infobox "Setting system clock and time zone..." 3 50
    
    ln -sf /usr/share/zoneinfo/"$TIMEZONE" /mnt/etc/localtime

    if $UTC_TIME; then
        arch-chroot /mnt hwclock --systohc --utc
    else
        arch-chroot /mnt hwclock --systohc --localtime
    fi 

    # Locale and keyboard layout settings
    dialog --infobox "Generating locale info..." 3 50
    # Set locale
    # Always enable US English locale
    sed -i "s/#en_US.UTF-8/en_US.UTF-8/" /mnt/etc/locale.gen
    # Enable the user-selected locale
    if [[ "$LOCALE" != "en_US.UTF-8" ]]; then
        sed -i "s/#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
    fi
    echo "LANG=$LOCALE" > /mnt/etc/locale.conf
    # Set keyboard layout
    if [[ "$KEYMAP" != "us" ]]; then
        echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf
    fi
    # Generate the locale
    arch-chroot /mnt locale-gen &> /dev/null

    # Set system hostname
    dialog --infobox "Setting appliance hostname..." 3 50
    echo "$HOST_NAME" > /mnt/etc/hostname
    echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$HOST_NAME.localdomain\t$HOST_NAME" >> /mnt/etc/hosts

    # User account setup
    dialog --infobox "Creating user account and password..." 3 50
    if [[ -z "$FULL_NAME" ]]; then
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USER_NAME"
    else
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash -c "$FULL_NAME" "$USER_NAME"
    fi
    arch-chroot /mnt chpasswd <<<"$USER_NAME:$USER_PW"
    # Add user to "wheel" for sudo access
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers

    # Set root password
    dialog --infobox "Setting root password..." 3 50
    arch-chroot /mnt chpasswd <<<"root:$ROOT_PW"

    # Enable networking and bluetooth daemons
    dialog --infobox "Enabling networking service..." 3 50
    arch-chroot /mnt systemctl enable NetworkManager.service &> /dev/null
    if $BT_SUPPORT; then
        dialog --infobox "Enabling bluetooth service..." 3 50
        arch-chroot /mnt systemctl enable bluetooth.service &> /dev/null
    fi

    # Create initramfs
    arch-chroot /mnt mkinitcpio -P &> /dev/null

    # Set up bootloader
    # If UEFI we will use systemd boot
    #if $UEFI_SUPPORT; then
        # 
    #fi
    
}

test_func () {
    if $UEFI_SUPPORT; then
dialog --title "UEFI" --msgbox "UEFI SUPPORT ENABLED" 5 55
    fi

    if $BT_SUPPORT; then
    dialog --title "BT" --msgbox "BT SUPPORT ENABLED" 5 55
    fi
}

welcome
#network_check
#set_keymap
#set_locale
#set_timezone
#set_hostname
#set_userinfo
#set_root_pw
format_disk
#create_filesystem
#update_mirrors
#prepare_install
#install_system
#postinstall_setup
#test_func
#format_disk