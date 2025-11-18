#!/bin/bash

# Harvester VM Memory Calculator
# Bash script to calculate reserved memory for Harvester virtual machines

show_help() {
    cat << EOF
Harvester VM Memory Calculator - Calculate reserved memory for Harvester virtual machines

Usage: 
  $0 <vm_memory> [options]           # Calculate reserved memory for given VM size
  $0 --guest <guest_memory> [options] # Calculate VM size needed for desired guest memory
  $0 --list-common                   # Show calculations for common VM sizes

Arguments:
  vm_memory          VM memory size (examples: 4Gi, 8GB, 512Mi, 2G)

Options:
  --guest MEMORY     Calculate VM size needed for desired guest memory
  --method METHOD    Calculation method: auto, legacy, or ratio (default: auto)
  --annotation       Show only the annotation for YAML files
  --verbose          Show detailed information
  --list-common      Show calculations for common VM sizes
  --help             Show this help message

Examples:
  FORWARD CALCULATION (VM size -> reserved memory):
  $0 4Gi                    # Calculate for 4GB VM (auto method)
  $0 8GB --method legacy    # Use legacy 100MiB method
  $0 2Gi --method ratio     # Use ratio-based method
  $0 512Mi --verbose        # Show detailed information
  $0 16G --annotation       # Show only annotation for YAML

  REVERSE CALCULATION (guest memory -> VM size):
  $0 --guest 24Gi           # Calculate VM size needed for 24GB guest memory
  $0 --guest 8GB --method legacy  # Use legacy method
  $0 --guest 4Gi --annotation    # Show only annotation

Common VM Sizes:
  $0 2Gi    # Small VM
  $0 4Gi    # Medium VM  
  $0 8Gi    # Large VM
  $0 16Gi   # Extra Large VM
EOF
}

parse_size() {
    local size_str="$1"
    local size_num
    local size_unit
    local multiplier=1
    
    # Convert to uppercase and remove spaces
    size_str=$(echo "$size_str" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
    
    # Extract number and unit
    if [[ "$size_str" =~ ^([0-9]+(\.[0-9]+)?)([A-Z]+)$ ]]; then
        size_num="${BASH_REMATCH[1]}"
        size_unit="${BASH_REMATCH[3]}"
    elif [[ "$size_str" =~ ^[0-9]+$ ]]; then
        size_num="$size_str"
        size_unit="B"
    else
        echo "Error: Invalid size format: $size_str" >&2
        return 1
    fi
    
    # Set multiplier based on unit
    case "$size_unit" in
        B)    multiplier=1 ;;
        K|KB) multiplier=1024 ;;
        M|MB) multiplier=$((1024*1024)) ;;
        G|GB) multiplier=$((1024*1024*1024)) ;;
        T|TB) multiplier=$((1024*1024*1024*1024)) ;;
        KI)   multiplier=1024 ;;
        MI)   multiplier=$((1024*1024)) ;;
        GI)   multiplier=$((1024*1024*1024)) ;;
        TI)   multiplier=$((1024*1024*1024*1024)) ;;
        *)    echo "Error: Unknown unit: $size_unit" >&2; return 1 ;;
    esac
    
    # Calculate bytes (using bc for floating point)
    local bytes
    bytes=$(echo "$size_num * $multiplier" | bc | cut -d. -f1)
    echo "$bytes"
}

format_size() {
    local bytes="$1"
    local units=("B" "Ki" "Mi" "Gi" "Ti")
    local unit_index=0
    local size="$bytes"
    
    while [ "$(echo "$size >= 1024" | bc)" -eq 1 ] && [ "$unit_index" -lt 4 ]; do
        size=$(echo "scale=2; $size / 1024" | bc)
        unit_index=$((unit_index + 1))
    done
    
    echo "${size} ${units[$unit_index]}"
}

get_ratio() {
    local vm_memory_gb="$1"
    local ratio
    
    if [ "$(echo "$vm_memory_gb <= 1" | bc)" -eq 1 ]; then
        ratio="0.01"
    elif [ "$(echo "$vm_memory_gb <= 2" | bc)" -eq 1 ]; then
        ratio="0.02"
    elif [ "$(echo "$vm_memory_gb <= 4" | bc)" -eq 1 ]; then
        ratio="0.03"
    elif [ "$(echo "$vm_memory_gb <= 8" | bc)" -eq 1 ]; then
        ratio="0.04"
    else
        ratio="0.05"
    fi
    
    echo "$ratio"
}

