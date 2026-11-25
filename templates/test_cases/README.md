# Test cases

Plain-language test cases. A person or an AI agent reads a case, drives the app with the steps,
and checks the expected results. Matching Maestro flows in `maestro/` can automate the same
cases.

## Layout

- One Markdown file per feature area, for example `login.md`, `navigation.md`.
- Each case has a stable ID: `TC-<AREA>-<NNN>`. IDs are never reused.
- Sections in every case: **Preconditions**, **Steps**, **Expected**.
- Controls are named by their test key from `docs/test-keys.md`.

## Running

See [AUTOMATION-TESTING.md](../docs/AUTOMATION-TESTING.md) for setup and the run commands.

Run every step the way a user would, by tapping, from the case's starting page. The agent's
`uiOnly…` shortcuts skip the user path, so a run that uses them has not tested the case. They
are only for checking one page's layout when that is all that was asked.

## Writing a case

1. Give it the next free ID in its area file.
2. Describe only what a user can see or do, never the code.
3. Use test keys for controls. Add a key to the app first if the control has none.
4. Mark cases that are not yet automated with a `> Not yet automated:` note.
5. Use made-up data only. Never put real people's details in a case.
