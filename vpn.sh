#!/bin/bash 
#Version 0.7 - BakedPizza
#Updates and instructions: https://forum.synology.com/enu/viewtopic.php?f=39&t=65444&start=45#p459096
domain="example.com"
syn_conf_id="o1234567890"
syn_conf_name="foobar"
syn_protocol="openvpn"
timeout_seconds="10"
http_status_check_urls=("https://example.com/" "https://example.org/")
http_status_check_accepted_codes=("200")

function vpn_check_tun0 {
	ifconfig tun0 | grep -q "00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00"
	if [ $? -eq 0 ]; then
		echo 'VPN check: tun0 is up'
	else
		vpn_reconnect "tun0 down"
	fi
}

function vpn_check_ip {
	current_remote_ip=$(curl --connect-timeout "$timeout_seconds" -s https://ipinfo.io/ip)
	echo 'VPN check: Grabbed current remote:' $current_remote_ip
	real_remote_ip=$(nslookup -timeout="$timeout_seconds" "$domain" | awk '/^Address: / { print $2 ; exit }')
	echo 'VPN check: Grabbed real remote:' $real_remote_ip
	sudo ipcalc -s "$current_remote_ip"
	if [ $? -eq 255 ]; then # TODO: Why does it return 255 when confronted with a valid IP?
	  sudo ipcalc -s "$real_remote_ip"
	  if [ $? -eq 255 ]; then
		if [[ "$current_remote_ip" != "$real_remote_ip" ]]; then
			echo 'VPN check: Remote IP is hidden'
		else
			vpn_reconnect "The remote IP is indentical to the remote IP"
		fi
	  else
		vpn_reconnect "The received current remote IP is invalid. Timeout?"
	  fi
	else
	  vpn_reconnect "The received current remote IP is invalid. Timeout?"
	fi
}

function vpn_check_http_status {
	grep_arguments=''
	if [ ${#http_status_check_accepted_codes[@]} -eq 0 ]; then
		grep_arguments+=' -e 200'
	else
		for status_code in "${http_status_check_accepted_codes[@]}";do
			grep_arguments+=' -e '$status_code
		done
	fi
	
	for i in "${!http_status_check_urls[@]}";do
		curl -o /dev/null --connect-timeout "$timeout_seconds" --silent --head --write-out %{http_code} "${http_status_check_urls[i]}" | grep -Fxq $grep_arguments
		if [ $? -eq 0 ]; then
			break
		elif [ $i -eq $((${#http_status_check_urls[@]} - 1)) ]; then
			vpn_reconnect "Not allowed to connect to any of the specified URLs"
		else
			echo 'VPN check: VPN not allowed to connect to URL: '${http_status_check_urls[i]}
		fi
	done
}

function vpn_reconnect {
	if [ -z "$1" ]; then
		echo 'VPN check: VPN is reconnecting without known cause.'
	else
		echo 'VPN check: VPN is reconnecting. Cause: "'$1'"'
	fi
	
	sudo /usr/syno/bin/synovpnc kill_client
	sudo tee /usr/syno/etc/synovpnclient/vpnc_connecting > /dev/null <<-EOF
		conf_id="$syn_conf_id"
		conf_name="$syn_conf_name"
		proto="$syn_protocol"
		EOF
	sudo /usr/syno/bin/synovpnc reconnect --protocol="$syn_protocol" --name="$syn_conf_name"
	
	exit $?
}

echo 'VPN check: Start ['"`date +%Y-%m-%d\ %H:%M:%S\ %:::z`"']'
vpn_check_tun0
vpn_check_ip
vpn_check_http_status
echo 'VPN check: End'
exit 0