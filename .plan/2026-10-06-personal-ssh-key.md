# Personal SSH key and a dedicated deploy key
status: READY
created: 2026-10-06 · updated: 2026-10-06
goal: The running Gateway VM trusts the owner's personal key and a new CI deploy key instead of the old shared key, without being replaced, and no key comment (the owner's email) reaches Hetzner, the Terraform state or a public Actions log.
verify: (cd hetzner/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate) && ASDF_SHELLCHECK_VERSION=0.10.0 uvx --from actionlint-py actionlint .github/workflows/hetzner.yml
commit: per-node
push: none
budgets: 2 tries per brief · 2 replans per node
tier: M

## Intent

Goal: Swap the root SSH keys of the live Gateway VM for two new ones, the owner's personal key for people and a dedicated deploy key for the three CI workflows, keeping access at every step and never replacing the VM. Make sure no public key comment (which holds the owner's email) is stored in Hetzner or the state, or printed in a public log, and clean up logs that already printed one.

In scope: Gateway's Terraform in `hetzner/terraform`, its workflow `.github/workflows/hetzner.yml`, `hetzner/README.md` and `CLAUDE.md`; owner-run steps on the VM, in Hetzner, and in the `production` environments of Gateway, Sonar and Kita (secrets and old run logs).

Out of scope: Sonar and Kita code (only their SSH_PRIVATE_KEY secret changes); any VM replacement or zero-downtime work (separate plan); the AWS stack; git author emails in commit history.

Constraints: D1-D10. The VM stays the same server the whole time. No key material, email, hostname or IP goes into a tracked file. Every owner step is a gate; agents never touch private keys, state or credentials.

Definition of done: Hetzner holds only the comment-free operator and deploy keys; the VM's authorized_keys accepts exactly those two and rejects the old key; Gateway, Sonar and Kita CI use the deploy key; Gateway's latest run is green with no server change; no stored log contains the owner's email.

## Decisions

- D1 Two keys: the owner's personal key (only on the laptop, never in GitHub) for people and local applies; a new ed25519 deploy key `~/.ssh/gateway_deploy` for CI, stored as SSH_PRIVATE_KEY in the `production` environments of Gateway, Sonar and Kita. New VMs trust both; the old key is removed from the VM and from Hetzner | confirmed
- D2 No VM replacement: Hetzner injects SSH keys only when a server is created, and a change to `hcloud_server.ssh_keys` forces a new server. The live VM gets the new keys by hand in `/root/.ssh/authorized_keys`; `hcloud_server.v2ray` adds `ssh_keys` to `lifecycle.ignore_changes`, so key resources can change without touching it. Any plan that replaces or updates `hcloud_server.v2ray` stops the plan | confirmed
- D3 No key comments anywhere: Terraform keeps only the first two whitespace-separated fields (type and base64 body) of each public key, so no comment reaches Hetzner or the state, and a variable validation rejects anything that is not an `ssh-ed25519`, `ssh-rsa` or `ecdsa-sha2-nistp*` key. The deploy key's comment is `gateway-deploy`; keys appended to authorized_keys by hand are cut to two fields first | confirmed
- D4 Public keys become secrets: OPERATOR_SSH_PUBLIC_KEY and DEPLOY_SSH_PUBLIC_KEY are `production` secrets in Gateway (masked in logs) and replace the variable SSH_PUBLIC_KEY, because a variable is printed unmasked in every step's `env:` block of the public log. The workflow fails, without printing the value, if either secret has more than two fields. The old variable is deleted in N06 | confirmed
- D5 Access is never lost: new keys are added to the VM and tested (N02) before any secret or Terraform change (N05), and the old key is removed last (N06). If access is ever lost, the Hetzner Console's web console or rescue system recovers it without replacing the VM | confirmed
- D6 Key resources: `hcloud_ssh_key.operator` and `hcloud_ssh_key.deploy`, named `<name>-operator-<first 8 hex of sha256(key)>` and `<name>-deploy-<…>`, replace `hcloud_ssh_key.this`, which is destroyed (deleting a Hetzner key object never changes a running VM). The hash in the name lets a later rotation create-before-destroy without Hetzner's 409 on duplicate names. `public_key` is no longer ignored, since the stripped key is identical locally and in CI | confirmed
- D7 Local defaults: the readiness gate's private key and the operator public key come from the first of `~/.ssh/id_ed25519` and `~/.ssh/id_rsa` that has a `.pub` (Sonar and Kita already default to id_ed25519); the deploy public key from `~/.ssh/gateway_deploy.pub`. A file is read only when its variable is null (a conditional, not `coalesce`), so CI never reads `~/.ssh`. Overrides: `ssh_private_key_path`, `operator_ssh_public_key`, `deploy_ssh_public_key` | confirmed
- D8 Agents never read, print or handle a private key, `terraform.tfvars`, `backend.hcl`, `.terraform/` or state, and never plan or apply against R2: the owner does (gates N02, N05, N06). Pre-authorized for agents: `terraform fmt`, `terraform init -backend=false`, `terraform validate`, `terraform test`, actionlint through uvx, and read-only `gh` calls that list names or runs | confirmed
- D9 Old logs: Gateway runs printed `vars.SSH_PUBLIC_KEY` in step `env:` blocks. The owner searches the run logs of all three repos for the email, typed into a shell variable (never written to a file in these public repos), and deletes the logs of every matching run (N06) | confirmed
- D10 The repos are public: no email, hostname, IP, fingerprint or key material goes into a tracked file, commit message or plan log; owner gates report pass or defects only | confirmed

