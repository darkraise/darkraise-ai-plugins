# CI parity

A plan names the project's CI jobs, the commands this host can run from them,
and the CI platforms this host does not cover. This file says how to find
those, and lists what breaks on each uncovered platform.

## Finding the CI configuration

Look for the CI configuration in this order: `.github/workflows/*.yml` first,
then `.gitlab-ci.yml`, `azure-pipelines.yml`, `.circleci/config.yml`. The
first configuration found is the project's CI. When several workflow files
exist under `.github/workflows/`, read every one. When none of these files
exists, the project has no CI, and the plan's CI line is `none`.

## Reading jobs, platforms and commands

Read each job's platform from its configuration:

- GitHub Actions: `runs-on`, with each matrix value expanded into its own
  platform.
- GitLab CI: the job's `image`, or its runner `tags`.
- Azure Pipelines: `pool.vmImage`.
- CircleCI: the job's executor.

Map each platform to a Platform name of the Pitfalls table below. A
`windows-*` image is `Windows Git Bash`. A `macos-*` image is `macOS`.
`ubuntu-latest` is `uutils (ubuntu-latest)`. Any other image, such as
`ubuntu-22.04`, has no row and is never listed under `uncovered:`, which
names only Platform-column names.

Read the local platform with `uname -s`. `Linux` is a GNU Linux host.
`Darwin` is macOS. `MINGW*` or `MSYS*` is Git Bash on Windows.

A platform is uncovered when the host running dforge is not that platform.
The host covers `uutils (ubuntu-latest)` only when `cp --version` names
uutils.

Read the commands from each job's `run:` or `script:` steps. Keep the lines
that test, validate or build, and that this host can run without secrets or
services. Drop checkout, setup, install, cache and upload steps. List a
command once, however many platforms run it. A multi-line block gives one
command per test or validation line.

Note whether the workflow's `on:` declares `workflow_dispatch`. Only such a
workflow can be started early.

## Pitfalls

Each row names one platform, one fact that breaks a script there, and one
remedy.

| Platform | Pitfall | Do instead |
|---|---|---|
| Windows Git Bash | A native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). | Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`. |
| Windows Git Bash | The same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. | Normalise both sides with `cygpath -m`, or compare with `-ef`. |
| Windows Git Bash | Files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. | Pipe through `tr -d '\r'` before comparing or parsing. |
| Windows Git Bash | `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. | Pass the value in the environment and read `ENVIRON["NAME"]`. |
| Windows Git Bash | Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. | Import with `import(pathToFileURL(path).href)`. |
| macOS | BSD `sed -i` requires a suffix argument, so GNU's `sed -i 's/a/b/' file` fails. | Write a temporary file and `mv` it over the original. |
| macOS | BSD `date` has no `date -d`. | Use `date -r <epoch>` for epoch input, or compute the value in awk or Node. |
| macOS | BSD `readlink` lacks `readlink -f` before macOS 12.3. | Resolve the directory with `cd "$(dirname "$p")" && pwd -P`. |
| uutils (ubuntu-latest) | A lock built on `mkdir` failing when the directory exists does not exclude a second process. | Create the lock file with `set -C` (noclobber), or use `flock`. |
| uutils (ubuntu-latest) | `timeout` signals only the command it started, so the command's children keep running. | Run the command in its own process group (`setsid`) and signal the group. |
