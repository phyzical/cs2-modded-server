#!/usr/bin/env bash

# Install
# As root (sudo su)
# cd / && curl --silent --output "gcp.sh" "https://raw.githubusercontent.com/kus/csgo-modded-server/master/gcp.sh" && chmod +x gcp.sh && bash gcp.sh

METADATA_URL="${METADATA_URL:-http://metadata.google.internal/computeMetadata/v1/instance/attributes}"

get_metadata () {
    if [ -z "$1" ]
    then
        local result=""
    else
        local result=$(curl -s "$METADATA_URL/$1?alt=text" -H "Metadata-Flavor: Google")
		if [[ $result == *"<!DOCTYPE html>"* ]]; then
			result=""
		fi
    fi

    echo $result
}

# Get meta data from GCP and set environment variables
META_RCON_PASSWORD=$(get_metadata RCON_PASSWORD)
META_API_KEY=$(get_metadata API_KEY)
META_MOD_URL=$(get_metadata MOD_URL)
META_PORT=$(get_metadata PORT)
META_TICKRATE=$(get_metadata TICKRATE)
META_MAXPLAYERS=$(get_metadata MAXPLAYERS)
export LAN="${LAN:-$(get_metadata LAN)}"
export RCON_PASSWORD="${META_RCON_PASSWORD:-changeme}"
export API_KEY="${META_API_KEY:-changeme}"
export STEAM_ACCOUNT="${STEAM_ACCOUNT:-$(get_metadata STEAM_ACCOUNT)}"
export FAST_DL_URL="${FAST_DL_URL:-$(get_metadata FAST_DL_URL)}"
export MOD_URL="${META_MOD_URL:-https://github.com/kus/csgo-modded-server/archive/master.zip}"
export SERVER_PASSWORD="${SERVER_PASSWORD:-$(get_metadata SERVER_PASSWORD)}"
export PORT="${META_PORT:-27015}"
export TICKRATE="${META_TICKRATE:-128}"
export MAXPLAYERS="${META_MAXPLAYERS:-32}"
export DUCK_DOMAIN="${DUCK_DOMAIN:-$(get_metadata DUCK_DOMAIN)}"
export DUCK_TOKEN="${DUCK_TOKEN:-$(get_metadata DUCK_TOKEN)}"

cd /

# Update DuckDNS with our current IP
if [ ! -z "$DUCK_TOKEN" ]; then
    echo url="http://www.duckdns.org/update?domains=$DUCK_DOMAIN&token=$DUCK_TOKEN&ip=$(dig +short myip.opendns.com @resolver1.opendns.com)" | curl -k -o /duck.log -K -
fi

# Variables
user="steam"
IP="0.0.0.0"
PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Check distrib
if ! command -v apt-get &> /dev/null; then
	echo "ERROR: OS distribution not supported..."
	exit 1
fi

# Check root
if [ "$EUID" -ne 0 ]; then
	echo "ERROR: Please run this script as root..."
	exit 1
fi

if [ -z "$PUBLIC_IP" ]; then
	echo "ERROR: Cannot retrieve your public IP address..."
	exit 1
fi

echo "Updating Operating System..."
apt update -y -q && apt upgrade -y -q >/dev/null
if [ "$?" -ne "0" ]; then
	echo "ERROR: Updating Operating System..."
	exit 1
fi

echo "Adding i386 architecture..."
dpkg --add-architecture i386 >/dev/null
if [ "$?" -ne "0" ]; then
	echo "ERROR: Cannot add i386 architecture..."
	exit 1
fi

echo "Installing required packages..."
apt-get update -y -q >/dev/null
apt-get install -y -q libc6-i386 lib32stdc++6 lib32gcc1 lib32ncurses5 lib32z1 wget gdb screen tar unzip nano >/dev/null
if [ "$?" -ne "0" ]; then
	echo "ERROR: Cannot install required packages..."
	exit 1
fi

