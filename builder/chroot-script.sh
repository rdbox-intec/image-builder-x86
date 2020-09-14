#!/bin/bash
set -ex

KEYSERVER="hkp://ha.pool.sks-keyservers.net:80"

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
        if [[ "${fingerprint}" != "${nospaces}" ]]; then printf "%-10s %50s\\n" fpr: "${fingerprint}"
        fi
        # if [[ "${nospaces}" != "${tolowercase}" ]]; then
        #   printf "%-10s %50s\n" nospaces: $nospaces
        # fi
        if [[ "${tolowercase}" != "${KEYID_long}" ]]; then
            printf "%-10s %50s\\n" lower: "${tolowercase}"
        fi
        printf "%-10s %50s\\n" long: "${KEYID_long}"
        printf "%-10s %50s\\n" short: "${KEYID_short}"
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
echo "EDITION=$EDITION"

# device specific settings
HYPRIOT_DEVICE="Debian10(x86-64bit)"

# set up /etc/resolv.conf
DEST=$(readlink -m /etc/resolv.conf)
export DEST
mkdir -p "$(dirname "${DEST}")"
echo "nameserver 8.8.8.8" > "${DEST}"
echo "nameserver 8.8.4.4" >> "${DEST}"

# set up Docker CE repository
DOCKERREPO_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
DOCKERREPO_KEY_URL=https://download.docker.com/linux/debian/gpg
get_gpg "${DOCKERREPO_FPR}" "${DOCKERREPO_KEY_URL}"

echo "deb [arch=amd64] https://download.docker.com/linux/debian buster $DOCKER_CE_CHANNEL" > /etc/apt/sources.list.d/docker.list

c_rehash

# our repo
curl -s https://bintray.com/user/downloadSubjectPublicKey?username=rdbox | apt-key add -
echo "deb https://dl.bintray.com/rdbox/deb buster main" | tee /etc/apt/sources.list.d/rdbox.list
echo 'Package: *
Pin: release n=buster
Pin: release c=rdbox
Pin: origin dl.bintray.com
Pin-Priority: 999' | tee /etc/apt/preferences.d/rdbox

# install kubeadmn
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
################################################ RDBOX #


# reload package sources
apt-get update
apt-get upgrade -y

# install WiFi firmware packages (same as in Raspbian)
apt-get install -y \
--no-install-recommends \
firmware-atheros \
firmware-iwlwifi \
firmware-realtek \
firmware-brcm80211 \
firmware-libertas \
firmware-misc-nonfree \
firmware-realtek

# install packages for managing wireless interfaces
apt-get install -y \
--no-install-recommends \
wpasupplicant \
wireless-tools \
crda

# ensure compatibility with Docker install.sh, so `raspbian` will be detected correctly
apt-get install -y \
--no-install-recommends \
lsb-release \
gettext

# install cloud-init
apt-get install -y \
--no-install-recommends \
cloud-init \
ssh-import-id

# Link cloud-init config to VFAT /boot partition
mkdir -p /var/lib/cloud/seed/nocloud-net
ln -s /boot/user-data /var/lib/cloud/seed/nocloud-net/user-data
ln -s /boot/meta-data /var/lib/cloud/seed/nocloud-net/meta-data

# Fix duplicate IP address for eth0, remove file from os-rootfs
rm -f /etc/network/interfaces.d/eth0

# install docker-machine
curl -sSL -o /usr/local/bin/docker-machine "https://github.com/docker/machine/releases/download/v${DOCKER_MACHINE_VERSION}/docker-machine-Linux-x86_64"
chmod +x /usr/local/bin/docker-machine

# install bash completion for Docker Machine
curl -sSL "https://raw.githubusercontent.com/docker/machine/v${DOCKER_MACHINE_VERSION}/contrib/completion/bash/docker-machine.bash" -o /etc/bash_completion.d/docker-machine

# [PRE] install docker-compose
apt-get install -y \
  --no-install-recommends \
  python3 python3-pip python3-setuptools
update-alternatives --install /usr/bin/python python /usr/bin/python3.7 2

