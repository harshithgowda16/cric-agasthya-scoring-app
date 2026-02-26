#!/bin/bash

# =============================================================================
# VM3 - Multi-Platform Probe (Linux/Ubuntu)
# Custom Script Extension - linuxscript.sh
# =============================================================================

exec > /var/log/linuxscript.log 2>&1

echo "======== Linux Script Started: $(date) ========"

# 1. Set hostname
hostnamectl set-hostname multiplatformprobe
echo "Hostname set to multiplatformprobe"

# 2. Create 'training' user with password prtg4training
if ! id "training" &>/dev/null; then
    useradd -m -s /bin/bash training
    echo "training:prtg4training" | chpasswd
    usermod -aG sudo training
    echo "User 'training' created and added to sudo"
else
    echo "User 'training' already exists - updating password"
    echo "training:prtg4training" | chpasswd
fi

# 3. Delete 'labuser' if exists
if id "labuser" &>/dev/null; then
    userdel -r labuser 2>/dev/null || userdel labuser
    echo "User 'labuser' deleted"
else
    echo "User 'labuser' not found - skipping"
fi

# 4. Allow password authentication for SSH (needed since password auth may be off)
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
echo "SSH password authentication enabled"

echo "======== Linux Script Completed: $(date) ========"
