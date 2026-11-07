# Is the answer a durable ruling?

The `jev` spec. `QUESTION` is the question as the user saw it, one or two sentences; `ANSWER` is the
user's choice and their words, verbatim. When the answer points at an option instead of saying
it ("yes", "option 1", "as written"), put that option's text into `ANSWER` after the user's words:
measured 2026-11-07, "Yes, narrowed as written" alone was judged a one-off, the same answer with the
narrowed ruling's text durable. Keep both short; the state stays far under Jev's limit.

```json
{
  "state": "Question put to the project's owner: QUESTION\n\nThe owner's answer: ANSWER",
  "questions": {
    "durable": {
      "instructions": "Decide whether the owner's answer is a durable ruling that later work must follow, or a choice that applies only to the task it was asked in.",
      "choices": {
        "durable": "The answer states a rule, a preference or a principle that would decide similar questions later: how the product should behave, what to never or always do, which convention to follow, whose interest wins in a kind of trade-off.",
        "this_task": "The answer settles one choice inside one task and says nothing about later cases: a size or number for this change, which of two drafts to keep, the order of tasks, a one-off scope call, or approval to proceed."
      }
    }
  }
}
```

A confidence under about 0.6 is close to a coin toss: ask the user in one line whether to record
it, rather than writing a ruling or dropping one.
