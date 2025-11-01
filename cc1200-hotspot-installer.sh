#!/bin/bash
#
# cc1200-hotspot-installer.sh - M17 Hotspot Installation Script for Raspberry Pi with CC1220 HAT
#
# Author: DK1MI <dk1mi@qrz.is>
# License: GNU General Public License v3.0 (GPLv3)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# ---------------- CONFIGURATION ----------------
REQUIRED_PACKAGES="git libzmq3-dev cmake libgpiod-dev nginx php-fpm stm32flash jq"
BOOT_CONFIG_FILE="/boot/firmware/config.txt"
M17_HOME="/opt/m17"
M17_USER="m17"
NGINX_DEFAULT="/etc/nginx/sites-enabled/default"
CMDLINE_FILE="/boot/firmware/cmdline.txt"
HOSTFILE_URL="https://hostfiles.refcheck.radio/M17Hosts.txt"
# ------------------------------------------------

set -e

show_menu() {
    echo "Please select an action:"
    echo "1) Install (Fresh setup)"
    echo "2) Update (Pull latest software)"
    echo "3) Repair (Fix permissions, groups, symlinks)"
    read -rp "Enter your choice (1/2/3): " MODE
}

update_hostfile() {
    echo "Now taking care of the M17 Hostfile..."

    FILES_DIR="$M17_HOME/rpi-dashboard/files"
    M17_HOSTS="$FILES_DIR/M17Hosts.txt"

    echo "Deleting $M17_HOSTS"
    rm -f $M17_HOSTS

    if [ ! -d "$FILES_DIR" ]; then
        mkdir -p "$FILES_DIR"
    fi
    chown "$M17_USER:www-data" $FILES_DIR
    chmod 775 $FILES_DIR

    echo "Downloading hostfile to $M17_HOSTS"
    /usr/bin/curl $HOSTFILE_URL -o $M17_HOSTS -A "rpi-dashboard Hostfile Updater"

    echo "Setting ownership and permissions of $M17_HOSTS"
    if [ -f $M17_HOME/rpi-dashboard/files/M17Hosts.txt ]; then
        chown "$M17_USER:www-data" $M17_HOSTS
        chmod 664 $M17_HOSTS
    fi
}

run_update() {
    echo "🔄 Updating software as $M17_USER..."

    sudo -u "$M17_USER" bash <<EOF
set -e
cd "$M17_HOME/libm17"
echo "📥 Updating libm17..."
git pull
cmake -DCMAKE_INSTALL_PREFIX=/usr -B build
cmake --build build
sudo cmake --install build

cd "$M17_HOME/CC1200_HAT-fw"
echo "📥 Updating CC1200_HAT-fw..."
git pull

cd "$M17_HOME/rpi-dashboard"
echo "📥 Updating rpi-dashboard..."
git pull
EOF

    update_hostfile

    echo "📥 Updating m17-gateway..."
    curl -s https://api.github.com/repos/jancona/m17/releases/latest \
        | jq -r '.assets[].browser_download_url | select(. | contains("_arm64.deb") and contains("m17-gateway"))' \
        | xargs -I {} curl -L -o /tmp/m17-gateway.deb {}

    systemctl stop m17-gateway.service

    dpkg -i /tmp/m17-gateway.deb

    systemctl start m17-gateway.service

    echo "✅ Update complete!"
    exit 0
}

run_repair() {
    echo "🔧 Repairing permissions and symlinks..."

    echo "👥 Ensuring group memberships..."
    usermod -aG dialout,gpio "$M17_USER"
    usermod -aG m17-gateway-control www-data

    echo "🔗 Fixing symlinks..."
    ln -sf $M17_HOME/m17-gateway/dashboard.log $M17_HOME/rpi-dashboard/files/dashboard.log
    ln -sf /etc/m17-gateway.ini $M17_HOME/rpi-dashboard/files/m17-gateway.ini

    echo "🔐 Fixing permissions and ownerships..."
    chgrp www-data $M17_HOME/rpi-dashboard/
    chmod g+w $M17_HOME/rpi-dashboard/
    chown -R m17-gateway:m17-gateway $M17_HOME/m17-gateway
    chmod 644 $M17_HOME/m17-gateway/dashboard.log

    update_hostfile

    if [ -f $M17_HOME/rpi-dashboard/files/OverrideHosts.txt ]; then
        chown "$M17_USER:www-data" $M17_HOME/rpi-dashboard/files/OverrideHosts.txt
        chmod 664 $M17_HOME/rpi-dashboard/files/OverrideHosts.txt
    fi

    echo "✅ Repair complete!"
    exit 0
}