## Graph

| id | title | type | deps | model | try | rp | status | note |
|----|-------|------|------|-------|-----|----|--------|------|
| N01 | preflight | check | - | -/sonnet | 0 | 0 | TODO | |
| N02 | owner: create the keys and add them to the VM | gate | N01 | -/- | 0 | 0 | TODO | |
| N03 | Gateway terraform: two comment-free keys | exec | N01 | opus/sonnet | 0 | 0 | TODO | |
| N04 | Gateway workflow, README and CLAUDE.md | exec | N03 | sonnet/sonnet | 0 | 0 | TODO | |
| N05 | owner: secrets, plan, push and check | gate | N02,N04 | -/- | 0 | 0 | TODO | |
| N06 | owner: remove the old key and clean old logs | gate | N05 | -/- | 0 | 0 | TODO | |
| N07 | plan acceptance | check | N06 | -/sonnet | 0 | 0 | TODO | |

## N01 preflight
Do: Confirm the starting point: the repo checks pass on the untouched tree, the tools the executors run work, and `gh` can list Gateway's `production` secret and variable names (the owner's own gates need the same login).
Done when:
- C1 [cmd] `(cd hetzner/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate) && ASDF_SHELLCHECK_VERSION=0.10.0 uvx --from actionlint-py actionlint .github/workflows/hetzner.yml`
- C2 [cmd] `terraform version | head -1 | grep -q 'v1.16.5'`
- C3 [cmd] `gh secret list -R IVIR3zaM/Gateway --env production --json name --jq '.[].name' | grep -qx SSH_PRIVATE_KEY`
- C4 [cmd] `gh variable list -R IVIR3zaM/Gateway --env production --json name --jq '.[].name' | grep -qx SSH_PUBLIC_KEY`

