# issue-ops

Turn inputs into well-structured GitHub issues. Two skills:

| Skill | What it does | Trigger |
|-------|--------------|---------|
| `bug-rca` | Bug triage & root-cause analysis (diagnosis only — never edits code). Fetches the issue, analyzes the codebase, optionally queries whatever observability backend is connected, synthesizes an RCA, sets priority/size, and updates the issue. | "analyze bug #N", "triage issue #N" |
| `spec-to-issues` | Converts a spec/PRD into an Epic→Spec→Task GitHub issue hierarchy with acceptance criteria, sizes, and blocked-by/blocking links. Detects the spec layout (OpenSpec, single PRD, or generic docs folder). Dry-run preview before creating. | "create issues from this spec", "convert spec to issues" |

## Install
```bash
/plugin install issue-ops@claude-plugins
```

## Dependencies
- **Required:** the GitHub CLI (`gh`, authenticated) and `git`. `spec-to-issues` uses GitHub's GraphQL API
  (issue types, projects, sub-issues).
- **Optional:** `bug-rca`'s observability phase uses whatever monitoring MCP is connected (GCP Cloud
  Operations, Datadog, Sentry, CloudWatch, …). With none connected, it skips that phase and works from the
  issue's logs + code analysis. Priority/Size are written to a GitHub Project if one exists, otherwise as
  `priority:Px` / `size:XX` labels.

`bug-rca` is **diagnosis-only**: it writes findings to the issue and never modifies source files.
