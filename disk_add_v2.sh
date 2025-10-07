#!/bin/bash

# This script prepares and mounts an extra disk (/dev/vdb).
# It must be run with root privileges (e.g., using sudo).

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
DISK="/dev/vdb"
MOUNT_POINT="/data"
FILESYSTEM_TYPE="ext4"

# --- 1. Create a new partition ---
echo "Creating a new partition on ${DISK}..."
# Use parted to create a new GPT partition table and a single primary partition
# that uses 100% of the disk space.
parted ${DISK} --script mklabel gpt mkpart primary ${FILESYSTEM_TYPE} 0% 100%
echo "Partition created successfully."

# Tell the kernel to re-read the partition table
partprobe ${DISK}

# The new partition will be named based on the disk name, e.g., /dev/vdb1
PARTITION="${DISK}1"

# --- 2. Format the partition ---
echo "Formatting ${PARTITION} as ${FILESYSTEM_TYPE}..."
# Use -F to force the format without interactive prompts.
mkfs.${FILESYSTEM_TYPE} -F ${PARTITION}
echo "Formatting complete."

# --- 3. Create mount directory ---
echo "Creating mount point directory ${MOUNT_POINT}..."
# Use -p to ensure parent directories are created if they don't exist
# and to avoid an error if the directory already exists.
mkdir -p ${MOUNT_POINT}
echo "Mount point created."

# --- 4. Mount the new partition ---
echo "Mounting ${PARTITION} on ${MOUNT_POINT}..."
mount ${PARTITION} ${MOUNT_POINT}
echo "${PARTITION} mounted on ${MOUNT_POINT}."

# --- 5. Make the mount permanent in /etc/fstab ---
echo "Making the mount permanent by adding it to /etc/fstab..."
# Get the UUID of the new partition. Using UUID is more robust than device names.
UUID=$(blkid -s UUID -o value ${PARTITION})

# Check if an entry for this UUID already exists in fstab to avoid duplicates.
if grep -q "UUID=${UUID}" /etc/fstab; then
    echo "fstab entry for UUID=${UUID} already exists. Skipping."
else
    # Append the new fstab entry.
    echo "UUID=${UUID} ${MOUNT_POINT} ${FILESYSTEM_TYPE} defaults 0 0" >> /etc/fstab
    echo "fstab entry added."
fi

echo "---"
echo "Disk setup is complete!"
echo "You can verify the mount by running: df -h"

