#!/bin/bash

# mem_usage_details.sh - Comprehensive Memory Usage Monitor
# This script monitors various memory-related metrics in real-time to help diagnose
# potential causes of Out-of-Memory (OOM) errors.
# This script is designed to be run on a system that is experiencing memory issues.
# It will monitor the following metrics:
# - Total memory usage
# - Swap usage
# - Memory pressure indicators
# - Kernel memory details
# - Top memory-consuming processes
# - Memory fragmentation
# - Memory leaks
# - Memory usage by process
# - Memory usage by user
# - Memory usage by application
# - Memory usage by service
# - Memory usage by kernel
# - Memory usage by swap    

#creator: GPUGus
#version: 1.0
#date: 2025-03-11
#usage: ./mem_usage_details.sh
#notes: I was tracking down OOM crashes while using Cursonr. Pay attention to your VSZ values.
# https://forum.cursor.com/t/cursor-memory-leak-7gb-ram-usage-makes-it-unusable-crashes-constantly/60625/3


# Set terminal colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print section headers
print_header() {
    echo -e "${YELLOW}===== $1 =====${NC}"
}

# Function to get memory sizes in human-readable format with space between value and unit
get_human_size() {
    # Get the basic output from numfmt
    local result=$(numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1 B")
    
    # Insert a space between the number and the unit (e.g., change "16GiB" to "16 GiB")
    result=$(echo "$result" | sed -E 's/([0-9.]+)([A-Za-z]+)/\1 \2/')
    
    echo "$result"
}

# Function to get percentage with color coding
get_percent() {
    local value=$1
    local color=${NC}
    
    if (( $(echo "$value >= 90" | bc -l) )); then
        color=${RED}
    elif (( $(echo "$value >= 70" | bc -l) )); then
        color=${YELLOW}
    elif (( $(echo "$value >= 0" | bc -l) )); then
        color=${GREEN}
    fi
    
    echo -e "${color}${value}%${NC}"
}

# Function to convert possible scientific notation to integer
to_integer() {
    echo "$1" | awk '{printf "%.0f", $1}'
}

# Function to display data in three columns: key, value, note
print_metric() {
    local key="$1"
    local value="$2"
    local note="$3"
    local key_width=30
    local value_width=8
    
    printf "%${key_width}s %${value_width}s %s\n" "$key" "$value" "$note"
}

# Function to monitor system memory usage
monitor_system_memory() {
    print_header "SYSTEM MEMORY OVERVIEW"
    echo -e "${CYAN}# System memory is the primary resource monitored by the OOM killer.${NC}"
    echo -e "${CYAN}# High usage percentages (>90%) indicate imminent OOM risk.${NC}"
    
    # Get memory info from /proc/meminfo and ensure integers
    local mem_total=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')
    local mem_free=$(grep 'MemFree' /proc/meminfo | awk '{print $2}')
    local mem_available=$(grep 'MemAvailable' /proc/meminfo | awk '{print $2}')
    
    # Convert to bytes (KB * 1024) using awk to avoid scientific notation issues
    mem_total=$(echo "$mem_total * 1024" | bc)
    mem_total=$(to_integer "$mem_total")
    
    mem_free=$(echo "$mem_free * 1024" | bc)
    mem_free=$(to_integer "$mem_free")
    
    mem_available=$(echo "$mem_available * 1024" | bc)
    mem_available=$(to_integer "$mem_available")
    
    # Calculate used memory and percentage
    local mem_used=$(echo "$mem_total - $mem_available" | bc)
    local mem_usage_percent=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc)
    
    print_metric "Total Memory:" "$(get_human_size $mem_total)" ""
    print_metric "Used Memory:" "$(get_human_size $mem_used)" "($(get_percent $mem_usage_percent))"
    print_metric "Available Memory:" "$(get_human_size $mem_available)" ""
    
    # Memory breakdown - with safer conversions
    local buffers=$(grep 'Buffers' /proc/meminfo | awk '{print $2}')
    local cached=$(grep 'Cached' /proc/meminfo | awk '{print $2}')
    local slab=$(grep 'Slab' /proc/meminfo | awk '{print $2}')
    
    buffers=$(echo "$buffers * 1024" | bc)
    buffers=$(to_integer "$buffers")
    
    cached=$(echo "$cached * 1024" | bc)
    cached=$(to_integer "$cached")
    
    slab=$(echo "$slab * 1024" | bc)
    slab=$(to_integer "$slab")
    
    echo -e "\n${CYAN}# Memory breakdown - helps identify what's consuming memory${NC}"
    print_metric "Buffers:" "$(get_human_size $buffers)" "File system metadata, device I/O cache"
    print_metric "Cached:" "$(get_human_size $cached)" "Page cache, can be reclaimed when needed"
    print_metric "Slab:" "$(get_human_size $slab)" "Kernel data structures"
}

