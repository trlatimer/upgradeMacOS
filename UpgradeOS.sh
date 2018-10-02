#!/bin/bash

###########################################################################################################################
#
# Upgrade Mac OS
#
###########################################################################################################################
#
#   Version 1.2
#   Date: 10/1/2018
#
#   Author: Tyler Latimer
#
# DESCRIPTION
#   The purpose of this script is to provide a streamline process for upgrading Macintosh systems to the newest OS. We ran into several issues with upgrading to High Sierra from old versions (pre-Sierra 10.12.6) due to the File System changes.
#   This script starts by obtaining the version of OS that is currently on the system. It then evaluates the values from that and determines whether or not Sierra 10.12.6 needs to be installed first or not. If it does, then it begins the installation. If the installer is not already on the system, it will go onto JAMF and download it.
#   If the system is at 10.12.6 then it will pass the check for upgrading to High Sierra and begin the download or installation.
#   The installation is set to no-interaction so it proceeds all the way through without requiring any user interaction.
#
# PRECAUTIONS
#   This script is only test on Sierra and El Capitan systems so far. Use caution when using on other versions of macOS.
#   This script requires the use of JAMF. If you wish to run it locally, you will need to manually input the parameters for the install path, version, and download triggers.
#   If the script determines that Sierra is needed first, you will need to run it a second time in order for it to go to High Sierra.
#
# TO DO
#   Refactor/Clean up
#
# TO ADD NEW MAC OS VERSIONS
#   If there is a new MacOS version available you will need to add the functionality for it to upgrade in the MAIN APPLICATION section
#
# KNOWN ISSUES
#   Issue with download loop
#       Possible Causes:
#           JAMF download policy not downloading installer, mismatching installer versions
#       What Happens:
#           Script prompts that it needs to download the macOS Installer. User clicks continue and the pop-up that the installer is downloading appears. Within a couple minutes, the pop-up that it needs to download the installer appears again. This will continue until the 'Cancel' is selected in the pop-up.
#       How to Correct:
#           Manually download the installer
#               1. Find a trusted source for downloading the Installer. App Store is the preferred choice
#               2. Ensure that the download is in your Applications directory
#               3. Run the script again
#           Examine the download policy, ensure that the triggers match and versions match. I ran into this issue and found that the cause was that my installer was version 10.13.4 but my desired version to upgrade to was 10.13.6 so it was flagging the download as the incorrect version.
#               1. Obtain a recent installer and ensure that it is the version desired
#               2. You could also correct the version listed in your parameters to match that of the installer
#               3. Ensure triggers match and that the download policy works by itself
#               4. Run the script again.
#
# RESOURCES
#   The install functions in this script were obtained from https://github.com/kc9wwh/macOSUpgrade but has been edited to fit into our environment. 
#   I placed the majority of the upgrade into a function that takes parameters so it can be used for more than just High Sierra. We were running into issues upgrading from older versions to High Sierra. I found that by upgraded to Sierra 10.12.6 and then up to High Sierra prevents these issues and reduces errors significantly. I added functionality to check for OS Version and upgrade accordingly. I also added some user interaction to the original script to allow users to cancel if they did not want to wait for the upgrade yet.
#
#
###########################################################################################################################

## FOR TESTING ONLY
## set -x
## trap read debug

# Determine current OS version - Used to determine appropriate upgrade path
osMajor=$( /usr/bin/sw_vers -productVersion | awk -F. {'print $2'} )
osMinor=$( /usr/bin/sw_vers -productVersion | awk -F. {'print $3'} )


