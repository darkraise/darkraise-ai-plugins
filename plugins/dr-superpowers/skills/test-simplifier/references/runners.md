# Runner reference

Flags for dr-superpowers:test-simplifier, by ecosystem. Check each against the
project's installed versions before relying on it; prefer a tool the project
already uses over adding one.

## JUnit XML for `test-profile`

| Runner | Flag or setting |
|---|---|
| pytest | `--junitxml=reports/junit.xml` |
| Jest | `jest-junit` reporter: `--reporters=default --reporters=jest-junit` |
| Vitest | `--reporter=junit --outputFile=reports/junit.xml` |
| Playwright | `--reporter=junit` with `PLAYWRIGHT_JUNIT_OUTPUT_NAME` |
| Go | `gotestsum --junitfile reports/junit.xml` |
| Rust | `cargo nextest run` with a `[profile.ci.junit]` path |
| JVM (Maven, Gradle) | written by default under `target/surefire-reports/`, `build/test-results/` |
| .NET | `dotnet test --logger "junit;LogFilePath=reports/junit.xml"` (JunitXml.TestLogger) |
| PHPUnit | `--log-junit reports/junit.xml` |

## Finding slow setup

- pytest: `--durations=30 --durations-min=1.0` lists setup and teardown apart
  from the call.
- Jest: `--verbose` prints per-test time; `--logHeapUsage` shows leaks that slow
  later files.
- A large "suite time outside any case" in `test-profile` points at
  suite-level fixtures, container start-up, or a global setup file.

## Parallel and sharded runs

pytest-xdist `-n auto --dist loadscope`; Jest `--maxWorkers`, `--shard=i/n`;
Vitest `--shard=i/n`; Playwright `--workers`, `--shard`; Go runs packages in
parallel by default (`-p`); cargo-nextest is parallel by default; Gradle
`maxParallelForks`; Maven Surefire `forkCount`.

## Impact selection for the inner loop

| Tool | Selects |
|---|---|
| pytest-testmon | tests whose recorded coverage touches changed code |
| `jest --changedSince=<base>` / `--onlyChanged` | tests importing changed files |
| `vitest --changed <base>` | the same, for Vitest |
| `nx affected -t test` | projects downstream of the change |
| bazel-diff, target-determinator | Bazel targets downstream of the change |
| `go test` on changed packages and their importers | `go list -deps` gives the graph |
| Gradle build cache with `--continue` | skips tasks whose inputs did not change |

Selection serves the inner loop only. The branch gate and full sweep still run
what they declare, which is what catches a dependency the selector missed.

## Mutation tools

Scope every run to the wave's module.

| Ecosystem | Tool | Scope flag |
|---|---|---|
| JavaScript, TypeScript | StrykerJS | `--mutate 'src/<module>/**/*.ts'`, `--incremental` |
| JVM | PIT | `-DtargetClasses=<package>.*`, `-DwithHistory` |
| Python | mutmut | `paths_to_mutate` in `setup.cfg` or `pyproject.toml` |
| Python | cosmic-ray | the `module-path` in its config |
| Rust | cargo-mutants | `-f <file>`, `--in-diff` |
| Go | gremlins, go-mutesting | the package path |
| .NET | Stryker.NET | `--mutate` |
| PHP | Infection | `--filter=<path>` |
| Ruby | mutant | the subject expression, e.g. `'MyApp::Price*'` |

Count `Killed` and `Timeout` as caught on both sides of a comparison.
`NoCoverage` and `Survived` before the wave are not losses: the wave only has
to keep what was caught. Keep the configuration, test command and seed
identical between the before and after runs.
