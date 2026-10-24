#!/bin/sh
# serve-ssh-setup.sh PUBKEY_FILE [PORT]  one-time SSH setup for a
# Haiku guest. Ask the user first: it installs a
# key and leaves sshd enabled at boot.
#
# Writes setup.sh to a temp dir and serves it on the host's LAN IP (VirtualBox
# 7 NAT blocks guest→host-localhost). Run this in the background, type the
# printed curl line into the guest Terminal, then stop this server.
#
# Before that, add the port forward with the VM powered off:
#   VBoxManage modifyvm <vm> --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
set -eu
PUB=$(cat "$1")
PORT=${2:-8731}
IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
DIR=$(mktemp -d)

cat > "$DIR/setup.sh" <<EOF
#!/bin/sh
# Key-only SSH for a Haiku-family test VM.
set -e
PUB='$PUB'
# Haiku's sshd reads this file, not ~/.ssh/authorized_keys.
mkdir -p "\$HOME/config/settings/ssh"
grep -qF "\$PUB" "\$HOME/config/settings/ssh/authorized_keys" 2>/dev/null \\
	|| echo "\$PUB" >> "\$HOME/config/settings/ssh/authorized_keys"
chmod 600 "\$HOME/config/settings/ssh/authorized_keys"

CONF=/boot/system/settings/ssh/sshd_config
mkdir -p /boot/system/settings/ssh
[ -f "\$CONF" ] || : > "\$CONF"
# The Haiku user is uid 0: allow root, by key only.
sed -i '/^PermitRootLogin/d; /^PasswordAuthentication/d; /^PubkeyAuthentication/d' "\$CONF"
printf 'PermitRootLogin prohibit-password\nPubkeyAuthentication yes\nPasswordAuthentication no\n' >> "\$CONF"
ssh-keygen -A

# launch_daemon starts sshd at boot; restart the running one with the new
# config (sshd must be started by absolute path).
# Haiku's ps prints "name [args] team threads gid uid": the team id is the
# 4th field from the end (the name may contain spaces).
for pid in \$(ps | awk '/[s]shd/ {print \$(NF-3)}'); do kill \$pid 2>/dev/null || :; done
sleep 1
/bin/sshd
echo "sshd setup done"
EOF

echo "In the guest Terminal type:  curl http://$IP:$PORT/setup.sh | sh"
exec python3 -m http.server "$PORT" --bind "$IP" --directory "$DIR"
