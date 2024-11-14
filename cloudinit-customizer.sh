#!/bin/bash

# -------------------------------------------------------------------------
# CloudInit Image Customizer Script
#
#  This script is used to customize a cloud image (.qcow2 format) 
#  using the virt-customize tool. It finds a .qcow2 image in the 
#  current directory and applies various configurations such as:
#  - Installing necessary packages (e.g., qemu-guest-agent, rsyslog, etc)
#  - Setting DHCP client identifier to use MAC address, for unique IPs
#  - Clearing machine-id to ensure a unique identity for the image
#  - Setting the system timezone
#  - Adding a firstboot script to be executed on the first boot of each VM
#  - Compressing the customized image
#
#  If multiple .qcow2 images are found, the user is prompted to select one.
# -------------------------------------------------------------------------

# -----------------------------------------------------------
#  Configuration:

# Packages to install in the image:
#   (rsyslog is installed to restore normal /var/log'ging.
#   Otherwise dumb journalctl gets used.)
PACKAGES=(
    qemu-guest-agent
    rsyslog
    sudo
    nano
    tmux
    htop
    git
    curl
    bmon
    avahi-daemon
    iptables
    rsync
    pv
    fail2ban
)

# Timezone to set in the image
TIMEZONE="America/Chicago"

# -----------------------------------------------------------

# Check if libguestfs-tools is installed, install if not
if ! dpkg -l | grep -qw libguestfs-tools; then
    echo "libguestfs-tools is not installed. Installing..."
    sudo apt-get update && sudo apt-get install -y libguestfs-tools
fi

# Find all qcow2 images in the current directory
IMAGES=(*.qcow2)

# If no qcow2 image is found, exit with an error message
if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "No .qcow2 images found in the current directory."
    exit 1
fi

# If only one qcow2 image is found, use it
if [ ${#IMAGES[@]} -eq 1 ]; then
    IMAGE="${IMAGES[0]}"
else
    # If multiple qcow2 images are found, prompt the user to choose one
    echo "Multiple .qcow2 images found. Please select one:"
    select IMAGE in "${IMAGES[@]}"; do
        if [ -n "$IMAGE" ]; then
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
fi

# Check if firstboot.sh is in the current directory
if [ ! -f "firstboot.sh" ]; then
    echo "firstboot.sh not found in the current directory."
    exit 1
fi

# Prompt user for confirmation before starting customization
read -p "Do you want to customize $IMAGE? (y/n) " CONFIRMATION
if [[ ! "$CONFIRMATION" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Notify user that customization is starting
echo "Starting customization of $IMAGE..."

# - Install packages
# - Set DHCP identifier to use MAC address for unique DHCP addresses
# - Clear machine-id to make it unique
# - Set timezone
# - Install firstboot script (see script for more info)
if ! virt-customize -a "$IMAGE" \
    --install "$(IFS=,; echo "${PACKAGES[*]}")" \
    --run-command "sed -i 's|send host-name = gethostname();|send dhcp-client-identifier = hardware;|' /etc/dhcp/dhclient.conf" \
    --run-command "echo -n > /etc/machine-id" \
    --timezone "$TIMEZONE" \
    --firstboot firstboot.sh; then
    echo "Error: Customization of $IMAGE failed."
    exit 1
fi

# Notify user that customization is complete
echo "Customization of $IMAGE completed successfully."

# Compress the customized image
COMPRESSED_IMAGE="${IMAGE%.qcow2}-shrink.qcow2"
echo "Compressing image..."
if ! qemu-img convert -O qcow2 -c -o preallocation=off "$IMAGE" "$COMPRESSED_IMAGE"; then
    echo "Error: Compression of $IMAGE failed."
    exit 1
fi

echo "Image has been customized and compressed as $COMPRESSED_IMAGE"

# Compare file sizes
ORIGINAL_SIZE=$(du -h "$IMAGE" | cut -f1)
COMPRESSED_SIZE=$(du -h "$COMPRESSED_IMAGE" | cut -f1)
REDUCTION=$(du -b "$IMAGE" "$COMPRESSED_IMAGE" | awk 'NR==1{orig=$1} NR==2{comp=$1} END{printf "%.2f", (orig-comp)/orig*100}')

echo "Original image size: $ORIGINAL_SIZE"
echo "Compressed image size: $COMPRESSED_SIZE"
echo "Size reduction: $REDUCTION%"
