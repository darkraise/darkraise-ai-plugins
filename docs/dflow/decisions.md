# Decisions

Append-only. Each entry states the decision, the reason and what it supersedes.

## D-0001 · 2026-11-12

The weakened-test check ignores files a diff adds: a new test file had nothing to weaken, and fixture text in it must not trip the skip-marker pattern

Source: plans/2026-11-12-dflow-v1.md, Task 2

## D-0002 · 2026-11-12

The dead-path check reads project.md and gotchas.md only; decisions.md is history and may name files that are gone

Source: plans/2026-11-12-dflow-v1.md, Task 3

## D-0003 · 2026-11-12

An unblocked task is sent to darkmem with state todo, so the board stops showing it blocked before work resumes; the contract's task states are todo, wip, review, blocked, done

Source: plans/2026-11-12-dflow-v1.md, Task 6

## D-0004 · 2026-11-12

A worker's prompt is one line naming a brief file the CLI writes, so dispatching a worker costs the session a line instead of a copy of the task

Source: plans/2026-11-12-dflow-v1.md, Task 7

## D-0005 · 2026-11-12

The mod treats only a main-loop turn end as a task boundary: turn.complete also fires for subagent turns, which carry agentId

Source: plans/2026-11-12-dflow-v1.md, Task 10