# Function to monitor swap usage
monitor_swap() {
    print_header "SWAP USAGE"
    echo -e "${CYAN}# High swap usage with frequent swapping indicates memory pressure.${NC}"
    echo -e "${CYAN}# If system is heavily swapping, OOM can occur due to thrashing.${NC}"
    
    local swap_total=$(grep 'SwapTotal' /proc/meminfo | awk '{print $2}')
    swap_total=$(echo "$swap_total * 1024" | bc)
    swap_total=$(to_integer "$swap_total")
    
    # Get physical RAM for swap recommendations
    local mem_total=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')
    mem_total=$(echo "$mem_total * 1024" | bc)
    mem_total=$(to_integer "$mem_total")
    local mem_total_gb=$(echo "scale=1; $mem_total / 1024 / 1024 / 1024" | bc)
    
    # Calculate recommended swap based on RAM size and hibernation needs
    local recommended_swap=0
    if (( $(echo "$mem_total_gb <= 2" | bc -l) )); then
        # For RAM <= 2GB, recommended swap is 2x RAM
        recommended_swap=$(echo "$mem_total * 2" | bc)
    elif (( $(echo "$mem_total_gb <= 8" | bc -l) )); then
        # For RAM 2-8GB, recommended swap is 1.5x RAM
        recommended_swap=$(echo "$mem_total * 1.5" | bc)
    elif (( $(echo "$mem_total_gb <= 64" | bc -l) )); then
        # For RAM 8-64GB, recommended swap is RAM
        recommended_swap=$mem_total
    else
        # For RAM > 64GB, recommended swap is 16GB + hibernation if needed
        recommended_swap=$(echo "16 * 1024 * 1024 * 1024" | bc)
    fi
    
    # Add hibernation needs (equal to RAM) if system supports hibernation
    # This is a simplified check - real hibernation support depends on more factors
    local supports_hibernation=false
    if [ -d "/sys/power/state" ] && grep -q "disk" /sys/power/state 2>/dev/null; then
        supports_hibernation=true
        local hibernation_swap=$mem_total
    else
        hibernation_swap=0
    fi
    
    # Current swap section
    if [ "$swap_total" -eq 0 ]; then
        echo -e "${RED}No swap configured. System more vulnerable to OOM when memory pressure is high.${NC}"
    else
        local swap_free=$(grep 'SwapFree' /proc/meminfo | awk '{print $2}')
        swap_free=$(echo "$swap_free * 1024" | bc)
        swap_free=$(to_integer "$swap_free")
        
        local swap_used=$(echo "$swap_total - $swap_free" | bc)
        local swap_usage_percent=$(echo "scale=1; $swap_used * 100 / $swap_total" | bc)
        
        print_metric "Current Swap:" "$(get_human_size $swap_total)" "Total configured swap space"
        print_metric "Used Swap:" "$(get_human_size $swap_used)" "($(get_percent $swap_usage_percent))"
        print_metric "Free Swap:" "$(get_human_size $swap_free)" ""
        
        # Get swap activity metrics
        if command_exists vmstat; then
            local swap_stats=$(vmstat 1 2 | tail -1)
            local swap_in=$(echo "$swap_stats" | awk '{print $7}')
            local swap_out=$(echo "$swap_stats" | awk '{print $8}')
            
            echo -e "\n${CYAN}# Current swapping activity (pages/sec)${NC}"
            print_metric "Swap In:" "$swap_in" "Higher values indicate memory pressure"
            print_metric "Swap Out:" "$swap_out" "Higher values indicate memory pressure"
        fi
    fi
    
    # Potential swap section
    echo -e "\n${CYAN}# Potential Swap Analysis${NC}"
    
    # Check for unused swap partitions
    local inactive_swap=0
    local inactive_swap_info=""
    if command_exists swapon; then
        local inactive_parts=$(swapon --show=NAME,TYPE --noheadings 2>/dev/null | wc -l)
        local all_parts=$(blkid -t TYPE=swap -o device 2>/dev/null | wc -l)
        if [ "$all_parts" -gt "$inactive_parts" ]; then
            inactive_swap_info=$(blkid -t TYPE=swap -o device 2>/dev/null | grep -v -f <(swapon --show=NAME --noheadings 2>/dev/null) | tr '\n' ' ')
            echo -e "${YELLOW}Inactive swap partitions found: $inactive_swap_info${NC}"
            # Try to get sizes of inactive swap partitions
            for part in $inactive_swap_info; do
                if [ -e "$part" ]; then
                    local part_size=$(blockdev --getsize64 "$part" 2>/dev/null || echo 0)
                    inactive_swap=$(echo "$inactive_swap + $part_size" | bc)
                fi
            done
            if [ "$inactive_swap" -gt 0 ]; then
                print_metric "Inactive Swap:" "$(get_human_size $inactive_swap)" "Could be enabled with 'swapon'"
            fi
        fi
    fi
    
    # Check for available disk space for potential swap files
    local available_space=0
    local root_available=0
    if command_exists df; then
        root_available=$(df -B1 / | awk 'NR==2 {print $4}')
        # Reserve 10% of available space to avoid completely filling disk
        available_space=$(echo "$root_available * 0.9" | bc | cut -d. -f1)
        
        print_metric "Disk Space:" "$(get_human_size $available_space)" "Available for potential swap files"
    fi
    
    # Recommend additional swap if needed
    local total_potential_swap=$(echo "$swap_total + $inactive_swap" | bc)
    local additional_needed=$(echo "$recommended_swap - $total_potential_swap" | bc)
    
    print_metric "Recommended:" "$(get_human_size $recommended_swap)" "Based on $(get_human_size $mem_total) RAM"
    
    # Hibernation recommendation
    if $supports_hibernation; then
        print_metric "Hibernation:" "$(get_human_size $hibernation_swap)" "Additional swap needed for hibernation"
        additional_needed=$(echo "$additional_needed + $hibernation_swap" | bc)
    fi
    
    if [ "$additional_needed" -gt 0 ]; then
        print_metric "Additional:" "$(get_human_size $additional_needed)" "More swap recommended"
        
        if [ "$available_space" -gt "$additional_needed" ]; then
            echo -e "${GREEN}✓ Sufficient disk space available to create additional swap${NC}"
            echo -e "${CYAN}# To create a swap file:${NC}"
            local swap_file_example="/swapfile"
            local swap_size_mb=$(echo "scale=0; $additional_needed / 1024 / 1024" | bc)
            echo -e "sudo swapoff -a $swap_file_example"
            echo -e "sudo fallocate -l ${swap_size_mb}M $swap_file_example"
            echo -e "sudo chmod 600 $swap_file_example"
            echo -e "sudo mkswap $swap_file_example"
            echo -e "sudo swapon $swap_file_example"
            echo -e "# Add to /etc/fstab for persistence:"
            echo -e "$swap_file_example none swap sw 0 0"
        else
            echo -e "${RED}✗ Insufficient disk space to create recommended swap${NC}"
        fi
    else
        echo -e "${GREEN}✓ Current swap space meets or exceeds recommendations${NC}"
    fi
}

