#!/bin/bash
#
# m17-hotspot-installer.sh - M17 Hotspot Installation Script for Raspberry Pi with CC1220 or MMDVM HAT
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
REQUIRED_PACKAGES="git nginx php-fpm stm32flash jq"
BOOT_CONFIG_FILE="/boot/firmware/config.txt"
M17_HOME="/opt/m17"
M17_USER="m17"
NGINX_DEFAULT="/etc/nginx/sites-enabled/default"
CMDLINE_FILE="/boot/firmware/cmdline.txt"
HOSTFILE_URL="https://hostfiles.refcheck.radio/M17Hosts.txt"
# ------------------------------------------------

set -e

update_hostfile() {
    echo "Now taking care of the M17 Hostfile..."

    FILES_DIR="$M17_HOME/rpi-dashboard/files"
    M17_HOSTS="$FILES_DIR/M17Hosts.txt"
    if [ ! -d "$FILES_DIR" ]; then
        mkdir -p "$FILES_DIR"
    fi
    chown "$M17_USER:www-data" $FILES_DIR
    chmod 775 $FILES_DIR

    # Don't refresh if the file is less than 2 hours old
    if ! [ -f $M17_HOSTS ] || [ $(find $M17_HOSTS -cmin +120) ]; then
        # echo "Deleting $M17_HOSTS"
        # rm -f $M17_HOSTS

        echo "Downloading hostfile to $M17_HOSTS"
        /usr/bin/curl $HOSTFILE_URL -o $M17_HOSTS -A "rpi-dashboard Hostfile Updater"

        echo "Setting ownership and permissions of $M17_HOSTS"
        if [ -f $M17_HOSTS ]; then
            chown "$M17_USER:www-data" $M17_HOSTS
            chmod 664 $M17_HOSTS
        fi
    fi
}

flash_firmware() {
    # It would be nice to add modem type detection here
    # Start with a limited list of modems and add more as people test them.
    systemctl list-unit-files m17-gateway.service >/dev/null
    exists=$?
    if [ $exists ]; then
        systemctl stop m17-gateway.service
    fi

    firmware=( \
        "No option 0" \
        "CC1200_HAT-fw/Release/CC1200_HAT-fw.bin" \
        "MMDVM_HS/release/MMDVM_HS_Hat.bin" \
        "MMDVM_HS/release/MMDVM_HS_Dual_Hat.bin" \
        "MMDVM_HS/release/generic_gpio.bin" \
        "MMDVM_HS/release/generic_duplex_gpio.bin" \
        "MMDVM/release/Repeater-Builder_v3.bin" \
        "MMDVM/release/Repeater-Builder_v4.bin" \
        "MMDVM/release/Repeater-Builder_v5.bin" \
    )
    HW=0
    while [ $HW -lt 1 -o $HW -gt 8 ]
    do 
        echo "Please select your hardware type:"
        echo "1) CC1200"
        echo "2) MMDVM_HS_Hat"
        echo "3) MMDVM_HS_Dual_Hat"
        echo "4) generic_gpio"
        echo "5) generic_duplex_gpio"
        echo "6) Repeater-Builder_v3"
        echo "7) Repeater-Builder_v4"
        echo "8) Repeater-Builder_v5"
        read -rp "Enter your choice (1-8): " HW
    done

    echo "⚡ Flashing firmware to HAT..."
    stm32flash -v -R -i "-532&-533&532,533,:-532,-533,533" -w "$M17_HOME/${firmware[$HW]}" /dev/ttyAMA0

    if [ $exists ]; then
        systemctl start m17-gateway.service
    fi
}

# Must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root. Please use sudo."
    exit 1
fi


# Check for Raspberry Pi OS Bookworm or Trixie
if ! grep -q "trixie\|bookworm" /etc/os-release; then
    echo "❌ This script is intended for Raspberry Pi OS Bookworm or Trixie only."
    exit 1
fi

# Update and check if reboot is needed
echo "📦 Updating system packages..."
apt update && apt -y dist-upgrade

if [ -f /var/run/reboot-required ]; then
    echo "🔁 A system reboot is required to continue."
    echo "ℹ️  Please reboot the system, rerun this script and select 1) (Fresh Setup) again."
    exit 0
fi

# Ensure UART config is correct
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

# Install required packages
echo "📦 Installing required packages: $REQUIRED_PACKAGES"
apt install -y $REQUIRED_PACKAGES

# Create M17 user
if ! id "$M17_USER" >/dev/null 2>&1; then
    echo "👤 Creating user '$M17_USER' with home at $M17_HOME..."
    useradd -m -d "$M17_HOME" -s /bin/bash "$M17_USER"
    PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo "$M17_USER:$PASSWORD" | chpasswd
    echo "User '$M17_USER' created with password: $PASSWORD"
    echo "$M17_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$M17_USER"
fi
mkdir -p "$M17_HOME"
chown -R "$M17_USER:$M17_USER" "$M17_HOME"

# Add m17 user to the groups dialout and gpio
usermod -aG dialout,gpio "$M17_USER"
echo "User '$M17_USER' has been added to the 'dialout' and 'gpio' groups."

# Use a subshell to switch to m17 user
sudo -u "$M17_USER" bash <<EOF
set -e
cd "$M17_HOME"
if [ ! -d CC1200_HAT-fw ]; then
    echo "📥 Cloning CC1200_HAT-fw..."
    git clone https://github.com/M17-Project/CC1200_HAT-fw.git
