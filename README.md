# Sun Empire Discourse — Infrastructure (ONE-12)

Ansible + rootless Podman + Quadlet definition for deploying **Discourse** as
the 太陽帝國 (Sun Empire) community official site. This implements the approved
[ONE-12](/ONE/issues/ONE-12) plan (`document-plan`, rev1, **A1 gate approved**)
and is built by [ONE-14](/ONE/issues/ONE-14).

**Development-scope only.** Production is reachable exclusively through the
gated `prod-promote.yml` path and requires individual human approval of the
A3/A4/A5 gates. Nothing here deploys to Production, and this branch never stops,
deletes, rebuilds, or changes existing Paperclip / Hermes / SmartCondo /
monitoring services or their data.

## Layout

```
infra/
├── ansible.cfg
├── inventories/
│   ├── development/{hosts.ini, group_vars/all.yml}   # dev host 100.94.136.15
│   └── production/{hosts.ini, group_vars/all.yml}    # EMPTY until A3-A5+human
├── group_vars/{discourse.yml, discourse_production.yml}
├── host_vars/{dev-dc1.yml, prod-dc1.yml}
├── roles/
│   ├── discourse-deps/      # podman, fuse-overlayfs, slirp4netns, uidmap, linger
│   ├── discourse-image/     # render app.yml + podman build pinned tag + digest
│   ├── discourse-db/        # Postgres 15 Quadlet + env (dedicated, pod-internal)
│   ├── discourse-redis/     # Redis 7 Quadlet + env (requirepass, RDB, dedicated)
│   ├── discourse-web/       # pod/web/sidekiq Quadlets + env + systemd user start
│   ├── discourse-verify/    # health checks, admin init, checklist for A2
│   └── discourse-backup/    # pg_dump + uploads via systemd-user timer + retention
├── templates/
│   ├── quadlet/             # discourse.pod, *-web/-sidekiq/-postgres/-redis.container
│   ├── env/                 # discourse.env.j2, postgres.env.j2, redis.env.j2
│   └── app.yml.j2           # Discourse tunable (build input)
├── files/scripts/           # discourse-backup.sh, restore.sh, healthcheck.sh
├── playbooks/
│   ├── site.yml             # Development provision (hosts: discourse_dev only)
│   ├── dev-verify.yml       # §6 nine-step verification
│   └── prod-promote.yml     # GATED Production promotion (A3-A5)
└── vars/vault/              # Encrypted vault structure (names only, no values)
```

## Security model

- **Zero secrets in git.** Repo stores templates and variable **names** only.
  Secret **values** live on the host in `0600` env files
  (`~/.config/containers/systemd/*.env`) or in encrypted Ansible vault files
  (`vars/vault/*.vault.yml`). Never commit or paste any `*_PASSWORD`,
  `*_API_KEY`, or SMTP credentials.
- `site.yml` pre-flight **fails a real run** if the DB/Redis passwords resolve
  empty, so you cannot deploy with blank secrets.
- **Prod cannot be triggered from dev:** `site.yml` targets `discourse_dev`
  only, and `prod-promote.yml` targets `discourse_prod`, which the development
  inventory never defines.

## Development deployment runbook

Prereqs (control machine): Ansible core + the `containers.podman` collection
(`ansible-galaxy collection install containers.podman`).

1. **Provision** (Development, `100.94.136.15`):

   ```sh
   ansible-playbook -i inventories/development/hosts.ini playbooks/site.yml
   ```

2. **Verify** (§6 nine-step flow; steps 1–3 automated, 4–9 manual QA):

   ```sh
   ansible-playbook -i inventories/development/hosts.ini playbooks/dev-verify.yml
   ```

3. Record the A2 checklist (steps 4–9: test accounts 管委會/管理室/住戶/待審核,
   announcements/threads, permissions, email, backup-restore rehearsal) back on
   [ONE-14](/ONE/issues/ONE-14) as the promotion gate.

## Production promotion (GATED — do not run without approval)

Requires individual human approval of **A3** (DNS/TLS/domain `forum.opc4u.shop`),
**A4** (promotion plan review), **A5** (go-live window). A human must also fill
`inventories/production/hosts.ini`.

```sh
ansible-playbook -i inventories/production/hosts.ini playbooks/prod-promote.yml \
  --extra-vars "promotion_consent=<board-approval-ref>"
```

The playbook refuses to run without `promotion_consent` or with an empty
production inventory. It never opens public ports and never edits firewall,
DNS, or the existing reverse-proxy/TLS.

## Verification (this repo)

Static syntax check (no host required):

```sh
ansible-playbook -i inventories/development/hosts.ini playbooks/site.yml --syntax-check
ansible-playbook -i inventories/development/hosts.ini playbooks/dev-verify.yml --syntax-check
```

## Upgrade / Rollback / DR

See ONE-12 plan §7: bump `discourse_version` → `discourse-image` rebuild →
`rake db:migrate` → restart web/sidekiq; keep the previous image tag + volumes
for rollback; restore via `files/scripts/discourse-restore.sh`.
