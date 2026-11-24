# Fixture greeting — design

**Register:** docs/dforge/registers/2026-01-01-fixture.md

## Design

`greet.sh` gains a `--shout` flag that prints the greeting in capitals, and a
new `farewell.sh` prints `Goodbye, NAME!`, NAME defaulting to `world`.

## Acceptance

- A1. `bash greet.sh --shout Ada` prints `HELLO, ADA!`.
- A2. `bash farewell.sh Ada` prints `Goodbye, Ada!`.