# Function to monitor memory pressure metrics
monitor_memory_pressure() {
    print_header "MEMORY PRESSURE INDICATORS"
    echo -e "${CYAN}# These metrics show if the system is under memory pressure before OOM occurs${NC}"
    
    # Check if the pressure interface exists (newer kernels)
    if [ -f /proc/pressure/memory ]; then
        echo -e "${CYAN}# PSI (Pressure Stall Information) metrics show time processes spent stalled due to memory${NC}"
        cat /proc/pressure/memory
    fi
    
    # Get page fault statistics
    if command_exists vmstat; then
        local vm_stats=$(vmstat 1 2 | tail -1)
        local minor_faults=$(echo "$vm_stats" | awk '{print $7}')
        local major_faults=$(echo "$vm_stats" | awk '{print $8}')
        
        echo -e "\n${CYAN}# Page Faults/sec (high major faults indicate heavy swapping)${NC}"
        print_metric "Minor Faults:" "$minor_faults" "Resolved without disk I/O, low impact"
        print_metric "Major Faults:" "$major_faults" "Require disk I/O, high impact, can lead to OOM"
    fi
    
    # Get /proc/vmstat metrics related to memory pressure
    if [ -f /proc/vmstat ]; then
        echo -e "\n${CYAN}# VM Statistics related to OOM${NC}"
        echo -e "${CYAN}# High allocstall/kswapd values indicate severe memory pressure${NC}"
        
        # Make a more readable output of the VM stats
        local pgmajfault=$(grep 'pgmajfault' /proc/vmstat | awk '{print $2}')
        local allocstall=$(grep 'allocstall' /proc/vmstat 2>/dev/null | awk '{print $2}' || echo "N/A")
        local oom_kill=$(grep 'oom_kill' /proc/vmstat 2>/dev/null | awk '{print $2}' || echo "0")
        
        print_metric "Page major faults:" "$pgmajfault" "Since boot"
        print_metric "Allocation stalls:" "$allocstall" "Times memory reclaim was triggered"
        print_metric "OOM kills:" "$oom_kill" "Processes killed by OOM killer"
        
        if [ "$oom_kill" -gt 0 ]; then
            echo -e "${RED}OOM killer has been active $oom_kill times since boot!${NC}"
        fi
    fi
}

