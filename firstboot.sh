#!/bin/bash

# Firstboot script for VMs!
# v2.0
#
# This script gets incorporated into a Debian Cloudinit image and performs initial configuration for every subsequent virtual machine.
# The script includes the following functions:
#
# 1. Set default shell to /bin/bash for the user with UID 1000 (The primary user created during VM cloning/creation).
# 2. Add the user to the sudoers group and configure password-less sudo access.
# 3. Modify the user's .bashrc file to add helpful aliases and color prompt settings, and apply the same to the root user.
# 4. Copy the user's password to the root account (toggle this off with the COPY_PASSWORD_TO_ROOT variable below, if it freaks you out).
# 5. Download and install scripts (currently Darkhand81's Decompress and Console) to specified locations, optionally making them executable.
# 6. Set GRUB timeout to 1 second if it is greater than 1 second.
# 7. Configure journald to forward logs to syslog and disable its storage. Because it is yucky.
# 8. Configure SSH to allow root login and password authentication, only from the local network.


echo "=============================================="
echo "Starting Firstboot Configuration Script v1.0"
echo "=============================================="
echo ""

COPY_PASSWORD_TO_ROOT=true

# ############ FUNCTIONS ############

# A helper function to uncomment a config file line or add it if it doesn't exist (used for .bashrc additions)
function addOrUncommentLine() {
  local pattern="$1"
  local newLine="$2"
  local file="$3"

  echo "Uncommenting/adding $newLine in $file..."

  # Check if the line exists in any form (commented or uncommented)
  if grep -qE "$pattern" "$file"; then
    # Line exists, replace it with the new line
    echo "Updating existing line matching pattern: $pattern"
    sed -i "/$pattern/c\\$newLine" "$file"
  else
    # Line does not exist, add the new line
    echo "Adding new line: $newLine"
    echo "$newLine" >> "$file"
  fi
  echo ""
}

# A helper function to download a script and set executable permission with true or false
# Usage: downloadAndSetExecutable "https://www.location.com/filename.ext" "/foo/bar/name" true|false
function downloadAndSetExecutable() {
  local url="$1"
  local destination="$2"
  local set_executable="$3"

  echo "Downloading script from $url..."
  wget -O "$destination" "$url" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "Download successful."
    if [ "$set_executable" == "true" ]; then
      echo "Setting execute permissions for $destination..."
      chmod +x "$destination" && echo "Script installed and made executable at $destination."
    fi
  else
    echo "Failed to download script from $url."
  fi
  echo ""
}

# A helper function to copy the password of one user to another
function copyUserPassword() {
  local source_user="$1"
  local target_user="$2"
  echo "Copying password from user '$source_user' to user '$target_user'..."
  local hashed_password=$(getent shadow "$source_user" | cut -d: -f2)
  if [ -n "$hashed_password" ]; then
    usermod -p "$hashed_password" "$target_user" && echo "Password copied successfully from '$source_user' to '$target_user'."
  else
    echo "Failed to retrieve the password for user '$source_user'."
  fi
  echo ""
}

# ############ START ############

# We'll work with the username of UID 1000 (The primary username created during VM setup)
USERNAME=$(getent passwd 1000 | cut -d: -f1)
if [ -z "$USERNAME" ]; then
  echo "Error: No user with UID 1000 found. Exiting script."
  exit 1
fi

echo "Configuring settings for user: $USERNAME"
echo ""

# Set bash as default shell for the user
echo "Setting /bin/bash as the default shell for user '$USERNAME'..."
usermod -s /bin/bash "$USERNAME" && echo "Default shell set to /bin/bash for user '$USERNAME'."
echo ""

# Add user to sudoers group
echo "Adding user '$USERNAME' to the 'sudo' group..."
usermod -a -G sudo "$USERNAME" && echo "User '$USERNAME' added to 'sudo' group."
echo ""

