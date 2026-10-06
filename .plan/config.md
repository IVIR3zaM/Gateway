# Planzilla config (FORMAT §8). A missing key takes its default; a plan's header wins over this file.
# Engineering rules and the repo's "don't" list live in CLAUDE.md and AGENTS.md, not here.

verify: (cd hetzner/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate) && ASDF_SHELLCHECK_VERSION=0.10.0 uvx --from actionlint-py actionlint .github/workflows/hetzner.yml
verify_fast: cd hetzner/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate
commit: per-node
push: none
retention: keep
models: planner=opus, exec=sonnet, verify=sonnet
preauthorized: terraform fmt, terraform init -backend=false and terraform validate in any Terraform root; actionlint through uvx; read-only gh calls that list names or runs (gh secret list, gh variable list, gh run list, gh run view without --log)
always_review: no
