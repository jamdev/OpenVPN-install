## OpenVPN-install
Secure OpenVPN installer for Ubuntu 16.04.

This script will let you setup your own secure VPN server in just a few minutes.

This is based on https://github.com/Angristan/OpenVPN-install but customised to my requirements.  It is shared here for community use.

It adds:

* Dual instance UDP+TCP
* Sets server hostname (designed to be run on newly instantiated VPSs only)
* Optionally adds Duo 2FA
* Optionally adds Authy 2FA

It removes support for non-Debian based distros.  It is not tested on any distro other than 16.04.  It also removes support for uninstalling, as it is designed to be used on 'throwaway' VPS instances.

## Credits & Licence

Thanks to the [contributors](https://github.com/Angristan/OpenVPN-install/graphs/contributors) and of course Angristan's and Nyr's orginal work.

[MIT Licence](https://raw.githubusercontent.com/Angristan/openvpn-install/master/LICENSE)
