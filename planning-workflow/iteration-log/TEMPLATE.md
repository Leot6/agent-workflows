# <id> — <one-line hook>

- **source**: topic alias + rounds (member obs ids) — public text: the mechanism,
  never the project (A§11); no names, paths or delivered-repository SHAs
- **observation**: what the workflow did/failed to do, as seen (diagnosis-free)
- **suspected mechanism**: the one-line hypothesis of WHY
- **falsifiable expectation**: REQUIRED — what future event proves/disproves the
  hypothesis; an entry without one is a landfill contribution, not an observation
- **anchors**: count + where seen (rounds, obs ids, file:line); a second
  INDEPENDENT anchor is the promotion trigger (A§11)
- **state**: open | adopted (mechanism landed in-tree; INDEX cites the landing
  commit) | landing ordered (owner-ruled batch in flight) | closed
- **topics elapsed**: integer; `REMOVAL_TOPICS` without a second anchor ⇒ retire
  to the INDEX line (git holds this file's text)

State-file rule: closed entries DELETE this file and keep one INDEX line;
prune at harvest, never mid-topic.
