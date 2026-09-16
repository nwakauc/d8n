# D8N Quality Gates and Definition of Done

## Layered gates

1. **Architecture:** one explicit D8N domain owner; shared capability considered first; brand policy/configuration used; no duplicate capability or “empire inside kingdom”; abstraction is justified. ADR/specification triggers pass before `IMPLEMENTING`.
2. **Implementation:** correct invariants, transactions, concurrency, idempotency, failure handling, soft deletion, tenant ownership, and observability/error surfacing. Scheduled or recurring jobs require retry and idempotency review.
3. **Tests:** meaningful unit/domain, request/API, integration, regression, authorization-denial, cross-brand isolation, persistence/reload, failure/error-path, and contract coverage as applicable. Test adequacy is reviewed against risk; tests must assert behavior, not merely execute code. Number of passing tests is not proof of correctness.
4. **Security/privacy:** authentication, authorization, brand isolation, PII, sensitive verification/media access, abuse/rate limits, auditability, and safe logging reviewed.
5. **Behavioral parity:** compare with actual Date9ja source behavior; preserve semantics unless explicitly approved.
6. **Independent review:** significant work reviewed by someone other than the builder.
7. **Product acceptance:** relevant journey in `FEATURE-PARITY-ACCEPTANCE.md` passes.
8. **Migration/data:** where applicable, counts, relationships, media, rerun/idempotency, and zero unexplained loss/orphans/duplicates pass.

Risk determines evidence depth. Reviewers may mark a check `N/A` only with a short reason. Applicable work must demonstrate authorization denial, cross-brand isolation, persistence after reload, failure behavior, regression behavior, and preservation of Date9ja behavior. Use the existing performance guardrails in [`docs/architecture/performance-guardrails.md`](../architecture/performance-guardrails.md).

## Definition of Done

- [ ] Correct D8N domain ownership
- [ ] Existing shared capability extended where appropriate
- [ ] No unnecessary Date9ja-specific fork
- [ ] Brand policy/configuration used appropriately
- [ ] Intentional public/domain contracts defined
- [ ] Data model and database invariants correct
- [ ] Authorization, privacy, and error semantics defined
- [ ] Idempotency/concurrency considered where applicable
- [ ] API contract tested
- [ ] Applicable unit/domain, request/API, integration, and regression tests added
- [ ] Existing relevant tests remain green
- [ ] Static/style checks pass
- [ ] Security checks pass where relevant
- [ ] Date9ja behavior and edge cases verified
- [ ] Documentation updated
- [ ] Independent review completed and findings resolved
- [ ] Relevant acceptance journey passes
- [ ] Migration reconciliation passes where applicable
- [ ] Observability, error surfacing, and scheduled-job behavior reviewed where applicable

Document justified `N/A` items; do not manufacture meaningless tests. A capability is complete only at `PARITY_ACCEPTED`, not merely when code exists or tests pass.

## Verification evidence

Every significant handoff must state exact commands/suites, results and counts where useful, acceptance scenarios exercised, known untested surfaces, and any environment limitations. Use `NOT VERIFIED` when evidence was not obtained. Never fabricate production or staging evidence.

## Canonical command recommendation

The repository currently documents separate baseline commands; no `bin/quality` wrapper is being introduced in Phase 1.0. Run the applicable existing commands: `bin/rails test`, `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bin/rubocop --no-server`, `bin/brakeman --no-pager`, `bundle exec bundle-audit check --update`, `bin/rails zeitwerk:check`, and `bin/rails test test/contracts/openapi_contract_test.rb`. The existing CI workflow remains the integration reference. Reconsider a wrapper after Wave A when real runtime tiers are known.
