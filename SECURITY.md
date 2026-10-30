<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Security Policy

The canonical disclosure policy is the protocol specification's
[Disclosure Policy](https://gitlab.com/vauchi/spec/-/blob/main/src/disclosure.md)
page. This file is a pointer to it; where the two differ, the
specification's page wins.

## Reporting a Vulnerability

Write to **security@vauchi.app**. Do not open a public GitLab issue
for a vulnerability. Encrypt to the project's PGP key,
[pgp-key.txt](https://vauchi.app/.well-known/pgp-key.txt), fingerprint
`4347 B1C6 57A3 97E5 206E 4709 A84E 1AAB D783 0274`; `security.txt`
carries the same fingerprint, so you can check one against the other.
Only the maintainer's hardware tokens can decrypt. If you cannot use
PGP, write in clear and say so; the reply offers another channel.

Send what you found, how to reproduce it, which security claim it
breaks if it maps to one (the
[claims page](https://gitlab.com/vauchi/spec/-/blob/main/src/claims.md)
numbers them S1 to S17), and whether you want to be named.

What to expect: an acknowledgment within 48 hours, an initial
assessment within 7 days, and a fix credited if you wish. There is no
bug bounty.

Scope, safe harbour and what the design promises are on the
specification's page and its claims page.
