# CloudInit Image Customizer and Firstboot Script

This repository contains two Bash scripts, `cloudinit-customizer.sh` and `firstboot.sh`, designed to streamline the creation and configuration of Debian-based virtual machines (VMs) using cloud-init images. It automates the repetitive customization of VM images and sets them up the ways I likes 'em, without having to go through a manual OS install each time.

## Scripts

### 1. `cloudinit-customizer.sh`

The `cloudinit-customizer.sh` script customizes a cloud image in `.qcow2` format. It utilizes the `virt-customize` tool to:

- **Install packages**: A set of my most commonly used tools and utilities are installed into the image. Curently, those are:
  - qemu-guest-agent
  - rsyslog (because journald is yucky)
  - sudo
  - nano
  - tmux
  - htop
  - git
  - curl
  - bmon
  - avahi-daemon
  - iptables
  - rsync
  - pv
  - fail2ban

- **Network Configuration**: By default, the cloud images use the hostname as the DHCP identifier. We change to the MAC address, since at clone time, the hostname is still the template name! It'd always be the same otherwise.
- **Machine Identity**: We also need to reset the machine-id. Otherwise VMs will each acquire the same IP address when using DHCP (even if the MAC is different)
- **Timezone**: Configures the system timezone to `America/Chicago` by default (can be changed within the script).
- **Firstboot Script**: Integrates the `firstboot.sh` script (detailed below) to apply all my configurations that I usually make after OS install, during the first VM boot.
- **Image Compression**: Compresses the customized image.

#### Usage

1. Place a `.qcow2` cloud-init image (such as https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2) in the same directory as the `cloudinit-customizer.sh` and `firstboot.sh` scripts.
2. Run `cloudinit-customizer.sh` and follow the prompts to select and customize the image.
3. The script will run and output a compressed version of the customized image.

### 2. `firstboot.sh`

The `firstboot.sh` script is embedded into each customized VM and is executed during the first VM boot. This script performs the following configurations:

- **User Setup**
  - Sets the primary user's (UID 1000, the one set up in Proxmox at VM clone time) default shell to `/bin/bash`
  - Adds the user to the sudoers group with passwordless sudo access
  - Configures their `.bashrc` with ll/la aliases and color prompts.
  - Copies the same `.bashrc` to the root user's directory since we want the same customizations when logged in as root.
- **Root Access Configuration**: Copies the primary user's password to the root account (configurable by setting `COPY_PASSWORD_TO_ROOT` to `false`, in case this freaks you out).
- **Download and install utility scripts**: Downloads utility scripts directly from Github, to ensure they're up to date (currently my Decompress and Console scripts).
- **System Logging**: Configures `journald` to forward logs to `syslog` and disables `journald` storage, because `journald` is yucky.
- **GRUB Timeout**: Sets the GRUB boot timeout to 1 second if it exceeds this value (Debian cloudimit images default to 0 seconds already, but just in case).
- **SSH Configuration**: Allows root login and password authentication, but only on the local network (currently 192.168.1.0/24).

### 3. Creating a VM template

Once you have your cusomtized image, set up a Proxmox template to clone VMs from, and attach the customized image. You can use a tutorial such as https://static.xtremeownage.com/blog/2024/proxmox---debian-cloud-init-templates/#step-3-create-a-vm
