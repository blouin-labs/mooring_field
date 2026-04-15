#!/bin/bash
set -e
sudo /usr/local/bin/init-firewall.sh
ttyd --port 7681 zsh &
exec "$@"
