#!/usr/bin/env bash

# Parse command line arguments
SILENT=false
COMPRESS=true
while [[ $# -gt 0 ]]; do
  case $1 in
  --silent)
    SILENT=true
    shift
    ;;
  --no-compress)
    COMPRESS=false
    shift
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [--silent] [--no-compress]"
    exit 1
    ;;
  esac
done

SAVE_DIR="$HOME/Videos/screenrecs"
mkdir -p "$SAVE_DIR"

# ── Stop if already recording ──────────────────────────────────────────────
if pgrep -x wl-screenrec >/dev/null; then
  pkill -INT wl-screenrec
  
  # Wait up to 3 seconds for graceful shutdown
  for i in {1..15}; do
    pgrep -x wl-screenrec >/dev/null || break
    sleep 0.2
  done
  
  # Force kill if still running (prevents infinite loops with stuck processes)
  if pgrep -x wl-screenrec >/dev/null; then
    pkill -9 wl-screenrec
    sleep 0.5
  fi
  
  LATEST=$(ls -t "$SAVE_DIR"/*.mp4 | head -n1)

  # Compress the video if enabled
  if [[ "$COMPRESS" == true ]] && command -v ffmpeg >/dev/null; then
    notify-send "Compressing video..." "Please wait" --expire-time=5000
    
    COMPRESSED="${LATEST%.mp4}_compressed.mp4"

    mapfile -t DIMS < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=nw=1:nk=1 $LATEST)
     if [ $? != 0 ]; then
      notify-send "Finding dimensions failed" "Please check the video file" --expire-time=5500
      exit 1
    fi

    W=${DIMS[0]}
    H=${DIMS[1]}

       VF=""
    if (( W % 2 != 0 || H % 2 != 0 )); then
      notify-send "Fixing odd resolution" "${W}x${H} → even dimensions" --expire-time=1500
      VF='-vf "crop=trunc(iw/2)*2:trunc(ih/2)*2"'
    fi
    
    ffmpeg -i "$LATEST" $VF -c:v libx264 -crf 23 -preset medium -c:a copy -movflags +faststart "$COMPRESSED" -y

    #ret=$(ffmpeg -i "$LATEST" -c:v libx264 -crf 23 -preset medium -c:a copy -movflags +faststart "$COMPRESSED" -y)
    if [ $? = 0 ]; then
      # Get file sizes for comparison
      ORIG_SIZE=$(du -h "$LATEST" | cut -f1)
      COMP_SIZE=$(du -h "$COMPRESSED" | cut -f1)
      
      # Replace original with compressed version
      #mv "$COMPRESSED" "$LATEST"
      
      notify-send "Recording finished & compressed" "Size: $ORIG_SIZE → $COMP_SIZE to $COMPRESSED" --expire-time=5500
    else
      notify-send "Recording finished" "Compression failed, keeping original $W x $H " --expire-time=5500
    fi
  else
    notify-send "Recording finished" "Path copied: $(basename "$LATEST")" --expire-time=5500
  fi

  # Copy the file path to clipboard as text
  echo "$LATEST" | wl-copy

  # Also try to open the file location in file manager for easy drag-and-drop
#  if command -v xdg-open >/dev/null; then
#    xdg-open "$(dirname "$LATEST")" &
#  fi

  # Signal waybar to update
  pkill -RTMIN+8 waybar 2>/dev/null || true
  
  exit 0
fi

# ── Pick region ────────────────────────────────────────────────────────────
REGION=$(slurp) || exit 1

FILE="$SAVE_DIR/$(date +'%Y-%m-%d_%H-%M-%S').mp4"

if [[ "$SILENT" == false ]]; then
  # ── Choose which ONE source to record ──────────────────────────────────────
  MIC_SRC=$(pactl info | awk -F': ' '/Default Source/ {print $2}')
  AUDIO_SRC="$MIC_SRC"
  DESC=$(pactl list sources | awk -v s="$AUDIO_SRC" '$2==s {getline;sub(/^\s*Description: /,"");print;exit}')

  notify-send "Recording… (source: $DESC)" --expire-time=1000

  wl-screenrec -g "$REGION" --audio --audio-device "$AUDIO_SRC" -f "$FILE" &
else
  notify-send "Recording… (silent mode)" --expire-time=1000

  wl-screenrec -g "$REGION" -f "$FILE" &
fi

# Signal waybar to update
pkill -RTMIN+8 waybar 2>/dev/null || true
