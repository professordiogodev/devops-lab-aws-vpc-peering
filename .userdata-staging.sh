#!/bin/bash
# Staging server: answers on port 80 with a fixed text.
mkdir -p /srv/www && echo "clippy-staging" > /srv/www/index.html
cat > /etc/systemd/system/staging-web.service <<UNIT
[Service]
WorkingDirectory=/srv/www
ExecStart=/usr/bin/python3 -m http.server 80
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now staging-web
