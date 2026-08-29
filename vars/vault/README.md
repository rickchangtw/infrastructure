# Vault directory — secret values NEVER live in git.
#
# Per the ONE-12 plan §2.4: Git stores templates and variable NAMES only. Real
# secret VALUES are supplied at deploy time from:
#   * the host-side 0600 env files under ~/.config/containers/systemd/ (used by
#     the Quadlet units directly), and/or
#   * an Ansible vault file in this directory, e.g. discourse-dev.vault.yml.
#
# To create an encrypted vault on the control machine (not committed with a
# value), use:
#   ansible-vault create vars/vault/discourse-dev.vault.yml
# then reference it in the playbook with:
#   vars_files:
#     - ../vars/vault/discourse-dev.vault.yml
# The vault is passed at run time with --ask-vault-pass / a vault password file.
#
# SECRET NAMES used by this infra (values only on host/vault, never here):
#   discourse_db_password       (DISCOURSE_DB_PASSWORD / POSTGRES_PASSWORD)
#   discourse_redis_password    (DISCOURSE_REDIS_PASSWORD)
#   discourse_smtp_username     (DISCOURSE_SMTP_USER_NAME)
#   discourse_smtp_password     (DISCOURSE_SMTP_PASSWORD)
#   discourse_developer_emails  (DISCOURSE_DEVELOPER_EMAILS — not itself a
#                                credential, but held out of git by default)
#
# Files in this directory:
#   discourse-dev.vault.yml     Development secrets (encrypted)
#   discourse-prod.vault.yml    Production secrets  (encrypted, A3-A5 gated)
