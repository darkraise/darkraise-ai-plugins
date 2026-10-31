## The three Step 1 forms

Step 1 takes one of three forms.

The first, `- [ ] **Step 1: Write the failing test**`, is for a behaviour no
existing or planned test reaches.

The second, ``- [ ] **Step 1: Extend the test `<file>::<name>`**``, is for a
variant of a behaviour already tested, or new behaviour that belongs in an
existing test. The step gives the added row, case or assertion in full, and
it must fail before the implementation, as a new test would. Steps 2 and 4
run that test.

The third, ``- [ ] **Step 1: Covered by Task <N>'s test `<name>`**``, applies
only for a task that adds no new observable behaviour: wiring, extraction or
configuration whose result an earlier task's test exercises end to end. A
task that adds behaviour uses Extend. The step names the fault in this task's
code that the test would catch. The task has no step that writes its own
failing test, and its verification runs the covering test. The plan reviewer
judges such a task's Executability by the named fault. plan-lint fails a
`Covered by Task <N>` when Task `<N>` does not exist, has no test step of its
own, or does not run before the citing task.

Plan tests per behaviour: one test per acceptance statement or behaviour, at
the lowest layer that can fail for it, rather than one per task.
