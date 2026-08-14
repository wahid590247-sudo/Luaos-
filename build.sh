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
cat > "$ROOTFS_DIR/etc/fstab" << 'EOF'
/dev/sda1   /           ext4    defaults,errors=remount-ro  0 1
proc        /proc       proc    defaults                     0 0
sysfs       /sys        sysfs   defaults                     0 0
devtmpfs    /dev        devtmpfs defaults                    0 0
tmpfs       /tmp        tmpfs   defaults,size=64M            0 0
EOF

echo "luaos" > "$ROOTFS_DIR/etc/hostname"

cat > "$ROOTFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/shell
EOF

cat > "$ROOTFS_DIR/etc/group" << 'EOF'
root:x:0:
EOF

# Create luanosmake config
cat > "$ROOTFS_DIR/etc/luanosmake/config.lua" << 'EOF'
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
EOF

echo -e "${GREEN}✓ Configuration files created${NC}"

# ============================================================================
# STEP 7: Install LuaOS Scripts & Create Disk Image
# ============================================================================
echo -e "\n${YELLOW}[7/7] Installing LuaOS scripts and creating disk image...${NC}"

# Copy scripts if they exist
if [ -d "$BUILD_DIR/scripts" ]; then
    cp "$BUILD_DIR/scripts"/* "$ROOTFS_DIR/bin/" 2>/dev/null || true
fi

chmod +x "$ROOTFS_DIR/bin"/* 2>/dev/null || true

# Create a minimal init script as fallback
if [ ! -f "$ROOTFS_DIR/bin/init" ] || [ ! -x "$ROOTFS_DIR/bin/init" ]; then
    cat > "$ROOTFS_DIR/bin/init" << 'LUAEOF'
#!/usr/bin/env lua
-- LuaOS Init System
print("\n=== LuaOS Booting ===\n")

-- Mount pseudo-filesystems (would normally use os.execute)
print("Mounting filesystems...")

-- Launch shell
print("Starting LuaOS Shell...\n")
os.execute("/bin/shell")
LUAEOF
    chmod +x "$ROOTFS_DIR/bin/init"
fi

# Create initramfs (cpio gzip archive)
echo "  Creating initramfs..."
cd "$ROOTFS_DIR"
find . -print0 | cpio -0 -o -H newc | gzip -9 > "$BUILD_DIR/initramfs.cpio.gz"
cd "$BUILD_DIR"

# Create disk image
echo "  Creating disk image ($DISK_SIZE MB)..."
dd if=/dev/zero of="$DISK_IMAGE" bs=1M count=$DISK_SIZE 2>&1 | grep -v "records"

# For v86, we'll embed the initramfs in the image
# This is a simple approach - just create a raw filesystem image
dd if=initramfs.cpio.gz of="$DISK_IMAGE" bs=512 seek=2048 2>&1 | grep -v "records"

echo -e "${GREEN}✓ Disk image created${NC}"

# ============================================================================
# Summary
# ============================================================================
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Build Complete!                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "Disk Image: ${BLUE}$DISK_IMAGE${NC}"
echo -e "Size: ${BLUE}$(du -h "$DISK_IMAGE" | cut -f1)${NC}"
echo -e "Initramfs: ${BLUE}$BUILD_DIR/initramfs.cpio.gz${NC}"
echo ""
echo "For v86 emulation:"
echo "  1. Use the disk image directly in v86"
echo "  2. Or extract and use the initramfs separately"
echo ""
echo "Boot command for v86:"
echo "  linux /initramfs.cpio.gz root=/dev/sda1 console=ttyS0 rw"
echo ""
