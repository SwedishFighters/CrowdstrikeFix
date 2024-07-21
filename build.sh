#!/bin/bash

# Ask for admin credentials
read -p "Enter AD admin username: " ADMIN_USER
read -s -p "Enter AD admin password: " ADMIN_PASSWORD
echo

# Download Debian netboot files
wget https://deb.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/netboot.tar.gz
tar -xzvf netboot.tar.gz

# Create custom preseed file
cat << EOF > preseed.cfg
d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_domain string unassigned-domain
d-i netcfg/wireless_wep string
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password $(openssl passwd -1 -salt xyz temppass)
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server dislocker ldap-utils krb5-user ntfs-3g fuse cryptsetup
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i finish-install/reboot_in_progress note
d-i preseed/late_command string in-target wget http://\${http_server}/post-install.sh -O /root/post-install.sh; in-target chmod +x /root/post-install.sh; in-target /root/post-install.sh
EOF

# Create post-install script
cat << EOF > post-install.sh
#!/bin/bash

cat << 'EOT' > /root/automount_and_cleanup.sh
#!/bin/bash

LOG_FILE="/var/log/automount_cleanup.log"

log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"
}

get_domain() {
    local domain=\$(hostname -d)
    if [ -z "\$domain" ]; then
        domain=\$(grep '^domain' /etc/resolv.conf | awk '{print \$2}')
    fi
    echo "\$domain"
}

get_dc_server() {
    local domain=\$1
    local dc=\$(host -t SRV _ldap._tcp.dc._msdcs.\$domain | awk '/has SRV record/ {print \$NF}' | sed 's/\.$//' | head -1)
    if [ -z "\$dc" ]; then
        dc=\$(host -t A \$domain | awk '/has address/ {print \$4}' | head -1)
    fi
    echo "\$dc"
}

retrieve_bitlocker_key() {
    local computer_name=\$(hostname)
    local domain=\$(get_domain)
    local dc_server=\$(get_dc_server "\$domain")

    log "Retrieving BitLocker key for \$computer_name"

    echo "
[libdefaults]
default_realm = \${domain^^}
dns_lookup_realm = false
dns_lookup_kdc = true

[realms]
\${domain^^} = {
    kdc = \$dc_server
    admin_server = \$dc_server
}

[domain_realm]
.\$domain = \${domain^^}
\$domain = \${domain^^}
" > /etc/krb5.conf

    echo "$ADMIN_PASSWORD" | kinit "$ADMIN_USER@\${domain^^}" 2>> "\$LOG_FILE"
    if [ \$? -ne 0 ]; then
        log "Failed to authenticate with Kerberos"
        return 1
    fi

    dn=\$(ldapsearch -H ldaps://\$dc_server -Y GSSAPI -b "DC=\${domain//./,DC=}" "(cn=\$computer_name)" dn | grep dn: | cut -d ' ' -f 2-)
    if [ -z "\$dn" ]; then
        log "Failed to find computer object in AD"
        kdestroy
        return 1
    fi

    recovery_key=\$(ldapsearch -H ldaps://\$dc_server -Y GSSAPI -b "\$dn" -s sub "(objectClass=msFVE-RecoveryInformation)" msFVE-RecoveryPassword | grep msFVE-RecoveryPassword: | tail -1 | cut -d ' ' -f 2-)
    if [ -z "\$recovery_key" ]; then
        log "No BitLocker recovery key found for this computer"
        kdestroy
        return 1
    fi

    kdestroy

    log "Successfully retrieved BitLocker key"
    echo "\$recovery_key"
}

mount_bitlocker_drive() {
    for drive in /dev/sd*; do
        if [ -b "\$drive" ]; then
            if blkid -p -o value -s TYPE "\$drive" | grep -q "BitLocker"; then
                log "BitLocker drive found: \$drive"
                mount_point="/mnt/bitlocker"
                mkdir -p "\$mount_point"
                mkdir -p "/tmp/dislocker"
                
                bitlocker_key=\$(retrieve_bitlocker_key)
                if [ -z "\$bitlocker_key" ]; then
                    log "Failed to retrieve BitLocker key"
                    return 1
                fi
                
                if dislocker -V "\$drive" -p"\$bitlocker_key" -- "/tmp/dislocker"; then
                    if mount -o loop "/tmp/dislocker/dislocker-file" "\$mount_point"; then
                        log "Successfully mounted BitLocker drive \$drive to \$mount_point"
                        return 0
                    else
                        log "Failed to mount decrypted BitLocker drive"
                        return 1
                    fi
                else
                    log "Failed to decrypt BitLocker drive"
                    return 1
                fi
            fi
        fi
    done
    log "No BitLocker drive found"
    return 1
}

delete_crowdstrike_file() {
    local windows_dir="/mnt/bitlocker/Windows"
    if [ -d "\$windows_dir" ]; then
        local target_dir="\$windows_dir/System32/drivers/CrowdStrike"
        if [ -d "\$target_dir" ]; then
            local file_to_delete=\$(find "\$target_dir" -name "C-00000291*.sys" -print -quit)
            if [ -n "\$file_to_delete" ]; then
                if rm "\$file_to_delete"; then
                    log "Successfully deleted \$file_to_delete"
                else
                    log "Failed to delete \$file_to_delete"
                fi
            else
                log "No matching CrowdStrike file found"
            fi
        else
            log "CrowdStrike directory not found"
        fi
    else
        log "Windows directory not found on BitLocker drive"
    fi
}

if [ -f "/tmp/cleanup_complete" ]; then
    log "Cleanup already performed. Exiting."
    exit 0
fi

log "Starting automount and cleanup process"

if mount_bitlocker_drive; then
    delete_crowdstrike_file
    umount /mnt/bitlocker
    umount /tmp/dislocker
else
    log "Failed to mount BitLocker drive"
fi

touch /tmp/cleanup_complete
log "Process completed. Rebooting..."
reboot
EOT

chmod +x /root/automount_and_cleanup.sh

# Add the script to run at boot
echo "@reboot root /root/automount_and_cleanup.sh" >> /etc/crontab
EOF

# Modify PXE configuration
cat << EOF > pxelinux.cfg/default
default debian-installer
label debian-installer
  menu label ^Install Debian (Custom)
  kernel debian-installer/amd64/linux
  append vga=788 initrd=debian-installer/amd64/initrd.gz auto=true priority=critical url=http://\${http_server}/preseed.cfg
EOF

# Modify Grub configuration
cat << EOF > debian-installer/amd64/grub/grub.cfg
menuentry 'Fix CrowdStrike' {
  linux   debian-installer/amd64/linux
  initrd  debian-installer/amd64/initrd.gz auto=true priority=critical url=\${http_server}/preseed.cfg append vga=788
}
EOF
echo "Build complete. Please set up a web server to serve preseed.cfg and post-install.sh, and configure your DHCP server for PXE boot."
