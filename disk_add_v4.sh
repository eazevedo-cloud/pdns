#!/bin/bash

# This script prepares and mounts an extra disk (/dev/vdb).
# It must be run with root privileges (e.g., using sudo).

set -e

# --- Configuration ---
DISK="/dev/vdb"
MOUNT_POINT="/data"
FILESYSTEM_TYPE="ext4"

# --- 1. Create a new partition ---
echo "Creating a new partition on ${DISK}..."
parted ${DISK} --script mklabel gpt mkpart primary ${FILESYSTEM_TYPE} 0% 100%
echo "Partition created successfully."

# Tell the kernel to re-read the partition table
partprobe ${DISK}

PARTITION="${DISK}1"

# --- Wait for partition to become available ---
for i in {1..10}; do
    if [ -b "${PARTITION}" ]; then
        break
    fi
    echo "Waiting for ${PARTITION} to appear..."
    sleep 1
done

if [ ! -b "${PARTITION}" ]; then
    echo "Error: Partition ${PARTITION} not found after 10 seconds."
    exit 1
fi

# --- 2. Format the partition ---
echo "Formatting ${PARTITION} as ${FILESYSTEM_TYPE}..."
mkfs.${FILESYSTEM_TYPE} -F ${PARTITION}
echo "Formatting complete."

# --- 3. Create mount directory ---
echo "Creating mount point directory ${MOUNT_POINT}..."
mkdir -p ${MOUNT_POINT}
echo "Mount point created."

# --- 4. Mount the new partition ---
echo "Mounting ${PARTITION} on ${MOUNT_POINT}..."
mount ${PARTITION} ${MOUNT_POINT}
echo "${PARTITION} mounted on ${MOUNT_POINT}."

# --- 5. Make the mount permanent in /etc/fstab ---
echo "Making the mount permanent by adding it to /etc/fstab..."
UUID=$(blkid -s UUID -o value ${PARTITION})

if grep -q "UUID=${UUID}" /etc/fstab; then
    echo "fstab entry for UUID=${UUID} already exists. Skipping."
else
    echo "UUID=${UUID} ${MOUNT_POINT} ${FILESYSTEM_TYPE} defaults 0 0" >> /etc/fstab
    echo "fstab entry added."
fi

echo "---"
echo "Disk setup is complete!"
echo "You can verify the mount by running: df -h"