calculate_memory() {
    local vm_memory_bytes="$1"
    local method="$2"
    
    local reserved_legacy=$((100 * 1024 * 1024))  # 100 MiB
    
    # Convert to GB for ratio calculation
    local vm_memory_gb
    vm_memory_gb=$(echo "scale=2; $vm_memory_bytes / (1024*1024*1024)" | bc)
    
    # Get ratio based on size
    local ratio
    ratio=$(get_ratio "$vm_memory_gb")
    
    local reserved_ratio
    reserved_ratio=$(echo "$vm_memory_bytes * $ratio" | bc | cut -d. -f1)
    
    local reserved_auto method_used
    case "$method" in
        legacy)
            reserved_auto="$reserved_legacy"
            method_used="legacy (100MiB fixed)"
            ;;
        ratio)
            reserved_auto="$reserved_ratio"
            method_used="ratio-based"
            ;;
        *)
            # Auto: Use ratio-based for large VMs, legacy for small ones
            if [ "$(echo "$vm_memory_gb >= 4" | bc)" -eq 1 ]; then
                reserved_auto="$reserved_ratio"
                method_used="ratio-based"
            else
                reserved_auto="$reserved_legacy"
                method_used="legacy (100MiB fixed)"
            fi
            ;;
    esac
    
    local guest_memory
    guest_memory=$((vm_memory_bytes - reserved_auto))
    
    local overhead_percent
    overhead_percent=$(echo "scale=1; ($reserved_auto * 100) / $vm_memory_bytes" | bc)
    
    # Return results as string (we'll parse it back)
    echo "$vm_memory_bytes|$reserved_auto|$guest_memory|$method_used|$reserved_legacy|$reserved_ratio|$overhead_percent|$ratio"
}

calculate_reverse() {
    local desired_guest_bytes="$1"
    local method="$2"
    
    local vm_memory_bytes reserved_auto guest_memory method_used ratio
    
    case "$method" in
        legacy)
            # For legacy method: VM = guest + 100MiB
            vm_memory_bytes=$((desired_guest_bytes + 100 * 1024 * 1024))
            method_used="legacy (100MiB fixed)"
            ;;
        ratio)
            # For ratio method, we need to iteratively find the right size
            # Start with guest memory as base and add estimated overhead
            local estimated_vm_bytes
            estimated_vm_bytes=$(echo "$desired_guest_bytes / 0.97" | bc | cut -d. -f1)
            
            # Refine calculation
            vm_memory_bytes="$estimated_vm_bytes"
            local i=0
            while [ $i -lt 10 ]; do  # Max 10 iterations to avoid infinite loop
                local current_gb
                current_gb=$(echo "scale=2; $vm_memory_bytes / (1024*1024*1024)" | bc)
                ratio=$(get_ratio "$current_gb")
                
                local calculated_guest
                calculated_guest=$(echo "$vm_memory_bytes * (1 - $ratio)" | bc | cut -d. -f1)
                
                if [ "$calculated_guest" -ge "$desired_guest_bytes" ]; then
                    break
                fi
                
                # Increase VM size slightly
                vm_memory_bytes=$(echo "$vm_memory_bytes * 1.01" | bc | cut -d. -f1)
                i=$((i + 1))
            done
            method_used="ratio-based"
            ;;
        *)
            # Auto: Use ratio for large guest memory, legacy for small
            if [ "$(echo "$desired_guest_bytes >= 4 * 1024*1024*1024" | bc)" -eq 1 ]; then
                # Use ratio method for large guest memory
                vm_memory_bytes=$(echo "$desired_guest_bytes / 0.97" | bc | cut -d. -f1)
                method_used="ratio-based"
            else
                # Use legacy method for small guest memory
                vm_memory_bytes=$((desired_guest_bytes + 100 * 1024 * 1024))
                method_used="legacy (100MiB fixed)"
            fi
            ;;
    esac
    
    # Recalculate with final VM size to get accurate values
    local result
    result=$(calculate_memory "$vm_memory_bytes" "$method")
    IFS='|' read -r vm_memory_bytes reserved_auto guest_memory method_used reserved_legacy reserved_ratio overhead_percent ratio <<< "$result"
    
    echo "$vm_memory_bytes|$reserved_auto|$guest_memory|$method_used|$reserved_legacy|$reserved_ratio|$overhead_percent|$ratio"
}