# Function to show kernel memory details
monitor_kernel_memory() {
    print_header "KERNEL MEMORY DETAILS"
    echo -e "${CYAN}# Kernel memory leaks or excessive usage can trigger OOM even with free userspace memory${NC}"
    
    # Get kernel memory information with human-readable values
    if [ -f /proc/meminfo ]; then
        echo -e "${CYAN}# High SReclaimable vs SUnreclaim ratio is healthy${NC}"
        
        local sreclaimable=$(grep 'SReclaimable' /proc/meminfo | awk '{print $2 * 1024}')
        sreclaimable=$(to_integer "$sreclaimable")
        
        local sunreclaim=$(grep 'SUnreclaim' /proc/meminfo | awk '{print $2 * 1024}')
        sunreclaim=$(to_integer "$sunreclaim")
        
        local kernel_stack=$(grep 'KernelStack' /proc/meminfo | awk '{print $2 * 1024}')
        kernel_stack=$(to_integer "$kernel_stack")
        
        local slab=$(grep 'Slab' /proc/meminfo | awk '{print $2 * 1024}')
        slab=$(to_integer "$slab")
        
        print_metric "SReclaimable:" "$(get_human_size $sreclaimable)" "Kernel memory that can be reclaimed"
        print_metric "SUnreclaim:" "$(get_human_size $sunreclaim)" "Kernel memory that cannot be reclaimed"
        print_metric "KernelStack:" "$(get_human_size $kernel_stack)" "Memory used by kernel stacks"
        print_metric "Slab:" "$(get_human_size $slab)" "Total kernel slab memory usage"
        
        # Calculate ratio
        if [ "$sunreclaim" -gt 0 ]; then
            local reclaim_ratio=$(echo "scale=2; $sreclaimable / $sunreclaim" | bc)
            print_metric "Reclaimable/Unreclaimable:" "${reclaim_ratio}x" "Higher is better"
        fi
    fi
    
    # SLUB statistics if available
    if [ -d /sys/kernel/slab ]; then
        local top_slabs=$(find /sys/kernel/slab -type f -name "object_size" -exec grep -l "." {} \; | xargs dirname | xargs -I{} sh -c "echo -n {}' '; cat {}/object_size" | sort -nrk2 | head -5)
        
        if [ -n "$top_slabs" ]; then
            echo -e "\n${CYAN}# Top 5 kernel SLUB allocators by object size${NC}"
            echo "$top_slabs" | while read slab_name size; do
                local allocator_name=$(basename "$slab_name")
                print_metric "$allocator_name:" "$(get_human_size $size)" "Object size"
            done
        fi
    fi
}

