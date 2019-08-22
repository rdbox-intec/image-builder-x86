# -*- mode: ruby -*-
# vi: set ft=ruby :
ENV['VAGRANT_DEFAULT_PROVIDER'] = 'virtualbox'

Vagrant.configure(2) do |config|
  config.vm.box = "generic/debian10"
  config.disksize.size = '60GB'

  config.vm.network "forwarded_port", guest: 2375, host: 2375, auto_correct: true
  config.vm.synced_folder ".", "#{`pwd`.chomp}"

  config.vm.provider "vmware_fusion" do |v|
    # Customize the amount of memory on the VM:
    v.memory = "2048"
  end

  config.vm.provider "virtualbox" do |vb|
    # Customize the amount of memory on the VM:
    vb.memory = "6144"
    vb.cpus = 3
  end

  config.vm.provision "shell", inline: <<-SHELL
    sudo apt-get update
    sudo apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    sudo add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/debian \
      $(lsb_release -cs) \
      stable"
    sudo apt-get update
    sudo apt-get install docker-ce -y
    mkdir -p /etc/systemd/system/docker.service.d/
    # https://docs.docker.com/engine/admin/#troubleshoot-conflicts-between-the-daemonjson-and-startup-scripts
    echo "[Service]
ExecStart=
ExecStart=/usr/bin/dockerd" > /etc/systemd/system/docker.service.d/docker.conf
    echo '{ "hosts": ["tcp://0.0.0.0:2375"] }' > /etc/docker/daemon.json
     sudo systemctl daemon-reload
     sudo systemctl enable docker
     sudo systemctl restart docker


  SHELL
end
