#!/bin/bash

# Upgrade openSUSE Leap to openSUSE Tumbleweed
# --------------------------------------------

LOG_FILE="/var/log/UpgradeLeapToTumbleweed.log"
SERVER_NAME=$(hostname)  # Automatically get server name
FLAG_FILE="/var/log/UpgradeLeapToTumbleweed-flag"  # File to track script progress

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    log "ERROR: This script must be run as root. Use 'sudo bash $0'"
    exit 1
fi

log "Starting upgrade process for '$SERVER_NAME'..."
log "Log file: $LOG_FILE"

# Step 1: Check if openSUSE Leap is already updated
if [[ ! -f "$FLAG_FILE" ]]; then
    log "Checking if openSUSE Leap is up to date..."
    
    # Get the installed Leap version
    CURRENT_VERSION=$(grep VERSION= /etc/os-release | cut -d'=' -f2 | tr -d '"')

    # Get the latest Leap release from openSUSE's repo
    LATEST_VERSION=$(curl -s https://download.opensuse.org/distribution/leap/ | grep -oP '(?<=<td  class="name"><a href="./)15\.[0-9]+(?=/")' | sort -V | tail -1)

    log "Installed Leap Version: $CURRENT_VERSION"
    log "Latest Leap Version: $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        log "System is already updated to the latest openSUSE Leap version. Skipping update step."
		echo "1" > "$FLAG_FILE"  # Save progress
		
    else
        log "Updating openSUSE Leap before upgrade..."
        zypper refresh && zypper update -y
        if [[ $? -ne 0 ]]; then
            log "ERROR: System update failed!"
            exit 1
        fi

        log "System updated successfully. Rebooting..."
        echo "1" > "$FLAG_FILE"  # Save progress
        reboot
        exit 0  # Stop script execution to allow reboot
    fi
fi


# Step 2: Remove existing Leap repositories
if [[ $(cat "$FLAG_FILE") -eq 1 ]]; then
    log "Removing old openSUSE Leap repositories..."
	for repo in $(zypper lr -u | awk 'NR>2 {print $1}'); do
    	zypper rr "$repo"
	done
    echo "2" > "$FLAG_FILE"
fi


# Step 3: Add Tumbleweed repositories
if [[ $(cat "$FLAG_FILE") -eq 2 ]]; then
    log "Adding openSUSE Tumbleweed repositories..."

    REPOS=(
        "https://download.opensuse.org/tumbleweed/repo/oss/ openSUSE-Tumbleweed-Oss"
        "https://download.opensuse.org/tumbleweed/repo/non-oss/ openSUSE-Tumbleweed-Non-Oss"
        "https://download.opensuse.org/update/tumbleweed/ openSUSE-Tumbleweed-Update"
        "https://download.opensuse.org/tumbleweed/repo/debug/ openSUSE-Tumbleweed-Debug"
        "http://download.opensuse.org/tumbleweed/repo/src-oss repo-src-oss"
        "http://download.opensuse.org/tumbleweed/repo/src-non-oss repo-src-non-oss"
    )

    for repo in "${REPOS[@]}"; do
        zypper ar -f -d -c $repo
        if [[ $? -ne 0 ]]; then
            log "ERROR: Failed to add repository $repo"
            exit 1
        fi
    done

    log "All repositories added successfully."
    echo "3" > "$FLAG_FILE"
fi

# Step 4: Verify repositories
if [[ $(cat "$FLAG_FILE") -eq 3 ]]; then
    log "Verifying new repository list..."
    zypper lr | tee -a "$LOG_FILE"
    echo "4" > "$FLAG_FILE"
fi

# Step 5: Enable and Refresh repositories and trust new GPG keys
if [[ $(cat "$FLAG_FILE") -eq 4 ]]; then
    log "Refreshing repositories and trusting new GPG keys..."
	zypper modifyrepo --all --enable
    zypper refresh
    if [[ $? -ne 0 ]]; then
        log "ERROR: Repository refresh failed!"
        exit 1
    fi
    echo "5" > "$FLAG_FILE"
fi

# Step 6: Start the full distribution upgrade
if [[ $(cat "$FLAG_FILE") -eq 5 ]]; then
    log "Starting the full distribution upgrade..."
    zypper cc -a
	zypper ref
    zypper dup --allow-vendor-change -y
    if [[ $? -ne 0 ]]; then
        log "ERROR: Distribution upgrade failed!"
        exit 1
    fi
    log "Upgrade completed successfully!"
    echo "6" > "$FLAG_FILE"
fi

# Step 7: Reboot after upgrade
if [[ $(cat "$FLAG_FILE") -eq 6 ]]; then
    log "Rebooting server '$SERVER_NAME' to finalize upgrade..."
    rm -f "$FLAG_FILE"  # Remove flag file after completion
    reboot
    exit 0
fi