# Require no password for sudo commands
echo "Configuring password-less sudo for user '$USERNAME'..."
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/sudoer_"$USERNAME" && \
echo "Password-less sudo configured for user '$USERNAME'."
echo ""

# .bashrc additions
BASHRC_FILE="/home/$USERNAME/.bashrc"
echo "Modifying $BASHRC_FILE with ll aliases and color prompt settings..."
addOrUncommentLine "alias ll=" "alias ll='ls -lh'" "$BASHRC_FILE"
addOrUncommentLine "alias la=" "alias la='ls -alh'" "$BASHRC_FILE"
addOrUncommentLine "force_color_prompt=" "force_color_prompt=yes" "$BASHRC_FILE"
echo "Aliases and configurations added to $BASHRC_FILE."
echo ""

# Copy the modified .bashrc to /root/.bashrc, since we want these modifications when logged in as root as well
echo "Copying modified .bashrc to /root/.bashrc..."
cp "$BASHRC_FILE" /root/.bashrc && echo "/root/.bashrc updated."
echo ""

# Copy user's password to root user, controlled by COPY_PASSWORD_TO_ROOT variable
if [ "$COPY_PASSWORD_TO_ROOT" == "true" ]; then
  copyUserPassword "$USERNAME" "root"
else
  echo "Skipping copying password to root as per configuration."
fi

# Install decompress script and set executable
downloadAndSetExecutable "https://raw.githubusercontent.com/Darkhand81/decompress/main/decompress.sh" "/usr/local/bin/decompress" true

# Install console script and set executable
downloadAndSetExecutable "https://raw.githubusercontent.com/Darkhand81/bootstrap/refs/heads/main/console.sh" "/home/$USERNAME/console.sh" true

# Configure journald to forward to syslog and disable journald storage, because it is yucky.
echo "Configuring journald to forward logs to syslog and disable journald storage..."
addOrUncommentLine "Storage=" "Storage=none" "/etc/systemd/journald.conf"
addOrUncommentLine "ForwardToSyslog=" "ForwardToSyslog=yes" "/etc/systemd/journald.conf"
echo "Restarting systemd-journald to apply changes..."
systemctl restart systemd-journald && echo "systemd-journald restarted successfully."
echo ""

# Change GRUB timeout at boot to 1 second if greater than 1 second
# Debian Cloudinit currently sets a 0 second timeout by default, so this doesn't usually get used.
echo "Configuring GRUB timeout..."
current_timeout=$(grep -oP '(?<=^GRUB_TIMEOUT=)\d+' /etc/default/grub)
if [[ "$current_timeout" -gt 1 ]]; then
  echo "Setting GRUB_TIMEOUT to 1..."
  sed -i 's/GRUB_TIMEOUT=[0-9]*/GRUB_TIMEOUT=1/' /etc/default/grub && \
  echo "GRUB_TIMEOUT set to 1."

  echo "Updating GRUB configuration..."
  update-grub > /dev/null 2>&1 && echo "GRUB updated successfully."
else
  echo "GRUB_TIMEOUT is already 1 second or less, no changes made."
fi
echo ""

# Configure SSH to allow root and password login only from local network if not already set
echo "Configuring SSH to allow root and password login only from the local network..."
if ! grep -q "Match Address 192.168.1.0/24" /etc/ssh/sshd_config; then
    echo "Adding SSH Match Address configuration for local network..."
    {
        echo ""
        echo "# Allow root and password login only from local network"
        echo "Match Address 192.168.1.0/24,fe80::%eth0/10"
        echo "    PermitRootLogin yes"
        echo "    PasswordAuthentication yes"
    } >> /etc/ssh/sshd_config
    echo "SSH configuration updated to restrict root and password login to the local network."

    # Restart SSH service to apply changes
    echo "Restarting SSH service to apply changes..."
    systemctl restart ssh && echo "SSH service restarted."
else
    echo "SSH is already configured to allow root login from the local network."
fi
echo ""

echo "======================================================="
echo "Firstboot Configuration Script Completed Successfully!"
echo "======================================================="
