# Loki 502 / "Log volume has not been configured"

**Symptom:** Grafana's Logs Drilldown showed "Log volume has not been configured"
plus a toast "An error occurred within the plugin". The Loki datasource
(`http://host.containers.internal:3100`, the nginx gateway) returned 502 for
every `/loki/api/*` route.

## Root cause

`roles/o11y_install/templates/config/loki-gateway.conf.j2` proxied requests
with `proxy_pass http://read:3100$request_uri;` (and same for `write`).
Appending `$request_uri` makes the proxy target an nginx **variable**, which
forces nginx to resolve the hostname (`read`, `write`) at **request time**
via the `resolver` directive — which the config deliberately didn't set,
because a comment (wrongly) assumed aardvark-dns lived at `127.0.0.11` and
refused connections.

In reality this network's DNS server is the podman bridge gateway
(`10.89.x.1`, see `/etc/resolv.conf` inside the container), not
`127.0.0.11`. So the per-request resolve always failed → nginx returned
502 for every proxied path (the static `/` health route still worked,
which is what masked this at first).

**Fix:** drop `$request_uri` from every `proxy_pass`. With no URI in
`proxy_pass`, nginx forwards the original request URI unmodified anyway,
and goes back to resolving `read`/`write` once at startup (no resolver
needed) — which is what the original comment intended.

## Bonus bug found along the way

`roles/o11y_install/templates/loki-compose.yml.j2` healthchecked
`read`/`write`/`backend` with `/usr/bin/loki -health`, which isn't a real
flag (`flag provided but not defined`). All three containers were stuck
permanently "unhealthy" (crash-looping the healthcheck, not the actual
process). Replaced with:

```
wget --spider -q http://localhost:3100/ready
```

## Verified

After redeploying (`ansible-playbook o11y-install.yml`), both
`/loki/api/v1/labels` and `/loki/api/v1/index/volume` return 200 through
the gateway on port 3100, and all `loki_*` containers report `healthy`.

Unrelated, noticed but not fixed: `tempo_tempo_1` was `Exited (1)` on the
host at the time of this investigation.