## N02 owner: create the keys and add them to the VM
Do: The owner makes the two keys and adds them to the live VM next to the old key, then proves both log in (D1, D3, D5). Nothing in Terraform, Hetzner or GitHub changes yet. Run the commands on your laptop; `$IP` is the VM's IPv4 and stays in your shell only.
Context: The current key is the one Gateway's state trusts: `~/.ssh/id_rsa` unless your tfvars set `ssh_private_key_path`. If your personal key IS that key, stop and report it: D1 then needs only the deploy key.
  Port 22 opens only to the last applier's IP (a CI runner after a CI run), so step C3 points it at you first; `-target` limits the apply to the firewall, and Terraform's targeting warning is expected.
  Lost access at any point: Hetzner Console → the server → Console (web terminal) or Rescue; never replace the VM.
  Keep the first SSH session open until C6 passes. Report only pass or a defect (D10): never paste keys, fingerprints, the IP or an email.
Done when:
- C1 [human] Full steps: `.planzilla/plz brief personal-ssh-key N02`. Personal key ready with no email in it: `ls ~/.ssh/id_ed25519.pub` (create one with `ssh-keygen -t ed25519 -C laptop` if missing; to drop an email comment from an existing one: `ssh-keygen -c -C laptop -f ~/.ssh/id_ed25519`).
- C2 [human] Deploy key made: `ssh-keygen -t ed25519 -N "" -C gateway-deploy -f ~/.ssh/gateway_deploy`.
- C3 [human] Port 22 open to you: in `hetzner/terraform`, `terraform apply -lock-timeout=10m -target=hcloud_firewall.v2ray`, whose plan updates only `hcloud_firewall.v2ray`; then `IP=$(terraform output -raw server_ipv4)`.
- C4 [human] Logged in with the old key and inventoried: `ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes root@$IP`, then on the VM `cp /root/.ssh/authorized_keys /root/.ssh/authorized_keys.bak && ssh-keygen -lf /root/.ssh/authorized_keys`; every line is one you recognize (an unknown line is a defect to report).
- C5 [human] New keys appended without comments, from a second laptop terminal (set `IP` there too): `{ cut -d' ' -f1,2 ~/.ssh/id_ed25519.pub; cut -d' ' -f1,2 ~/.ssh/gateway_deploy.pub; } | ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes root@$IP 'cat >> /root/.ssh/authorized_keys'`.
- C6 [human] Both new keys log in: `ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes root@$IP true && ssh -i ~/.ssh/gateway_deploy -o IdentitiesOnly=yes root@$IP true` exits 0.

## N03 Gateway terraform: two comment-free keys
Do: Replace `hcloud_ssh_key.this` with an operator and a deploy key whose public keys are stripped of comments (D3, D6), stop key changes from ever touching the server (D2), and move the local key defaults to id_ed25519 first (D7). Code and a mocked `terraform test` only; no backend, plan or apply.
Context: D2: `hcloud_server.v2ray` (`hetzner/terraform/server.tf:84-105`) gets `ssh_keys = [hcloud_ssh_key.operator.id, hcloud_ssh_key.deploy.id]` and `ignore_changes = [ssh_keys]` next to its `create_before_destroy`, with a one-line why (keys apply at creation only; a change would replace the VM).
  D3/D6: replace `server.tf:62-73` with the two resources; names `${var.name}-operator-${substr(sha256(key), 0, 8)}` and `-deploy-` likewise; drop the old trim/ignore comment. Strip in one local (first two whitespace-separated fields); a `validation` on each new variable accepts null or a key matching `^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/]+=*( .*)?$` after trimspace.
  D7: in `hetzner/terraform/variables.tf:63-73` replace `ssh_public_key` with `operator_ssh_public_key` and `deploy_ssh_public_key` (string, default null, descriptions naming the defaults and that comments are dropped); `ssh_private_key_path`'s description names the new default. In `local_env.tf:30-43` the candidates become `~/.ssh/id_ed25519` then `~/.ssh/id_rsa`; the operator key falls back to the detected `.pub`, the deploy key to `~/.ssh/gateway_deploy.pub`, each through a conditional so a set variable never reads a file.
  Add a non-sensitive output `ssh_key_names` (both resource names) in `outputs.tf`; it holds no key material.
  Test: `hetzner/terraform/tests/ssh_keys.tftest.hcl` with `mock_provider` for every provider and `override_data` for the http, cloudflare zone and IP-range data sources; `command = plan`; assert the stripped keys and that a malformed key fails validation (`expect_failures`). If mocking cannot work with this config, reply BLOCKED with the reason.
  Never open `terraform.tfvars`, `backend.hcl`, `.terraform/` or state; other uncommitted changes are not this node's.