echo "Checking $user user exists..."
getent passwd ${user} >/dev/null 2&>1
if [ "$?" -ne "0" ]; then
	echo "Adding $user user..."
	addgroup ${user} && \
	adduser --system --home /home/${user} --shell /bin/false --ingroup ${user} ${user} && \
	usermod -a -G tty ${user} && \
	mkdir -m 777 /home/${user}/csgo && \
	chown -R ${user}:${user} /home/${user}/csgo
	if [ "$?" -ne "0" ]; then
		echo "ERROR: Cannot add user $user..."
		exit 1
	fi
fi

echo "Checking steamcmd exists..."
if [ ! -d "/steamcmd" ]; then
	mkdir /steamcmd && cd /steamcmd
	wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
	tar -xvzf steamcmd_linux.tar.gz
	mkdir -p /root/.steam/sdk32/
	ln -s /steamcmd/linux32/steamclient.so /root/.steam/sdk32/steamclient.so
fi

echo "Downloading any updates for CS:GO..."
/steamcmd/steamcmd.sh +login anonymous \
  +force_install_dir /home/${user}/csgo \
  +app_update 740 \
  +quit

cd /home/${user}/csgo/csgo/warmod/ && python3 -m http.server 80 </dev/null &>/dev/null &

cd /home/${user}

echo "Dynamically writing /home/$user/csgo/csgo/cfg/env.cfg"
echo "rcon_password						\"$RCON_PASSWORD\"" > /home/${user}/csgo/csgo/cfg/env.cfg
echo "sv_setsteamaccount					\"$STEAM_ACCOUNT\"			// Required for online https://steamcommunity.com/dev/managegameservers" >> /home/${user}/csgo/csgo/cfg/env.cfg
if [ -z "$SERVER_PASSWORD" ]; then
	echo "sv_password							\"\"" >> /home/${user}/csgo/csgo/cfg/env.cfg
else
	echo "sv_password							\"$SERVER_PASSWORD\"" >> /home/${user}/csgo/csgo/cfg/env.cfg
fi
if [ "$LAN" = "1" ]; then
	echo "sv_lan								1" >> /home/${user}/csgo/csgo/cfg/env.cfg
else
	echo "sv_lan								0" >> /home/${user}/csgo/csgo/cfg/env.cfg
fi
echo "sv_downloadurl						\"$FAST_DL_URL\"			// Fast download (custom files uploaded to web server)" >> /home/${user}/csgo/csgo/cfg/env.cfg
echo "sv_allowupload						0" >> /home/${user}/csgo/csgo/cfg/env.cfg
if [ -z "$FAST_DL_URL" ]; then
	# No Fast DL
	echo "sv_allowdownload					1			// If using Fast download change to 0" >> /home/${user}/csgo/csgo/cfg/env.cfg
else
	# Has Fast DL
	echo "sv_allowdownload					0			// If using Fast download change to 0" >> /home/${user}/csgo/csgo/cfg/env.cfg
fi
echo "" >> /home/${user}/csgo/csgo/cfg/env.cfg
echo "echo \"env.cfg executed\"" >> /home/${user}/csgo/csgo/cfg/env.cfg

# Uncomment below for custom admins
# echo "Dynamically writing /home/$user/csgo/csgo/addons/sourcemod/configs/admins_simple.ini"
# echo "\"STEAM_0:0:56050\"	\"9:z\"	// Kus" > /home/${user}/csgo/csgo/addons/sourcemod/configs/admins_simple.ini
# echo "\"STEAM_0:0:2\"	\"8:z\"	// Second user" >> /home/${user}/csgo/csgo/addons/sourcemod/configs/admins_simple.ini
# echo "\"STEAM_0:0:3\"	\"8:z\"	// Third user" >> /home/${user}/csgo/csgo/addons/sourcemod/configs/admins_simple.ini

chown -R ${user}:${user} /home/${user}/csgo

cd /home/${user}/csgo

echo "Starting server on $PUBLIC_IP:$PORT"
./srcds_run \
    -console \
    -usercon \
    -autoupdate \
    -game csgo \
    -tickrate $TICKRATE \
    -port $PORT \
    +map de_dust2 \
    -maxplayers_override $MAXPLAYERS \
    -authkey $API_KEY
    +ip $IP \
    +game_type 0 \
    +game_mode 0 \
    +mapgroup mg_active