# Stella Project Forge

Project Forge is Stella's professional project-development workflow layer.

## Purpose

Project Forge allows Stella to manage projects as small, traceable tasks rather than treating an entire project as one operation.

## Workflow

DISCOVER
PLAN
IMPLEMENT
TEST
REVIEW
STAGE
COMMIT
PUSH
VERIFY
DOCUMENT

## Safety

Local inspection, planning, testing and documentation may run automatically.

Staging, commits, pushes, merges and releases require explicit approval unless a future project policy explicitly authorizes automatic execution.

Force push, hard reset, repository deletion and destructive cleanup are blocked.

## Evidence

Every meaningful operation should eventually record:

- task
- action
- result
- test result
- timestamp
- changed files
- commit
- remote verification
- failure/recovery information

## Principle

Generated output is not considered completed implementation until it has passed the applicable validation workflow.
