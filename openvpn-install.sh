#!/bin/bash

# Secure OpenVPN server installer for Debian and Ubuntu
# Derived from https://github.com/Angristan/OpenVPN-install
# This version is Ubuntu only (tested on 16.04) and installs two instances, a UDP (1194) and a TCP (443) instance


if [[ "$EUID" -ne 0 ]]; then
	echo "Sorry, you need to run this as root."
	exit 1
fi

if [[ ! -e /dev/net/tun ]]; then
	echo "TUN is not available. Please install TUN."
	exit 2
fi


if [[ -e /etc/debian_version ]]; then
	OS="debian"
	# Getting the version number, to verify that a recent version of OpenVPN is available
	VERSION_ID=$(cat /etc/os-release | grep "VERSION_ID")
	RCLOCAL='/etc/rc.local'
	SYSCTL='/etc/sysctl.conf'
	if [[ "$VERSION_ID" != 'VERSION_ID="7"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="8"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="9"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="12.04"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="14.04"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="16.04"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="16.10"' ]] && [[ "$VERSION_ID" != 'VERSION_ID="17.04"' ]]; then
		echo "Your version of Debian/Ubuntu is not supported."
		echo "I can't install a recent version of OpenVPN on your system."
		echo ""
		echo "However, if you're using Debian unstable/testing, or Ubuntu beta,"
		echo "then you can continue, a recent version of OpenVPN is available on these."
		echo "Keep in mind they are not supported, though."
		while [[ $CONTINUE != "y" && $CONTINUE != "n" ]]; do
			read -p "Continue ? [y/n]: " -e CONTINUE
		done
		if [[ "$CONTINUE" = "n" ]]; then
			echo "Ok, bye !"
			exit 4
		fi
	fi
else
	echo "Looks like you aren't running this installer on a Debian or Ubuntu."
	exit 4
fi

newclient () {
	# Generates the custom client.ovpn
	cp /etc/openvpn/client-template.txt ~/$1.ovpn
	echo "<ca>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1.ovpn
	echo "</ca>" >> ~/$1.ovpn
	echo "<cert>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn
	echo "</cert>" >> ~/$1.ovpn
	echo "<key>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1.ovpn
	echo "</key>" >> ~/$1.ovpn
	echo "key-direction 1" >> ~/$1.ovpn
	echo "<tls-auth>" >> ~/$1.ovpn
	cat /etc/openvpn/tls-auth.key >> ~/$1.ovpn
	echo "</tls-auth>" >> ~/$1.ovpn
}

# Try to get our IP from the system and fallback to the Internet.
# I do this to make the script compatible with NATed servers (LowEndSpirit/Scaleway)
# and to avoid getting an IPv6.
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ "$IP" = "" ]]; then
	IP=$(wget -qO- ipv4.icanhazip.com)
fi
# Get Internet network interface with default route
NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)')

if [[ -e /etc/openvpn/server-base.include ]]; then
	while :
	do
	clear
		echo "OpenVPN-install (github.com/Angristan/OpenVPN-install)"
		echo ""
		echo "Looks like OpenVPN is already installed"
		echo ""
		echo "What do you want to do?"
		echo "   1) Add a cert for a new user"
		echo "   2) Revoke existing user cert"
		echo "   3) Exit"
		read -p "Select an option [1-3]: " option
		case $option in
			1)
			echo ""
			echo "Tell me a name for the client cert"
			echo "Please, use one word only, no special characters"
			read -p "Client name: " -e -i client CLIENT
			cd /etc/openvpn/easy-rsa/
			./easyrsa build-client-full $CLIENT nopass
			# Generates the custom client.ovpn
			newclient "$CLIENT"
			echo ""
			echo "Client $CLIENT added, certs available at ~/$CLIENT.ovpn"
			exit
			;;
			2)
			NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
			if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
				echo ""
				echo "You have no existing clients!"
				exit 5
			fi
			echo ""
			echo "Select the existing client certificate you want to revoke"
			tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
			if [[ "$NUMBEROFCLIENTS" = '1' ]]; then
				read -p "Select one client [1]: " CLIENTNUMBER
			else
				read -p "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
			fi
			CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
			cd /etc/openvpn/easy-rsa/
			./easyrsa --batch revoke $CLIENT
			./easyrsa gen-crl
			rm -rf pki/reqs/$CLIENT.req
			rm -rf pki/private/$CLIENT.key
			rm -rf pki/issued/$CLIENT.crt
			rm -rf /etc/openvpn/crl.pem
			cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
			chmod 644 /etc/openvpn/crl.pem
			echo ""
			echo "Certificate for client $CLIENT revoked"
			echo "Exiting..."
			exit
			;;
			3) exit;;
		esac
	done
