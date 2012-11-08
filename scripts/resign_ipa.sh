#!/bin/bash

#**************************************************************************
#   Copyright (C) 2012, Flemming Jønsson                                  *
#                                                                         *
#   This program is free software; you can redistribute it and/or modify  *
#   it under the terms of the GNU General Public License as published by  *
#   the Free Software Foundation; either version 2 of the License, or     *
#   (at your option) any later version.                                   *
#                                                                         *
#   This program is distributed in the hope that it will be useful,       *
#   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
#   GNU General Public License for more details.                          *
#                                                                         *
#   You should have received a copy of the GNU General Public License     *
#   along with this program; if not, write to the                         *
#   Free Software Foundation, Inc.,                                       *
#   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
#**************************************************************************



#**************************************************************************
# This script can be used to re-sign an Apple ipa file for OTA            *
# distribution.                                                           *
#                                                                         *
# Requirements:                                                           *
#  - XCode command line tools must be installed on the system             *
#  - The distribution certificate in the mobileprovision file must be     *
#    installed on the system                                              *
#                                                                         *
# Usage:                                                                  *
# resign_ipa.sh <some_ipa.ipa> <some_profile.mobileprovision>             *
#     A re-signed ipa with the name <some_ipa.resigned.ipa> will be       *
#     created in the current working directory.                           *
#                                                                         *
#   Note: Code signing identity, bundle identifiers etc. will be          *
#         extracted from the provisioning profile.                        *
#**************************************************************************


if [ $# -lt 2 ]; then
  echo "Usage: $0 <IPA_FILE> <PROVISIONING_FILE> [OUTPUTDIR]"
  echo "   Parameters:"
  echo "      1: IPA file to re-sign."
  echo "      2: MobileProvision file to use for re-signing."
  echo "     [3]: Optional. Output directory for the re-signed IPA file."
  echo "   If parameter 3 is not specified the default is current dir"
  exit 1
fi



WORKDIR="${TMPDIR}/resign"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"




###################### BEGIN FUNCTIONS ######################

function failed()
{
    local error=${1:-Undefined error}
    echo "Failed: $error" >&2
    exit 1
}

function absolute_path()
{
  python -c "import os.path; print os.path.abspath('$1')"
}

function plist_from_mobileprovision()
{
	
	tmp_file="/tmp/tmp.plist"
	
	if [ ! -f "${1}" ]; then
  		echo "Mobileprovision file '${1}' not found"
  		exit 1
  	fi

	## get the plist embedded in the provisioning profile
	# 1. sed - Get contents between <?xml.... xml </plist> both tags inclusive
	# 2. sed - If any content is left in xml prolog, delete it
	# 3 xmllist - just to make the file nicer to look at
	plist_xml=$(strings "${1}" | sed -n "/<?xml*/,/<\/plist>/p" | sed "s/^.*\(<?.*>\)/\1/g;s/date>/string>/g")
	$(echo ${plist_xml} | xmllint --format - > "$tmp_file")
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
  echo $developer_certificates > "${WORKDIR}/tmp_cert"

  local iphone_dist
  iphone_dist=$(strings "${WORKDIR}/tmp_cert" | grep "iPhone Distribution")
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


### Check input ###
if [ ! -f "${1}" ]; then
  failed "File '$1' not found"
else
  IPA_FILE=$(absolute_path "${1}")
fi

if [ ! -f "${2}" ]; then
  failed "File '$2' not found"
else
  MOBILE_PROVISION=$(absolute_path "${2}")
fi

if [ $# -gt 2 ]; then
  if [ -d "${3}" ]; then
    OUTDIR=$(absolute_path "${3}")
  else 
    echo "Output dir '${3}' does not exist, falling back to current dir"
    OUTDIR="$(pwd)"
  fi
else
  OUTDIR="$(pwd)"
fi

IPA_FILENAME_ONLY=$(basename "${IPA_FILE}")
OUTPUT_IPA_FILE="${IPA_FILENAME_ONLY%.ipa}.resigned.ipa"

echo ""
echo "Re-signing ipa with content from mobileprovision"
echo "  IPA:             '${IPA_FILE}'"
echo "  MobileProvision: '${MOBILE_PROVISION}'"
echo ""
echo "  Result:          '${OUTDIR}/${OUTPUT_IPA_FILE}'"
echo ""




#Extract the plist from the .mobileprovision file
provisioning_plist_file=$(plist_from_mobileprovision "${MOBILE_PROVISION}")

#Extract BUNDLE_IDENTIFIER from plist
BUNDLE_IDENTIFIER=$(bundle_identifier_from_plist "$provisioning_plist_file")
if [ -z "${BUNDLE_IDENTIFIER}" ]; then
	failed "Failed fetching BUNDLE_IDENTIFIER from '$provisioning_plist_file'"
fi

#Extract CODE_SIGNING_IDENTITY from plist
CODE_SIGNING_IDENTITY=$(code_signing_identity_from_plist "$provisioning_plist_file")
if [ -z "${CODE_SIGNING_IDENTITY}" ]; then
	failed "Failed fetching CODE_SIGNING_IDENTITY from '$provisioning_plist_file'"
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
	failed "The mobile provisioning file has expired: $expiration_date  ---> $expiration_date_epoch  ---> $(date -r $expiration_date_epoch)"
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
cp "${MOBILE_PROVISION}" "Payload/${APP_NAME}.app/embedded.mobileprovision" || failed "Failed copying mobileprovision to app dir"


## Set the bundleidentifier in Info.plist to match 
echo "CFBundleIdentifier: '${BUNDLE_IDENTIFIER}' ($(basename ${MOBILE_PROVISION}))" 
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier "${BUNDLE_IDENTIFIER}"' "Payload/${APP_NAME}.app/Info.plist" || failed "Setting CFBundleIdentifier failed"

#Re-sign
echo "Code signing identity: '${CODE_SIGNING_IDENTITY}' ($(basename ${MOBILE_PROVISION}))"
/usr/bin/codesign -f -s "${CODE_SIGNING_IDENTITY}" --resource-rules "Payload/${APP_NAME}.app/ResourceRules.plist" "Payload/${APP_NAME}.app" || failed "Code signing failed"

#Re-package
echo "Packaging IPA file"
zip -qr "${OUTDIR}/${OUTPUT_IPA_FILE}" Payload || failed "Unable to package ipa"

echo ""
echo "DONE - produced '${OUTPUT_IPA_FILE}'"
