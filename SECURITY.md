# Security policy

## Reporting a vulnerability

Please report security problems privately using the repository host's private
vulnerability reporting (for example, GitHub's **Security › Report a
vulnerability**), not a public issue. Include steps to reproduce and the affected
version. You'll get a reply as soon as possible, and credit if you'd like it.

## Scope

Especially interesting:
- anything that lets an extension or imported `.stitchyext` file run code, read
  local files, send data, or reach a host the user didn't configure;
- secrets (tokens, Keychain items) leaking into files, exports or logs;
- lock screen windows receiving keystrokes or exposing content while locked;
- permission prompts appearing without a user action.

## Design notes

Stitchy's security model is described in [Privacy](docs/PRIVACY.md) and in the
[Extensions security model](docs/EXTENSIONS.md#security-model).
