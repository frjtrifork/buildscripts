buildscripts
===========

The scripts collected in this repository are mainly useful in situations where
you have a headless setup or need to do things from a buildserver like Jenkins. 

Or maybe you simply prefer to use the Terminal rather than click around in the
XCode UI.

XCode
=====
Scripts specific for iOS development will be collected in this folder.

Dependencies
============
All the scripts are based on the Apple XCode command line tools which are installed
along with XCode (or can be installed by going to the Download preferences pane in 
XCode - XCode->Preferences->Downloads and install Command Line Tools). 

If you don't have XCode installed on the system, you can download the XCode Command 
Line Tools as a separate install from the Apple Developer Portal:
https://developer.apple.com/downloads/
You will need your Apple-ID to be able to download the tools.

Note: There are different versions for OSx 10.7 and OSx 10.8 - so make sure you 
select the correct one for your system.
E.g. the latest version for OSx 10.8 Mountain Lion is called "Command Line Tools 
(OS X Mountain Lion) for Xcode - November 2012" - so it should be fairly easy
to locate. New releases comes every month or so, usually it is safe to go with the 
lates version.

Other than XCode Command Line Tools, the scripts should work out of the box on OSx 
systems. Other tools the scripts typically use include PlistBuddy and Python - but 
both are included in a normal OSx installation.

Description
===========
The scripts can be used to install new provisioning profiles, re-sign 
IPA files for OTA distribution, build an XCode iOS project from scratch
for distribution using defined code signing identity and bundle identifier and
similar tasks.
