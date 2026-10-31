# Pictures of docs/port/midi-actions-plan.md

Both are **stand-ins** (the page was built afterwards and differs: see section 9 of the plan, the real list has no group names and the walk has no progress bar): the real window and box (pixel style, DARK look, headless: Xvfb, dummy jackd) with the screen drawn by a throw-away function through the real screen API and font, cropped to the screen. The rows, wording and numbers are the proposal.

| file | what it is |
|---|---|
| `actions-list-standin.png` | the ACTIONS list, the PAGES group, TAPE selected |
| `actions-walk-standin.png` | the ASSIGN ALL walkthrough at the third of 14 actions |
| `draw_list.lua`, `draw_walk.lua`, `standin_page.lua` | what made them (`linux/tests/norns_probe.sh docs/port/midi-actions-previews/standin_page.lua`; not part of the product or of `run_all.sh`) |
