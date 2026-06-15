# Priority & Size Matrix

## Priority Levels

| Priority | Criteria | Examples |
|----------|----------|----------|
| **P0 - Critical** | Production down, data loss/corruption, security breach, all users affected | Auth completely broken, records deleted, sensitive data exposed |
| **P1 - High** | Major feature broken, data integrity risk, most users affected, no workaround | Core pipeline failing, duplicate records created, calculations wrong |
| **P2 - Medium** | Feature degraded but functional, workaround exists, subset of users affected | Slow operation, incorrect status display, export formatting issues |
| **P3 - Low** | Minor inconvenience, cosmetic, edge case, single user affected | UI alignment, rare edge case error, non-critical log noise |

### Priority Signal Checklist

- [ ] Affects production environment?
- [ ] Involves data integrity or correctness?
- [ ] Security or compliance (e.g. PII/GDPR/HIPAA) implications?
- [ ] Has a workaround?
- [ ] How many users/tenants affected?
- [ ] Revenue or compliance impact?
- [ ] Error rate from observability (sporadic vs constant)?

## Size Levels

| Size | Criteria |
|------|----------|
| **XS** | Config change, typo fix, single-line fix with obvious cause |
| **S** | Single file change, clear root cause, no migration needed |
| **M** | 2-5 files, may need migration or test updates, moderate investigation |
| **L** | Multiple modules, migration required, significant refactoring or new logic |
| **XL** | Architectural change, cross-cutting concern, multiple services affected |

### Size Signal Checklist

- [ ] How many files/modules involved?
- [ ] Database migration needed?
- [ ] API contract change?
- [ ] Cross-module dependencies?
- [ ] Test coverage gaps to fill?
- [ ] Infrastructure/config changes needed?
