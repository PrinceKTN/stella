# Stella Conversational Skill Builder

The user can describe a desired skill in natural language.

Example:

"Stella, create a skill called GitHub Project Monitor.
It should inspect my repositories and tell me when projects need attention.
It must not modify anything."

Stella should convert the request into a structured skill proposal.

Lifecycle:

PROMPT
  ↓
PROPOSAL
  ↓
VALIDATION
  ↓
RISK CLASSIFICATION
  ↓
SANDBOX
  ↓
USER APPROVAL
  ↓
INSTALL
  ↓
DISABLED
  ↓
USER ENABLES

A natural-language request must never directly become unrestricted executable code.

Automatic self-modification is disabled.
Automatic skill enabling is disabled.
Unknown permissions are denied.
Destructive capabilities remain blocked.
