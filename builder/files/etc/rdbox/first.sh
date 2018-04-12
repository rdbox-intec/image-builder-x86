#!/bin/bash

regex_master='^.*master.*'
regex_slave='^.*slave.*'
hname=`/bin/hostname`

if [[ $hname =~ $regex_master ]]; then
  mv /etc/network/interfaces /etc/network/interfaces.org
  cp -rf /etc/rdbox/networks/interface/master /etc/network/interfaces
  /etc/init.d/networking restart
elif [[ $hname =~ $regex_slave ]]; then
  mv /etc/network/interfaces /etc/network/interfaces.org
  cp -rf /etc/rdbox/networks/interface/slave /etc/network/interfaces
  /etc/init.d/networking restart
fi

ln -s /etc/rdbox/services/rdbox_boot.service /lib/systemd/system/rdbox_boot.service
/bin/bash /etc/rdbox/boot.sh

exit 0
