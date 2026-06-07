---
name: terraform
description: Enforces a safe, gated Terraform workflow — plan first, explain changes, flag destructive actions, confirm before apply. Use when starting any Terraform session, before running plan/apply, or when the user says "let's do a terraform apply", "plan this", "run terraform", or "apply the infra changes". Activates the workflow rules for the entire session.
---

# Terraform Workflow

This skill activates a gated Terraform workflow for the current session. Every apply is preceded by a plan, every plan is explained, and every destructive action is explicitly called out and confirmed before proceeding.

**Default posture: plan only.** Never run `terraform apply` unless the user explicitly says "go ahead", "apply it", "you can apply", or similar direct authorization. A plan alone is always safe to run.

---

## Step 1 — Establish session context

Before running anything, confirm:

1. **Which root** — the Terraform root directory to work in (e.g. `v2/environments/base`).
2. **Which var file** — the `.tfvars` or `.tfvars.json` to use, if required.
3. **Which AWS profile** — the profile that targets the correct account. Never assume; the wrong profile can plan against production.
4. **What the goal is** — what change is being made and why. If the user just says "apply" without context, ask what they're trying to accomplish first.

Restate these back before running the first plan so there's a clear record of what session this is.

---

## Step 2 — Run the plan

Construct and run the plan command. Always capture full output — never use `-compact-warnings` or suppress output at this stage.

```bash
AWS_PROFILE=<profile> terraform plan -var-file="<path/to/vars.json>"
```

If `init` hasn't been run yet, or if the working directory is stale (providers missing, module cache outdated), run init first and explain why.

---

## Step 3 — Parse and explain the plan

Do **not** dump the raw plan output at the user. Parse it and present a structured summary:

### 3a — Change count headline

```
Plan: X to add, Y to change, Z to destroy.
```

State this clearly at the top.

### 3b — Changes table

Group resources by action type. For each resource, show:

| Action | Resource | Notes |
|--------|----------|-------|
| `+` create | `aws_acm_certificate.this["qa.example.com"]` | new cert, DNS validation required |
| `~` update | `aws_ecs_service.service` | task definition revision bump |
| `-` destroy | `aws_s3_bucket.old_bucket` | ⚠️ permanent deletion |
| `-/+` replace | `aws_cloudfront_distribution.main` | triggers destroy+create |

Add a **Notes** column for anything non-obvious: what the change affects downstream, whether it causes downtime, whether it's reversible.

### 3c — Destructive action analysis

Identify every resource with action `-` (destroy) or `-/+` (replace). For each one, answer:

1. **Was this expected?** Does it match what the user said the goal was?
2. **What is the blast radius?** What depends on this resource?
3. **Is it reversible?** (S3 versioned = recoverable; Aurora without snapshot = not)
4. **Is there data at risk?** Databases, S3 buckets, secrets.

**Hard stops — always require explicit acknowledgment before continuing:**
- Any `aws_db_instance`, `aws_rds_cluster`, `aws_aurora_*` destruction
- Any `aws_s3_bucket` destruction (check for versioning and content first)
- Any `aws_elasticache_*` destruction
- Any `aws_iam_role` or `aws_iam_policy` destruction that affects running services
- Any `aws_route53_zone` destruction (DNS outage)
- Any `aws_vpc` destruction (takes down everything inside it)
- Any `aws_cloudfront_distribution` destruction with active traffic
- Any resource with `prevent_destroy = true` that would need to be overridden

For hard stops, present the finding clearly and wait for explicit acknowledgment:

> ⚠️ **Destructive action requires confirmation**
> `aws_rds_cluster.aurora` will be **destroyed**. This cluster has no `final_snapshot_identifier` set (`skip_final_snapshot = true`), meaning **no backup will be taken**. This is irreversible. Do you want to proceed?

Do not continue until the user responds with a clear yes.

### 3d — Unexpected changes

If the plan includes changes that the user did not mention as the goal, call them out explicitly:

> ℹ️ **Unrelated change detected:** `aws_ecs_task_definition.bev4w-server` will be updated. This was not part of the stated goal. This may be config drift — confirm this is expected before applying.