# Function to monitor top memory-consuming processes
monitor_top_processes() {
    print_header "TOP MEMORY-CONSUMING PROCESSES"
    echo -e "${CYAN}# These processes are the most likely candidates for the OOM killer${NC}"
    echo -e "${CYAN}# Processes with high RSS and low shared memory consume more physical RAM${NC}"
    echo -e "${CYAN}# RSS (Resident Set Size) is the amount of physical RAM (random access memory) that a process is currently using.${NC}"
    echo -e "${CYAN}# VSZ (Virtual Size) represents the total amount of virtual memory that a process has allocated.${NC}"
    echo -e "${CYAN}# VSZ includes both the memory that's currently in RAM and the memory that's been swapped out to disk.${NC}"
    echo -e "${CYAN}# VSZ is often much larger than RSS because it includes all the memory that the process could potentially use, even if it's not currently in RAM.${NC}"
    echo -e "${CYAN}# A very high VSZ can indicate a memory leak, even if the RSS is reasonable. A program could be allocating memory, but not releasing it, and this allocated, but unused, memory will increase the VSZ.${NC}"

    if command_exists ps; then
        # Define column widths for consistent alignment
        local pid_width=7
        local rss_width=9
        local vsz_width=9
        local mem_width=6
        
        # Print headers with proper spacing to align with values
        # Right-justify RSS and VSZ headers
        printf "%-${pid_width}s %${rss_width}s %${vsz_width}s %-${mem_width}s %s\n" "PID" "RSS" "VSZ" "%MEM" "COMMAND"
        
        # Get top processes with human-readable memory values and handle scientific notation
        ps aux --sort=-%mem | head -6 | tail -5 | awk -v pid_w="$pid_width" -v rss_w="$rss_width" -v vsz_w="$vsz_width" -v mem_w="$mem_width" '{ 
            # Handle command truncation
            cmd = $11;
            if (length(cmd) > 40) {
                cmd = substr(cmd, 1, 37) "...";
            }
            
            # Calculate memory values (in KB)
            rss = $6;
            vsz = $5;
            
            # Format PID with left alignment
            printf("%-" pid_w "s ", $2);
            
            # Convert RSS to human-readable, handling scientific notation with right alignment
            if (rss ~ /[eE]/) {
                # Convert scientific notation to regular number and ensure space between value and unit
                printf("%" rss_w "s ", sprintf("%.0f KiB", rss * 1));
            } else {
                # Convert regular number and ensure space between value and unit
                if (rss >= 1048576) {
                    printf("%" rss_w "s ", sprintf("%.1f GiB", rss/1048576));
                } else if (rss >= 1024) {
                    printf("%" rss_w "s ", sprintf("%.1f MiB", rss/1024));
                } else {
                    printf("%" rss_w "s ", sprintf("%d KiB", rss));
                }
            }
            
            # Convert VSZ to human-readable, handling scientific notation with right alignment
            if (vsz ~ /[eE]/) {
                # Convert scientific notation to regular number and ensure space between value and unit
                printf("%" vsz_w "s ", sprintf("%.0f KiB", vsz * 1));
            } else {
                # Convert regular number and ensure space between value and unit
                if (vsz >= 1048576) {
                    printf("%" vsz_w "s ", sprintf("%.1f GiB", vsz/1048576));
                } else if (vsz >= 1024) {
                    printf("%" vsz_w "s ", sprintf("%.1f MiB", vsz/1024));
                } else {
                    printf("%" vsz_w "s ", sprintf("%d KiB", vsz));
                }
            }
            
            # Print memory percentage and command with consistent spacing
            printf("%-" mem_w "s %s\n", $4, cmd);
        }'
        
        # Show OOM scores for top processes, now showing top 10 processes sorted by OOM score
        echo -e "\n${CYAN}# OOM Score: Higher values (e.g., 1000) are more likely to be killed by the OOM killer${NC}"
        echo -e "${CYAN}# Top 10 processes by OOM score${NC}"
        
        # Define column widths for OOM score display
        local pid_width=8
        local score_width=10
        local adj_width=8
        
        # Print header for OOM scores
        printf "%-${pid_width}s %${score_width}s %-${adj_width}s %s\n" "PID" "OOM SCORE" "OOM ADJ" "COMMAND"
        
        # Get all running processes, read their OOM scores, sort by score (highest first), and display top 10
        ps -e -o pid= | while read pid; do
            if [ -f /proc/$pid/oom_score ]; then
                oom_score=$(cat /proc/$pid/oom_score 2>/dev/null || echo "0")
                oom_adj=$(cat /proc/$pid/oom_score_adj 2>/dev/null || echo "N/A")
                comm=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' || cat /proc/$pid/comm 2>/dev/null || echo "unknown")
                
                # Truncate command to 50 characters if longer
                if [ ${#comm} -gt 50 ]; then
                    comm="${comm:0:47}..."
                fi
                
                # Output with consistent format for sorting
                echo "$oom_score:$pid:$oom_adj:$comm"
            fi
        done | sort -nr | head -10 | while IFS=: read -r score pid adj cmd; do
            printf "%-${pid_width}s %${score_width}s %-${adj_width}s %s\n" "$pid" "$score" "$adj" "$cmd"
        done
    else
        echo "ps command not available. Cannot show process information."
    fi
}

# Function to monitor GPU memory usage
monitor_gpu_memory() {
    print_header "GPU MEMORY USAGE"
    echo -e "${CYAN}# GPU memory issues can indirectly cause system OOM in some scenarios${NC}"
    echo -e "${CYAN}# Some frameworks may allocate excessive system RAM when GPU memory is exhausted${NC}"
    
    if command_exists nvidia-smi; then
        echo -e "NVIDIA GPU Memory Usage:"
        
        # Get the data from nvidia-smi but process it for better formatting
        nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader,nounits | while IFS=, read -r index name total used free; do
            # Convert memory values from MiB to bytes for consistent formatting
            total_bytes=$(echo "${total// /} * 1024 * 1024" | bc)
            used_bytes=$(echo "${used// /} * 1024 * 1024" | bc)
            free_bytes=$(echo "${free// /} * 1024 * 1024" | bc)
            
            # Use our human-readable formatter for consistent display
            echo -e "GPU $index: $name"
            print_metric "  Total memory:" "$(get_human_size $total_bytes)" ""
            print_metric "  Used memory:" "$(get_human_size $used_bytes)" ""
            print_metric "  Free memory:" "$(get_human_size $free_bytes)" ""
            echo ""
        done
    elif command_exists rocm-smi; then
        echo -e "AMD GPU Memory Usage:"
        # Process rocm-smi output for better formatting
        rocm-smi --showmeminfo vram --csv | grep -v "=" | tail -n +2 | while IFS=, read -r gpu_id used total; do
            # Extract numeric values and convert to bytes
            used=$(echo "$used" | grep -o '[0-9.]*' | head -1)
            total=$(echo "$total" | grep -o '[0-9.]*' | head -1)
            
            used_bytes=$(echo "$used * 1024 * 1024" | bc)
            total_bytes=$(echo "$total * 1024 * 1024" | bc)
            free_bytes=$(echo "$total_bytes - $used_bytes" | bc)
            
            echo -e "GPU $gpu_id:"
            print_metric "  Total memory:" "$(get_human_size $total_bytes)" ""
            print_metric "  Used memory:" "$(get_human_size $used_bytes)" ""
            print_metric "  Free memory:" "$(get_human_size $free_bytes)" ""
            echo ""
        done
    else
        echo "No supported GPU tools found (nvidia-smi or rocm-smi)"
    fi
}

# Function to monitor cgroup memory limits
monitor_cgroup_limits() {
    print_header "TOP 10 CGROUP MEMORY CONSUMERS"
    echo -e "${CYAN}# Containers and services with highest memory usage that may trigger local OOM events${NC}"
    
    # Define column widths for consistent alignment
    local path_width=60
    local value_width=15
    
    # Check for cgroup v2
    if [ -d /sys/fs/cgroup/system.slice ]; then
        echo -e "Using cgroup v2"
        
        # Print the header with proper spacing
        printf "%-${path_width}s %${value_width}s\n" "CGROUP PATH" "MEMORY.CURRENT"
        
        # Find all memory.current files and sort by value (highest first), then take top 10
        find /sys/fs/cgroup -name "memory.current" 2>/dev/null | xargs -I{} sh -c 'val=$(cat {} 2>/dev/null || echo 0); echo "$val {}:"' | sort -nr | head -10 | while read val path; do
            # Extract the cgroup path
            cgroup_path=$(dirname $path)
            # Format the memory value in human-readable format
            human_val=$(get_human_size $val)
            
            # Print with proper alignment
            printf "%-${path_width}s %${value_width}s\n" "$cgroup_path" "$human_val"
        done
    # Check for cgroup v1
    elif [ -d /sys/fs/cgroup/memory ]; then
        echo -e "Using cgroup v1"
        
        # Print the header with proper spacing
        printf "%-${path_width}s %${value_width}s\n" "CGROUP PATH" "MEMORY.USAGE"
        
        # Find all memory.usage_in_bytes files and sort by value (highest first), then take top 10
        find /sys/fs/cgroup/memory -name "memory.usage_in_bytes" 2>/dev/null | xargs -I{} sh -c 'val=$(cat {} 2>/dev/null || echo 0); echo "$val {}:"' | sort -nr | head -10 | while read val path; do
            # Extract the cgroup path
            cgroup_path=$(dirname $path)
            # Format the memory value in human-readable format
            human_val=$(get_human_size $val)
            
            # Print with proper alignment
            printf "%-${path_width}s %${value_width}s\n" "$cgroup_path" "$human_val"
        done
    else
        echo "No cgroup memory information found"
    fi
}

# Function to show memory fragmentation
monitor_fragmentation() {
    print_header "MEMORY FRAGMENTATION"
    echo -e "${CYAN}# Fragmentation can cause allocation failures even when free memory exists${NC}"
    echo -e "${CYAN}# This is particularly important for large contiguous allocations${NC}"
    
    if [ -f /proc/buddyinfo ]; then
        echo -e "Buddy Allocator Information (free blocks by order):"
        echo -e "${CYAN}# Higher values in larger orders (right columns) mean less fragmentation${NC}"
        echo -e "${CYAN}# Order 0: 4KB, each next order doubles (1: 8KB, 2: 16KB, etc.)${NC}"
        
        # Enhanced display of buddy allocator info
        echo -e "Node\tZone\t4KB\t8KB\t16KB\t32KB\t64KB\t128KB\t256KB\t512KB\t1MB\t2MB\t4MB"
        cat /proc/buddyinfo | awk '{
            printf "%s\t%s\t", $1, $2;
            for(i=4; i<=NF; i++) printf "%s\t", $i;
            printf "\n";
        }'
    else
        echo "Memory fragmentation information not available"
    fi
}

