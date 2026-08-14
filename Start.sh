mkdir -p luaos-build && cd luaos-build

cat > build.sh << 'EOF'
#!/bin/bash
# LuaOS Build Script - Direct Disk Image for v86 (No ISO)
# Run: bash build.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BUILD_DIR="$(pwd)"
ROOTFS_DIR="$BUILD_DIR/rootfs"
DISK_IMAGE="$BUILD_DIR/luaos.img"
DISK_SIZE=256  # MB

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   LuaOS Disk Image Builder (v86)       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"

# ============================================================================
# STEP 1: Check Dependencies
# ============================================================================
echo -e "\n${YELLOW}[1/7] Checking dependencies...${NC}"

DEPS=("lua" "luarocks" "busybox" "cpio" "dd")
MISSING=()

for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING+=("$dep")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${RED}✗ Missing: ${MISSING[*]}${NC}"
    echo "Install with: sudo pacman -S ${MISSING[*]}"
    exit 1
fi

echo -e "${GREEN}✓ All dependencies found${NC}"

# ============================================================================
# STEP 2: Create Directory Structure
# ============================================================================
echo -e "\n${YELLOW}[2/7] Creating rootfs directory structure...${NC}"

bash "$BUILD_DIR/mkdir.sh" "$ROOTFS_DIR"

echo -e "${GREEN}✓ Directories created${NC}"

# ============================================================================
# STEP 3: Install Lua Interpreter
# ============================================================================
echo -e "\n${YELLOW}[3/7] Installing Lua interpreter...${NC}"

LUA_BIN=$(which lua)
mkdir -p "$ROOTFS_DIR/usr/bin"
cp "$LUA_BIN" "$ROOTFS_DIR/usr/bin/lua"
chmod +x "$ROOTFS_DIR/usr/bin/lua"

# Symlink to /bin
mkdir -p "$ROOTFS_DIR/bin"
ln -sf /usr/bin/lua "$ROOTFS_DIR/bin/lua"

echo -e "${GREEN}✓ Lua at /usr/bin/lua${NC}"

# ============================================================================
# STEP 4: Install LuaRocks
# ============================================================================
echo -e "\n${YELLOW}[4/7] Installing LuaRocks...${NC}"

LUAROCKS_BIN=$(which luarocks)
cp "$LUAROCKS_BIN" "$ROOTFS_DIR/usr/bin/luarocks"
chmod +x "$ROOTFS_DIR/usr/bin/luarocks"
ln -sf /usr/bin/luarocks "$ROOTFS_DIR/bin/luarocks"

