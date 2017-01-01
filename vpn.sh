#!/bin/bash 
#Version 0.9.0 - BakedPizza
#Updates and instructions: https://forum.synology.com/enu/viewtopic.php?f=39&t=65444&start=45#p459096
domain="example.com"
syn_conf_id="o1234567890"
syn_conf_name="foobar"
syn_protocol="openvpn"
timeout_seconds="10"
http_status_check_urls=("https://example.com/" "https://example.org/")
http_status_check_accepted_codes=("200")
log_to_file=true
log_filename=vpn.log
log_size_limit_bytes=500000
test_run=false

function script_log_to_file {
	if [ "$log_to_file" = true ]; then
		script_log_info 'Log to file has been enabled (this line is not logged to the file)'
		touch $log_filename
		log_size_bytes=$(stat --printf="%s" "$log_filename")
		if [ "$log_size_bytes" -gt "$log_size_limit_bytes" ]; then
			echo "[INFO] VPN check: log purged because it exceeded $log_size_limit_bytes bytes" | tee $log_filename
		fi
		exec &> >(tee -a "$log_filename")
		exec 2>&1
	else
		script_log_info 'Log to file has been disabled'
	fi
}

function script_check_sudo {
	uid=$(sudo sh -c 'echo $UID')
	if [ "$uid" -eq 0 ]; then
		script_log_info 'Running with user with sufficient privileges'
	else
		script_log_error 'You need to run this script with an sudo-enabled user (by default: "admin")'
		script_exit
	fi
}

function vpn_check_tun0 {
	ifconfig tun0 | grep -q "00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00"
	if [ "$?" -eq 0 ]; then
		script_log_info 'Interface tun0 is up'
	else
		vpn_reconnect "Interface tun0 is down"
	fi
}

function vpn_check_ip {
	if [ -n "$domain" ]; then
		current_remote_ip=$(curl --connect-timeout "$timeout_seconds" -s https://ipinfo.io/ip)
		real_remote_ip=$(nslookup -timeout="$timeout_seconds" "$domain" | awk '/^Address: / { print $2 ; exit }')
		sudo ipcalc -s "$current_remote_ip"
		if [ "$?" -eq 255 ]; then  # TODO: Why does it return 255 when confronted with a valid IP? Why does it return bad IP while using the -p parameter? :/
		  sudo ipcalc -s "$real_remote_ip"
		  if [ "$?" -eq 255 ]; then
			if [[ "$current_remote_ip" != "$real_remote_ip" ]]; then
				script_log_info 'Remote IP is different from the domain IP'
			else
				vpn_reconnect "The current remote IP is indentical to the real remote IP"
			fi
		  else
			vpn_reconnect "The received real remote IP is invalid. Timeout?"
		  fi
		else
		  vpn_reconnect "The received current remote IP is invalid. Timeout?"
		fi
	else
		script_log_warn 'Skipping IP check; no domain defined'
	fi
}

function vpn_check_http_status {
	if [ "${#http_status_check_urls[@]}" -gt 0 ]; then
		grep_arguments=''
		if [ "${#http_status_check_accepted_codes[@]}" -eq 0 ]; then
			script_log_info 'No HTTP status codes defined; assuming status 200'
			grep_arguments+=' -e 200'
		else
			for status_code in "${http_status_check_accepted_codes[@]}";do
				grep_arguments+=' -e '$status_code
			done
		fi

		while read -r -a random_url; do
			curl -o /dev/null --connect-timeout "$timeout_seconds" --silent --head --write-out %{http_code} "$random_url" | grep -Fxq $grep_arguments
			last_exit_code="$?"
			if [ "$last_exit_code" -eq 0 ]; then
				script_log_info 'VPN allowed to connect to at least one of the specified URLs'
				break
			else
				script_log_info 'VPN not allowed to connect to URL: '$random_url
			fi
		done < <(shuf -e ${http_status_check_urls[@]})
		
		if [ "$last_exit_code" -ne 0 ]; then
			vpn_reconnect "Not allowed to connect to any of the specified URLs"		
		fi
	else
		script_log_warn 'Skipping HTTP status check; no URLs defined'
	fi
}

function vpn_reconnect {
	log_message='VPN needs to be reconnected'
	if [ -z "$1" ]; then
		log_message+=' without known cause.'
	else
		log_message+='. Cause: "'$1'"'
	fi
	
	script_log_warn "$log_message"
	
	if [ "$test_run" = true ]; then
		script_log_warn 'Test run is enabled; will not reconnect the VPN!'
		script_exit
	fi
	
	sudo /usr/syno/bin/synovpnc kill_client
	sudo tee /usr/syno/etc/synovpnclient/vpnc_connecting > /dev/null <<-EOF
		conf_id="$syn_conf_id"
		conf_name="$syn_conf_name"
		proto="$syn_protocol"
		EOF
	sudo /usr/syno/bin/synovpnc reconnect --protocol="$syn_protocol" --name="$syn_conf_name"
	reconnect_status_code="$?"
	
	script_log_info 'End'
	exit "$reconnect_status_code"
}

function script_log_error {
	if [ -n "$1" ]; then
		echo '[ERROR] VPN check: '$1
	fi
}

function script_log_warn {
	if [ -n "$1" ]; then
		echo '[WARN] VPN check: '$1
	fi
}

function script_log_info {
	if [ -n "$1" ]; then
		echo '[INFO] VPN check: '$1
	fi
}

function script_exit {
	script_log_info 'End'
	exit 0
}

script_log_to_file
script_log_info 'Start ['"`date +%Y-%m-%d\ %H:%M:%S\ %:::z`"']'
script_check_sudo
vpn_check_tun0
vpn_check_ip
vpn_check_http_status
script_exit