Read: `hetzner/terraform/server.tf`, `hetzner/terraform/local_env.tf`, `hetzner/terraform/variables.tf`, `hetzner/terraform/readiness.tf`, `hetzner/terraform/outputs.tf`, `hetzner/terraform/cloudflare.tf`, `hetzner/terraform/firewall.tf`
Write: `hetzner/terraform/server.tf`, `hetzner/terraform/local_env.tf`, `hetzner/terraform/variables.tf`, `hetzner/terraform/outputs.tf`, `hetzner/terraform/tests/**`
Test first: the tftest plan fails before the change (no `hcloud_ssh_key.operator`) and passes after: a key with a trailing email comment comes out as type and body only, and an invalid key is rejected.
Done when:
- C1 [cmd] `cd hetzner/terraform && ! grep -q 'hcloud_ssh_key" "this"' *.tf && grep -q 'resource "hcloud_ssh_key" "operator"' server.tf && grep -q 'resource "hcloud_ssh_key" "deploy"' server.tf && ! grep -qw 'var.ssh_public_key' *.tf`
- C2 [cmd] `cd hetzner/terraform && awk '/resource "hcloud_server" "v2ray"/,/^}/' server.tf | grep -Eq 'ignore_changes *= *\[[^]]*ssh_keys'`
- C3 [cmd] `cd hetzner/terraform && terraform init -backend=false -input=false >/dev/null && terraform test`
- C4 [review] Only the two key resources, their variables and local defaults, the server's `ssh_keys` and lifecycle, the output and the test change; `create_before_destroy` stays; no key, email, hostname or IP is added (D10).
- C5 [cmd] `cd hetzner/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate`

## N04 Gateway workflow, README and CLAUDE.md
Do: Feed the two public keys to Terraform from masked secrets, fail early on a key that still has a comment, and document the two-key model and how to rotate a key without replacing the VM (D1-D7).
Context: D4, workflow `.github/workflows/hetzner.yml`: in "Check the required inputs are set" (`:92-115`) swap `SSH_PUBLIC_KEY: ${{ vars.SSH_PUBLIC_KEY }}` for `OPERATOR_SSH_PUBLIC_KEY` and `DEPLOY_SSH_PUBLIC_KEY` from `secrets.` and list both in the loop; in the same step, fail with `::error::<NAME> has a comment: store only the type and the key` when one has more than two whitespace-separated fields, never echoing the value. In "terraform plan" (`:180-190`) replace `TF_VAR_ssh_public_key` with `TF_VAR_operator_ssh_public_key` and `TF_VAR_deploy_ssh_public_key` from those secrets. Keep the existing comment style (a "why" line above a step).
  README `hetzner/README.md`: rewrite the SSH paragraph (`:128-140`) for two keys, their local defaults (D7), that comments are dropped (D3) and that keys apply only when a VM is created (D2); add a short "Rotating an SSH key" list: add the new key to authorized_keys and test it, update the secret or local default, apply (only key resources change), then remove the old line. "Expect" (`:210`) becomes 2 × `hcloud_ssh_key`. The table (`:263-281`): SSH_PRIVATE_KEY is the deploy key's private half (the same secret value in Sonar and Kita); replace the SSH_PUBLIC_KEY row with the two secret rows, each "comment-free, type and key only". Keep the hard-wrapped style.
  CLAUDE.md, Hetzner stack: one bullet: two SSH keys (operator, deploy), comment-free, applied only when a VM is created; `ssh_keys` is ignored on the server so key changes never replace it.
  D10: nothing added may print or contain a key, email, hostname or IP.