list_common_sizes() {
    echo "Common VM Sizes Calculation:"
    echo "============================================================"
    local sizes=("1Gi" "2Gi" "4Gi" "8Gi" "16Gi" "32Gi")
    
    for size in "${sizes[@]}"; do
        local bytes
        bytes=$(parse_size "$size")
        if [ $? -eq 0 ]; then
            local result
            result=$(calculate_memory "$bytes" "auto")
            IFS='|' read -r vm_memory_bytes reserved_auto guest_memory method_used reserved_legacy reserved_ratio overhead_percent ratio <<< "$result"
            
            local vm_formatted guest_formatted reserved_formatted
            vm_formatted=$(format_size "$vm_memory_bytes")
            reserved_formatted=$(format_size "$reserved_auto")
            guest_formatted=$(format_size "$guest_memory")
            
            printf "  %-5s -> Reserved: %-8s -> Guest: %-8s\\n" \
                   "$size" "$reserved_formatted" "$guest_formatted"
        fi
    done
}

show_forward_calculation() {
    local vm_memory_bytes="$1"
    local method="$2"
    local show_annotation="$3"
    local show_verbose="$4"
    
    local result
    result=$(calculate_memory "$vm_memory_bytes" "$method")
    IFS='|' read -r vm_memory_bytes reserved_auto guest_memory method_used reserved_legacy reserved_ratio overhead_percent ratio <<< "$result"
    
    # Format sizes for display
    local vm_formatted guest_formatted reserved_formatted legacy_formatted ratio_formatted
    vm_formatted=$(format_size "$vm_memory_bytes")
    reserved_formatted=$(format_size "$reserved_auto")
    guest_formatted=$(format_size "$guest_memory")
    legacy_formatted=$(format_size "$reserved_legacy")
    ratio_formatted=$(format_size "$reserved_ratio")
    
    # Show annotation only if requested
    if [ "$show_annotation" = true ]; then
        echo "harvesterhci.io/reservedMemory: \"$reserved_auto\""
        return 0
    fi
    
    # Normal output
    echo "FORWARD CALCULATION: VM Size -> Reserved Memory"
    echo "========================================"
    echo "VM Memory:       $vm_formatted"
    echo "Reserved:        $reserved_formatted"
    echo "Guest Memory:    $guest_formatted"
    echo "Method:          $method_used"
    echo "Overhead:        ${overhead_percent}%"
    echo "Ratio:           $(echo "scale=3; $ratio * 100" | bc)%"
    
    if [ "$show_verbose" = true ]; then
        echo ""
        echo "Detailed Information:"
        echo "VM Memory Bytes: $(printf "%'d" "$vm_memory_bytes")"
        echo "Reserved Bytes:  $(printf "%'d" "$reserved_auto")"
        echo "Guest Bytes:     $(printf "%'d" "$guest_memory")"
        echo ""
        echo "Alternative Methods:"
        echo "  Legacy:  $legacy_formatted (100MiB fixed)"
        local ratio_percent
        ratio_percent=$(echo "scale=1; ($reserved_ratio * 100) / $vm_memory_bytes" | bc)
        echo "  Ratio:   $ratio_formatted (${ratio_percent}% overhead)"
    fi
    
    echo ""
    echo "YAML Annotation:"
    echo "  annotations:"
    echo "    harvesterhci.io/reservedMemory: \"$reserved_auto\""
}