# 1. Must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root. Please use sudo."
    exit 1
fi

show_menu

case "$MODE" in
    1)
        echo "🛠️ Proceeding with INSTALL..."
        ;; # Let the script continue normally for full install
    2)
        run_update
        ;;
    3)
        run_repair
        ;;
    *)
        echo "❌ Invalid choice. Exiting."
        exit 1
        ;;
esac


# 2. Check for Raspberry Pi OS Bookworm
if ! grep -q "bookworm" /etc/os-release; then
    echo "❌ This script is intended for Raspberry Pi OS Bookworm only."
    exit 1
fi

# 3. Fresh install warning
echo "⚠️  WARNING: This script is intended to be run on a fresh Raspberry Pi OS installation."
read -rp "❓ Do you wish to proceed? (Y/n): " CONFIRM
if [[ "$CONFIRM" != "Y" ]]; then
    echo "❌ Aborting setup."
    exit 1
fi

# 4. Update and check if reboot is needed
echo "📦 Updating system packages..."
apt update && apt -y dist-upgrade

if [ -f /var/run/reboot-required ]; then
    echo "🔁 A system reboot is required to continue."
    echo "ℹ️  Please reboot the system, rerun this script and select 1) (Fresh Setup) again."
    exit 0
fi

# 5. Ensure UART config is correct
CONFIG_CHANGED=false

if ! grep -q "^dtoverlay=miniuart-bt" "$BOOT_CONFIG_FILE"; then
    echo "dtoverlay=miniuart-bt" >> "$BOOT_CONFIG_FILE"
    CONFIG_CHANGED=true
fi

if ! grep -q "^enable_uart=1" "$BOOT_CONFIG_FILE"; then
    echo "enable_uart=1" >> "$BOOT_CONFIG_FILE"
    CONFIG_CHANGED=true
fi

if grep -q "console=serial0,115200" "$CMDLINE_FILE"; then
    sed -i 's/console=serial0,115200 *//' "$CMDLINE_FILE"
    CONFIG_CHANGED=true
fi

if $CONFIG_CHANGED; then
    echo "⚙️  UART configuration updated. A reboot is required."
    echo "🔁 Please reboot the system and rerun this script."
    exit 0
fi

# 6. Install required packages
echo "📦 Installing required packages: $REQUIRED_PACKAGES"
apt install -y $REQUIRED_PACKAGES

# 7. Create M17 user
echo "👤 Creating user '$M17_USER' with home at $M17_HOME..."
useradd -m -d "$M17_HOME" -s /bin/bash "$M17_USER"
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
echo "$M17_USER:$PASSWORD" | chpasswd
echo "User '$M17_USER' created with password: $PASSWORD"
echo "$M17_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$M17_USER"
mkdir -p "$M17_HOME"
chown -R "$M17_USER:$M17_USER" "$M17_HOME"

# Add m17 user to the groups dialout and gpio
usermod -aG dialout,gpio "$M17_USER"
echo "User '$M17_USER' has been added to the 'dialout' and 'gpio' groups."

# Use a subshell to switch to m17 user
sudo -u "$M17_USER" bash <<EOF
set -e
cd "$M17_HOME"
echo "📥 Cloning libm17..."
git clone https://github.com/M17-Project/libm17.git
cd libm17
cmake -DCMAKE_INSTALL_PREFIX=/usr -B build
cmake --build build
sudo cmake --install build

echo "📥 Cloning CC1200_HAT-fw..."
cd "$M17_HOME"
git clone https://github.com/M17-Project/CC1200_HAT-fw.git
EOF