mkdir -p "$ROOTFS_DIR/usr/lib/lua/5.1"
if [ -d "/usr/lib/lua/5.1" ]; then
    cp -r /usr/lib/lua/5.1/* "$ROOTFS_DIR/usr/lib/lua/5.1/" 2>/dev/null || true
fi

echo -e "${GREEN}✓ LuaRocks at /usr/bin/luarocks${NC}"

# ============================================================================
# STEP 5: Install BusyBox
# ============================================================================
echo -e "\n${YELLOW}[5/7] Installing BusyBox...${NC}"

BUSYBOX_BIN=$(which busybox)
cp "$BUSYBOX_BIN" "$ROOTFS_DIR/bin/busybox"
chmod +x "$ROOTFS_DIR/bin/busybox"

# Create utility symlinks
cd "$ROOTFS_DIR/bin"
for cmd in ls cat mkdir pwd grep cp mv rm touch echo ash sh init; do
    ln -sf busybox "$cmd" 2>/dev/null || true
done
cd "$BUILD_DIR"

echo -e "${GREEN}✓ BusyBox at /bin/busybox${NC}"

# ============================================================================
# STEP 6: Create Configuration Files
# ============================================================================
echo -e "\n${YELLOW}[6/7] Creating configuration files...${NC}"

mkdir -p "$ROOTFS_DIR/etc"
mkdir -p "$ROOTFS_DIR/etc/luanosmake"

# Create /etc/fstab
cat > "$ROOTFS_DIR/etc/fstab" << 'ETCEOF'
/dev/sda1   /           ext4    defaults,errors=remount-ro  0 1
proc        /proc       proc    defaults                     0 0
sysfs       /sys        sysfs   defaults                     0 0
devtmpfs    /dev        devtmpfs defaults                    0 0
tmpfs       /tmp        tmpfs   defaults,size=64M            0 0
ETCEOF

# Create /etc/hostname
echo "luaos" > "$ROOTFS_DIR/etc/hostname"

# Create /etc/hosts
cat > "$ROOTFS_DIR/etc/hosts" << 'ETCEOF'
127.0.0.1       localhost
127.0.0.1       luaos
::1             localhost
ETCEOF

# Create /etc/luanosmake/config.lua
cat > "$ROOTFS_DIR/etc/luanosmake/config.lua" << 'ETCEOF'
-- LuaOS System Configuration
return {
    theme = "default",
    color_prompt = "\27[1;32m",
    color_reset = "\27[0m",
    color_error = "\27[1;31m",
    color_success = "\27[1;32m",
    color_info = "\27[1;34m",
    color_warning = "\27[1;33m",
    shell_prompt = "luaos> ",
    editor_name = "Luano",
    show_ascii_art = true,
}
ETCEOF

# Create init script
cat > "$ROOTFS_DIR/sbin/init" << 'ETCEOF'
#!/bin/sh
# LuaOS Init Script

echo "======================================"
echo "  LuaOS v1.0 - Lua Operating System"
echo "======================================"

# Mount filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Create device nodes
mknod /dev/console c 5 1
mknod /dev/null c 1 3
mknod /dev/zero c 1 5
mknod /dev/random c 1 8

# Setup environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export SHELL=/bin/sh

echo ""
echo "Booting LuaOS..."
echo ""

# Start shell
exec /bin/sh
ETCEOF

chmod +x "$ROOTFS_DIR/sbin/init"

echo -e "${GREEN}✓ Configuration files created${NC}"

# ============================================================================
# STEP 7: Create Disk Image
# ============================================================================
echo -e "\n${YELLOW}[7/7] Creating disk image (${DISK_SIZE}MB)...${NC}"

# Create sparse image file
dd if=/dev/zero of="$DISK_IMAGE" bs=1M count=$DISK_SIZE

# Format as ext4
mkfs.ext4 -F "$DISK_IMAGE"

# Mount and copy rootfs
MOUNT_POINT=$(mktemp -d)
sudo mount -o loop "$DISK_IMAGE" "$MOUNT_POINT"
sudo cp -r "$ROOTFS_DIR"/* "$MOUNT_POINT/"
sudo umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

echo -e "${GREEN}✓ Disk image created: $DISK_IMAGE${NC}"

echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Build Complete!                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"

echo -e "\n${GREEN}Output:${NC}"
echo "  Disk Image: $DISK_IMAGE"
echo "  Rootfs: $ROOTFS_DIR"

echo -e "\n${GREEN}v86 Boot Command:${NC}"
echo "  linux /luaos.img root=/dev/sda1 console=ttyS0 rw"

echo -e "\n${GREEN}Next Steps:${NC}"
echo "  1. Upload luaos.img to your v86 instance"
echo "  2. Configure v86 to boot from the disk image"
echo "  3. Run: bash build.sh"

EOF

chmod +x build.sh

cat > mkdir.sh << 'EOF'
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

EOF

chmod +x mkdir.sh

# Create scripts directory with lua scripts
mkdir -p scripts

cat > scripts/init.lua << 'EOF'
-- LuaOS Initialization Script
-- This runs at startup

local config = dofile("/etc/luanosmake/config.lua")

print(config.color_prompt .. "╔════════════════════════════════════════╗" .. config.color_reset)
print(config.color_prompt .. "║   LuaOS v1.0 - Lua Operating System   ║" .. config.color_reset)
print(config.color_prompt .. "╚════════════════════════════════════════╝" .. config.color_reset)
print("")

if config.show_ascii_art then
    print(config.color_info .. [[
    ___                 ___  ___
   / _ \  ________ __  / _ \/ _ \
  / /_\ \/ __ / _ `\ \/ / _ / _ \
 /  ___ / /_/ / /_/ /\ / / _ / _ \
/_ _/  \_____/\_____/ \_/ \_\_\_\
    ]] .. config.color_reset)
    print("")
end

print(config.color_success .. "System initialized successfully!" .. config.color_reset)
print("")

-- Load user shell
dofile("scripts/shell.lua")
EOF

cat > scripts/shell.lua << 'EOF'
-- LuaOS Interactive Shell
-- Provides command-line interface

local config = dofile("/etc/luanosmake/config.lua")

local shell = {}

function shell.prompt()
    io.write(config.color_prompt .. config.shell_prompt .. config.color_reset)
    io.flush()
end

function shell.run()
    print(config.color_info .. "LuaOS Shell Ready" .. config.color_reset)
    print("")
    
    while true do
        shell.prompt()
        local cmd = io.read()
        
        if not cmd or cmd == "exit" or cmd == "quit" then
            print(config.color_warning .. "Shutting down..." .. config.color_reset)
            break
        end
        
        if cmd ~= "" then
            print(config.color_info .. "Command: " .. cmd .. config.color_reset)
        end
    end
end

shell.run()
EOF

cat > scripts/daemon.lua << 'EOF'
-- LuaOS Background Daemon
-- Manages system services

local daemon = {}

function daemon.start(name, callback)
    print("Starting daemon: " .. name)
    if callback then
        callback()
    end
end

function daemon.stop(name)
    print("Stopping daemon: " .. name)
end

function daemon.status(name)
    print("Status: " .. name .. " is running")
end

return daemon
EOF

echo ""
echo "✓ LuaOS build directory structure created!"
echo ""
echo "📁 Files created:"
echo "  - build.sh (main builder script)"
echo "  - mkdir.sh (enhanced directory creation)"
echo "  - scripts/init.lua (system initialization)"
echo "  - scripts/shell.lua (interactive shell)"
echo "  - scripts/daemon.lua (daemon management)"
echo ""
echo "📝 Directory structure includes:"
echo "  - Standard directories (bin, sbin, etc, usr, var, tmp, boot)"
echo "  - Lua libraries (usr/lib/lua/5.1)"
echo "  - Daemon structure (daemons/{network,storage,system})"
echo ""
echo "🚀 To build: bash build.sh"
