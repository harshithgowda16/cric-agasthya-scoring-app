#!/bin/bash
# =============================================================================
# VM3 - Multi-Platform Probe (Linux/Ubuntu)
# Usage: bash ptrg.sh <password>
# =============================================================================
exec > /var/log/linuxscript.log 2>&1
TRAINING_PASSWORD=$1
echo "======== Linux Script Started: $(date) ========"
# 1. Set hostname
hostnamectl set-hostname prtgprobe02
echo "Hostname set to prtgprobe02"
# 2. Create 'training' user
if ! id "training" &>/dev/null; then
    useradd -m -s /bin/bash training
    echo "User 'training' created"
else
    echo "User 'training' already exists - updating password"
fi
# Set password from parameter
echo "training:${TRAINING_PASSWORD}" | chpasswd
usermod -aG sudo training
echo "Password set and added to sudo"
# 3. Delete 'labuser' if exists
if id "labuser" &>/dev/null; then
    userdel -r labuser 2>/dev/null || userdel labuser
    echo "User 'labuser' deleted"
else
    echo "User 'labuser' not found - skipping"
fi
# 4. Allow password authentication for SSH
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
echo "SSH password authentication enabled"
echo "======== Linux Script Completed: $(date) ========"
