#!/bin/bash -e
set -x
# This script should be run only inside of a Docker container
if [ ! -f /.dockerenv ]; then
  echo "ERROR: script works only in a Docker container!"
  exit 1
fi

# get versions for software that needs to be installed
# shellcheck disable=SC1091
source /workspace/versions.config

### setting up some important variables to control the build process

# place to store our created sd-image file
BUILD_RESULT_PATH="/workspace"

# place to build our sd-image
BUILD_PATH="/build"

# Show CIRCLE_TAG in Circle builds
echo CIRCLE_TAG="${CIRCLE_TAG}"

# name of the sd-image we gonna create
if [ "$1" = "rdbox" ]; then
  VERSION=${VERSION}
else
  VERSION=${VERSION}_$1
fi
HYPRIOT_IMAGE_VERSION=${VERSION:="dirty"}
HYPRIOT_IMAGE_NAME="hypriotos-x86-${HYPRIOT_IMAGE_VERSION}.img"
export HYPRIOT_IMAGE_VERSION

# download the ready-made raw image for the x86
if [ ! -f "${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" ]; then
  wget -q -O "${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" "https://github.com/rdbox-intec/image-builder-raw/releases/download/${RAW_IMAGE_VERSION}/${RAW_IMAGE}.zip"
fi

# verify checksum of the ready-made raw image
echo "${RAW_IMAGE_CHECKSUM} ${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" | sha256sum -c -

unzip -p "${BUILD_RESULT_PATH}/${RAW_IMAGE}" > "${BUILD_RESULT_PATH}/${HYPRIOT_IMAGE_NAME}"

# export the image partition UUID for use in the chroot script
IMAGE_PARTUUID_PREFIX=$(dd if="${BUILD_RESULT_PATH}/${HYPRIOT_IMAGE_NAME}" skip=440 bs=1 count=4 2>/dev/null | xxd -e | cut -f 2 -d' ')
export IMAGE_PARTUUID_PREFIX

# create build directory for assembling our image filesystem
rm -rf ${BUILD_PATH}
mkdir ${BUILD_PATH}

cd ${BUILD_PATH}
lb config \
  --debian-installer live \
  --architectures amd64 \
  --distribution buster \
  --iso-volume HypriotOS \
  --archive-areas 'main contrib non-free' \
  --bootappend-install 'preseed/file=/preseed.cfg'
cat <<EOF > ${BUILD_PATH}/config/package-lists/os-rootfs.list.chroot
apt-transport-https
avahi-daemon
bash-completion
binutils
ca-certificates
curl
git
htop
locales
net-tools
ntp
openssh-server
parted
sudo
usbutils
wget
libpam-systemd
cloud-init
gpg
EOF
lb bootstrap
lb chroot

#############
lb chroot_cache restore
lb chroot_devpts install
lb chroot_proc install
lb chroot_selinuxfs install
lb chroot_sysfs install
lb chroot_debianchroot install
lb chroot_dpkg install
lb chroot_tmpfs install
lb chroot_sysv-rc install
lb chroot_hosts install
lb chroot_resolv install
lb chroot_hostname install
lb chroot_archives chroot install
#===========================================================================================
cp -R /builder/files/* ${BUILD_PATH}/chroot/
EDITION=$1 BUILDER=$2 chroot ${BUILD_PATH}/chroot /bin/bash < /builder/chroot-script.sh
#===========================================================================================
lb chroot_archives chroot remove
lb chroot_apt remove
lb chroot_hostname remove
lb chroot_resolv remove
lb chroot_hosts remove
lb chroot_sysv-rc remove
lb chroot_tmpfs remove
lb chroot_dpkg remove
lb chroot_debianchroot remove
lb chroot_sysfs remove
lb chroot_selinuxfs remove
lb chroot_proc remove
lb chroot_devpts remove
lb chroot_cache save
#############


lb installer


#############
mkdir ${BUILD_PATH}/initrd
gunzip < ${BUILD_PATH}/binary/install/initrd.gz | cpio -i -D ${BUILD_PATH}/initrd/
cp -rf ${BUILD_RESULT_PATH}/preseed.cfg ${BUILD_PATH}/initrd/preseed.cfg
cd ${BUILD_PATH}/initrd
find . | cpio -H newc --create | gzip -9 >  ../initrd.gz
cd ${BUILD_PATH}
cp -rf ${BUILD_PATH}/initrd.gz ${BUILD_PATH}/binary/install/initrd.gz
#############

lb binary
lb source

if [ ! -f "${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" ]; then
  wget -q -O "${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" "https://github.com/rdbox-intec/image-builder-raw/releases/download/${RAW_IMAGE_VERSION}/${RAW_IMAGE}.zip"
fi

# verify checksum of the ready-made raw image
echo "${RAW_IMAGE_CHECKSUM} ${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" | sha256sum -c -

unzip -p "${BUILD_RESULT_PATH}/${RAW_IMAGE}" > "${BUILD_RESULT_PATH}/${HYPRIOT_IMAGE_NAME}"

#############
cp -rL ${BUILD_PATH}/binary ${BUILD_PATH}/rdbox 2>/dev/null || :
cp -rf ${BUILD_RESULT_PATH}/syslinux.cfg ${BUILD_PATH}/rdbox
cp -rf /builder/files/boot/* ${BUILD_PATH}/rdbox
cp -rf ${BUILD_RESULT_PATH}/splash.png ${BUILD_PATH}/rdbox/splash.png
cp -rf ${BUILD_RESULT_PATH}/splash.png ${BUILD_PATH}/rdbox/isolinux/splash.png
sed -i '/^label=/c label=HypriotOS' ${BUILD_PATH}/rdbox/autorun.inf
sed -i '/^timeout/c timeout 30' ${BUILD_PATH}/rdbox/isolinux/isolinux.cfg
sed -i -e '3i\
\tmenu default' ${BUILD_PATH}/rdbox/isolinux/install.cfg
cd ${BUILD_PATH}/rdbox
tar cvzf /rdbox.tar.gz .
ls -lah /rdbox.tar.gz
#############

# create the image and add root base filesystem
guestfish -a "${BUILD_RESULT_PATH}/${HYPRIOT_IMAGE_NAME}"<<_EOF_
  run
  pwrite-device /dev/sda "1234" 0x01b8
  syslinux /dev/sda1
  part-set-bootable /dev/sda 1 1
  mount /dev/sda1 /
  tar-in /rdbox.tar.gz / compress:gzip
_EOF_

# ensure that the CircleCI user can access the sd-card image file
umask 0000

# compress image
cd ${BUILD_RESULT_PATH} && zip "${HYPRIOT_IMAGE_NAME}.zip" "${HYPRIOT_IMAGE_NAME}"
cd ${BUILD_RESULT_PATH} && sha256sum "${HYPRIOT_IMAGE_NAME}.zip" > "${HYPRIOT_IMAGE_NAME}.zip.sha256" && cd -

# test sd-image that we have built
cd ${BUILD_RESULT_PATH}
VERSION=${HYPRIOT_IMAGE_VERSION} rspec --format documentation --color ${BUILD_RESULT_PATH}/builder/test > ${BUILD_RESULT_PATH}/testresult.log