# 8. Optionally flash firmware
read -rp "💾 Do you want to flash the latest CC1200 firmware to the HAT? (Y/n): " FLASH_CONFIRM
if [[ "$FLASH_CONFIRM" == "Y" ]]; then
    echo "⚡ Flashing firmware to CC1200 HAT..."
    stm32flash -v -R -i "-532&-533&532,533,:-532,-533,533" -w "$M17_HOME/CC1200_HAT-fw/Release/CC1200_HAT-fw.bin" /dev/ttyAMA0
fi

# 9. Install dashboard
sudo -u "$M17_USER" bash <<EOF
cd "$M17_HOME"
echo "📥 Cloning rpi-dashboard..."
git clone https://github.com/M17-Project/rpi-dashboard
EOF

update_hostfile

# 10. Configure Nginx and PHP
echo "🛠️  Configuring nginx and PHP..."
systemctl enable nginx
systemctl enable php8.2-fpm || true

tee "$NGINX_DEFAULT" > /dev/null << 'EOF'
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /opt/m17/rpi-dashboard;
        access_log off;

    index index.php index.html index.htm;

        server_name _;

        location / {
                try_files $uri $uri/ =404;
        }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        }
}
EOF

echo "🔁 Restarting nginx..."
systemctl restart nginx

# 11. Install M17 Gateway and configure links
echo "📥 Downloading and installing m17-gateway..."
curl -s https://api.github.com/repos/jancona/m17/releases/latest | jq -r '.assets[].browser_download_url | select(. | contains("_arm64.deb") and contains("m17-gateway"))' | xargs -I {} curl -L -o /tmp/m17-gateway.deb {}
dpkg -i /tmp/m17-gateway.deb

echo "👥 Adding 'www-data' to 'm17-gateway-control' group..."
usermod -aG m17-gateway-control www-data

echo "🚚 Moving host files to dashboard..."
#if [ ! -f /opt/m17/rpi-dashboard/files/M17Hosts.txt ]; then
#   mv /opt/m17/m17-gateway/M17Hosts.txt /opt/m17/rpi-dashboard/files/
#   chown m17:www-data /opt/m17/rpi-dashboard/files/M17Hosts.txt
#   chmod 664 /opt/m17/rpi-dashboard/files/M17Hosts.txt
#
if [ ! -f /opt/m17/rpi-dashboard/files/OverrideHosts.txt ]; then
    mv /opt/m17/m17-gateway/OverrideHosts.txt /opt/m17/rpi-dashboard/files/
    chown m17:www-data /opt/m17/rpi-dashboard/files/OverrideHosts.txt
    chmod 664 /opt/m17/rpi-dashboard/files/OverrideHosts.txt
fi

echo "Making /opt/m17/rpi-dashboard/ writable for www-data..."
chgrp www-data /opt/m17/rpi-dashboard/
chmod g+w /opt/m17/rpi-dashboard/

echo "Updating m17-gateway.ini..."
sed \
    -e 's|HostFile=/opt/m17/m17-gateway/M17Hosts.txt|HostFile=/opt/m17/rpi-dashboard/files/M17Hosts.txt|g' \
    -e 's|OverrideHostFile=/opt/m17/m17-gateway/OverrideHosts.txt|OverrideHostFile=/opt/m17/rpi-dashboard/files/OverrideHosts.txt|g' \
    /etc/m17-gateway.ini > /tmp/m17-gateway.ini
cp /tmp/m17-gateway.ini /etc/m17-gateway.ini

echo "🔗 Creating symlinks to expose gateway data to dashboard..."
ln -sf /opt/m17/m17-gateway/dashboard.log /opt/m17/rpi-dashboard/files/dashboard.log
ln -sf /etc/m17-gateway.ini /opt/m17/rpi-dashboard/files/m17-gateway.ini

IP_ADDRESS=$(hostname -I | awk '{print $1}')

# 12. Final Instructions
echo -e "\n🎉 All done! PLEASE REBOOT YOUR RASPBERRY NOW!"
echo -e "\nAfter the reboot, open your browser and go to: http://$IP_ADDRESS/"
echo -e "\nThere, click on 'Gateway Config' to configure your node (call sign, frequency etc)."
echo -e "You will find further information under 'Help' in the dashboard."
