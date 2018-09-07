#!/bin/bash

#########################################################################################################
#                                                                                                       # 
# Enable Secure token and FileVault 2 for local admin and current logged in user during provisioning    #
# For use with DEP workflow in JAMF Pro                                                                 # 
#                                                                                                       # 
# Author: Tim Lee                                                                                       #
# Created: 6/8/18                                                                                       #
#                                                                                                       # 
# VERSION: 1.0.6                                                                                        #
#                                                                                                       # 
#########################################################################################################

# INPUT Local Administrator account into JAMF parameters to enable secure token
localAdminAccount="$4"
localAdminPass="$5"

# ENTER Company specific variables here
loggingOn="TRUE"
LogLocation=
promptTitle=
promptLogo=



scriptLogging(){

if [ "$loggingOn" == "TRUE" ]; then
    DATE=`date +%Y-%m-%d\ %H:%M:%S`
    LOG="$LogLocation"
    echo "$DATE" " $1" >> $LOG
fi

}



# Get current logged in username
loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')



## Functions ##

promptForPass() {
# Prompt user for password
scriptLogging "promting user for password"

pwResult=$(su - $loggedInUser -c '/usr/bin/osascript << EOT
display dialog "Please enter your password to enable encryption on your Mac" \
buttons {"OK"} default button {"OK"} hidden answer true default answer "" \
with title "$promptTitle" with icon POSIX file "$promptLogo"
EOT'
)

userPassword=$(/bin/echo $pwResult | /usr/bin/cut -d "," -f2 | /usr/bin/cut -d ":" -f2)

}


validatePass() {
    scriptLogging "validating password"
    /bin/cp /Users/${loggedInUser}/Library/Keychains/login.keychain-db /Users/${loggedInUser}/Library/Keychains/login.keychain-db.BAK
    /usr/bin/security lock-keychain /Users/${loggedInUser}/Library/Keychains/login.keychain-db.BAK
    if $(/usr/bin/security unlock-keychain -p "$userPassword" /Users/${loggedInUser}/Library/Keychains/login.keychain-db.BAK); then
        scriptLogging "pw validation success"
        passValidate=1
    else
        scriptLogging "pw validation failed.  Retrying."
    fi
    /bin/rm /Users/${loggedInUser}/Library/Keychains/login.keychain-db.BAK
}


#### START HERE ####

scriptLogging "Enabling FileVault - START"

# Collect and validate password
passValidate=0

while [ $passValidate == 0 ]; do
    promptForPass
    validatePass
done


# Enable secure token
scriptLogging "Setting secure token"

/usr/sbin/sysadminctl -secureTokenOn "$loggedInUser" -password "$userPassword" -adminUser $localAdminAccount -adminPassword "$localAdminPass"


# write plist
/bin/echo "<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Username</key>
<string>${loggedInUser}</string>
<key>Password</key>
<string>${userPassword}</string>
<key>AdditionalUsers</key>
<array>
    <dict>
        <key>Username</key>
        <string>${localAdminAccount}</string>
        <key>Password</key>
        <string>${localAdminPass}</string>
    </dict>
</array>
</dict>
</plist>" > /tmp/fv2.plist


# enable filevault
scriptLogging "enabling FileVault"

/usr/bin/fdesetup enable -inputplist < /tmp/fv2.plist

## remove admin rights from localAdmin account - commenting out for public consumption
# scriptLogging "removing sudo access for $localAdminAccount"

# /usr/bin/dscl . -delete /Groups/admin GroupMembership $localAdminAccount


# clean up
scriptLogging "clean up"
/bin/rm /tmp/fv2.plist

scriptLogging "Enabling FileVault - Complete"

su - $loggedInUser -c '/usr/bin/osascript << EOT
display dialog "Encryption Enabled" \
buttons {"OK"} default button {"OK"} \
with title "$promptTitle" with icon POSIX file \
"$promptLogo"
EOT'
