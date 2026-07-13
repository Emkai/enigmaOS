#!/bin/bash

# Script to get connected bluetooth devices with battery levels for tooltip

# Get connected devices using bluetoothctl
connected_devices=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}')

if [ -z "$connected_devices" ]; then
    echo "No devices connected"
    exit 0
fi

output="Devices"
for mac in $connected_devices; do
    # Get device name
    name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Name:" | cut -d' ' -f2-)
    
    if [ -z "$name" ]; then
        continue
    fi
    
    # Get device info using upower
    device_path=$(upower -e 2>/dev/null | grep -i "$mac" | head -n1)
    
    # Default icon (using FontAwesome unicode)
    icon=$'\uf10b'  # Mobile phone
    battery=""
    
    if [ -n "$device_path" ]; then
        # Get battery percentage
        battery=$(upower -i "$device_path" 2>/dev/null | grep -E "percentage" | awk '{print $2}' | sed 's/%//')
        
        # Get device type/icon from upower
        upower_icon=$(upower -i "$device_path" 2>/dev/null | grep -i "icon-name" | awk '{print $2}' | head -n1)
        
        # Map icon names to FontAwesome icons (using $'...' syntax for unicode)
        case "$upower_icon" in
            *audio-card*|*headset*|*headphones*|*audio*)
                icon=$'\uf025'  # Headphones
                ;;
            *mouse*|*input-mouse*)
                icon=$'\uf8cc'  # Mouse (or use simple text)
                ;;
            *keyboard*|*input-keyboard*)
                icon=$'\uf11c'  # Keyboard
                ;;
            *phone*)
                icon=$'\uf10b'  # Mobile phone
                ;;
            *computer*|*laptop*)
                icon=$'\uf109'  # Laptop
                ;;
            *speaker*)
                icon=$'\uf028'  # Speaker
                ;;
        esac
    fi
    
    # If no icon from upower, try to infer from device class
    default_icon=$'\uf10b'
    if [ "$icon" = "$default_icon" ] && [ -z "$upower_icon" ]; then
        device_class=$(bluetoothctl info "$mac" 2>/dev/null | grep "Class:" | awk '{print $2}')
        if [ -n "$device_class" ]; then
            # Device class is in hex, check major class bits (first 2 hex digits)
            class_hex=${device_class:0:2}
            class_dec=$((0x$class_hex))
            case $class_dec in
                0x01|0x04) icon=$'\uf109' ;;  # Computer/Misc - Laptop
                0x02) icon=$'\uf10b' ;;      # Phone - Mobile
                0x03) icon=$'\uf025' ;;      # Audio/Video - Headphones
                0x05) icon=$'\uf025' ;;      # Peripheral (often audio) - Headphones
                *) icon=$'\uf10b' ;;         # Default - Mobile
            esac
        fi
    fi
    
    # Check sysfs for battery if upower didn't have it
    if [ -z "$battery" ]; then
        battery_path=$(find /sys/class/power_supply/ -name "*${mac//:/_}*" -o -name "*${mac}*" 2>/dev/null | head -n1)
        if [ -n "$battery_path" ] && [ -f "${battery_path}/capacity" ]; then
            battery=$(cat "${battery_path}/capacity" 2>/dev/null)
        fi
    fi
    
    # Format output
    if [ -n "$battery" ] && [ "$battery" != "" ]; then
        output="${output}\r${icon} ${name}: ${battery}%%"
    else
        output="${output}\r${icon} ${name}"
    fi
done

# Remove trailing <br> and output
printf "$output" 