# Function to monitor virtual memory metrics
monitor_virtual_memory() {
    print_header "VIRTUAL MEMORY METRICS"
    echo -e "${CYAN}# VM tuning parameters affect OOM behavior and memory management${NC}"
    
    echo -e "\n${CYAN}# VM Overcommit setting${NC}"
    echo -e "${CYAN}# 0=Conservative (never overcommit), 1=Always allow, 2=Overcommit with ratio${NC}"
    local overcommit=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "N/A")
    print_metric "vm.overcommit_memory:" "$overcommit" "How the kernel handles memory allocation requests"
    
    if [ "$overcommit" = "2" ]; then
        local ratio=$(cat /proc/sys/vm/overcommit_ratio 2>/dev/null || echo "N/A")
        print_metric "vm.overcommit_ratio:" "${ratio}%" "Percentage of RAM to allow for overcommit"
    fi
    
    echo -e "\n${CYAN}# OOM Killer adjustment${NC}"
    echo -e "${CYAN}# Controls how aggressively the OOM killer selects processes to kill${NC}"
    local kill_allocating=$(cat /proc/sys/vm/oom_kill_allocating_task 2>/dev/null || echo "N/A")
    print_metric "vm.oom_kill_allocating_task:" "$kill_allocating" "1=Kill requestor, 0=Select based on score"
    
    echo -e "\n${CYAN}# Swappiness - lower values reduce swap usage${NC}"
    local swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "N/A")
    print_metric "vm.swappiness:" "$swappiness" "0-100, lower=less swapping, higher=more aggressive swap"
    
    echo -e "\n${CYAN}# Min Free KB - memory reserved for critical allocations${NC}"
    local min_free_kb=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null || echo "N/A")
    if [[ "$min_free_kb" != "N/A" ]]; then
        min_free_bytes=$(echo "$min_free_kb * 1024" | bc)
        print_metric "vm.min_free_kbytes:" "$min_free_kb KB" "($(get_human_size $min_free_bytes))"
    else
        print_metric "vm.min_free_kbytes:" "N/A" ""
    fi
}

