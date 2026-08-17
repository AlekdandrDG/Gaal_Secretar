# systemd drop-ins

`onfailure.conf` is symlinked/copied into each unit's `.d/` dir so a unit
failure fires a Telegram alert via `d-brain-notify@<unit>.service`.

Install for a unit, e.g. d-brain-process.service:
    sudo mkdir -p /etc/systemd/system/d-brain-process.service.d
    sudo cp deploy/dropins/onfailure.conf /etc/systemd/system/d-brain-process.service.d/
    sudo systemctl daemon-reload

Currently applied to: bot, process, weekly.