else
    cd "$M17_HOME/CC1200_HAT-fw"
    echo "📥 Updating CC1200_HAT-fw..."
    git pull
fi

cd "$M17_HOME"
if [ ! -d MMDVM ]; then
    echo "📥 Cloning MMDVM..."
    git clone https://github.com/M17-Project/MMDVM.git
else
    cd "$M17_HOME/MMDVM"
    echo "📥 Updating MMDVM firmware..."
    git pull
fi

cd "$M17_HOME"
if [ ! -d MMDVM_HS ]; then
    echo "📥 Cloning MMDVM_HS..."
    git clone https://github.com/M17-Project/MMDVM_HS.git
else
    cd "$M17_HOME/MMDVM_HS"
    echo "📥 Updating MMDVM_HS firmware..."
    git pull
fi
EOF

# Optionally flash firmware
read -rp "💾 Do you want to flash the latest firmware to the HAT? (Y/n): " FLASH_CONFIRM
if [[ "$FLASH_CONFIRM" == "Y" || "$FLASH_CONFIRM" == "y" ]]; then
    flash_firmware
fi

# Install dashboard
sudo -u "$M17_USER" bash <<EOF
cd "$M17_HOME"
if [ ! -d rpi-dashboard ]; then
    echo "📥 Cloning rpi-dashboard..."
    git clone https://github.com/M17-Project/rpi-dashboard
else
    cd "$M17_HOME/rpi-dashboard"
    echo "📥 Updating rpi-dashboard..."
    git pull
fi
EOF

update_hostfile

# Configure Nginx and PHP
echo "🛠️  Configuring nginx and PHP..."
systemctl enable nginx
if grep -q "bookworm" /etc/os-release; then
    systemctl enable php8.2-fpm
else
    systemctl enable php8.4-fpm
fi

if ! grep -q 'root /opt/m17/rpi-dashboard' "$NGINX_DEFAULT"; then
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
fi

# Install M17 Gateway and configure links
echo "📥 Downloading and installing m17-gateway..."
curl -s https://api.github.com/repos/jancona/m17/releases/latest | jq -r '.assets[].browser_download_url | select(. | contains("_arm64.deb") and contains("m17-gateway"))' | xargs -I {} curl -L -o /tmp/m17-gateway.deb {}

# Avoid intermittent dpkg frontend lock errors
max_attempts=5
attempt=1
success=false

while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt of $max_attempts..."

    if dpkg -i /tmp/m17-gateway.deb; then
        success=true
        break
    fi

    if [ $attempt -lt $max_attempts ]; then
        echo "Failed, retrying in 2 seconds..."
        sleep 2
    fi

    ((attempt++))
done

if [ "$success" = false ]; then
    echo "Failed after $max_attempts attempts"
    exit 1
fi

echo "👥 Adding 'www-data' to 'm17-gateway-control' group..."
usermod -aG m17-gateway-control www-data

echo "🚚 Moving host files to dashboard..."
if [ ! -f /opt/m17/rpi-dashboard/files/OverrideHosts.txt ]; then
    mv /opt/m17/m17-gateway/OverrideHosts.txt /opt/m17/rpi-dashboard/files/
    chown m17:www-data /opt/m17/rpi-dashboard/files/OverrideHosts.txt
    chmod 664 /opt/m17/rpi-dashboard/files/OverrideHosts.txt
fi

echo "Making /opt/m17/rpi-dashboard/ writable for www-data..."
chgrp www-data /opt/m17/rpi-dashboard/
chmod g+w /opt/m17/rpi-dashboard/

if ! grep -q 'HostFile=/opt/m17/rpi-dashboard/files/M17Hosts.txt' /etc/m17-gateway.ini; then
    echo "Updating m17-gateway.ini..."
    sed \
        -e 's|HostFile=/opt/m17/m17-gateway/M17Hosts.txt|HostFile=/opt/m17/rpi-dashboard/files/M17Hosts.txt|g' \
        -e 's|OverrideHostFile=/opt/m17/m17-gateway/OverrideHosts.txt|OverrideHostFile=/opt/m17/rpi-dashboard/files/OverrideHosts.txt|g' \
        /etc/m17-gateway.ini > /tmp/m17-gateway.ini
    cp /tmp/m17-gateway.ini /etc/m17-gateway.ini
fi

echo "🔗 Creating symlinks to expose gateway data to dashboard..."
ln -sf /opt/m17/m17-gateway/dashboard.log /opt/m17/rpi-dashboard/files/dashboard.log
ln -sf /etc/m17-gateway.ini /opt/m17/rpi-dashboard/files/m17-gateway.ini

if [ -f $M17_HOME/m17-gateway/dashboard.log ]; then
    # Ensure dashboard.log is accessible
    chmod 644 $M17_HOME/m17-gateway/dashboard.log
fi

IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Final Instructions
echo -e "\n🎉 All done! If this is a new installation, PLEASE REBOOT YOUR RASPBERRY NOW!"
echo -e "\nTo access the dashboard go to: http://$IP_ADDRESS/ or http://$(hostname).local/"
echo -e "\nThere, to configure your node (call sign, frequency etc), click on 'Gateway Config'."
echo -e "\nIf you have an MMDVM HAT, you must make configuration changes before it will work!"
echo -e "\nSee the README for details: https://github.com/M17-Project/cc1200-hotspot-installer/tree/main#mmdvm-configuration"
echo -e "\nYou will find further information under 'Help' in the dashboard."