else
	clear
	echo "Welcome to the secure OpenVPN installer (Chris James)"
	echo ""
	# OpenVPN setup and first user creation
	echo "I need to ask you a few questions before starting the setup"
	echo "You can leave the default options and just press enter if you are ok with them"
	echo ""
	echo "I need to know the IPv4 address of the network interface you want OpenVPN listening to."
	echo "If your server is running behind a NAT, (e.g. LowEndSpirit, Scaleway) leave the IP address as it is. (local/private IP)"
	echo "Otherwise, it should be your public IPv4 address."
	read -p "IP address: " -e -i $IP IP
	echo ""
	echo "What hostname do you want for OpenVPN?"
	read -p "Hostname: " -e HOSTNM
	echo ""
	echo "What DNS do you want to use with the VPN?"
	echo "   1) Current system resolvers (in /etc/resolv.conf)"
	echo "   2) FDN (France)"
	echo "   3) DNS.WATCH (Germany)"
	echo "   4) OpenDNS (Anycast: worldwide)"
	echo "   5) Google (Anycast: worldwide)"
	echo "   6) Yandex Basic (Russia)"
	while [[ $DNS != "1" && $DNS != "2" && $DNS != "3" && $DNS != "4" && $DNS != "5" ]]; do
		read -p "DNS [1-5]: " -e -i 1 DNS
	done
	echo ""
	echo "See https://github.com/Angristan/OpenVPN-install#encryption to learn more about "
	echo "the encryption in OpenVPN and the choices made in this script."
	echo "Please note that all the choices proposed are secure (to a different degree)"
	echo "and are still viable to date, unlike some default OpenVPN options"
	echo ''
	echo "Choose which cipher you want to use for the data channel:"
	echo "   1) AES-128-CBC (fastest and sufficiently secure for everyone, recommended)"
	echo "   2) AES-192-CBC"
	echo "   3) AES-256-CBC"
	echo "Alternatives to AES, use them only if you know what you're doing."
	echo "They are relatively slower but as secure as AES."
	echo "   4) CAMELLIA-128-CBC"
	echo "   5) CAMELLIA-192-CBC"
	echo "   6) CAMELLIA-256-CBC"
	echo "   7) SEED-CBC"
	while [[ $CIPHER != "1" && $CIPHER != "2" && $CIPHER != "3" && $CIPHER != "4" && $CIPHER != "5" && $CIPHER != "6" && $CIPHER != "7" ]]; do
		read -p "Cipher [1-7]: " -e -i 1 CIPHER
	done
	case $CIPHER in
		1)
		CIPHER="cipher AES-128-CBC"
		;;
		2)
		CIPHER="cipher AES-192-CBC"
		;;
		3)
		CIPHER="cipher AES-256-CBC"
		;;
		4)
		CIPHER="cipher CAMELLIA-128-CBC"
		;;
		5)
		CIPHER="cipher CAMELLIA-192-CBC"
		;;
		6)
		CIPHER="cipher CAMELLIA-256-CBC"
		;;
		5)
		CIPHER="cipher SEED-CBC"
		;;
	esac
	echo ""
	echo "Choose what size of Diffie-Hellman key you want to use:"
	echo "   1) 2048 bits (fastest)"
	echo "   2) 3072 bits (recommended, best compromise)"
	echo "   3) 4096 bits (most secure)"
	while [[ $DH_KEY_SIZE != "1" && $DH_KEY_SIZE != "2" && $DH_KEY_SIZE != "3" ]]; do
		read -p "DH key size [1-3]: " -e -i 2 DH_KEY_SIZE
	done
	case $DH_KEY_SIZE in
		1)
		DH_KEY_SIZE="2048"
		;;
		2)
		DH_KEY_SIZE="3072"
		;;
		3)
		DH_KEY_SIZE="4096"
		;;
	esac
	echo ""
	echo "Choose what size of RSA key you want to use:"
	echo "   1) 2048 bits (fastest)"
	echo "   2) 3072 bits (recommended, best compromise)"
	echo "   3) 4096 bits (most secure)"
	while [[ $RSA_KEY_SIZE != "1" && $RSA_KEY_SIZE != "2" && $RSA_KEY_SIZE != "3" ]]; do
		read -p "DH key size [1-3]: " -e -i 2 RSA_KEY_SIZE
	done
	case $RSA_KEY_SIZE in
		1)
		RSA_KEY_SIZE="2048"
		;;
		2)
		RSA_KEY_SIZE="3072"
		;;
		3)
		RSA_KEY_SIZE="4096"
		;;
	esac

	echo "We can secure this VPN using Duo 2FA.  Would you like to do so?"
	while [[ $USEDUO != "y" && $USEDUO != "n" ]]; do
			read -p "Use Duo ? [y/n]: " -e USEDUO
	done
	if [[ "$USEDUO" = "y" ]]; then
	
		echo ""
		echo "Duo: Enter IKEY "
		while [[ $DUOIKEY = "" ]]; do
			echo "As per Duo web interface"
			read -p "IKEY: " -e DUOIKEY
		done

		echo ""
		echo "Duo: Enter SKEY "
		while [[ $DUOSKEY = "" ]]; do
			echo "As per Duo web interface"
			read -p "SKEY: " -e DUOSKEY
		done

		echo ""
		echo "Duo: Enter API hostname "
		while [[ $DUOHOST = "" ]]; do
			echo "As per Duo web interface"
			read -p "Hostname: " -e DUOHOST
		done

	fi

	echo ""
	echo "Finally, tell me a name for the first client certificate and configuration"
	while [[ $CLIENT = "" ]]; do
		echo "Please, use one word only, no special characters"
		read -p "Client name: " -e -i client CLIENT
	done
	echo ""
	echo "Okay, that was all I needed. We are ready to setup your OpenVPN server now"
	read -n1 -r -p "Press any key to continue..."

	if [[ "$OS" = 'debian' ]]; then
		apt-get install ca-certificates -y
		# We add the OpenVPN repo to get the latest version.
		# Debian 7
		if [[ "$VERSION_ID" = 'VERSION_ID="7"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt wheezy main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		# Debian 8
		if [[ "$VERSION_ID" = 'VERSION_ID="8"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt jessie main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt update
		fi
		# Ubuntu 12.04
		if [[ "$VERSION_ID" = 'VERSION_ID="12.04"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt precise main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		# Ubuntu 14.04
		if [[ "$VERSION_ID" = 'VERSION_ID="14.04"' ]]; then
			echo "deb http://swupdate.openvpn.net/apt trusty main" > /etc/apt/sources.list.d/swupdate-openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		# Ubuntu >= 16.04 and Debian > 8 have OpenVPN > 2.3.3 without the need of a third party repository.
		# The we install OpenVPN
		apt-get install openvpn iptables openssl wget ca-certificates curl -y

		# Add Duo
		if [[ "$USEDUO" = "y" ]]; then
			apt-get install python -y
			apt-get install build-essential -y
			wget https://github.com/duosecurity/duo_openvpn/tarball/master -O duo.tgz
			tar -xvf duo.tgz
			cd duosecurity*
			make && make install
			cd ..
			rm -rf duosecurity*
		fi

		# Set hostname
		echo "$HOSTNM" > /etc/hostname
		SHORTHOST=`echo $HOSTNM | cut -d"." -f1`
		echo "$IP	$SHORTHOST" >> /etc/hosts
		echo "$IP	$HOSTNM" >> /etc/hosts
		hostname $SHORTHOST
		
	fi
	# Find out if the machine uses nogroup or nobody for the permissionless group
	if grep -qs "^nogroup:" /etc/group; then
	        NOGROUP=nogroup
	else
        	NOGROUP=nobody
	fi

	# An old version of easy-rsa was available by default in some openvpn packages
	if [[ -d /etc/openvpn/easy-rsa/ ]]; then
		rm -rf /etc/openvpn/easy-rsa/
	fi
	# Get easy-rsa
	wget -O ~/EasyRSA-3.0.1.tgz https://github.com/OpenVPN/easy-rsa/releases/download/3.0.1/EasyRSA-3.0.1.tgz
	tar xzf ~/EasyRSA-3.0.1.tgz -C ~/
	mv ~/EasyRSA-3.0.1/ /etc/openvpn/
	mv /etc/openvpn/EasyRSA-3.0.1/ /etc/openvpn/easy-rsa/
	chown -R root:root /etc/openvpn/easy-rsa/
	rm -rf ~/EasyRSA-3.0.1.tgz
	cd /etc/openvpn/easy-rsa/
	echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE" > vars
	# Create the PKI, set up the CA, the DH params and the server + client certificates
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass
	openssl dhparam -out dh.pem $DH_KEY_SIZE
	./easyrsa build-server-full server nopass
	./easyrsa build-client-full $CLIENT nopass
	./easyrsa gen-crl
	# generate tls-auth key
	openvpn --genkey --secret /etc/openvpn/tls-auth.key
	# Move all the generated files
	cp pki/ca.crt pki/private/ca.key dh.pem pki/issued/server.crt pki/private/server.key /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
	# Make cert revocation list readable for non-root
	chmod 644 /etc/openvpn/crl.pem
	
	# Generate server config files
	echo "port 1194" > /etc/openvpn/server-udp.conf
	echo "proto udp" >> /etc/openvpn/server-udp.conf
	echo "port 443" > /etc/openvpn/server-tcp.conf
	echo "proto tcp" >> /etc/openvpn/server-tcp.conf
	echo "config server-base.include" >> /etc/openvpn/server-udp.conf
	echo "config server-base.include" >> /etc/openvpn/server-tcp.conf
	echo "server 10.9.0.0 255.255.255.0" >> /etc/openvpn/server-udp.conf
	echo "server 10.8.0.0 255.255.255.0" >> /etc/openvpn/server-tcp.conf

	# Generate server-base.include

	echo "dev tun
user nobody
group $NOGROUP
persist-key
persist-tun
keepalive 10 120
topology subnet
ifconfig-pool-persist ipp.txt
reneg-sec 0" >> /etc/openvpn/server-base.include

	if [[ "$USEDUO" = "y" ]]; then
			echo "plugin /opt/duo/duo_openvpn.so $DUOIKEY $DUOSKEY $DUOHOST" >> /etc/openvpn/server-base.include
			# Use automatic push https://duo.com/docs/openvpn-faq
			echo "auth-user-pass-optional" >> /etc/openvpn/server-base.include
	fi

	# DNS resolvers
	case $DNS in
		1)
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server-base.include
		done
		;;
		2) #FDN
		echo 'push "dhcp-option DNS 80.67.169.12"' >> /etc/openvpn/server-base.include
		echo 'push "dhcp-option DNS 80.67.169.40"' >> /etc/openvpn/server-base.include
		;;
		3) #DNS.WATCH
		echo 'push "dhcp-option DNS 84.200.69.80"' >> /etc/openvpn/server-base.include
		echo 'push "dhcp-option DNS 84.200.70.40"' >> /etc/openvpn/server-base.include
		;;
		4) #OpenDNS
		echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server-base.include
		echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server-base.include
		;;
		5) #Google
		echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server-base.include
		echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server-base.include
		;;
		6) #Yandex Basic
		echo 'push "dhcp-option DNS 77.88.8.8"' >> /etc/openvpn/server-base.include
		echo 'push "dhcp-option DNS 77.88.8.1"' >> /etc/openvpn/server-base.include
		;;
	esac
