# systemd units

These are **templates**. Placeholders must be substituted before installing —
`setup.sh` generates the bot unit on its own, so use these when wiring the
processing/weekly units by hand.

| Placeholder      | Meaning                                   | Example                      |
|------------------|-------------------------------------------|------------------------------|
| `__USER__`       | Unix user the service runs as             | `gaal`                       |
| `__HOME__`       | That user's home directory                | `/home/gaal`                 |
| `__PROJECT_DIR__`| Absolute path to the cloned project        | `/home/gaal/Gaal_Secretar`   |
| `__UV_BIN__`     | Absolute path to the `uv` binary          | `/home/gaal/.local/bin/uv`   |

Install, e.g. for the daily processing unit:

```bash
USER_NAME="$(id -un)"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

sed -e "s|__USER__|$USER_NAME|g" \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__UV_BIN__|$(command -v uv)|g" \
    deploy/d-brain-process.service \
  | sudo tee /etc/systemd/system/d-brain-process.service >/dev/null

sudo cp deploy/d-brain-process.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now d-brain-process.timer
```

Failure alerts: see `dropins/README.md`.
