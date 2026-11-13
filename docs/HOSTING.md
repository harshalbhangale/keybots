# The hosted server

- **Where:** AWS Lightsail `airkey-server`, ap-south-1 (Mumbai), Ubuntu 24.04, 1 GB ($7/month). Static IP `13.126.207.245` (`airkey-server-ip`).
- **Address:** https://13-126-207-245.sslip.io (Caddy gets the certificate; the server itself listens on 127.0.0.1:8787 only). Open ports: 22, 80, 443.
- **Auth:** on. The token is in `airkey/keys/api-token` (gitignored) and is built into the app as `AIRKEY_TOKEN`.
- **On the box:** code in `/opt/airkey/app`, keys in `/opt/airkey/keys` (only the pay, inbox and trader agent keys, and the AI keys; no owner key), receipts and orders in `/opt/airkey/data`. Runs as the `airkey` user under systemd (`airkey`, `caddy`).
- **SSH:** `ssh -i ~/.ssh/airkey-server.pem ubuntu@13.126.207.245`
- **Logs:** `sudo journalctl -u airkey -f`
- **Run only one server.** The Mac's dev server and this one would both watch the same orders. Keep the Mac's off while this one runs.

## Update the code

```sh
cd server
COPYFILE_DISABLE=1 tar -cz --exclude node_modules --exclude .env --exclude .claude --exclude data . \
  | ssh -i ~/.ssh/airkey-server.pem ubuntu@13.126.207.245 'rm -rf /tmp/a && mkdir /tmp/a && tar -xzf - -C /tmp/a 2>/dev/null; sudo rsync -a --exclude .env --exclude node_modules /tmp/a/ /opt/airkey/app/ && sudo chown -R airkey:airkey /opt/airkey/app && sudo -u airkey sh -c "cd /opt/airkey/app && npm ci --no-audit --no-fund" && sudo systemctl restart airkey'
```

## Build for the phone (free signing, every 7 days)

```sh
cd ios
xcodebuild -project AirKey.xcodeproj -scheme AirKey -destination 'id=00008140-000C752C3CC3801C' \
  -derivedDataPath /tmp/airkey-dd-device -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=R3D54PSMD2 CODE_SIGN_STYLE=Automatic CODE_SIGN_ENTITLEMENTS= \
  AIRKEY_SERVER=https://13-126-207-245.sslip.io AIRKEY_TOKEN=$(cat ../../airkey/keys/api-token) build
xcrun devicectl device install app --device 00008140-000C752C3CC3801C /tmp/airkey-dd-device/Build/Products/Debug-iphoneos/AirKey.app
```
