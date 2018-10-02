# Upgrade MacOS
Bash script to upgrade Macintosh operating systems

Version: 1.2
Date: 10/1/2018

Author: Tyler Latimer

## DESCRIPTION
The purpose of this script is to provide a streamline process for upgrading Macintosh systems to the newest OS. We ran into several issues with upgrading to High Sierra from old versions (pre-Sierra 10.12.6) due to the File System changes.

This script starts by obtaining the version of OS that is currently on the system. It then evaluates the values from that and determines whether or not Sierra 10.12.6 needs to be installed first or not. If it does, then it begins the installation. If the installer is not already on the system, it will go onto JAMF and download it.

If the system is at 10.12.6 then it will pass the check for upgrading to High Sierra and begin the download or installation.

The installation is set to no-interaction so it proceeds all the way through without requiring any user interaction.

## PRECAUTIONS
This script is only test on Sierra and El Capitan systems so far. Use caution when using on other versions of macOS.

This script requires the use of JAMF. If you wish to run it locally, you will need to manually input the parameters for the install path, version, and download triggers.

If the script determines that Sierra is needed first, you will need to run it a second time in order for it to go to High Sierra.

## TO ADD NEW MAC OS VERSIONS
- If there is a new MacOS version available you will need to add the functionality for it to upgrade in the MAIN APPLICATION section

## KNOWN ISSUES
Issue with download loop
- Possible Causes:
  - JAMF download policy not downloading installer, mismatching installer versions
- What Happens:
  - Script prompts that it needs to download the macOS Installer. User clicks continue and the pop-up that the installer is downloading appears. Within a couple minutes, the pop-up that it needs to download the installer appears again. This will continue until the 'Cancel' is selected in the pop-up.
- How to Correct:
  - Manually download the installer
    - Find a trusted source for downloading the Installer. App Store is the preferred choice
    - Ensure that the download is in your Applications directory
    - Run the script again
  - Examine the download policy, ensure that the triggers match and versions match. I ran into this issue and found that the cause was that my installer was version 10.13.4 but my desired version to upgrade to was 10.13.6 so it was flagging the download as the incorrect version.
    - Obtain a recent installer and ensure that it is the version desired
    - You could also correct the version listed in your parameters to match that of the installer
    - Ensure triggers match and that the download policy works by itself
    - Run the script again.

## RESOURCES
The install functions in this script were obtained from https://github.com/kc9wwh/macOSUpgrade but has been edited to fit into our environment. 

I placed the majority of the upgrade into a function that takes parameters so it can be used for more than just High Sierra. We were running into issues upgrading from older versions to High Sierra. I found that by upgraded to Sierra 10.12.6 and then up to High Sierra prevents these issues and reduces errors significantly. I added functionality to check for OS Version and upgrade accordingly. I also added some user interaction to the original script to allow users to cancel if they did not want to wait for the upgrade yet.
