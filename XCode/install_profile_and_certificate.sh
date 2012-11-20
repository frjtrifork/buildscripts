#!/bin/bash
set -e

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
# This script can be used to re(install) an Apple provisioning profile    *
# and certificate.                                                        *
#                                                                         *
#                                                                         *
# Requirements:                                                           *
#  - XCode command line tools must be installed on the system             *
#                                                                         *
# Usage:                                                                  *
# install_profile_and_certificate.sh <mobileprovision> <certificate>      *
#                                                                         *
#**************************************************************************


if [ ! $# -eq 3 ]; then
  echo "Usage: ENV_VARS $0 <mobileprovision> <certificate>"
  echo "   Parameters:"
  echo "      1: Mobile provisioning file."
  echo "      2: certificate.cer"
  echo "      3: pkcs12.p12"
  echo ""
  echo "   Environment variables [all optional]:"
  echo "      [CERTIFICATE_PASSWORD - Certificate password. Default is blank]"
  echo "      [KEYCHAIN - Path to keychain. Default is $(security default-keychain)]"
  echo "      [KEYCHAIN_PASSWORD - Keychain password. Default is blank. If non-blank the script will unlock the keychain]"
  echo ""
  exit 1
fi

KEYCHAIN="${KEYCHAIN:-$(security default-keychain | cut -d\" -f2)}"
KEYCHAIN_PASSWORD=${KEYCHAIN_PASSWORD:-""}
CERTIFICATE_PASSWORD=${CERTIFICATE_PASSWORD:-""}


WORKDIR="${TMPDIR}/install_mobileprovision_and_cert"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"

###################### BEGIN FUNCTIONS ######################

function debug_log()
{
  echo " [DEBUG] - ${1}" 
}

function info_log()
{
  echo " [INFO] - ${1}" 
}

function error_log()
{
  echo " [ERROR] - ${1}" 
}

function failed()
{
    local error=${1:-Undefined error}
    error_log "Failed: $error" 
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
  		failed "Mobileprovision file '${1}' not found"
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
  	failed "plist file '${1}' not found"
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
  	failed "plist file '${1}' not found"
  fi

  application_identifier=$(/usr/libexec/PlistBuddy -c "print :Entitlements:application-identifier" "$1")
  team_identifier="$(/usr/libexec/PlistBuddy -c 'print :TeamIdentifier:0' "$1")"

  team_identifier_length=$((${#team_identifier} + 1))
  echo "${application_identifier:$team_identifier_length}"
}

function uuid_from_plist()
{
  if [ ! -f "${1}" ]; then
  	failed "plist file '${1}' not found"
  fi

   uuid=$(/usr/libexec/PlistBuddy -c "print :UUID" "$1")
   echo "$uuid"
}

function install_provisioning_profile()
{
  if [ ! -f "${1}" ]; then
  	failed "mobileprovision file '${1}' not found"
  fi

  PROVISIONING_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
  
  tmp_plist=$(plist_from_mobileprovision "${1}")
  uuid=$(uuid_from_plist "$tmp_plist") 
  install_name="${uuid}.mobileprovision"

  # Copy the mobileprovision file into PROVISIONING_DIR
  cp "${PROVISIONING_FILE}" "${PROVISIONING_DIR}/${install_name}"
  echo $(absolute_path "${PROVISIONING_DIR}/${install_name}")
}

###################### END FUNCTIONS ######################




### Check input ###
if [ ! -f "${1}" ]; then
  failed "File '$1' not found"
else
  PROVISIONING_FILE=$(absolute_path "${1}")
fi

if [ ! -f "${2}" ]; then
  failed "File '$2' not found"
else
  CERTIFICATE_FILE=$(absolute_path "${2}")
fi

if [ ! -f "${3}" ]; then
  failed "File '$3' not found"
else
  PKCS12_FILE=$(absolute_path "${3}")
fi

if [ ! $# -eq 3 ]; then
	failed "This script requires three arguments"
fi


echo ""
echo "Installing provisioning profile and certificate: "
echo "  MobileProvision: '${PROVISIONING_FILE}'"
echo "  Certificate: '${CERTIFICATE_FILE}'"
echo "  PKCS12: '${PKCS12_FILE}'"
echo ""


info_log "Installing provisioning profile"
installed_mobileprovision=$(install_provisioning_profile "${PROVISIONING_FILE}")
debug_log "Provision path: $installed_mobileprovision"


# In either case, check that the keychain exists
if [ ! -f "$KEYCHAIN" ]; then
	failed "Keychain '$KEYCHAIN' not found - aborting"
fi
debug_log "Keychain: $KEYCHAIN"

# If KEYCHAIN_PASSWORD is set, use it to unlock the keychain
if [ -n "${KEYCHAIN_PASSWORD}" ]; then
	info_log "Unlocking $KEYCHAIN"
	security unlock-keychain -p ${KEYCHAIN_PASSWORD} "${KEYCHAIN}"
	if [ $? != 0 ]; then
		failed "Failed unlocking keychain $KEYCHAIN"
	fi
fi


#Obtain the code signing identity, and use it to search for existing certificate in keychain
provisioning_plist=$(plist_from_mobileprovision "$PROVISIONING_FILE")
code_signing_identity=$(code_signing_identity_from_plist "$provisioning_plist")

debug_log "Code signing identy: $code_signing_identity"


# Find code signing identity '$code_signing_identity' certificate in "${KEYCHAIN}"
#  -- if a certificate is found, delete it from the "${KEYCHAIN}"
pem=$(security find-certificate -c "$code_signing_identity" -p "${KEYCHAIN}" 2> /dev/null) || true
if [ -n "$pem" ]; then
	info_log "Deleting certificate '$code_signing_identity' from keychain ${KEYCHAIN}"
	security delete-certificate -c "$code_signing_identity" "${KEYCHAIN}"
#	echo "$pem" | openssl x509 -noout -enddate -subject
fi

info_log "Adding certificate to keychain"
security add-certificates -k "${KEYCHAIN}" "${CERTIFICATE_FILE}"

#info_log "Importing certificate - $(basename ${CERTIFICATE_FILE}) into $(basename ${KEYCHAIN})"
#security import "${CERTIFICATE_FILE}" -k "${KEYCHAIN}" -P "${CERTIFICATE_PASSWORD}" -T /usr/bin/codesign

#info_log "Trust certificate for codeSigning"
#security add-trusted-cert -p codeSign -k "${KEYCHAIN}" "${CERTIFICATE_FILE}"

info_log "Import private key - $(basename ${PKCS12_FILE}) into $(basename ${KEYCHAIN})"
security import "${PKCS12_FILE}" -k "${KEYCHAIN}" -P "${CERTIFICATE_PASSWORD}" -T /usr/bin/codesign


# List identities for code signing
echo "Find identities for codesigning"
security find-identity -p codesigning -v "${KEYCHAIN}"

echo "Find code signing certificate"
security find-certificate -a -c "$code_signing_identity" -Z "${KEYCHAIN}"

echo "Done"