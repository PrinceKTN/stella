# Stella

**A modular, resource-aware AI assistant designed to grow across devices,
models, tools, and execution environments.**

Stella is an open development project focused on building an assistant that
can work with available local capabilities, connect to configurable AI
providers, and gradually gain reliable tools for everyday tasks and
professional workflows.

The project prioritizes modularity, low-resource devices, explicit
permissions, provider flexibility, and incremental testing.

> **Development status:** Early development. Features, interfaces, and
> installation procedures must be verified against the current code.
> A feature appearing in the repository is not proof that it is production-ready.

## Vision

Stella aims to become a flexible assistant that can:

- Use configurable AI providers through replaceable adapters.
- Provide useful local capabilities when an online model is unavailable.
- Work within the resources and permissions of the current device.
- Support reusable skills, tools, and task workflows.
- Separate planning, execution, verification, and reporting.
- Support development across phones, laptops, and future environments.
- Protect credentials, user data, and important system operations.
- Let contributors build and test individual modules independently.

These are project goals, not a claim that every capability is already implemented.

## Current development areas

The current working tree includes early work in these areas:

| Area | Current scope |
|---|---|
| Terminal interface | Changes to the interactive terminal launcher |
| Brain and provider resolution | Initial brain-related scripts and configuration example |
| Local answering | Initial local-answer capability |
| Local file access | Initial local-file capability |
| Gate 1 installer | Initial installation/setup script |

These components require code review and testing before they can be considered stable.

## Architecture principles

1. **Modular:** Components should have clear responsibilities and interfaces.
2. **Provider-independent:** Core logic should not depend permanently on one AI vendor.
3. **Resource-aware:** Choose workloads that fit the available device and network.
4. **Offline-aware:** Local capabilities should remain useful where practical without
   internet access.
5. **Permission-based:** File access, commands, network operations, and other
   sensitive actions should have explicit boundaries.
6. **Test before release:** Experimental changes must pass relevant checks before
   being promoted to the stable branch.
7. **Human-approved upgrades:** Proposed changes should be reviewed and tested
   before they modify the approved core.

## Requirements

Requirements depend on the component being used. Stella is being developed with
resource-constrained devices in mind, but individual features may require
additional software, storage, memory, or network access.

Before installing, inspect the relevant installer and configuration examples.
Do not assume every component works on every supported device.

## Getting started

### Clone the repository

```bash
git clone https://github.com/PrinceKTN/stella.git
cd stella
```

### Inspect the project

```bash
git status --short --branch
git branch -a
find . -maxdepth 3 -type f -not -path './.git/*' | sort
```

Review the installer and its dependencies before executing it. Installation
instructions will be expanded as the setup process is verified on supported
devices.

### Configuration and secrets

Use example configuration files as templates. Keep real credentials in local,
untracked configuration or an appropriate secret store.

**Never commit API keys, access tokens, passwords, private keys, personal data,
or private logs.** Do not paste secrets into issues or pull requests. Rotate any
credential that has been accidentally published.

## Development workflow

Stella uses a review-first contribution process.

- `main`: approved, stable project history.
- `lab`: integration and testing work.
- Feature branches: isolated changes for individual capabilities or contributors.

Recommended workflow:

1. Start from the latest approved `main`.
2. Create a dedicated branch for one feature.
3. Make a small, clearly scoped change.
4. Run relevant tests and inspect the complete diff.
5. Document limitations, dependencies, and test results.
6. Open a pull request for review.
7. Merge into `main` only after the change is approved.

AI coding agents may help with individual tasks. Their output must be reviewed,
tested, and checked for secrets and unsafe behavior before it is accepted.

## Commit message convention

Use descriptive, imperative commit messages with a subsystem scope.

Examples:

- `docs: add project overview and contribution workflow`
- `feat(brain): add provider resolution foundation`
- `feat(capabilities): add local answering interface`
- `feat(capabilities): add local file operations`
- `feat(cli): improve terminal assistant interface`
- `feat(installer): add initial Gate 1 setup`
- `test: add checks for brain and local capabilities`
- `fix(installer): handle missing dependencies safely`

Use `feat`, `fix`, `docs`, `test`, `refactor`, or `chore` according to the
actual change. Do not claim tests passed unless they were run successfully.

## Testing and release status

Tests must be run for the affected components before release. Record the
commands used, the result, and any known limitations.

Until the relevant checks have passed, new modules should be treated as
experimental. A successful commit or GitHub push does not itself establish
that a feature works correctly.

## Roadmap

The intended direction is to develop these areas incrementally:

- [ ] Verify the initial installer and terminal interface.
- [ ] Define and test the brain/provider interface.
- [ ] Test local answering and local file capabilities.
- [ ] Establish repeatable tests and a documented release process.
- [ ] Introduce isolated feature branches and integration testing.
- [ ] Improve permission controls, secret handling, and audit logs.
- [ ] Expand provider adapters and resource-aware execution.
- [ ] Develop additional device, workflow, and automation capabilities.

Roadmap items are proposals until implemented and verified.

## Contributing

Contributions should be small, documented, and independently testable.
Please include:

- The problem being solved.
- The files and interfaces changed.
- Dependencies and setup requirements.
- Tests performed and their results.
- Known limitations and security considerations.

Avoid mixing unrelated features in one change.

## License

Check the repository's license before redistributing or reusing the project.
A license should be added explicitly once the project's intended terms are
decided. Do not assume that public availability automatically grants permission
to reuse the code.

## Repository

https://github.com/PrinceKTN/stella
