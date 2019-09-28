#!/bin/bash
# This script is based on
# https://github.com/authy/authy-ssh/blob/master/authy-ssh

VERSION="1.0"
AUTHY_URL="https://api.authy.com"
CONFIG_FILE="/etc/openvpn/authy/authy-vpn.conf"

export TERM="xterm-256color"
NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2; tput bold)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)

function red() {
    echo -e "$RED$*$NORMAL"
}

function green() {
    echo -e "$GREEN$*$NORMAL"
}

function yellow() {
    echo -e "$YELLOW$*$NORMAL"
}

function require_curl() {
    which curl 2>&1 > /dev/null
    if [ $? -eq 0 ]
    then
        return 0
    fi

    # if `which` is not installed this check is ran
    curl --help 2>&1 > /dev/null

    if [ $? -ne 0 ]
    then
        red "install curl and try again"
        exit 1
    fi
}

function check_api_key() {
    if [[ $AUTHY_API_KEY == "replace_me" || ! $AUTHY_API_KEY ]]
    then
        red "Cannot find a valid api key"
        exit 1
    fi
}

# usage: register_user "login" "<email>" "<country-code>" "<cellphone>" "<username>" 
function register_user() {
    local login=$1
    local username=$5
    url="$AUTHY_URL/protected/json/users/new?api_key=${AUTHY_API_KEY} -d user[email]=$2 -d user[country_code]=$3 -d user[cellphone]=$4 -s"

    green "Registering the user with Authy"

    response=`curl ${url} 2>/dev/null`
    ok=true

    if [[ $response == *cellphone* ]]
    then
        yellow "Cellphone is invalid"
        ok=false
    fi

    if [[ $response == *email* ]]
    then
        yellow "Email is invalid"
        ok=false
    fi

    if [[ $response == *country* ]]
    then
        yellow "Country Code is invalid"
        ok=false
    fi

    if [[ $ok == false ]]
    then
        return 1
    fi

    if [[ $response == *user*id* ]]
    then
        user_id=`echo $response | grep -o '[0-9]\{1,\}'` # match the authy id
        if [[ $user_id ]]
        then
            echo "$login $user_id $username" >> $CONFIG_FILE
            green "Success: User $login was registered with AUTHY_ID $user_id."
            return 0
        else
            red "Cannot register user: $response"
        fi
    elif [[ $response == "invalid key" ]]
    then
        yellow "The api_key value is not valid"
    else
        red "Unknown response: $response"
    fi
    return 1
}

function read_config()
{
  local api_key="$(cat /etc/openvpn/*.include | grep authy-openvpn.so -m 1 | cut -d" " -f4)"

  if [[ $api_key != "" ]]
  then
    echo $api_key
    return 0
  fi

  return 1
}

function register_users()
{
    echo "---------------------------------------------"
    echo "This script is to add users to Authy Open VPN"
    echo "---------------------------------------------"

    echo -n "OpenVPN certificate name (without .ovpn): "
    read username

    echo -n "Email: "
    read email

    echo -n "VPN Login: "
    read -i $email -e login

    echo -n "Country Code (EG. 44 for UK): "
    read -i "44" -e country_code

    echo -n "Mobile phone (without leading 0): "
    read cellphone

    register_user $login $email $country_code $cellphone $username

    if [[ $? -ne 0 ]] ; then
        red "Failed to add user. Try again."
        exit 1
    fi
}


# cd - >/dev/null
require_curl
AUTHY_API_KEY="$(read_config)"
if [ $? -ne 0 ] ; then
    exit 1
fi

mkdir -p `dirname "${CONFIG_FILE}"`
touch $CONFIG_FILE
if [ $? -ne 0 ] ; then
    exit 1
fi
chown root $CONFIG_FILE
chmod 644  $CONFIG_FILE

check_api_key
register_users

echo "Done. In case of problems check link in /etc/openvpn/authy/authy-vpn.conf"
echo "If OpenVPN won't start check permissions on that file (644)."

service openvpn restart
