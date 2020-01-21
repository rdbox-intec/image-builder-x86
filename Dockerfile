FROM debian:buster

RUN  \
    sed -i 's,http://httpredir.debian.org/debian,http://ftp.us.debian.org/debian/,' /etc/apt/sources.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python-pip \
    build-essential \
    libguestfs-tools \
    libncurses5-dev \
    tree \
    debootstrap \
    kpartx \
    lvm2 \
    dosfstools \
    zip \
    unzip \
    pigz \
    awscli \
    ruby \
    ruby-dev \
    shellcheck \
    --no-install-recommends && \
    sed -i 's,http://ftp.us.debian.org/debian/,http://httpredir.debian.org/debian,' /etc/apt/sources.list && \
    rm -rf /var/lib/apt/lists/*

RUN gem update --system && \
    gem install --no-document serverspec && \
    gem install --no-document pry-byebug && \
    gem install --no-document bundler

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    binfmt-support \
    qemu \
    qemu-user-static \
    jq \
    dirmngr \
    xxd \
    live-boot \
    live-build \
    live-config \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

RUN sed -i '1161s%umount%#umount%' /usr/share/debootstrap/functions

COPY builder/ /builder/

# build sd card image
CMD /builder/build.sh
