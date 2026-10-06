# Intent

Goal: The Gateway VM is replaced only when the owner deliberately rolls it out, never as a side effect of a config, site, key or image change. When it is rolled out, Gateway, Sonar and Kita move to the new VM together: the new VM is built and both apps are installed on it before one DNS flip moves all three hostnames at once. Gateway and Kita see zero downtime; Sonar, whose SQLite database sits on a volume only one server can hold, shows a clear 503 "back in a minute" page for one short handover.

In scope: Gateway `hetzner/terraform`: a stable bootstrap user_data with config pushed in place over SSH, servers kept in blue/green slots with roles taken from Hetzner labels, a `rollout_step` variable, a Gateway-owned origin record, `terraform test` coverage of the slot logic. Gateway's workflow: a `rollout` dispatch that adds, deploys the apps, promotes, hands Sonar over, drains and retires, plus a guard that refuses any implicit server replacement. Gateway's README and CLAUDE.md.
  Kita `deploy/terraform`: a CNAME to the origin record and one install per Gateway server. Sonar `deploy/terraform`, its install scripts, nginx template, CI workflow and deploy README: a CNAME to the origin record, one install per server, a volume and data handover that follows the active server, a 503 maintenance answer, an ssh-agent in CI.
  Owner gates: the in-place migration of the live VM, switching the apps to the origin record, and the first full rollout with request probes.

Out of scope: true zero downtime for Sonar (moving its data off the single-attach volume is a later Sonar plan); Floating IPs; SSH key rotation (the personal-ssh-key plan); the AWS stack; app features; the R2 bucket layout.

Constraints: D1-D18. Gateway's CLAUDE.md "Don't" list holds: never touch `aws/`. Every push to a main branch deploys, so agents push nothing and every push is an owner gate. The repos are public: no hostname, origin label, IP, email or token in tracked files, commits or CI logs. Cross-repo work is committed with `git -C` (D14).

Definition of done: Gateway's Terraform passes fmt, validate and its tests; Kita's and Sonar's checks pass; all three workflows pass actionlint. The owner confirms: the live VM was migrated in place with no replacement, and a site edit applied without one; Sonar's and Kita's records are CNAMEs to origin; a CI rollout replaced the VM while probes saw no failed request for Gateway or Kita and one Sonar 503 window of at most about 3 minutes, with Sonar's data intact; afterwards all three local plans show no changes.