Read: `.github/workflows/hetzner.yml`, `hetzner/README.md`, `CLAUDE.md`, `hetzner/terraform/variables.tf`
Write: `.github/workflows/hetzner.yml`, `hetzner/README.md`, `CLAUDE.md`
Test first: -
Done when:
- C1 [cmd] `! grep -n 'SSH_PUBLIC_KEY\b' .github/workflows/hetzner.yml | grep -v -e OPERATOR_SSH_PUBLIC_KEY -e DEPLOY_SSH_PUBLIC_KEY | grep -q . && grep -q 'TF_VAR_operator_ssh_public_key: ${{ secrets.OPERATOR_SSH_PUBLIC_KEY }}' .github/workflows/hetzner.yml && grep -q 'TF_VAR_deploy_ssh_public_key: ${{ secrets.DEPLOY_SSH_PUBLIC_KEY }}' .github/workflows/hetzner.yml`
- C2 [cmd] `! grep -q 'vars.SSH_PUBLIC_KEY' .github/workflows/hetzner.yml && grep -q 'has a comment' .github/workflows/hetzner.yml`
- C3 [cmd] `grep -q 'OPERATOR_SSH_PUBLIC_KEY' hetzner/README.md && grep -q 'DEPLOY_SSH_PUBLIC_KEY' hetzner/README.md && grep -qi 'rotating an ssh key' hetzner/README.md && grep -q 'ssh_keys' CLAUDE.md`
- C4 [review] The comment check never prints a key value; the README's rotation steps keep access at every step and never replace the VM; no other workflow behavior changes.
- C5 [cmd] `ASDF_SHELLCHECK_VERSION=0.10.0 uvx --from actionlint-py actionlint .github/workflows/hetzner.yml && cd hetzner/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate`

## N05 owner: secrets, plan, push and check
Do: The owner points all three CI workflows at the deploy key, confirms locally that Terraform only swaps the Hetzner key objects, pushes, and checks the CI run (D1, D2, D4, D6). Every secret is set from the key files, so a secret and its file can never differ.
Context: Secrets go into each repo's `production` environment; the commands read the files directly and print nothing. The push to main deploys, so set the secrets first.
  Expected plan, nothing else: create `hcloud_ssh_key.operator` and `hcloud_ssh_key.deploy`, destroy `hcloud_ssh_key.this[0]`, and possibly `hcloud_firewall.v2ray` (your IP). Any change to `hcloud_server.v2ray`, the DNS record, the cert or the UUID: stop and report a defect.
  Hetzner answers 409 "SSH key not unique" if one of the two keys already exists in the project: delete that stray key object in the Hetzner Console (it never changes a running VM), then plan again.
  Report only pass or defects (D10).
Done when:
- C1 [human] Full steps: `.planzilla/plz brief personal-ssh-key N05`. Gateway secrets set: `gh secret set OPERATOR_SSH_PUBLIC_KEY -R IVIR3zaM/Gateway --env production --body "$(cut -d' ' -f1,2 ~/.ssh/id_ed25519.pub)"`, the same for DEPLOY_SSH_PUBLIC_KEY from `~/.ssh/gateway_deploy.pub`, and `gh secret set SSH_PRIVATE_KEY -R IVIR3zaM/Gateway --env production < ~/.ssh/gateway_deploy`.
- C2 [human] Sonar and Kita use the deploy key: `for r in Sonar Kita; do gh secret set SSH_PRIVATE_KEY -R IVIR3zaM/$r --env production < ~/.ssh/gateway_deploy; done`.
- C3 [human] Local plan in `hetzner/terraform` (`terraform plan -lock-timeout=10m`) shows only the expected changes listed in Context.
- C4 [human] Pushed to main; Gateway's run is green and its plan lines name only the key resources (and the firewall): `gh run watch -R IVIR3zaM/Gateway $(gh run list -R IVIR3zaM/Gateway --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status`.
- C5 [human] Hetzner Console → Security → SSH keys lists exactly the two names from `terraform output ssh_key_names`, and neither shows an email.
- C6 [human] The deploy key deploys: in Kita's `deploy/terraform`, `terraform apply -lock-timeout=10m -replace=terraform_data.install -var ssh_private_key_path=~/.ssh/gateway_deploy -var kita_git_ref=$(git rev-parse origin/main)` (after `git fetch` in Kita) succeeds: a no-downtime reinstall of the deployed commit.

