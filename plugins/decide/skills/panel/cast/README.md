# The built-in cast

The people a persona panel brings when neither the project (`.personas/cast/`) nor the user
(`~/.config/personas/cast/`) has a cast of its own. They are generic on purpose: they know nothing
about the product beyond what the panel brief tells them. A card or review they answer says so on
its persona line, so a reader knows generic people answered.

A project gets a cast of its own by running `scripts/cast.py init`, which copies this one into
`.personas/cast/`, and then rewriting each file for the people who actually use, run and pay for
that product.

One file per persona. A file says who the person is, what they want, what they notice and what they
never see. It holds no system internals: the panel brief supplies the evidence for each option.

| Persona | File |
|---|---|
| A person who uses the product | `user.md` |
| The engineer who runs it in production | `operator.md` |
| The owner who pays for it and answers for it | `owner.md` |