# install bash completion for Docker Compose
curl -sSL "https://raw.githubusercontent.com/docker/compose/${DOCKER_COMPOSE_VERSION}/contrib/completion/bash/docker-compose" -o /etc/bash_completion.d/docker-compose

# install docker-ce (w/ install-recommends)
apt-get install -y --force-yes \
"docker-ce=${DOCKER_CE_VERSION}" \
"docker-ce-cli=${DOCKER_CE_VERSION}" \
containerd.io
apt-mark hold docker-ce docker-ce-cli containerd.io

# install bash completion for Docker CLI
curl -sSL https://raw.githubusercontent.com/docker/docker-ce/master/components/cli/contrib/completion/bash/docker -o /etc/bash_completion.d/docker


# RDBOX ##################################################
if [ "${BUILDER}" = "cloud" ]; then
    ## rdbox
    apt-get install -y \
    rdbox
    systemctl disable rdbox-boot.service
    # our repo
    apt-get install -y \
    softether-vpnclient \
    softether-vpnbridge \
    softether-vpncmd
    apt-get install -y \
    hostapd
    systemctl disable hostapd.service
    apt-get install -y \
    transproxy
elif [ "${BUILDER}" = "local" ]; then
    ## rdbox
    apt-get install -y \
    gdebi
    gdebi -n "$(echo /tmp/deb-files/*rdbox_*.deb | grep -v dbgsym | sed 's/ /\n/g' | sort -r | head -1)"
    systemctl disable rdbox-boot.service
    # our repo
    gdebi -n "$(echo /tmp/deb-files/*softether-vpncmd_*.deb | grep -v dbgsym | sed 's/ /\n/g' | sort -r | head -1)"
    gdebi -n "$(echo /tmp/deb-files/*softether-vpnbridge_*.deb | grep -v dbgsym | sed 's/ /\n/g' | sort -r | head -1)"
    gdebi -n "$(echo /tmp/deb-files/*softether-vpnclient_*.deb | grep -v dbgsym | sed 's/ /\n/g' | sort -r | head -1)"
    apt-get install -y \
    hostapd
    systemctl disable hostapd.service
    systemctl disable wpa_supplicant.service
    gdebi -n "$(echo /tmp/deb-files/*transproxy_*.deb | grep -v dbgsym | sed 's/ /\n/g' | sort -r | head -1)"
fi
apt-mark hold rdbox

# Built in WiFi
## suppress NIC barrel
echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="b8:27:eb:??:??:??", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="eth0"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="b8:27:eb:??:??:??", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="wlan*", NAME="wlan0"
' > /etc/udev/rules.d/70-persistent-net.rules

# enable daemon.json
mkdir -p /etc/docker
echo '{}' > /etc/docker/daemon.json

# Multi-hop Wi-Fi
## bridge and batman
apt-get install -y \
bridge-utils \
batctl
echo "batman-adv" >> /etc/modules

# install kubeadmn
## apt-get
apt-get install -y \
apt-transport-https
apt-get install -y \
kubelet="${KUBEADM_VERSION}" \
kubeadm="${KUBEADM_VERSION}" \
kubectl="${KUBEADM_VERSION}" \
kubernetes-cni="${KUBERNETES_CNI_VERSION}"
apt-mark hold kubelet kubeadm kubectl kubernetes-cni

# Security settings
## /etc/ssh/sshd_config
sed -i '/^#Port 22$/c Port 22' /etc/ssh/sshd_config
sed -i '/^#LoginGraceTime 2m$/c LoginGraceTime 10' /etc/ssh/sshd_config
sed -i '/^#PasswordAuthentication yes$/c PasswordAuthentication no' /etc/ssh/sshd_config
sed -i '/^#PermitRootLogin prohibit-password$/c PermitRootLogin no' /etc/ssh/sshd_config
echo "MaxAuthTries 2" >> /etc/ssh/sshd_config

