#!/bin/bash 
#Version 0.5 - BakedPizza
#Updates and instructions: https://forum.synology.com/enu/viewtopic.php?f=39&t=65444&start=45#p459096
domain="example.com"
syn_conf_id="o1234567890"
syn_conf_name="foobar"
syn_protocol="openvpn"
timeout_seconds="10"
http_code_check_urls=("https://example.com/" "https://example.org/")

function reconnect {
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
	if [[ -z "$current_remote_ip" || -z "$real_remote_ip" ]]; then
		reconnect "At least one of the remote IPs is empty. Timeout?"
	else
		current_remote_ip_check=$(sudo ipcalc -s "$current_remote_ip")
		real_remote_ip_check=$(sudo ipcalc -s "$real_remote_ip")
		if [[ -z "$current_remote_ip_check" &&  -z "$real_remote_ip_check" ]]; then
			if [[ "$current_remote_ip" != "$real_remote_ip" ]]; then
				echo 'VPN check: Remote IP is hidden'
				http_status_codes=()
				for i in "${!http_code_check_urls[@]}";do		
					http_status_codes+=($(curl -o /dev/null --connect-timeout "$timeout_seconds" --silent --head --write-out %{http_code} "${http_code_check_urls[i]}"))
					if [ "${http_status_codes[i]}" != "200" ]; then
						echo 'VPN check: VPN not allowed to connect to URL at position '$i' (first position is 0)'
					fi
				done
				one_http_ok=false;
				for status_code in "${http_status_codes[@]}"; do
					if [ "$status_code" == "200" ]; then
						one_http_ok=true;
					fi
				done
				if $one_http_ok; then
					echo 'VPN check: VPN allowed to connect to at least one of the specified URLs'
				else
					reconnect "Not allowed to connect to all of the specified URLs"
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