# Function to show transparent huge pages status
monitor_thp() {
    print_header "TRANSPARENT HUGE PAGES"
    echo -e "${CYAN}# THP can increase memory usage but improve performance${NC}"
    echo -e "${CYAN}# If enabled, memory usage may be higher than expected${NC}"
    
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        local thp_status=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
        print_metric "THP Status:" "$thp_status" "For all memory allocations"
    else
        echo "Transparent Huge Pages information not available"
    fi
}

# Function to show memory-mapped files
monitor_mmap_files() {
    print_header "MEMORY-MAPPED FILES"
    echo -e "${CYAN}# Large memory-mapped files can consume significant address space${NC}"
    
    if command_exists lsof; then
        echo -e "${CYAN}# Top 5 processes by mapped file size${NC}"
        
        # Define column widths for consistent alignment
        local pid_width=8
        local proc_width=12
        local size_width=10
        
        # Print header with right-justified SIZE column
        printf "%-${pid_width}s %-${proc_width}s %${size_width}s %s\n" "PID" "PROCESS" "SIZE" "FILE PATH"
        
        # This is an approximation as it's hard to get exact mmap sizes
        # Suppress warnings about fuse filesystems by redirecting stderr
        lsof -a -d mem 2>/dev/null | grep -v "can't stat() fuse" | awk '{print $2, $1, $9}' | sort -u | head -5 | \
        while read pid proc filepath; do
            # Get file size if file exists and is accessible
            if [ -r "$filepath" ]; then
                # Get file size in bytes and convert to human-readable
                size=$(stat -c %s "$filepath" 2>/dev/null)
                if [ -n "$size" ]; then
                    size_human=$(get_human_size $size)
                else
                    size_human="N/A"
                fi
            else
                size_human="N/A"
            fi
            
            # Print with proper alignment and right-justified size
            printf "%-${pid_width}s %-${proc_width}s %${size_width}s %s\n" "$pid" "$proc" "$size_human" "$filepath"
        done
    else
        echo "lsof command not available. Cannot show memory-mapped files."
    fi
}

