#!/bin/sh

LOG_FILE="/var/log/automount_cleanup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

get_domain() {
    local domain=$(hostname -d)
    if [ -z "$domain" ]; then
        domain=$(grep '^domain' /etc/resolv.conf | awk '{print $2}')
    fi
    echo "$domain"
}

get_dc_server() {
    local domain=$1
    local dc=$(host -t SRV _ldap._tcp.dc._msdcs.$domain | awk '/has SRV record/ {print $NF}' | sed 's/\.$//' | head -1)
    if [ -z "$dc" ]; then
        dc=$(host -t A $domain | awk '/has address/ {print $4}' | head -1)
    fi
    echo "$dc"
}


retrieve_bitlocker_key() {
    local computer_name=$(hostname)
    local domain=$(get_domain)
    local dc_server=$(get_dc_server "$domain")
    local admin_user="your_admin_user"
    local admin_password="your_admin_password"

    log "Retrieving BitLocker key for $computer_name"

    # Ensure Kerberos configuration is set
    echo "
[libdefaults]
default_realm = ${domain^^}
dns_lookup_realm = false
dns_lookup_kdc = true

[realms]
${domain^^} = {
    kdc = $dc_server
    admin_server = $dc_server
}

[domain_realm]
.$domain = ${domain^^}
$domain = ${domain^^}
" > /etc/krb5.conf

    # Authenticate with Kerberos
    echo "$admin_password" | kinit "$admin_user@${domain^^}" 2>> "$LOG_FILE"
    if [ $? -ne 0 ]; then
        log "Failed to authenticate with Kerberos"
        return 1
    fi

    # Get the computer's Distinguished Name
    dn=$(ldapsearch -H ldaps://$dc_server -Y GSSAPI -b "DC=${domain//./,DC=}" "(cn=$computer_name)" dn | grep dn: | cut -d ' ' -f 2-)
    if [ -z "$dn" ]; then
        log "Failed to find computer object in AD"
        kdestroy
        return 1
    fi

    # Retrieve the BitLocker recovery key
    recovery_key=$(ldapsearch -H ldaps://$dc_server -Y GSSAPI -b "$dn" -s sub "(objectClass=msFVE-RecoveryInformation)" msFVE-RecoveryPassword | grep msFVE-RecoveryPassword: | tail -1 | cut -d ' ' -f 2-)
    if [ -z "$recovery_key" ]; then
        log "No BitLocker recovery key found for this computer"
        kdestroy
        return 1
    fi

    # Clean up Kerberos ticket
    kdestroy

    log "Successfully retrieved BitLocker key"
    echo "$recovery_key"
}

mount_bitlocker_drive() {
    for drive in /dev/sd*; do
        if [ -b "$drive" ]; then
            if blkid -p -o value -s TYPE "$drive" | grep -q "BitLocker"; then
                log "BitLocker drive found: $drive"
                mount_point="/mnt/bitlocker"
                mkdir -p "$mount_point"
                mkdir -p "/tmp/dislocker"
                
                bitlocker_key=$(retrieve_bitlocker_key)
                if [ -z "$bitlocker_key" ]; then
                    log "Failed to retrieve BitLocker key"
                    return 1
                fi
                
                if dislocker -V "$drive" -p"$bitlocker_key" -- "/tmp/dislocker"; then
                    if mount -o loop "/tmp/dislocker/dislocker-file" "$mount_point"; then
                        log "Successfully mounted BitLocker drive $drive to $mount_point"
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
    if [ -d "$windows_dir" ]; then
        local target_dir="$windows_dir/System32/drivers/CrowdStrike"
        if [ -d "$target_dir" ]; then
            local file_to_delete=$(find "$target_dir" -name "C-00000291*.sys" -print -quit)
            if [ -n "$file_to_delete" ]; then
                if rm "$file_to_delete"; then
                    log "Successfully deleted $file_to_delete"
                else
                    log "Failed to delete $file_to_delete"
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

# Main execution
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
