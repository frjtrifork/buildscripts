#!/bin/bash

if [ $# -lt 2 ]; then
  echo "Usage: $0 <IPA_FILE> <PROVISIONING_FILE>"
  exit 1
fi


if [ ! -f "${1}" ]; then
  echo "File '$1' not found"
  exit 1
else
  IPA_FILE="${1}"
fi

if [ ! -f "${2}" ]; then
  echo "File '$2' not found"
  exit 1
else
	MOBILE_PROVISION="$2"
fi


echo ""
echo "Re-signing ipa with content from mobileprovision"
echo "  IPA:             '${IPA_FILE}'"
echo "  MobileProvision: '${MOBILE_PROVISION}'"
echo ""

CURDIR=$(pwd)

WORKDIR="/tmp/resign"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"

OUTPUT_IPA_FILE="${IPA_FILE%.ipa}.resigned.ipa"

###################### BEGIN FUNCTIONS ######################
function plist_from_mobileprovision()
{
	
	tmp_file="/tmp/tmp.plist"
	local input_file="${1}"

	## get the plist embedded in the provisioning profile
	# 1. sed - Get contents between <?xml.... xml </plist> both tags inclusive
	# 2. sed - If any content is left in xml prolog, delete it
	# 3 xmllist - just to make the file nicer to look at
	plist_xml=$(strings "$input_file" | sed -n "/<?xml*/,/<\/plist>/p" | sed "s/^.*\(<?.*>\)/\1/g;s/date>/string>/g")
	$(echo ${plist_xml} | xmllint --format - > "$tmp_file")
	if [ -n "${DEBUG}" ]; then
		cat "${tmp_file}"
	fi
	echo "${tmp_file}"
	
}

function code_signing_identity_from_plist()
{
  if [ ! -f "${1}" ]; then
  	echo "plist file '${1}' not found"
  	exit 1
  fi


  ## Extract certificate from mobileprovision plist
  local developer_certificates
  developer_certificates=$(/usr/libexec/PlistBuddy -c 'print :DeveloperCertificates:0' "$1")  
  echo $developer_certificates > "tmp_cert"

  local iphone_dist
  iphone_dist=$(strings "tmp_cert" | grep "iPhone Distribution")
  iphone_dist=${iphone_dist:2}

  local iphone_dist_length
  iphone_dist_length=${#iphone_dist}

  ## Finally get the name of the certificate that will be used for re-signing the ipa
  iphone_dist=${iphone_dist:0:$((${iphone_dist_length} - 1))}

  echo "$iphone_dist"

}

function bundle_identifier_from_plist()
{
  if [ ! -f "${1}" ]; then
  	echo "plist file '${1}' not found"
  	exit 1
  fi

  application_identifier=$(/usr/libexec/PlistBuddy -c "print :Entitlements:application-identifier" "$1")
  team_identifier="$(/usr/libexec/PlistBuddy -c 'print :TeamIdentifier:0' "$1")"

  team_identifier_length=$((${#team_identifier} + 1))
  echo "${application_identifier:$team_identifier_length}"
}

###################### END FUNCTIONS ######################


#Extract the plist from the .mobileprovision file
provisioning_plist_file=$(plist_from_mobileprovision "${MOBILE_PROVISION}")

#Extract BUNDLE_IDENTIFIER from plist
BUNDLE_IDENTIFIER=$(bundle_identifier_from_plist "$provisioning_plist_file")
if [ -z "${BUNDLE_IDENTIFIER}" ]; then
	echo "Failed fetching BUNDLE_IDENTIFIER from '$provisioning_plist_file'"
	exit 1
fi

#Extract CODE_SIGNING_IDENTITY from plist
CODE_SIGNING_IDENTITY=$(code_signing_identity_from_plist "$provisioning_plist_file")
if [ -z "${CODE_SIGNING_IDENTITY}" ]; then
	echo "Failed fetching CODE_SIGNING_IDENTITY from '$provisioning_plist_file'"
	exit 1
fi

#Extract uuid and expiration_date from plist
uuid=$(/usr/libexec/PlistBuddy -c "print :UUID" "$provisioning_plist_file")  
expiration_date=$(/usr/libexec/PlistBuddy -c "print :ExpirationDate" "$provisioning_plist_file")

if [ -n "${DEBUG}" ]; then
	echo "Mobile provioning '${MOBILE_PROVISION}' details:"
	echo "	uuid: ${uuid}"
	echo "	application_identifier: ${application_identifier}"
	echo "	team_identifier: ${team_identifier}"
	echo "	expiration_date: ${expiration_date}"
	echo "	bundle_identifier: ${BUNDLE_IDENTIFIER}"
fi


## Check if certificate has expired and fail if expired
expiration_date_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$expiration_date" +%s)
#2012-11-10T12:00:15Z 
today_epoch=$(date +%s)

if [ "${today_epoch}" -ge "${expiration_date_epoch}" ]; then
	echo "The mobile provisioning file has expired: $expiration_date  ---> $expiration_date_epoch  ---> $(date -r $expiration_date_epoch)"
	exit 1
fi




# Unzip the IPA
cp "${1}" "${WORKDIR}"
cp "${MOBILE_PROVISION}" "${WORKDIR}"

cd "${WORKDIR}"
unzip -oq "${IPA_FILE}"

APP_NAME=$(name=$(ls -1 Payload);echo ${name%.app})

#Remove old CodeSignature
echo "Removing old signature"
rm -r "Payload/${APP_NAME}.app/_CodeSignature" "Payload/${APP_NAME}.app/CodeResources" 2> /dev/null | true

#Replace embedded mobile provisioning profile
echo "Embedding mobileprovision in app"
cp "${MOBILE_PROVISION}" "Payload/${APP_NAME}.app/embedded.mobileprovision"


## Set the bundleidentifier in Info.plist to match 
echo "CFBundleIdentifier: '${BUNDLE_IDENTIFIER}' (${MOBILE_PROVISION})" 
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier "${BUNDLE_IDENTIFIER}"' "Payload/${APP_NAME}.app/Info.plist"

#Re-sign
echo "Code signing identity: '${CODE_SIGNING_IDENTITY}' (${MOBILE_PROVISION})"
/usr/bin/codesign -f -s "${CODE_SIGNING_IDENTITY}" --resource-rules "Payload/${APP_NAME}.app/ResourceRules.plist" "Payload/${APP_NAME}.app"

#Re-package
echo "Packaging IPA file"
zip -qr "${CURDIR}/${OUTPUT_IPA_FILE}" Payload

echo ""
echo "DONE - produced '${OUTPUT_IPA_FILE}'"