---

## Step 4 — Pre-apply alignment check

Before applying, run through this checklist aloud:

- [ ] The plan matches the stated goal for this session.
- [ ] All destructive actions are accounted for and acknowledged.
- [ ] No unexpected resources are changing.
- [ ] The correct AWS profile and var file are in use.
- [ ] If any resource has `prevent_destroy`, the override was intentional and will be reverted after.

If all pass, present a one-line summary and ask for the go-ahead:

> Plan looks clean: 3 creates, 1 update, 0 destroys — all expected. Ready to apply?

If the user says yes, proceed. If anything in the checklist is unresolved, do not apply.

---

## Step 5 — Apply

Run apply with the same flags used for the plan. Never add flags that weren't in the plan (e.g. `-target` changes what gets applied vs. what was planned).

```bash
AWS_PROFILE=<profile> terraform apply -var-file="<path/to/vars.json>"
```

Stream output. Watch for:
- Resources that take unexpectedly long (cert validation, CloudFront deployment, Aurora modifications) — narrate what's happening so the user knows it's not stuck.
- Errors mid-apply — stop, diagnose the root cause, explain it, and propose a fix before retrying. Don't retry blindly.
- Partial applies (some resources succeeded, then error) — note exactly what was and wasn't applied. State is now partially updated.

---

## Step 6 — Post-apply verification

After a successful apply:

1. **Re-run plan** to confirm zero remaining changes. If the plan is not clean, explain the delta.
2. **Spot-check key outputs** relevant to the change — DNS records, certificate status, service health endpoints, etc.
3. **Call out any follow-on actions** needed: manual DNS record creation, cache invalidation, secret rotation, CloudFront deployment wait, etc.

---

## Step 7 — Session summary

After all operations are complete, always produce a session summary. Do this even if the apply failed. This is the closing record of what happened.

### Format

```
## Terraform Session Summary — <date> — <root> (<profile>)

**Goal:** <one sentence — what was being changed and why>
**Var file:** <path>
**Result:** ✅ Applied clean / ⚠️ Applied with warnings / ❌ Failed / 📋 Plan only

---

### Changes Applied

| Action | Resource | Result |
|--------|----------|--------|
| + create | `aws_acm_certificate.this["qa.example.com"]` | ✅ created |
| ~ update | `aws_ecs_service.service` | ✅ updated |
| - destroy | `aws_s3_bucket.old` | ✅ destroyed |

---

### Destructive Actions

List every destroy/replace that occurred, with:
- What was destroyed
- Whether a backup/snapshot existed
- Whether it was expected and acknowledged upfront

If none: "No destructive actions."

---

### Blockers Encountered

Any errors hit during plan or apply, with a one-line root cause and fix for each.
If none: "No blockers."

---

### Verification

| Check | Result |
|-------|--------|
| `terraform plan` post-apply | ✅ No changes |
| `https://endpoint/health` | ✅ 200 |

---

### Follow-on Actions

- [ ] Anything that still needs to happen (manual steps, waits, cleanups, reverts)

If none: "None."
```

**When to produce the summary:**
- After a successful apply — always.
- After a failed apply — summarize what succeeded before the failure, what failed and why, and what state the infrastructure is now in.
- After a plan-only session (no apply) — produce a shorter summary: goal, plan result, key findings, and what would happen if applied.
- If the user explicitly asks for the summary at any point mid-session, produce it for what has been done so far.

---

## General rules for the session

- **Never use `-auto-approve`.**
- **Never use `terraform destroy`** unless the user explicitly asks for a full teardown and confirms the target.
- **Never use `-target`** without explaining that it creates state drift (unapplied resources remain untracked).
- **State operations** (`terraform state rm`, `terraform state mv`, `terraform import`) are as risky as apply — explain what they do before running.
- **`prevent_destroy = true` overrides** must be explicitly discussed and reverted immediately after the apply that required them.
- If a plan output is very large (>200 lines), summarize rather than dumping it all — but always offer the full output on request.
- Keep track of what was planned vs. what was applied within the session. If the user asks to apply something later, cross-reference it against what was already planned.