# Locale settings
## For US JP
apt-get install -y \
task-english \
task-japanese \
task-chinese-s
sed -i '/^# ja_JP.UTF-8 UTF-8$/c ja_JP.UTF-8 UTF-8' /etc/locale.gen
sed -i '/^# zh_CN.UTF-8 UTF-8$/c zh_CN.UTF-8 UTF-8' /etc/locale.gen
sed -i '/^# en_AU.UTF-8 UTF-8$/c en_AU.UTF-8 UTF-8' /etc/locale.gen
sed -i '/^# en_CA.UTF-8 UTF-8$/c en_CA.UTF-8 UTF-8' /etc/locale.gen
sed -i '/^# en_GB.UTF-8 UTF-8$/c en_GB.UTF-8 UTF-8' /etc/locale.gen
sed -i '/^# en_HK.UTF-8 UTF-8$/c en_HK.UTF-8 UTF-8' /etc/locale.gen
sed -i '/^# en_SG.UTF-8 UTF-8$/c en_SG.UTF-8 UTF-8' /etc/locale.gen
locale-gen

# Network settings
## /etc/sysctl.conf
echo '
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
' >> /etc/sysctl.conf


# deprecated
# It will run on Docker.
## dnsmasq
apt-get install -y \
bind9 \
dnsmasq \
resolvconf
systemctl disable dnsmasq.service
systemctl disable bind9
cp /etc/dnsmasq.conf /etc/rdbox/dnsmasq.conf.org
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.org
touch /etc/rdbox/dnsmasq.conf
ln -s /etc/rdbox/dnsmasq.conf /etc/dnsmasq.conf

# enable auto update & upgrade
apt-get install -y \
unattended-upgrades
echo -e 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
echo -e 'Unattended-Upgrade::Origins-Pattern {
  origin=Raspbian,label=Raspbian;
  origin=Debian,label=Debian-Security;
  origin="Raspberry Pi Foundation",label="Raspberry Pi Foundation";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
' > /etc/apt/apt.conf.d/50unattended-upgrades

# install NFS
apt-get install -y \
nfs-kernel-server \
nfs-common
sudo systemctl disable nfs-kernel-server.service

# For Helm(k8s)
apt-get install -y \
snapd
ln -s /snap/bin/helm /usr/local/bin/helm

# For Network Debug
apt-get install -y \
dnsutils \
jq \
traceroute

## For ansible
apt-get install -y \
libffi-dev \
python3-crypto \
build-essential \
fakeroot \
zlib1g \
libssl-dev \
python3-dev
# For rdbox_cli
apt-get install -y \
hwinfo \
libcairo2-dev
pip3 install -r /opt/rdbox/bin/requirements.txt
mkdir -m 777 /etc/ansible
echo '[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
[defaults]
retry_files_save_path = "/tmp"
' > /etc/ansible/ansible.cfg

# install docker-compose
pip3 install wheel
pip3 install "docker-compose==${DOCKER_COMPOSE_VERSION}"

# disable dhcpcd
systemctl disable dhcpcd.service

# for TB3 used by Tutorial
echo 'ATTRS{idVendor}=="0483" ATTRS{idProduct}=="5740", ENV{ID_MM_DEVICE_IGNORE}="1", MODE:="0666"
ATTRS{idVendor}=="0483" ATTRS{idProduct}=="df11", MODE:="0666"
ATTRS{idVendor}=="fff1" ATTRS{idProduct}=="ff48", ENV{ID_MM_DEVICE_IGNORE}="1", MODE:="0666"
ATTRS{idVendor}=="10c4" ATTRS{idProduct}=="ea60", ENV{ID_MM_DEVICE_IGNORE}="1", MODE:="0666"
' > /etc/udev/rules.d/99-turtlebot3-cdc.rules

systemctl disable systemd-resolved

sed -i '/^#HandleLidSwitch=/c HandleLidSwitch=ignore' /etc/systemd/logind.conf

cd ~

################################################ RDBOX #






# fix eth0 interface name
ln -s /dev/null /etc/systemd/network/99-default.link

# cleanup APT cache and lists
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# set device label and version number
echo "HYPRIOT_DEVICE=\"$HYPRIOT_DEVICE\"" >> /etc/os-release
echo "HYPRIOT_IMAGE_VERSION=\"$HYPRIOT_IMAGE_VERSION\"" >> /etc/os-release
cp /etc/os-release /boot/os-release
