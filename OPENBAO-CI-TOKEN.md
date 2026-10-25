# OpenBao token for CI

The `Deploy` job in `.forgejo/workflows/o11y.yaml` needs an OpenBao token so that
`calvin.openbao.ssh_client_cert` can sign the runner's throwaway SSH key. This page
explains the policy the token gets and how to create (and renew) it.

## Forgejo settings

| Name          | Kind     | Value                                                     |
|---------------|----------|-----------------------------------------------------------|
| `BAO_ADDR`    | variable | `https://192.168.1.4:8200` (base URL, **not** `/ui/...`)  |
| `BAO_CACERT`  | secret   | Content of the pinned OpenBao CA (`~/.config/openbao/ca.pem`) |
| `BAO_TOKEN`   | secret   | The token created below                                   |

Variables: repo **Settings → Actions → Variables**. Secrets: **Settings → Actions → Secrets**.

## The policy: `ci-ssh-sign`

```hcl
path "ssh-client-signer/sign/ansible" {
  capabilities = ["update"]
}
```

- `ssh-client-signer` is the SSH secrets engine mount; `sign/ansible` is the
  endpoint that signs a public key with the `ansible` role.
- `update` is the capability behind a `POST`/`write`, which is what signing is.
  No `read`, `list`, `create` or `delete`, and no other path.
- So a token with this policy can **only** get SSH certificates for what the
  `ansible` role allows (principal `ansible`, 30 min TTL). It cannot read secrets,
  change config or create other tokens. If it leaks, that is the blast radius.

Create it in the UI: **Policies → ACL Policies → Create ACL policy**, name
`ci-ssh-sign`, paste the HCL above. Or with the CLI:

```sh
bao policy write ci-ssh-sign ci-ssh-sign.hcl
```

## Create the token

The UI has no token form: open the web console with the **`>_`** icon (top right)
and run commands without the `bao` prefix.

```
write auth/token/create policies=ci-ssh-sign period=768h no_parent=true display_name=forgejo-o11y
```

Copy `client_token` from the output (shown only once) into the `BAO_TOKEN` secret.

- `policies=ci-ssh-sign`: the only policy attached (no `default` policy is lost;
  it is added automatically and only allows the token to look itself up/renew).
- `period=768h`: periodic token. It has no max TTL, but **expires if not renewed
  within 768h (32 days)**. The workflow does not renew it.
- `no_parent=true`: orphan token, so it is not revoked when your own login token
  expires. Needs root or `sudo` on `auth/token/create`.
- `display_name`: shows up as `token-forgejo-o11y` in audit logs.

## Renew / check / revoke

Note the token's **accessor** (also in the create output): it identifies the token
without exposing it.

```
write auth/token/lookup-accessor accessor=<accessor>             # TTL left
write auth/token/renew-accessor accessor=<accessor>              # reset to 768h
write auth/token/revoke-accessor accessor=<accessor>             # kill it
```

(CLI equivalents: `bao token lookup -accessor <accessor>`,
`bao token renew -accessor <accessor>`, `bao token revoke -accessor <accessor>`.)

If the job fails with `permission denied` / `bad token`, the token probably
expired: create a new one and update the secret.

## Alternative: AppRole (no long-lived token)

Each run logs in and gets a short-lived token instead of storing one.

1. UI: **Access → Auth Methods → Enable new method → AppRole**.
2. Console:
   ```
   write auth/approle/role/forgejo-o11y token_policies=ci-ssh-sign token_ttl=15m token_max_ttl=30m
   read auth/approle/role/forgejo-o11y/role-id
   write -f auth/approle/role/forgejo-o11y/secret-id
   ```
3. Store `role_id` as `BAO_ROLE_ID` and `secret_id` as `BAO_SECRET_ID`, remove
   `BAO_TOKEN` from the job `env:`, and add this step after "Set up SSH":
   ```yaml
   - name: Log in to OpenBao
     run: |
       token=$(curl -sf --cacert "$BAO_CACERT" -X POST \
         -d '{"role_id":"${{ secrets.BAO_ROLE_ID }}","secret_id":"${{ secrets.BAO_SECRET_ID }}"}' \
         "$BAO_ADDR/v1/auth/approle/login" \
         | python3 -c 'import sys,json; print(json.load(sys.stdin)["auth"]["client_token"])')
       echo "::add-mask::$token"
       echo "BAO_TOKEN=$token" >> "$GITHUB_ENV"
   ```
