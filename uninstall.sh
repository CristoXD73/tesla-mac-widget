#!/bin/bash
# Removes Tesla Mac Widget from this Mac. Your Tesla account and car are not changed.
pkill -x "Tesla Widget" 2>/dev/null
rm -rf "/Applications/Tesla Widget.app"
read -r -p "Also delete your keys and settings in ~/.tesla-widget? [y/n] " a
[[ "$a" =~ ^[Yy] ]] && rm -rf "$HOME/.tesla-widget" && echo "Deleted ~/.tesla-widget"
echo "Done. To stop the app being allowed on your car, remove its key in the car: Controls → Locks."
