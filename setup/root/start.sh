#!/bin/bash

echo "[info] VPN is enabled, beginning configuration of VPN"

# create directory to store openvpn config files
mkdir -p /config/openvpn

# set perms and owner for openvpn directory
chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
exit_code_chown=$?
chmod -R 777 "/config/openvpn" &> /dev/null
exit_code_chmod=$?

# wildcard search for openvpn config files (match on first result)
VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)

# if ovpn filename is not custom.ovpn copy included ovpn and certs
if [[ "${VPN_CONFIG}" != "/config/openvpn/custom.ovpn" ]]; then
    # remove previous certs and ovpn files
    rm -f /config/openvpn/*
    echo "[info] VPN default certs defined, copying to /config/openvpn/..."
    # copy default encrption ovpn and certs
    cp -f /home/nobody/certs/*.crt /config/openvpn/
    cp -f /home/nobody/certs/*.pem /config/openvpn/
    cp -f "/home/nobody/certs/default.ovpn" "/config/openvpn/openvpn.ovpn"
fi
VPN_CONFIG="/config/openvpn/openvpn.ovpn"

if [[ "${DEBUG}" == "true" ]]; then
    echo "[debug] Environment variables defined as follows" ; set
    echo "[debug] Directory listing of files in /config/openvpn as follows" ; ls -al /config/openvpn
    echo "[debug] Contents of ovpn file ${VPN_CONFIG} as follows..." ; cat "${VPN_CONFIG}"
fi

echo "[info] VPN config file (ovpn extension) is located at ${VPN_CONFIG}"

if [[ "${VPN_PROTOCOL}" == "udp" && "${VPN_PORT}" != "1198" ]]; then
    echo "[warn] VPN provider remote port incorrect, overriding to 1198"
    VPN_PORT="1198"
elif [[ "${VPN_PROTOCOL}" == "tcp" && "${VPN_PORT}" != "502" ]]; then
    echo "[warn] VPN provider remote port incorrect, overriding to 502"
    VPN_PORT="502"
fi

# store credentials in separate file for authentication
if ! $(grep -Fq "auth-user-pass credentials.conf" "${VPN_CONFIG}"); then
    sed -i -e 's/auth-user-pass.*/auth-user-pass credentials.conf/g' "${VPN_CONFIG}"
fi

echo "${VPN_USER}" > /config/openvpn/credentials.conf

username_char_check=$(echo "${VPN_USER}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')
if [[ ! -z "${username_char_check}" ]]; then
    echo "[warn] Username contains characters which could cause authentication issues, please consider changing this if possible"
fi

echo "${VPN_PASS}" >> /config/openvpn/credentials.conf

password_char_check=$(echo "${VPN_PASS}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')
if [[ ! -z "${password_char_check}" ]]; then
    echo "[warn] Password contains characters which could cause authentication issues, please consider changing this if possible"
fi

# remove ping and ping-restart from ovpn file if present, now using flag --keepalive
if $(grep -Fq "ping" "${VPN_CONFIG}"); then
    sed -i '/ping.*/d' "${VPN_CONFIG}"
fi

# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
if $(grep -Fq "persist-tun" "${VPN_CONFIG}"); then
    sed -i '/persist-tun/d' "${VPN_CONFIG}"
fi

# remove reneg-sec from ovpn file if present, this is disabled via command line to prevent re-checks and dropouts
if $(grep -Fq "reneg-sec" "${VPN_CONFIG}"); then
    sed -i '/reneg-sec.*/d' "${VPN_CONFIG}"
fi

# disable proto from ovpn file if present, defined via env variable and passed to openvpn via command line argument
if $(grep -Fq "proto" "${VPN_CONFIG}"); then
    sed -i -e 's~^proto\s~# Disabled, as we pass this value via env var\n;proto ~g' "${VPN_CONFIG}"
fi

# disable remote from ovpn file if present, defined via env variable and passed to openvpn via command line argument
if $(grep -Fq "remote" "${VPN_CONFIG}"); then
    sed -i -e 's~^remote\s~# Disabled, as we pass this value via env var\n;remote ~g' "${VPN_CONFIG}"
fi

# disable dev from ovpn file if present, defined via env variable and passed to openvpn via command line argument
if $(grep -Fq "dev" "${VPN_CONFIG}"); then
    sed -i -e 's~^dev\s~# Disabled, as we pass this value via env var\n;dev ~g' "${VPN_CONFIG}"
fi

# create the tunnel device
[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/"${VPN_DEVICE_TYPE}" ] || mknod /dev/net/"${VPN_DEVICE_TYPE}" c 10 200

# get ip for local gateway (eth0)
DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')
echo "[info] Default route for container is ${DEFAULT_GATEWAY}"

# split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# remove existing ns, docker injects ns from host and isp ns can block/hijack
> /etc/resolv.conf

# process name servers in the list
for name_server_item in "${name_server_list[@]}"; do
    # strip whitespace from start and end of name_server_item
    name_server_item=$(echo "${name_server_item}" | sed -e 's/^[ \t]*//')
    echo "[info] Adding ${name_server_item} to /etc/resolv.conf"
    echo "nameserver ${name_server_item}" >> /etc/resolv.conf
done

if [[ "${DEBUG}" == "true" ]]; then
    echo "[debug] Show name servers defined for container" ; cat /etc/resolv.conf
    echo "[debug] Show name resolution for VPN endpoint ${VPN_REMOTE}" ; drill "${VPN_REMOTE}"
fi

# set perms and owner for files in /config/openvpn directory
chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
chmod -R 775 "/config/openvpn" &> /dev/null

if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
    echo "[warn] Unable to chown/chmod /config/openvpn, assuming SMB mountpoint"
fi

# remove file from previous run of getvpnport.sh
rm -rf /home/nobody/vpn_incoming_port.txt

# setup ip tables and routing for application
source /root/iptable.sh

# start openvpn tunnel
source /root/openvpn.sh
