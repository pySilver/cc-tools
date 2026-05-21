---
name: web-research
description: Researches topics online via web search and page fetching. Use whenever current external information is needed — when the user asks to research, look up, investigate, compare options, find documentation, fact-check, or get details beyond the codebase or training data.
model: claude-opus-4-6[1m]
allowed-tools: WebSearch, WebFetch, Read, Bash(gh *)
---

# Web Research

Ground answers in current, citable sources. The skill assumes the model already
knows how to think — it provides ordering, source-quality heuristics, and
reporting expectations only.

## Workflow

1. **Scope the question.** If genuinely ambiguous, ask one targeted question. Skip
   clarification when the topic is self-contained (a specific library version,
   a named API, an identifiable product).
2. **Search.** Use `WebSearch` with precise terms. Run multiple queries in parallel
   when investigating distinct angles or comparing alternatives.
3. **Fetch primary sources.** Use `WebFetch` with a focused extraction prompt — pull
   only the slice you need, not the whole page. For GitHub URLs prefer `gh` (e.g.
   `gh api`, `gh pr view`) over `WebFetch`.
4. **Cross-check claims that matter.** Versions, security advisories, prices,
   breaking changes, current state of an API — one source is a lead, two
   corroborating sources is a fact.
5. **Cite sources inline** in the final answer so the user can verify.

## Source quality

Prefer in this order:

- Official documentation, RFCs, standards bodies, vendor security advisories
- Project repositories, release notes, changelogs, issue trackers
- Reputable engineering blogs, conference talks, well-cited papers
- Stack Overflow / GitHub issues for symptom-driven debugging questions
- News outlets only when the question is genuinely news-driven

Discount AI-generated content farms, undated tutorials, SEO aggregator sites,
and any source that cannot be tied to a person, org, or date.

## Library docs: prefer Context7

For library/framework documentation (React, Django, FastStream, Vespa, anything
imported in the codebase), the project ships Context7 MCP. Use
`mcp__plugin_context7_context7__resolve-library-id` followed by `query-docs`
instead of a generic web search — version-accurate docs return faster and
without summarisation drift.

Fall back to `WebSearch` only when Context7 has no entry for the library or the
question is about something Context7 does not cover (release notes, security
advisories, community discussion, blog posts).

## Reporting

Keep the answer focused on what the user asked. Default structure:

- **Direct answer** — one or two sentences resolving the question.
- **Evidence** — relevant findings, each tied to a source URL.
- **Caveats** — outdated info, conflicting sources, gaps in coverage.

Do not narrate the search process. The user wants the answer, not a transcript
of how you found it.
