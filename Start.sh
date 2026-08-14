# 1. Setup
mkdir luaos-build && cd luaos-build

# 2. Create both scripts
cat > build.sh << 'EOF'
[paste build.sh above]
EOF

cat > mkdir.sh << 'EOF'
[paste mkdir.sh above]
EOF

chmod +x build.sh mkdir.sh

# 3. Create scripts folder for your Lua code
mkdir scripts
# Put your init.lua, shell.lua, daemon.lua here

# 4. Build!
bash build.sh
