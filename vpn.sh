#!/bin/bash 
#Version 0.4 - BakedPizza
#Updates and instructions: https://forum.synology.com/enu/viewtopic.php?f=39&t=65444&start=45#p459096
domain="example.com"
syn_conf_id="o1234567890"
syn_conf_name="foobar"
syn_protocol="openvpn"
timeout_seconds="10"
website_http_code_check="https://www.example.com"

function reconnect {
	if [ -z "$1" ]
	then
		echo 'VPN check: VPN is reconnecting without known cause.'
	else
		echo 'VPN check: VPN is reconnecting. Cause: "'$1'"'
	fi
	
	sudo rm /usr/syno/etc/synovpnclient/vpnc_connecting 2> /dev/null
	sudo /usr/syno/bin/synovpnc kill_client
	echo 'conf_id='$syn_conf_id | sudo tee /usr/syno/etc/synovpnclient/vpnc_connecting > /dev/null
	echo 'conf_name='$syn_conf_name | sudo tee --append /usr/syno/etc/synovpnclient/vpnc_connecting > /dev/null
	echo 'proto='$syn_protocol | sudo tee --append /usr/syno/etc/synovpnclient/vpnc_connecting > /dev/null
	sudo /usr/syno/bin/synovpnc reconnect --protocol="$syn_protocol" --name="$syn_conf_name"
	
	return 0
}

echo 'VPN check: Start'

if echo $(ifconfig tun0) | grep -q "00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00"
then
	echo 'VPN check: tun0 is up'
	current_remote_ip=$(curl --connect-timeout "$timeout_seconds" -s https://ipinfo.io/ip)
	echo 'VPN check: Grabbed current remote:' $current_remote_ip
	real_remote_ip=$(nslookup -timeout="$timeout_seconds" "$domain" | awk '/^Address: / { print $2 ; exit }')
	echo 'VPN check: Grabbed real remote:' $real_remote_ip
	if [[ -z "$current_remote_ip" || -z "$real_remote_ip" ]]
	then
		reconnect "At least one of the remote IPs is empty. Timeout?"
	else
		current_remote_ip_check=$(sudo ipcalc -s "$current_remote_ip")
		real_remote_ip_check=$(sudo ipcalc -s "$real_remote_ip")
		if [[ -z "$current_remote_ip_check" &&  -z "$real_remote_ip_check" ]]
		then
			if [[ "$current_remote_ip" != "$real_remote_ip" ]]
			then
				echo 'VPN check: Remote IP is hidden'
				status_code=$(curl -o /dev/null --connect-timeout "$timeout_seconds" --silent --head --write-out %{http_code} "$website_http_code_check")
				if [ "$status_code" == "200" ]
				then
					echo 'VPN check: VPN allowed to connect'
				else
					reconnect "Not allowed to connect (status code: $status_code)"
				fi
			else
				reconnect "The remote IP equals current IP"
			fi
		else
			reconnect "At least one of the received IPs is invalid. Timeout?"
		fi
	fi
else
	reconnect "tun0 down"
fi

exit 0