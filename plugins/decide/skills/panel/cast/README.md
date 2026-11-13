# The cast

The people a persona panel brings to a question, a story or a review. This cast is generic: it
knows nothing about the product beyond what the panel brief tells it. Rewrite each file for the
people who actually use, run and pay for the product, and add one for anyone else whose view a
decision turns on.

One file per persona. A file says who the person is, what they want, what they notice and what they
never see. It holds no system internals: the panel brief supplies the evidence.

| Persona | File |
|---|---|
| A person who uses the product | `user.md` |
| The engineer who runs it in production | `operator.md` |
| The engineer who builds the next change on it | `builder.md` |
| The owner who pays for it and answers for it | `owner.md` |

The cast knows nothing about the product. That comes from the project's own profile,
`.personas/profile.md`, which every persona reads before its own file: what the product is, its
scale, its rules and the teams it compares itself with. Each project writes its own, from
`references/profile-template.md` in this skill; no profile is shipped.
