#!/bin/bash
#set -x
SCRIPTPATH=$(cd "$(dirname "$0")"; pwd)
PROVISIONING_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
echo "Listing active provisioning profiles in $PROVISIONING_DIR"
echo
echo "-------------[ UUID ]---------------    ----[ Expires ]-----   ----------[application-identifier]----------   -------------[File]------------"

find "${PROVISIONING_DIR}" -type f -name "*.mobileprovision" -print0 | while read -d $'\0' file
do
#  echo "$file"
  bash "${SCRIPTPATH}/mobileprovision.sh" "$file"
done

echo
echo "--------------------------------------------------------------- DONE ------------------------------------------------------------------------"