# Function for upgrading. Takes 3 parameters.
# $1 is the installer path - "Applications/Install macOS Sierra.app"
# $2 is the desired version - 10.12.6
# $3 is the download trigger through JAMF - downloadSierra
function installUpgrade () {

##Erase & Install macOS (Factory Defaults)
##Requires macOS Installer 10.13.4 or later
##Disabled by default
##Options: 0 = Disabled / 1 = Enabled
eraseInstall=0

##Enter 0 for Full Screen, 1 for Utility window (screenshots available on GitHub)
userDialog=0

##Specify path to OS installer. Use Parameter 4 in the JSS, or specify here
##Example: /Applications/Install macOS High Sierra.app
OSInstaller="$1"

##Version of OS. Use Parameter 5 in the JSS, or specify here.
##Example: 10.12.5
version="$2"

##Trigger used for download. Use Parameter 6 in the JSS, or specify here.
##This should match a custom trigger for a policy that contains an installer
##Example: download-sierra-install
download_trigger="$3"

##MD5 Checksum of InstallESD.dmg
##This variable is OPTIONAL
##Leave the variable BLANK if you do NOT want to verify the checksum (DEFAULT)
##Example Command: /sbin/md5 /Applications/Install\ macOS\ High\ Sierra.app/Contents/SharedSupport/InstallESD.dmg
##Example MD5 Checksum: b15b9db3a90f9ae8a9df0f81741efa2b
installESDChecksum="" # was $7

##Title of OS
##Example: macOS High Sierra
macOSname=`echo "$OSInstaller" |sed 's/^\/Applications\/Install \(.*\)\.app$/\1/'`

##Title to be used for userDialog (only applies to Utility Window)
title="$macOSname Upgrade"

##Heading to be used for userDialog
heading="Please wait as we prepare your computer for $macOSname..."

##Title to be used for userDialog
description="This process will take approximately 5-10 minutes.
Once completed your computer will reboot and begin the upgrade."

##Description to be used prior to downloading the OS installer
dldescription="We need to download $macOSname to your computer, this will take several minutes."

##Jamf Helper HUD Position if macOS Installer needs to be downloaded
##Options: ul (Upper Left); ll (Lower Left); ur (Upper Right); lr (Lower Right)
##Leave this variable empty for HUD to be centered on main screen
dlPosition="ul"

##Icon to be used for userDialog
##Default is macOS Installer logo which is included in the staged installer package
icon="$OSInstaller/Contents/Resources/InstallAssistant.icns"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FUNCTIONS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Diplays a small popup showing that the installer is being downloaded and triggers the download policy to run
downloadInstaller() {
    /bin/echo "Preparing to download installer..."   
    /bin/echo "Downloading macOS Installer..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
        -windowType hud -windowPosition $dlPosition -title "$title"  -alignHeading center -alignDescription left -description "$dldescription" \
        -lockHUD -icon "$icon" -iconSize 100 &
    ##Capture PID for Jamf Helper HUD
    jamfHUDPID=$(echo $!)
    ##Run policy to cache installer
    /usr/local/jamf/bin/jamf policy -event $download_trigger
    ##Kill Jamf Helper HUD post download
    kill ${jamfHUDPID}
} # END downloadInstaller

verifyChecksum() {
    if [[ "$installESDChecksum" != "" ]]; then
        osChecksum=$( /sbin/md5 -q "$OSInstaller/Contents/SharedSupport/InstallESD.dmg" )
        if [[ "$osChecksum" == "$installESDChecksum" ]]; then
            echo "Checksum: Valid"
            break
        else
            echo "Checksum: Not Valid"
            echo "Beginning new dowload of installer"
            /bin/rm -rf "$OSInstaller"
            sleep 2
            downloadInstaller
        fi
    else
        break
    fi
}

cleanExit() {
    kill ${caffeinatePID}
    exit $1
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# SYSTEM CHECKS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Caffeinate
/usr/bin/caffeinate -dis &
caffeinatePID=$(echo $!)

##Get Current User
currentUser=$( stat -f %Su /dev/console )

##Check if FileVault Enabled
fvStatus=$( /usr/bin/fdesetup status | head -1 )

##Check if device is on battery or ac power
pwrAdapter=$( /usr/bin/pmset -g ps )
if [[ ${pwrAdapter} == *"AC Power"* ]]; then
    pwrStatus="OK"
    /bin/echo "Power Check: OK - AC Power Detected"
else
    pwrStatus="ERROR"
    /bin/echo "Power Check: ERROR - No AC Power Detected"
fi

##Check if free space > 15GB
osMajor=$( /usr/bin/sw_vers -productVersion | awk -F. {'print $2'} )
osMinor=$( /usr/bin/sw_vers -productVersion | awk -F. {'print $3'} )
if [[ $osMajor -eq 12 ]] || [[ $osMajor -eq 13 && $osMinor -lt 4 ]]; then
    freeSpace=$( /usr/sbin/diskutil info / | grep "Available Space" | awk '{print $6}' | cut -c 2- )
else
    freeSpace=$( /usr/sbin/diskutil info / | grep "Free Space" | awk '{print $6}' | cut -c 2- )
fi

if [[ ${freeSpace%.*} -ge 15000000000 ]]; then
    spaceStatus="OK"
    /bin/echo "Disk Check: OK - ${freeSpace%.*} Bytes Free Space Detected"
else
    spaceStatus="ERROR"
    /bin/echo "Disk Check: ERROR - ${freeSpace%.*} Bytes Free Space Detected"
fi

##Check for existing OS installer
loopCount=0
while [[ $loopCount -lt 3 ]]; do
    if [ -e "$OSInstaller" ]; then
        /bin/echo "$OSInstaller found, checking version."
        OSVersion=`/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$OSInstaller/Contents/SharedSupport/InstallInfo.plist"`
        /bin/echo "OSVersion is $OSVersion"
        if [ $OSVersion = $version ]; then
            /bin/echo "Installer found, version matches. Verifying checksum..."
            verifyChecksum
        else
            ##Delete old version.
            /bin/echo "Installer found, but old. Deleting..."
            /bin/rm -rf "$OSInstaller"
            sleep 2
            downloadInstaller
        fi
        ((loopCount++))
        if [ $loopCount -ge 3 ]; then
            /bin/echo "macOS Installer Downloaded 3 Times - Checksum is Not Valid"
            /bin/echo "Prompting user for error and exiting..."
            /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "Error Downloading $macOSname" -description "We were unable to prepare your computer for $macOSname. Please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1
            cleanExit 0
        fi
    else
        downloadInstaller
    fi
done

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# CREATE FIRST BOOT SCRIPT
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

/bin/mkdir /usr/local/jamfps

/bin/echo "#!/bin/bash
## First Run Script to remove the installer.
## Clean up files
/bin/rm -fdr \"$OSInstaller\"
/bin/sleep 2
## Update Device Inventory
/usr/local/jamf/bin/jamf recon
## Remove LaunchDaemon
/bin/rm -f /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
## Remove Script
/bin/rm -fdr /usr/local/jamfps
exit 0" > /usr/local/jamfps/finishOSInstall.sh

/usr/sbin/chown root:admin /usr/local/jamfps/finishOSInstall.sh
/bin/chmod 755 /usr/local/jamfps/finishOSInstall.sh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH DAEMON
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

cat << EOF > /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jamfps.cleanupOSInstall</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>/usr/local/jamfps/finishOSInstall.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    </dict>
    </plist>
EOF

##Set the permission on the file just made.
/usr/sbin/chown root:wheel /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
/bin/chmod 644 /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH AGENT FOR FILEVAULT AUTHENTICATED REBOOTS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Determine Program Argument
if [[ $osMajor -ge 11 ]]; then
    progArgument="osinstallersetupd"
elif [[ $osMajor -eq 10 ]]; then
    progArgument="osinstallersetupplaind"
fi

cat << EOP > /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.apple.install.osinstallersetupd</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>MachServices</key>
    <dict>
        <key>com.apple.install.osinstallersetupd</key>
        <true/>
    </dict>
    <key>TimeOut</key>
    <integer>Aqua</integer>
    <key>OnDemand</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>$OSInstaller/Contents/Frameworks/OSInstallerSetup.framework/Resources/$progArgument</string>
    </array>
</dict>
</plist>
EOP

##Set the permission on the file just made.
/usr/sbin/chown root:wheel /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
/bin/chmod 644 /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Performing Install
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ${pwrStatus} == "OK" ]] && [[ ${spaceStatus} == "OK" ]]; then
    #Prompt user to choose to continue or cancel
    /bin/echo "Verifying user wants to continue..."
    result2=`/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -countdown -timeout 600 -icon "$icon" -windowType utility -title "Continue Installing?" -heading "Continue installing?" -description "macOS is ready to upgrade. Please save all of your work and click 'Continue'" -button1 "Continue" -button2 "Cancel" -defaultButton 1 -cancelButton 2`
    #If user chooses to continue, perform the install
    if [[ ${result2} == 0 ]]; then
        /bin/echo "User chose to continue..."
        ##Launch jamfHelper
        if [[ ${userDialog} == 0 ]]; then
            /bin/echo "Launching jamfHelper as FullScreen..."
            /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "" -icon "$icon" -heading "$heading" -description "$description" &
            jamfHelperPID=$(echo $!)
        fi
        if [[ ${userDialog} == 1 ]]; then
            /bin/echo "Launching jamfHelper as Utility Window..."
            /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "$heading" -description "$description" -iconSize 100 &
            jamfHelperPID=$(echo $!)
        fi
        ##Load LaunchAgent
        if [[ ${fvStatus} == "FileVault is On." ]] && [[ ${currentUser} != "root" ]]; then
            userID=$( id -u ${currentUser} )
            launchctl bootstrap gui/${userID} /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
        fi
        ##Begin Upgrade
        /bin/echo "Launching startosinstall..."
        ##Check if eraseInstall is Enabled
        if [[ $eraseInstall == 1 ]]; then
            /bin/echo "   Script is configured for Erase and Install of macOS."
            "$OSInstaller/Contents/Resources/startosinstall" --applicationpath "$OSInstaller" --eraseinstall --nointeraction --pidtosignal $jamfHelperPID &
        else
            /bin/echo " Script is configured for Install of macOS"
            "$OSInstaller/Contents/Resources/startosinstall" --applicationpath "$OSInstaller" --nointeraction --pidtosignal $jamfHelperPID &
        fi
        /bin/sleep 3
    #If user chooses not to continue, cancel the install
    else
        # Diplay a pop-up detailing that install was cancelled. User must press 'Ok' to fully exit
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Cancel Install" -icon "$icon" -heading "Cancelling install" -description "Cancelling upgrade of macOS. Please try again when you have enough time to complete." -iconSize 100 -button1 "Ok" -defaultButton 1
        # Remove script
        /bin/rm -f /usr/local/jamfps/finishOSInstall.sh
        /bin/rm -f /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
        /bin/rm -f /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist

        cleanExit 0
    fi

