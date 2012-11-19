#!/bin/bash

if [ -f "$1" ]; then
	tmp_file="/tmp/tmp.plist"
	
	## get the plist embedded in the provisioning profile
	# 1. sed - Get contents between <?xml.... xml </plist> both tags inclusive
	# 2. sed - If any content is left in xml prolog, delete it
	# 3 xmllist - just to make the file nicer to look at
	strings "$1" | sed -n "/<?xml*/,/<\/plist>/p" 2>/dev/null | sed "s/^.*\(<?.*>\)/\1/g;s/date>/string>/g" | xmllint --format - > "$tmp_file"
	
	uuid=$(/usr/libexec/PlistBuddy -c "print :UUID" "$tmp_file")
	application_identifier=$(/usr/libexec/PlistBuddy -c "print :Entitlements:application-identifier" "$tmp_file")
	team_identifier=$(/usr/libexec/PlistBuddy -c 'print :TeamIdentifier:0' "$tmp_file" 2> /dev/null)
	expiration_date=$(/usr/libexec/PlistBuddy -c "print :ExpirationDate" "$tmp_file")

#2012-11-10T12:00:15Z 
	expiration_date_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$expiration_date" +%s)

	today_epoch=$(date +%s)
	
	if [ "${today_epoch}" -lt "${expiration_date_epoch}" ]; then
		echo "${uuid}    $expiration_date   ${application_identifier}      $1"
	#else 
	#	echo "expired: $expiration_date  ---> $expiration_date_epoch  ---> $(date -r $expiration_date_epoch)"
	fi

else 
	echo "$1 not found"
fi
