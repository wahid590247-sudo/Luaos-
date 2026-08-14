#!/bin/bash
# LuaOS Directory Structure Creator

set -e

ROOTFS="${1:-.}"

echo "Creating directory structure at: $ROOTFS"

mkdir -p "$ROOTFS"/{
    bin,sbin,
    etc/luanosmake,
    usr/{bin,sbin,lib/lua/5.1,lib/x86_64-linux-gnu,share/{man,doc},local/bin},
    home/root,
    root,
    dev,
    proc,
    sys,
    tmp,
    var/{log,cache,run,spool},
    mnt,media,opt,
    boot,
    daemons/{network,storage,system}
}

chmod 1777 "$ROOTFS/tmp"
chmod 755 "$ROOTFS/root"
chmod 755 "$ROOTFS/boot"

# Create daemon structure
for daemon in network storage system; do
    mkdir -p "$ROOTFS/daemons/$daemon"
    touch "$ROOTFS/daemons/$daemon/status"
    touch "$ROOTFS/daemons/$daemon/config"
done

echo "Directory structure created!"
