#!/bin/bash
set -ex

KEYSERVER="ha.pool.sks-keyservers.net"

function clean_print(){
  local fingerprint="${2}"
  local func="${1}"

  nospaces=${fingerprint//[:space:]/} tolowercase=${nospaces,,}
  KEYID_long=${tolowercase:(-16)}
  KEYID_short=${tolowercase:(-8)}
  if [[ "${func}" == "fpr" ]]; then
    echo "${tolowercase}"
  elif [[ "${func}" == "long" ]]; then
    echo "${KEYID_long}"
  elif [[ "${func}" == "short" ]]; then
    echo "${KEYID_short}"
  elif [[ "${func}" == "print" ]]; then
    if [[ "${fingerprint}" != "${nospaces}" ]]; then printf "%-10s %50s\n" fpr: "${fingerprint}"
    fi
    # if [[ "${nospaces}" != "${tolowercase}" ]]; then
    #   printf "%-10s %50s\n" nospaces: $nospaces
    # fi
    if [[ "${tolowercase}" != "${KEYID_long}" ]]; then
      printf "%-10s %50s\n" lower: "${tolowercase}"
    fi
    printf "%-10s %50s\n" long: "${KEYID_long}"
    printf "%-10s %50s\n" short: "${KEYID_short}"
    echo ""
  else
    echo "usage: function {print|fpr|long|short} GPGKEY"
  fi
}


function get_gpg(){
  GPG_KEY="${1}"
  KEY_URL="${2}"

  clean_print print "${GPG_KEY}"
  GPG_KEY=$(clean_print fpr "${GPG_KEY}")

  if [[ "${KEY_URL}" =~ ^https?://* ]]; then
    echo "loading key from url"
    KEY_FILE=temp.gpg.key
    wget -q -O "${KEY_FILE}" "${KEY_URL}"
  elif [[ -z "${KEY_URL}" ]]; then
    echo "no source given try to load from key server"
#    gpg --keyserver "${KEYSERVER}" --recv-keys "${GPG_KEY}"
    apt-key adv --keyserver "${KEYSERVER}" --recv-keys "${GPG_KEY}"
    return $?
  else
    echo "keyfile given"
    KEY_FILE="${KEY_URL}"
  fi

  FINGERPRINT_OF_FILE=$(gpg --with-fingerprint --with-colons "${KEY_FILE}" | grep fpr | rev |cut -d: -f2 | rev)

  if [[ ${#GPG_KEY} -eq 16 ]]; then
    echo "compare long keyid"
    CHECK=$(clean_print long "${FINGERPRINT_OF_FILE}")
  elif [[ ${#GPG_KEY} -eq 8 ]]; then
    echo "compare short keyid"
    CHECK=$(clean_print short "${FINGERPRINT_OF_FILE}")
  else
    echo "compare fingerprint"
    CHECK=$(clean_print fpr "${FINGERPRINT_OF_FILE}")
  fi

  if [[ "${GPG_KEY}" == "${CHECK}" ]]; then
    echo "key OK add to apt"
    apt-key add "${KEY_FILE}"
    rm -f "${KEY_FILE}"
    return 0
  else
    echo "key invalid"
    exit 1
  fi
}

## examples:
# clean_print {print|fpr|long|short} {GPGKEYID|FINGERPRINT}
# get_gpg {GPGKEYID|FINGERPRINT} [URL|FILE]

# device specific settings
HYPRIOT_DEVICE="Raspberry Pi"

# set up /etc/resolv.conf
DEST=$(readlink -m /etc/resolv.conf)
export DEST
mkdir -p "$(dirname "${DEST}")"
echo "nameserver 8.8.8.8" > "${DEST}"

# set up hypriot rpi repository for rpi specific kernel- and firmware-packages
PACKAGECLOUD_FPR=418A7F2FB0E1E6E7EABF6FE8C2E73424D59097AB
PACKAGECLOUD_KEY_URL=https://packagecloud.io/gpg.key
get_gpg "${PACKAGECLOUD_FPR}" "${PACKAGECLOUD_KEY_URL}"

echo 'deb https://packagecloud.io/Hypriot/rpi/debian/ jessie main' > /etc/apt/sources.list.d/hypriot.list

# set up hypriot schatzkiste repository for generic packages
echo 'deb https://packagecloud.io/Hypriot/Schatzkiste/debian/ jessie main' >> /etc/apt/sources.list.d/hypriot.list

# set up Docker CE repository
DOCKERREPO_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
DOCKERREPO_KEY_URL=https://download.docker.com/linux/raspbian/gpg
get_gpg "${DOCKERREPO_FPR}" "${DOCKERREPO_KEY_URL}"

CHANNEL=edge # stable, test or edge
echo "deb [arch=armhf] https://download.docker.com/linux/raspbian jessie $CHANNEL" > /etc/apt/sources.list.d/docker.list


RPI_ORG_FPR=CF8A1AF502A2AA2D763BAE7E82B129927FA3303E RPI_ORG_KEY_URL=http://archive.raspberrypi.org/debian/raspberrypi.gpg.key
get_gpg "${RPI_ORG_FPR}" "${RPI_ORG_KEY_URL}"

echo 'deb http://archive.raspberrypi.org/debian/ jessie main' | tee /etc/apt/sources.list.d/raspberrypi.list

# install cloud-init
## jessie backports
echo "deb http://ftp.`curl -s ipinfo.io/52.193.175.205/country | tr "[:upper:]" "[:lower:]"`.debian.org/debian jessie-backports main contrib non-free" | tee /etc/apt/sources.list.d/jessie-backports.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 8B48AD6246925553
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 7638D0442B90D010

# install ansible
## ppa
echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main" | tee /etc/apt/sources.list.d/ansible.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367

# install kubeadmn
## ppa
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

# reload package sources
apt-get update
apt-get upgrade -y

# install WiFi firmware packages (same as in Raspbian)
apt-get install -y \
  --no-install-recommends \
  firmware-atheros \
  firmware-brcm80211 \
  firmware-libertas \
  firmware-ralink \
  firmware-realtek

# install kernel- and firmware-packages
apt-get install -y \
  --no-install-recommends \
  "raspberrypi-kernel=${KERNEL_BUILD}" \
  "raspberrypi-bootloader=${KERNEL_BUILD}" \
  "libraspberrypi0=${KERNEL_BUILD}" \
  "libraspberrypi-dev=${KERNEL_BUILD}" \
  "libraspberrypi-bin=${KERNEL_BUILD}"

# enable serial console
printf "# Spawn a getty on Raspberry Pi serial line\nT0:23:respawn:/sbin/getty -L ttyAMA0 115200 vt100\n" >> /etc/inittab

# boot/cmdline.txt
echo "+dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 cgroup_enable=cpuset cgroup_enable=memory swapaccount=1 elevator=deadline fsck.repair=yes rootwait console=ttyAMA0,115200 kgdboc=ttyAMA0,115200" > /boot/cmdline.txt

# create a default boot/config.txt file (details see http://elinux.org/RPiconfig)
echo "
hdmi_force_hotplug=1
enable_uart=1
" > boot/config.txt

echo "# camera settings, see http://elinux.org/RPiconfig#Camera
start_x=1
disable_camera_led=1
gpu_mem=128
" >> boot/config.txt

# /etc/modules
echo "snd_bcm2835
" >> /etc/modules

# create /etc/fstab
echo "
proc /proc proc defaults 0 0
/dev/mmcblk0p1 /boot vfat defaults 0 0
/dev/mmcblk0p2 / ext4 defaults,noatime 0 1
" > /etc/fstab

# as the Pi does not have a hardware clock we need a fake one
apt-get install -y \
  --no-install-recommends \
  fake-hwclock

# install packages for managing wireless interfaces
apt-get install -y \
  --no-install-recommends \
  wpasupplicant \
  wireless-tools \
  ethtool \
  crda

# add firmware and packages for managing bluetooth devices
apt-get install -y \
  --no-install-recommends \
  bluetooth \
  pi-bluetooth

# ensure compatibility with Docker install.sh, so `raspbian` will be detected correctly
apt-get install -y \
  --no-install-recommends \
  lsb-release

# install cloud-init
apt-get -t jessie-backports install -y \
  cloud-init
apt-get install -y \
  debian-keyring \
  debian-archive-keyring
mkdir -p /var/lib/cloud/seed/nocloud-net
ln -s /boot/user-data /var/lib/cloud/seed/nocloud-net/user-data
ln -s /boot/meta-data /var/lib/cloud/seed/nocloud-net/meta-data

# install docker-machine
curl -sSL -o /usr/local/bin/docker-machine "https://github.com/docker/machine/releases/download/v${DOCKER_MACHINE_VERSION}/docker-machine-Linux-armhf"
chmod +x /usr/local/bin/docker-machine

# install bash completion for Docker Machine
curl -sSL "https://raw.githubusercontent.com/docker/machine/v${DOCKER_MACHINE_VERSION}/contrib/completion/bash/docker-machine.bash" -o /etc/bash_completion.d/docker-machine

# install docker-compose
apt-get install -y \
  --no-install-recommends \
  python-pip
pip install "docker-compose==${DOCKER_COMPOSE_VERSION}"

# install bash completion for Docker Compose
curl -sSL "https://raw.githubusercontent.com/docker/compose/${DOCKER_COMPOSE_VERSION}/contrib/completion/bash/docker-compose" -o /etc/bash_completion.d/docker-compose

# install docker-ce (w/ install-recommends)
apt-get install -y --force-yes \
  "docker-ce=${DOCKER_CE_VERSION}"

echo "Installing rpi-serial-console script"
wget -q https://raw.githubusercontent.com/lurch/rpi-serial-console/master/rpi-serial-console -O usr/local/bin/rpi-serial-console
chmod +x usr/local/bin/rpi-serial-console

# rtl8812au compliant
## add kernel headers
apt-get install -y \
  jq \
  linux-headers-${KERNEL_VERSION}-hypriotos-v7+ \
  build-essential
wget -q https://raw.githubusercontent.com/armbian/build/next/patch/headers-debian-byteshift.patch -P /tmp
patch -d /usr/src/linux-headers-${KERNEL_VERSION}-hypriotos-v7+ -p1 < /tmp/headers-debian-byteshift.patch
make -j`grep -c ^processor /proc/cpuinfo | tr -d '\n'` -C /usr/src/linux-headers-${KERNEL_VERSION}-hypriotos-v7+ scripts

# rtl8812au compliant
## add dmks driver
RTL8812AU_SITE=mk-fg/rtl8812au
RTL8812AU_COMMIT_VER=`curl -qsS https://api.github.com/repos/$RTL8812AU_SITE/commits | jq .[0].sha | sed 's/"//g' | cut -c 1-8 | tr -d '\n'`
RTL8812AU_STR_VER=`curl -qsS https://raw.githubusercontent.com/$RTL8812AU_SITE/master/README.rst | grep -A 1 -B 1 "which is based on " | tr -d '\n' |sed -e 's/^.*on \([0-9０-９.]*\).*$/\1/' | tr -d '\n'`
apt-get install -y \
  git \
  bc \
  unzip \
  dkms
wget -q https://github.com/$RTL8812AU_SITE/archive/master.zip -P /tmp
unzip /tmp/master.zip -d /tmp
sed -i -e "s/^ARCH ?= arm64$/ARCH ?= arm/g" /tmp/rtl8812au-master/Makefile
sed -i -e "s/^CONFIG_RTW_DEBUG = y$/CONFIG_RTW_DEBUG = n/g" /tmp/rtl8812au-master/Makefile
sed -i -e "s/^CONFIG_RTW_LOG_LEVEL = 4$/CONFIG_RTW_LOG_LEVEL = 0/g" /tmp/rtl8812au-master/Makefile
mv /tmp/rtl8812au-master /usr/src/rtl8812au-$RTL8812AU_STR_VER.$RTL8812AU_COMMIT_VER
dkms add -m rtl8812au -v $RTL8812AU_STR_VER.$RTL8812AU_COMMIT_VER -c /usr/src/rtl8812au-$RTL8812AU_STR_VER.$RTL8812AU_COMMIT_VER/dkms.conf -k ${KERNEL_VERSION}-hypriotos-v7+
dkms build -m rtl8812au -v $RTL8812AU_STR_VER.$RTL8812AU_COMMIT_VER -c /usr/src/rtl8812au-$RTL8812AU_STR_VER.$RTL8812AU_COMMIT_VER/dkms.conf -k ${KERNEL_VERSION}-hypriotos-v7+
dkms install -m rtl8812au -v $RTL8812AU_STR_VER.$RTL8812AU_COMMIT_VER -c /usr/src/rtl8812au-$RTL8812AU_STR_VER.$RTL8812AU_COMMIT_VER/dkms.conf -k ${KERNEL_VERSION}-hypriotos-v7+


# Built in WiFi
## enable udev/rules.d
sed -i '/^KERNEL!="ath/c KERNEL!="ath*|msh*|ra*|sta*|ctc*|lcs*|hsi*|eth*|wlan*", \\' /etc/udev/rules.d/75-persistent-net-generator.rules
cp /etc/rdbox/networks/70-persistent-net.rules /etc/udev/rules.d/70-persistent-net.rules

# install ansible
## apt-get
apt-get install -y \
  ansible

# Multi-hop Wi-Fi
## bridge and batman
apt-get install -y \
  bridge-utils \
  batctl \
  git
echo "batman-adv" >> /etc/modules
## hostapd
apt-get install -y \
  libnl-dev
apt-get install -y \
  libnl-3-dev \
  libnl-genl-3-dev \
  libssl-dev \
  pkg-config \
  git
apt-get install -y \
  binutils-dev \
  libiberty-dev
apt-get install -y \
  hostapd
wget -q http://blog.fraggod.net/misc/hostapd-2.6-no-bss-conflicts.patch -P /tmp
wget -q https://w1.fi/releases/hostapd-${HOSTAPD_VERSION}.tar.gz -P /tmp
tar xvzf /tmp/hostapd-${HOSTAPD_VERSION}.tar.gz -C /usr/local/src
patch -d /usr/local/src/hostapd-${HOSTAPD_VERSION} -p1 < /tmp/hostapd-2.6-no-bss-conflicts.patch
cp -rf /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/defconfig /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_LIBNL32=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_IEEE80211N=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_IEEE80211AC=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_ACS=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_WPS=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_EAP_PSK=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_WPA_TRACE=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_WPA_TRACE_BFD=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_EAP_GPSK=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
echo CONFIG_EAP_GPSK_SHA256=y >> /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/.config
make -j`grep -c ^processor /proc/cpuinfo | tr -d '\n'` -C /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/
cp -rf /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/hostapd /usr/sbin/hostapd
cp -rf /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/hostapd_cli /usr/sbin/hostapd_cli
update-rc.d hostapd remove
#make -C /usr/local/src/hostapd-${HOSTAPD_VERSION}/hostapd/ install

# install kubeadmn
## apt-get
apt-get install -y \
  apt-transport-https
apt-get install -y \
  kubelet \
  kubeadm \
  kubectl

# Security settings
## /etc/ssh/sshd_config
sed -i '/^Port 22$/c Port 12810' /etc/ssh/sshd_config
sed -i '/^LoginGraceTime 120$/c LoginGraceTime 15' /etc/ssh/sshd_config
#sed -i '/^#PasswordAuthentication yes$/c PasswordAuthentication no' /etc/ssh/sshd_config
echo "MaxAuthTries 2" >> /etc/ssh/sshd_config

# Locale settings
## For US JP
apt-get install -y \
  task-english \
  task-japanese
sed -i '/^# ja_JP.UTF-8 UTF-8$/c ja_JP.UTF-8 UTF-8' /etc/locale.gen
locale-gen

# Network settings
## /etc/sysctl.conf
echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.forwarding = 1" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.forwarding = 1" >> /etc/sysctl.conf
## /etc/wpa_supplicant/wpa_supplicant.conf
cp /etc/rdbox/networks/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
## /etc/hosts
cp /etc/rdbox/networks/hosts.debian.tmpl /etc/cloud/templates/hosts.debian.tmpl
## /etc/hostapd/hostapd.conf
cp /etc/rdbox/networks/hostapd/hostapd_be.conf /etc/hostapd/hostapd_be.conf
cp /etc/rdbox/networks/hostapd/hostapd_ap_ac.conf /etc/hostapd/hostapd_ap_ac.conf

# deprecated
# It will run on Docker.
## dnsmasq
apt-get install -y \
  dnsmasq
echo ""
echo ""
echo "no-dhcp-interface=eth0,wlan0,wlan1,wlan2,wlan3,wlan4" >> /etc/dnsmasq.conf
echo "listen-address=127.0.0.1,192.168.179.1" >> /etc/dnsmasq.conf
echo "interface=br0" >> /etc/dnsmasq.conf
echo "dhcp-leasefile=/etc/rdbox/share/dnsmasq.leases" >> /etc/dnsmasq.conf
echo "dhcp-hostsfile=/etc/rdbox/share/dnsmasq.hosts.conf" >> /etc/dnsmasq.conf
echo "dhcp-range=192.168.179.2,192.168.179.254,255.255.255.0,12h" >> /etc/dnsmasq.conf
echo "dhcp-option=option:router,192.168.179.1" >> /etc/dnsmasq.conf
echo "dhcp-option=option:dns-server,192.168.179.1,8.8.8.8,8.8.4.4" >> /etc/dnsmasq.conf
echo "dhcp-option=option:ntp-server,192.168.179.1" >> /etc/dnsmasq.conf

# cleanup APT cache and lists
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# set device label and version number
echo "HYPRIOT_DEVICE=\"$HYPRIOT_DEVICE\"" >> /etc/os-release
echo "HYPRIOT_IMAGE_VERSION=\"$HYPRIOT_IMAGE_VERSION\"" >> /etc/os-release
cp /etc/os-release /boot/os-release