## N06 owner: remove the old key and clean old logs
Do: The owner removes the old key from the VM and the old public-key variable from GitHub, then deletes every stored run log that printed the email (D5, D9). Afterwards only the operator and deploy keys open the VM.
Context: Port 22 may point at a CI runner again after N05's push: re-run N02's targeted firewall apply, and `IP=$(terraform output -raw server_ipv4)`.
  Type the email into a variable so it is never written down: `read -r MY_EMAIL`. Run-log search, per repo: `for id in $(gh run list -R IVIR3zaM/$r -L 300 --json databaseId --jq '.[].databaseId'); do gh run view $id -R IVIR3zaM/$r --log 2>/dev/null | grep -qiF "$MY_EMAIL" && echo $id; done`; delete each match's logs with `gh api -X DELETE repos/IVIR3zaM/$r/actions/runs/<id>/logs`.
  Keep `/root/.ssh/authorized_keys.bak` until C3 passes, then delete it.
  Report only pass or defects (D10).
Done when:
- C1 [human] Full steps: `.planzilla/plz brief personal-ssh-key N06`. On the VM (logged in with `~/.ssh/id_ed25519`), the old key's line is gone from `/root/.ssh/authorized_keys`; `ssh-keygen -lf /root/.ssh/authorized_keys` lists exactly the operator and deploy keys, neither with a comment.
- C2 [human] The old key is refused and the new ones work: `ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes root@$IP true` fails with "Permission denied"; the id_ed25519 and gateway_deploy logins exit 0.
- C3 [human] The old variable is gone: `gh variable delete SSH_PUBLIC_KEY -R IVIR3zaM/Gateway --env production`.
- C4 [human] The log search (Context) over Gateway, Sonar and Kita prints no run id after the deletions.
- C5 [human] Then `unset MY_EMAIL`; `~/.ssh/id_rsa` no longer opens the VM (keep or retire it for other uses).

## N07 plan acceptance
Do: Check the whole plan: the repo checks and the Terraform test pass, Gateway's `production` environment has the two public-key secrets and no SSH_PUBLIC_KEY variable, all three repos still have SSH_PRIVATE_KEY, and Gateway's latest main run is green.
Done when:
- C1 [cmd] `(cd hetzner/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate && terraform test) && ASDF_SHELLCHECK_VERSION=0.10.0 uvx --from actionlint-py actionlint .github/workflows/hetzner.yml`
- C2 [cmd] `s=$(gh secret list -R IVIR3zaM/Gateway --env production --json name --jq '.[].name') && echo "$s" | grep -qx OPERATOR_SSH_PUBLIC_KEY && echo "$s" | grep -qx DEPLOY_SSH_PUBLIC_KEY`
- C3 [cmd] `! gh variable list -R IVIR3zaM/Gateway --env production --json name --jq '.[].name' | grep -qx SSH_PUBLIC_KEY`
- C4 [cmd] `for r in Gateway Sonar Kita; do gh secret list -R IVIR3zaM/$r --env production --json name --jq '.[].name' | grep -qx SSH_PRIVATE_KEY || exit 1; done`
- C5 [cmd] `gh run list -R IVIR3zaM/Gateway --branch main --limit 1 --json conclusion --jq '.[0].conclusion' | grep -qx success`
- C6 [review] No tracked file or commit of this plan contains a key, fingerprint, email, hostname or IP (D10).

## Log
