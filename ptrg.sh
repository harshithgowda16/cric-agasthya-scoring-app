#!/bin/bash
# Usage: bash ptrg.sh <hostname>
NEW_HOSTNAME="${1:-PRTG-Multi-Platform-Probe}"
OLD_HOSTNAME="$(hostname)"

hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/\b${OLD_HOSTNAME}\b/${NEW_HOSTNAME}/g" /etc/hosts
grep -q "^127\.0\.1\.1" /etc/hosts && sed -i "s/^127\.0\.1\.1.*/127.0.1.1 ${NEW_HOSTNAME}/" /etc/hosts || echo "127.0.1.1 ${NEW_HOSTNAME}" >> /etc/hosts
[ -d /etc/cloud/cloud.cfg.d ] && echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg

exit 0