show_reverse_calculation() {
    local guest_memory_bytes="$1"
    local method="$2"
    local show_annotation="$3"
    local show_verbose="$4"
    
    local result
    result=$(calculate_reverse "$guest_memory_bytes" "$method")
    IFS='|' read -r vm_memory_bytes reserved_auto guest_memory method_used reserved_legacy reserved_ratio overhead_percent ratio <<< "$result"
    
    # Format sizes for display
    local vm_formatted guest_formatted reserved_formatted legacy_formatted ratio_formatted
    vm_formatted=$(format_size "$vm_memory_bytes")
    reserved_formatted=$(format_size "$reserved_auto")
    guest_formatted=$(format_size "$guest_memory")
    legacy_formatted=$(format_size "$reserved_legacy")
    ratio_formatted=$(format_size "$reserved_ratio")
    
    # Show annotation only if requested
    if [ "$show_annotation" = true ]; then
        echo "harvesterhci.io/reservedMemory: \"$reserved_auto\""
        return 0
    fi
    
    # Normal output
    echo "REVERSE CALCULATION: Desired Guest Memory -> VM Size"
    echo "========================================"
    echo "Desired Guest:   $(format_size "$guest_memory_bytes")"
    echo "Required VM:     $vm_formatted"
    echo "Reserved:        $reserved_formatted"
    echo "Actual Guest:    $guest_formatted"
    echo "Method:          $method_used"
    echo "Overhead:        ${overhead_percent}%"
    echo "Ratio:           $(echo "scale=3; $ratio * 100" | bc)%"
    
    if [ "$show_verbose" = true ]; then
        echo ""
        echo "Detailed Information:"
        echo "Desired Guest Bytes: $(printf "%'d" "$guest_memory_bytes")"
        echo "VM Memory Bytes:     $(printf "%'d" "$vm_memory_bytes")"
        echo "Reserved Bytes:      $(printf "%'d" "$reserved_auto")"
        echo "Actual Guest Bytes:  $(printf "%'d" "$guest_memory")"
        echo ""
        echo "Alternative Methods:"
        echo "  Legacy:  VM $(format_size "$((guest_memory_bytes + 100 * 1024 * 1024))") (100MiB fixed)"
        local ratio_vm
        ratio_vm=$(echo "$guest_memory_bytes / (1 - $ratio)" | bc | cut -d. -f1)
        echo "  Ratio:   VM $(format_size "$ratio_vm") ($(echo "scale=1; $ratio * 100" | bc)% overhead)"
    fi
    
    echo ""
    echo "YAML Configuration:"
    echo "  memory: $vm_formatted"
    echo "  annotations:"
    echo "    harvesterhci.io/reservedMemory: \"$reserved_auto\""
}

main() {
    local vm_memory=""
    local guest_memory=""
    local method="auto"
    local show_annotation=false
    local show_verbose=false
    local list_common=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --guest)
                guest_memory="$2"
                shift 2
                ;;
            --method)
                method="$2"
                shift 2
                ;;
            --annotation)
                show_annotation=true
                shift
                ;;
            --verbose)
                show_verbose=true
                shift
                ;;
            --list-common)
                list_common=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            -*)
                echo "Error: Unknown option $1" >&2
                show_help
                exit 1
                ;;
            *)
                if [ -z "$vm_memory" ] && [ -z "$guest_memory" ]; then
                    vm_memory="$1"
                else
                    echo "Error: Multiple memory sizes provided" >&2
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Handle list-common
    if [ "$list_common" = true ]; then
        list_common_sizes
        exit 0
    fi
    
    # Check if we're doing forward or reverse calculation
    if [ -n "$guest_memory" ]; then
        # Reverse calculation: guest memory -> VM size
        local guest_memory_bytes
        guest_memory_bytes=$(parse_size "$guest_memory")
        if [ $? -ne 0 ]; then
            exit 1
        fi
        show_reverse_calculation "$guest_memory_bytes" "$method" "$show_annotation" "$show_verbose"
    elif [ -n "$vm_memory" ]; then
        # Forward calculation: VM size -> reserved memory
        local vm_memory_bytes
        vm_memory_bytes=$(parse_size "$vm_memory")
        if [ $? -ne 0 ]; then
            exit 1
        fi
        show_forward_calculation "$vm_memory_bytes" "$method" "$show_annotation" "$show_verbose"
    else
        echo "Error: No memory size provided" >&2
        show_help
        exit 1
    fi
}

# Check if bc is available
if ! command -v bc &> /dev/null; then
    echo "Error: 'bc' command is required but not installed." >&2
    echo "Install it with: apt-get install bc  # Ubuntu/Debian" >&2
    echo "                 or yum install bc    # RHEL/CentOS" >&2
    exit 1
fi

main "$@"
