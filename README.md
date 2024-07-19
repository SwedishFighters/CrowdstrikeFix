## ⚠️ Disclaimer

This project is not affiliated with, endorsed by, or in any way officially connected to CrowdStrike, Inc.
CrowdStrike® and the CrowdStrike logo are the registered trademarks of CrowdStrike, Inc. All rights to the CrowdStrike name, logo, and brand belong to CrowdStrike, Inc.
CrowdStrike, Inc. is a cybersecurity technology company founded in 2011 by George Kurtz, Dmitri Alperovitch, and Gregg Marston. The company is headquartered in Austin, Texas, United States.
This repository is an independent project aimed at addressing specific issues related to CrowdStrike software updates. It is not an official solution provided by CrowdStrike, Inc.

For official support and information about CrowdStrike products, please visit [www.crowdstrike.com](https://www.crowdstrike.com).


# 🛠️ CrowdstrikeFix

<p align="center">
  <img src="https://img.shields.io/badge/Status-Experimental-yellow" alt="Status: Experimental">
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License: Apache 2.0">
  <img src="https://img.shields.io/badge/Contributions-Welcome-brightgreen" alt="Contributions: Welcome">
</p>

A scalable solution framework for addressing the Crowdstrike update issue. 
This project provides a potential approach to automate the fix across multiple systems.

## 🚀 What `build.sh` Does

Our build script automates the creation and modification of key files:

- Creates:
  - `preseed.cfg`
  - `post-install.sh`
- Modifies:
  - `pxelinux.cfg/default`

## 📋 Quick Start Guide

1. Make the build script executable:
   ```
   chmod 755 build.sh
   ```

2. Run the build script:
   ```
   ./build.sh
   ```

3. Set up a web server (e.g., Apache or Nginx) to serve `preseed.cfg` and `post-install.sh`.

4. Configure your DHCP server to offer PXE boot options pointing to your TFTP server.

5. Copy the modified netboot files to your TFTP server.

> 📝 **Note:** Replace `"${http_server}"` in the PXE configuration with your web server's actual IP or hostname.

## 🔍 How It Works
Served via PXE-boot which superseeds Windows-boot (requires PXE boot capability, UEFI or BIOS configured to allow network booting 
and BitLocker-encrypted drives (for the script to have an effect))

1. Boots into a minimal Debian environment
2. Installs necessary packages (dislocker, ldap-utils, krb5-user)
3. Sets up the `automount_and_cleanup.sh` script
4. Runs the script at each boot (cleanup performed only once)

## 🛠️ Script Functionality

The script will:

- Automatically detect the domain and domain controller
- Use pre-configured AD admin credentials
- Mount BitLocker-protected drives
- Locate the Windows directory on the BitLocker drive
- Remove the specified CrowdStrike file
- Reboot the system

# 📋 Requirements for CrowdstrikeFix

To successfully implement and run the CrowdstrikeFix solution, ensure the following requirements are met:

## 🖧 Network Infrastructure
- DHCP server configured for PXE boot options
- TFTP server for netboot files
- Web server (Apache/Nginx) for preseed.cfg and post-install.sh
- Reliable network connectivity

## 🏢 Active Directory
- Functioning AD domain with accessible Domain Controller
- AD admin account with BitLocker recovery key read permissions

## 💻 Target Machines
- PXE boot capability
- UEFI/BIOS configured for network booting
- BitLocker-encrypted drives

## 🛠️ Software and Packages
- Debian netboot files
- Required packages: dislocker, ntfs-3g, ldap-utils, krb5-user, fuse, cryptsetup

## 🔐 Permissions and Security
- Modify DHCP, TFTP, and web servers
- Root-level execution on target machines
- Secure AD admin credential handling
- Network security for PXE boot process

## 💾 Storage and Compatibility
- Sufficient disk space on target machines
- Hardware compatibility with chosen Debian version

## 🧪 Testing and Support
- Controlled testing environment
- Clear documentation and knowledgeable support personnel

## 📜 Compliance and Recovery
- Adherence to organizational security policies
- Backup solution for target machines
- Recovery plan for potential failures

## 🔍 Monitoring and Scalability
- Capability to monitor multiple machines
- Infrastructure for simultaneous PXE boots

## ⏱️ Time Management
- Synchronization across network components

## 🚀 Authorization
- Permission to modify system files and configurations

Ensure all these requirements are met before deploying the CrowdstrikeFix solution in your environment.


## ⚠️ Important Disclaimers

- **Experimental Solution:** This project is a proof of concept and starting point for a potential solution. It has not been thoroughly tested in production environments.

- **Use at Your Own Risk:** The authors and contributors take no responsibility for any consequences resulting from the use of this code. It is provided AS IS, without any warranties.

- **Expertise Required:** Only attempt to use or modify this solution if you have a thorough understanding of the systems involved and the potential risks.

## 🤝 Contributions

We welcome contributions to improve and refine this solution. If you're interested in collaborating, please reach out to @SwedishFighters on Twitter.

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Made with ❤️ by the SwedishFighters team
</p>
