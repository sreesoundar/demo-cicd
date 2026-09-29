#!/usr/bin/env bash
# One-time EC2 setup. Run once on the box as the SSH user CI will deploy as:
#   sudo bash setup-ec2.sh
# Creates a systemd service for the API on :5000,
# and an Nginx site serving React from /var/www/demo-ui with /api/ -> the API.
set -euo pipefail

DEPLOY_USER="${SUDO_USER:?run with sudo as the deploy user}"

# No .NET install: CI publishes the API self-contained (Ubuntu 26.04 has no .NET 8 package)

# Deploy dirs owned by the deploy user, so CI can copy files in without sudo
mkdir -p /var/www/demo-ui /var/www/demo-api
chown -R "$DEPLOY_USER": /var/www/demo-ui /var/www/demo-api

cat > /etc/systemd/system/demo-api.service <<EOF
[Unit]
Description=demo-cicd API
After=network.target

[Service]
WorkingDirectory=/var/www/demo-api
ExecStart=/var/www/demo-api/Api
Environment=ASPNETCORE_URLS=http://127.0.0.1:5000
Environment=ASPNETCORE_ENVIRONMENT=Production
Restart=always
User=$DEPLOY_USER

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable demo-api

# Ubuntu's default site would otherwise win on :80
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/conf.d/demo-cicd.conf <<'EOF'
server {
    listen 80 default_server;
    root /var/www/demo-ui;
    index index.html;

    # Trailing slash strips /api, so /api/weatherforecast -> :5000/weatherforecast
    location /api/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
nginx -t && systemctl reload nginx

# Let CI restart just this service without a password prompt
echo "$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart demo-api" > /etc/sudoers.d/demo-api
chmod 440 /etc/sudoers.d/demo-api

echo "Done."