else
    ## Remove Script
    /bin/rm -f /usr/local/jamfps/finishOSInstall.sh
    /bin/rm -f /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
    /bin/rm -f /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist

    /bin/echo "Launching jamfHelper Dialog (Requirements Not Met)..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least 15GB of Free Space.
    If you continue to experience this issue, please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1

    cleanExit 0

fi

}

###########################################################################################################################
#
# MAIN APPLICATION - DETERMINE OS VERSION AND UPGRADE ACCORDINGLY
#
###########################################################################################################################

## Check OS Version
## If OS is 13.* then error that they are already on High Sierra
/bin/echo "Checking upgrade path..."
if [[ $osMajor -eq 13 ]]; then
    /bin/echo "You are already running High Sierra"
## If OS is >= 12.5.* then allow upgrade to High Sierra
elif [[ $osMajor -ge 12 && $osMinor -ge 5 ]]; then
    /bin/echo "You can update to High Sierra"
    # Parameters are input in JAMF. 4 = Installer file path, 5 = Desired version (e.i 10.12.6), 6 = JAMF event trigger for download
    installUpgrade "$4" "$5" "$6"
## If OS is < 12.5.* then upgrade to Sierra first
elif [[ $osMajor -lt 12 ]] || [[ $osMajor -eq 12 && $osMinor -lt 5 ]]; then
    /bin/echo "You need to upgrade to Sierra 10.12.6"
    # Parameters are input in JAMF. 7 = Installer file path, 8 = Desired version (e.i 10.12.6), 9 = JAMF event trigger for download
    installUpgrade "$7" "$8" "$9"
else
    /bin/echo "Unable to determine OS version"
    exit
fi

exit