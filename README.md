# M17 CC1200 Hotspot Installation Script

This repository contains a Bash script to convert a Raspberry Pi (with a CC1200 hat) into a fully functional **M17 digital voice hotspot**. The script automates the entire installation and setup process, including compiling the necessary software, configuring UART, setting up the web dashboard, and flashing the firmware to the CC1200 HAT (optional).

---

## Install Script Usage

Execute the following on the Raspberry Pi to download the installer:

```
wget https://raw.githubusercontent.com/DK1MI/cc1200-hotspot-installer/main/cc1200-hotspot-installer.sh
```

Carefully read the script before you execute it with:

```
chmod u+x cc1200-hotspot-installer.sh
sudo ./cc1200-hotspot-installer.sh
```

## Features

- Verifies root and OS requirements
- Ensures it's run on a **fresh install** of Raspberry Pi OS Lite (Bookworm, 64-bit)
- Configures UART for GPIO access
- Prompts for required reboots after system update and boot option changes
- Installs all necessary packages via APT
- Creates a dedicated _m17_ user for running services
- Clones and compiles the following M17 Project repositories:
  - [libm17](https://github.com/M17-Project/libm17)
  - [CC1200_HAT-fw](https://github.com/M17-Project/CC1200_HAT-fw) (firmware flashing optional)
  - [rpi-dashboard](https://github.com/M17-Project/rpi-dashboard) (web interface)
- Installs [m17-gateway](https://github.com/jancona/m17)
- Configures NGINX and PHP-FPM to serve the dashboard
- Optionally flashes/updates the CC1200 firmware via stm32flash

---

## Tested Hardware and OS

This script was tested on:

- **Raspberry Pi Zero 2 W**
- **Raspberry Pi OS Lite (64-bit), Bookworm (Debian 12-based)**

Other Pi models or OS versions may work but are **not officially supported**.

---

## Prerequisites

- Fresh install of Raspberry Pi OS Bookworm **Lite (64-bit)**
- Raspberry Pi with internet access
- CC1200 HAT connected
- Run the script as **root**

---

## File Summary

- `/opt/m17/` - Main working directory for M17-related repositories
- `/opt/m17/rpi-dashboard/` - Web interface root (served by NGINX)
- `/opt/m17/m17-gateway/` - m17-gateway installation root
- `/etc/rpi-gateway.ini` - Gateway configuration file
- `/boot/firmware/config.txt` - UART settings applied here

---

## Hotspot Usage

This script builds an M17 hotspot which consists of two software components:

- [rpi-gateway](https://github.com/jancona/m17)
- [rpi-dashboard](https://github.com/M17-Project/rpi-dashboard)

Please read the manual of both software packages.

To start _m17-gateway_ manually, just execute the following line:

```
sudo systemctl start m17-gateway.service
```

This service will connect you to the M17 reflector of your choice and writes all available info to the console.

To access the dashboard, simply navigate your browser to _http://<IP_OF_YOUR_RPI>_.

---

## Disclaimer

This script makes **system-wide changes** and should **only be run on a clean install**. Do **not** use on a production system or one with existing services unless you know what you're doing.

---

## Support

For questions or issues, please contact [M17 Project](https://m17project.org/) or open a GitHub issue in the relevant repository.

---

## License

This script is provided as-is, under the GPL License. Contributions welcome.

