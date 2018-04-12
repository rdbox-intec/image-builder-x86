#!/bin/bash

WPA_AUTH_TIMEOUT=60
regex_master='^.*master.*'
regex_slave='^.*slave.*'
hname=`/bin/hostname`

connect_wifi_with_timeout () { is_connected=false
  current_time=$(date +%s)
  while read -t ${WPA_AUTH_TIMEOUT} line; do
    echo "  $line"
    echo $line | grep -wq 'CTRL-EVENT-CONNECTED'
    if [ $? -eq 0 ]; then
      is_connected=true
      break
    fi
    # judge timeout
    if [ $(($(date +%s) - ${current_time})) -gt ${WPA_AUTH_TIMEOUT} ]; then
      echo "Timeout."
      break
    fi
  done < <(nohup bash -c "stdbuf -oL wpa_supplicant -P /run/wpa_supplicant.wlan1.pid -i wlan1 -D nl80211,wext -c /etc/wpa_supplicant/wpa_supplicant.conf 2>&1 &")
  if ! $is_connected; then
    echo 'WPA authentication failed.'
    pkill -f "wpa_supplicant.+-i *$1 .*"
    return 5
  else
    return 0
  fi
}

if [[ $hname =~ $regex_slave ]]; then
  /sbin/dhclient br0
fi

if [[ $hname =~ $regex_master ]]; then
  /usr/sbin/hostapd -B -P /run/hostapd.pid /etc/hostapd/hostapd_be.conf /etc/hostapd/hostapd_ap_ac.conf
  sleep 20
  connect_wifi_with_timeout
  if [ $? -gt 0 ]; then
    echo heartbeat > /sys/class/leds/led0/trigger
    exit 5
  fi
elif [[ $hname =~ $regex_slave ]]; then
  connect_wifi_with_timeout
  if [ $? -gt 0 ]; then
    echo heartbeat > /sys/class/leds/led0/trigger
    exit 5
  fi
  sleep 20
  /usr/sbin/hostapd -B -P /run/hostapd.pid /etc/hostapd/hostapd_be.conf /etc/hostapd/hostapd_ap_ac.conf
fi

exit 0
