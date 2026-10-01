# r-plan-inline-mode

Source: defects of the plan's own code that later commits on the same branch had to fix, `2f617e7` and `9092788`; each confirmed in the plan at `69c6b48`.

## D1: the mode switch is detected by an unanchored search of the ledger

- Where: Task 4, the code inserted into `scripts/next-step`, and the matching Plan state prose in the executing-plans skill text
- Defect: the plan's code finds the switch with `grep -n 'escalated inline -> subagent'` and the return with `grep -n 'implementer inline'`, anywhere in any ledger line. A ruling, a parked finding or a checkpoint that merely mentions either phrase is read as a mode switch or as a return to inline mode, so `next-step` prints the wrong launch command.
- Evidence: `2f617e7` anchors both patterns to the start of a `Task <N>:` line and its exact form; the faulty lines are at plan lines 1121 and 1123.
- Minimum severity: Important

## D2: next-step tells the next session to start a task the ledger marks BLOCKED

- Where: Task 4, `scripts/next-step`
- Defect: the plan's skill text makes a `BLOCKED` ledger line terminal, a stop only a human resolves, but the plan's `next-step` changes never read `BLOCKED` lines, so the resume guide it writes launches the next session straight at the blocked task.
- Evidence: `9092788` adds `ledger_blocked`, a status line naming the blocked task, and no launch command; `scripts/next-step` at `69c6b48` and the plan's code for it do not mention `BLOCKED`, while the skill text at plan line 485 calls it terminal.
- Minimum severity: Important