# Function to analyze recent OOM incidents in system logs
analyze_oom_logs() {
    print_header "OOM CRASH ANALYSIS (LAST 24 HOURS)"
    echo -e "${CYAN}# Analysis of recent OOM killer events to identify recurring issues${NC}"
    
    # Define log files to check
    local log_files=("/var/log/kern.log" "/var/log/syslog" "/var/log/messages" "/var/log/dmesg")
    local logs_found=false
    local oom_count=0
    local yesterday=$(date -d "yesterday" "+%b %d")
    local today=$(date "+%b %d")
    
    # Create a temporary file to store OOM events
    local tmp_file=$(mktemp)
    
    # Search for OOM messages in logs
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            logs_found=true
            # Extract OOM killer messages from the last day
            grep -E "($yesterday|$today).*Out of memory|.*invoked oom-killer|.*Killed process" "$log_file" 2>/dev/null >> "$tmp_file" || true
        fi
    done
    
    if [ "$logs_found" = false ]; then
        echo -e "${YELLOW}No system logs found to analyze. Skipping OOM crash analysis.${NC}"
        rm "$tmp_file"
        return
    fi
    
    # Count OOM incidents
    oom_count=$(grep -c "invoked oom-killer" "$tmp_file")
    
    if [ "$oom_count" -eq 0 ]; then
        echo -e "${GREEN}No OOM killer events detected in the last 24 hours.${NC}"
        rm "$tmp_file"
        return
    fi
    
    # Display summary of OOM events
    echo -e "${RED}Found $oom_count OOM killer events in the last 24 hours.${NC}"
    echo -e "\n${CYAN}# Summary of OOM events:${NC}"
    
    # Extract timestamps of OOM events for timeline analysis
    local oom_times=$(grep "invoked oom-killer" "$tmp_file" | awk '{print $1, $2, $3}')
    echo -e "OOM Events occurred at: $oom_times"
    
    # Extract killed processes
    echo -e "\n${CYAN}# Processes killed by the OOM killer:${NC}"
    grep "Killed process" "$tmp_file" | awk '{
        printf "PID: %-8s Command: %-30s Memory: %s\n", 
        gensub(/.*Killed process ([0-9]+) .*/,"\\1","g"), 
        gensub(/.*\((.*)\).*/, "\\1", "g"),
        gensub(/.*\(([0-9]+) kB\).*/, "\\1 KiB", "g")
    }' | sort | uniq -c | sort -nr | head -10
    
    # Analyze memory conditions during OOM
    echo -e "\n${CYAN}# Memory conditions during OOM events:${NC}"
    
    # Extract memory statistics before OOM
    local total_mem=$(grep -B 5 "invoked oom-killer" "$tmp_file" | grep "Normal free" | head -1)
    if [ -n "$total_mem" ]; then
        echo -e "Memory state: $total_mem"
    fi
    
    # Extract cgroup information if present
    local cgroup_oom=$(grep -A 2 "oom-kill:" "$tmp_file" | grep "Task in" | head -1)
    if [ -n "$cgroup_oom" ]; then
        echo -e "Cgroup constraint: $cgroup_oom"
    fi
    
    # Determine high-risk indicators
    echo -e "\n${CYAN}# High-risk indicators to monitor:${NC}"
    
    # Check for memory fragmentation issues
    if grep -q "page allocation failure" "$tmp_file"; then
        echo -e "${RED}[CRITICAL] Memory Fragmentation detected${NC} - Monitor higher-order memory pages"
    fi
    
    # Check for cgroup memory limit issues
    if grep -q "Memory cgroup out of memory" "$tmp_file"; then
        echo -e "${RED}[CRITICAL] Container/Service memory limits exceeded${NC} - Check cgroup memory limits"
    fi
    
    # Check for swap issues
    if grep -q "Normal free:[[:space:]]*[0-9]+kB" "$tmp_file" | grep -q "low"; then
        echo -e "${RED}[CRITICAL] Swap thrashing detected${NC} - Monitor swap activity"
    fi
    
    # Check for specific process types that were killed
    if grep -q "chrome\|firefox\|browser" "$tmp_file"; then
        echo -e "${YELLOW}[WARNING] Browser processes killed${NC} - Consider limiting browser tabs/instances"
    fi
    
    if grep -q "java\|python\|node\|ruby" "$tmp_file"; then
        echo -e "${YELLOW}[WARNING] Application runtimes killed${NC} - Check for memory leaks in applications"
    fi
    
    if grep -q "docker\|containerd\|kube" "$tmp_file"; then
        echo -e "${YELLOW}[WARNING] Container processes killed${NC} - Adjust container memory limits"
    fi
    
    # Recommendations based on analysis
    echo -e "\n${CYAN}# Recommendations:${NC}"
    
    # Check frequency pattern
    if [ "$oom_count" -gt 3 ]; then
        echo -e "- ${RED}Frequent OOM events (${oom_count} in 24h)${NC} - Consider increasing total system memory"
    fi
    
    # Check if same process was killed multiple times
    local repeat_offender=$(grep "Killed process" "$tmp_file" | sort | uniq -c | sort -nr | head -1 | awk '{print $1}')
    if [ "$repeat_offender" -gt 1 ]; then
        echo -e "- ${YELLOW}Same process killed multiple times${NC} - Increase OOM score adjustment to avoid critical services"
    fi
    
    # Provide specific monitoring advice
    echo -e "- Monitor process with high anonymous memory usage (RSS)"
    echo -e "- Check for memory leaks in long-running processes"
    echo -e "- Verify swap configuration is appropriate"
    
    # Clean up temp file
    rm "$tmp_file"
}

# Main monitoring loop
monitor_memory() {
    clear
    echo -e "${MAGENTA}=== COMPREHENSIVE MEMORY USAGE MONITOR ===${NC}"
    echo -e "${MAGENTA}Press Ctrl+C to exit${NC}"
    echo -e "Date: $(date)\n"
    
    # Add OOM log analysis at the beginning
    analyze_oom_logs
    echo ""
    
    monitor_system_memory
    echo ""
    monitor_swap
    echo ""
    monitor_memory_pressure
    echo ""
    monitor_kernel_memory
    echo ""
    monitor_top_processes
    echo ""
    monitor_gpu_memory
    echo ""
    monitor_cgroup_limits
    echo ""
    monitor_fragmentation
    echo ""
    monitor_virtual_memory
    echo ""
    monitor_thp
    echo ""
    monitor_mmap_files
    
    echo -e "\n${MAGENTA}=== MEMORY USAGE SUMMARY ===${NC}"
    echo -e "${CYAN}# OOM risks increase with:${NC}"
    echo -e "${CYAN}# 1. High memory usage (>90%)${NC}"
    echo -e "${CYAN}# 2. High swap usage with active swapping${NC}"
    echo -e "${CYAN}# 3. High memory pressure indicators${NC}"
    echo -e "${CYAN}# 4. High OOM scores for critical processes${NC}"
    echo -e "${CYAN}# 5. Memory fragmentation with low availability of higher order pages${NC}"
    echo -e "${CYAN}# 6. Constrained cgroup limits${NC}"
    echo -e "${CYAN}# 7. Memory overcommit issues or too-small min_free_kbytes${NC}"
}

# Run continuously or just once
if [ "$1" == "-w" ] || [ "$1" == "--watch" ]; then
    # Run in watch mode
    while true; do
        monitor_memory
        sleep ${2:-5}  # Default to 5 seconds if no interval specified
        clear
    done
else
    # Run once
    monitor_memory
    echo -e "\n${MAGENTA}Run with -w or --watch to continuously monitor${NC}"
    echo -e "${MAGENTA}Example: $0 --watch 2     # Updates every 2 seconds${NC}"
fi