echo 'push "redirect-gateway def1 bypass-dhcp" '>> /etc/openvpn/server-base.include
echo "crl-verify crl.pem
ca ca.crt
cert server.crt
key server.key
tls-auth tls-auth.key 0
dh dh.pem
auth SHA256
$CIPHER
tls-server
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
status openvpn.log
verb 3" >> /etc/openvpn/server-base.include

	# Create the sysctl configuration file if needed (mainly for Arch Linux)
	if [[ ! -e $SYSCTL ]]; then
		touch $SYSCTL
	fi

	# Enable net.ipv4.ip_forward for the system
	sed -i '/\<net.ipv4.ip_forward\>/c\net.ipv4.ip_forward=1' $SYSCTL
	if ! grep -q "\<net.ipv4.ip_forward\>" $SYSCTL; then
		echo 'net.ipv4.ip_forward=1' >> $SYSCTL
	fi
	# Avoid an unneeded reboot
	echo 1 > /proc/sys/net/ipv4/ip_forward
	# Needed to use rc.local with some systemd distros
 	if [[ "$OS" = 'debian' && ! -e $RCLOCAL ]]; then
 		echo '#!/bin/sh -e
 exit 0' > $RCLOCAL
	fi
	chmod +x $RCLOCAL
	# Set NAT for the VPN subnet
	iptables -t nat -A POSTROUTING -o $NIC -s 10.8.0.0/24 -j MASQUERADE
	iptables -t nat -A POSTROUTING -o $NIC -s 10.9.0.0/24 -j MASQUERADE
	sed -i "1 a\iptables -t nat -A POSTROUTING -o $NIC -s 10.8.0.0/24 -j MASQUERADE" $RCLOCAL
	sed -i "1 a\iptables -t nat -A POSTROUTING -o $NIC -s 10.9.0.0/24 -j MASQUERADE" $RCLOCAL
	if iptables -L -n | grep -qE 'REJECT|DROP'; then
		# If iptables has at least one REJECT rule, we asume this is needed.
		# Not the best approach but I can't think of other and this shouldn't
		# cause problems.
		iptables -I INPUT -p udp --dport 1194 -j ACCEPT
		iptables -I INPUT -p tcp --dport 443 -j ACCEPT
		iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
		iptables -I FORWARD -s 10.9.0.0/24 -j ACCEPT
		iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
		sed -i "1 a\iptables -I INPUT -p udp --dport 1194 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I INPUT -p tcp --dport 443 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -s 10.9.0.0/24 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL
	fi
	
	# And finally, restart OpenVPN
	

	systemctl enable openvpn@server-udp
	systemctl enable openvpn@server-tcp
	systemctl restart openvpn@server-udp
	systemctl restart openvpn@server-tcp


	# Try to detect a NATed connection and ask about it to potential LowEndSpirit/Scaleway users
	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
	if [[ "$IP" != "$EXTERNALIP" ]]; then
		echo ""
		echo "Looks like your server is behind a NAT!"
		echo ""
                echo "If your server is NATed (e.g. LowEndSpirit, Scaleway, or behind a router),"
                echo "then I need to know the address that can be used to access it from outside."
                echo "If that's not the case, just ignore this and leave the next field blank"
                read -p "External IP or domain name: " -e USEREXTERNALIP
		if [[ "$USEREXTERNALIP" != "" ]]; then
			IP=$USEREXTERNALIP
		fi
	fi
	# client-template.txt is created so we have a template to add further users later
	echo "
client
remote $HOSTNM 1194 udp
remote $HOSTNM 443 tcp
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
$CIPHER
tls-client
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
setenv opt block-outside-dns
verb 3
reneg-sec 0
#viscosity name $HOSTNM
#viscosity autoreconnect false
#viscosity dns automatic
#viscosity usepeerdns true
#viscosity manageadapter true
#viscosity startonopen false" > /etc/openvpn/client-template.txt

	# Disabled as using automatic push https://duo.com/docs/openvpn-faq
	#if [[ "$USEDUO" = "y" ]]; then
	#		echo "auth-user-pass" >> /etc/openvpn/client-template.txt
	#fi

	# Generate the custom client.ovpn
	newclient "$CLIENT"
	echo ""
	echo "Finished!"
	echo ""
	echo "Your client config is available at ~/$CLIENT.ovpn"
	echo "If you want to add more clients, you simply need to run this script another time!"
fi
exit 0;
