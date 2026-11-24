# Alerting

How the fleet reports that something failed, what it watches, and the one known
weakness in the path. Harvested from the October 2026 rotation session, where the
thing being rotated was fine and the **backup that had silently stopped running**
was the actual incident.

## `rueb.failureMail`

`nix/machines/_common/base/failure-mail.nix` defines a `failure-mail@` template
unit that mails a `systemctl status` plus a journal excerpt to `r3v2@rueb.dev`.

It is **opt-in per machine and per unit**: systemd has no global `OnFailure`, so a
watched unit gains `OnFailure = [ "failure-mail@%n" ]`. That is deliberate — a
laptop that briefly loses a mount should not send mail.

A watched unit also gains `OnSuccess = [ "failure-mail-clear@%n" ]`, and the alert
script records a marker under `/var/lib/failure-mail`. Together they make the
contract **once per outage**: the first failure mails, further failures of the same
unit are suppressed for `rueb.failureMail.cooldown` (24h by default), and a clean
run clears the marker so the next outage mails immediately. Without the cap, a unit
on a six-hour timer mails every single run of a week-long outage. A send that fails
does not write the marker, so the next failure still gets out.

One systemd trap before editing the template: `%i` is expanded in unit-file
directives only, never inside the file `ExecStart` points at, and it strips the
`.service` suffix on the way through the instance name. The failing unit is
therefore passed as an argument and the suffix re-appended.

Transports differ by host:

- `ssdnodes-1` uses its postfix `sendmail` wrapper.
- `homeserver` has no mailer, so it submits to Stalwart over loopback with `msmtp`.
  Local `rueb.dev` mail never touches the SMTP2GO outbound route.

### What is watched

| Host | Units |
|---|---|
| `ssdnodes-1` | `matrix-snapshot`, `continuwuity`, `sops-install-secrets`, every `acme-order-renew-*` |
| `homeserver` | `matrix-backup`, `matrix-backup-freshness`, `hosted-sites-backup`, `hermes-backup`, `headscale`, `sops-install-secrets`, every `acme-order-renew-*` |

ACME renewal is watched because a failed renewal is otherwise invisible until a
certificate expires.

## The `sops-install-secrets` unit is not a health signal

`sops-install-secrets.service` is listed on both hosts and **does nothing**: secret
installation is not a unit here, it runs inside the activation script, and the unit
under that name carries only the `OnFailure=` line this module adds. With no
`ExecStart=` systemd marks it `bad-setting` and refuses to start it, so the watch
cannot fire. A failed install at deploy time is still loud (the activation fails
and `nup-fleet` reports it); a failed install at boot is not, and that gap is open.
The fix is either to drop those two entries or to assert that every watched unit
exists and is startable — see rueb/systems#36 notes.

Adding a watch is one line, and the failure mode of *not* adding one is a job that
stops running and nobody notices for weeks.

## Freshness must be a proof of run, not an mtime

`matrix-backup-freshness.service` fails when `ssdnodes-1`'s
`/srv/matrix/.snapshot-success` marker is older than 18h (three missed 6h runs).
The marker is written only after both rsyncs complete.

Two distinctions that matter, both earned the hard way:

- **mtime cannot tell fresh from frozen.** An idle Matrix server legitimately
  produces unchanged files, so mtime staleness cries wolf; a copy command that
  exits 0 says nothing about whether there was anything new to copy.
- **Freshness checking is a separate unit from the backup itself**, so an alarm can
  fail loudly without ever being in a position to skip a real backup.
- **A run can complete and still be worthless.** When the admin-room trigger that
  asks Continuwuity for a checkpoint is refused, `matrix-snapshot` mirrors the
  media and the last good checkpoint anyway and writes `.snapshot-degraded` beside
  the run marker; the freshness unit fails on that file. Aborting the run instead
  is what turned a dead admin token into a full backup outage in November 2026
  (rueb/notes#1088): the token failure cost the media mirror too, and the marker
  never advanced.

## Verify by negative test

The guards above were tested by making them fail on purpose:

| Test | Expected |
|---|---|
| marker missing | freshness `rc=1` |
| marker 30 days old | freshness `rc=1`, message names the broken job |
| marker fresh | `rc=0` |
| force a unit failure | `failure-mail@…` `Result=success` and a `delivery.completed` for the alert in Stalwart's log |

A happy-path-only test shipped three bugs in the first draft of this:
`systemd.services` keys omit `.service` (so the first version watched
`matrix-snapshot.service.service` and alerted on nothing), `%n` already includes
the suffix, and Stalwart rejects a non-FQDN EHLO with `550 Invalid EHLO domain`.

## Alert mail submits to Stalwart's internal listener (port 2525)

History: fleet alert mail used to be submitted to Stalwart's MX listener on
port 25 over the tailnet. Stalwart evaluated the connecting IP (a CGNAT
tailnet address) against the sender domain's public SPF record, so every
alert scored `SPF_FAIL`/`DMARC_NA` and landed in Junk. The public SPF record
(`v=spf1 ip4:172.93.51.14 -all`) authorizes only the VPS's public address,
and putting carrier-NAT space in it would mean nothing to real receivers.

Fix: Stalwart listens on an additional internal SMTP port (2525, tailnet-only
in the firewall). Stalwart's own defaults already skip SPF/DMARC/IPrev
verification on any port other than 25; two settings keys complete the
exemption (`session.auth.require` and `session.data.spam-filter` both key on
`listener == 'internal'`). All fleet submitters (Alertmanager, Gatus, msmtp
on homeserver/ssdnodes-1, CI runner mail) point at 2525.

Deploy order: homeserver first. Every submitter flips to 2525 in the same
fleet rollout, and a host that flips before homeserver binds 2525 loses its
alert path silently in the gap (failure-mail has no feedback loop when its
own transport is down). Switch homeserver with `nixos-rebuild --target-host`
first, verify 2525 answers, then the submitters.

The exemption keys on the **listener**, never on the source IP. That matters
because legitimate public mail also arrives from the tailnet — the
`ssdnodes-1` MX relay forwards to Stalwart on port 25 — and that path keeps
full SPF/DKIM/DMARC verification and spam filtering.

## CI notifications

CI reports failures two ways (behavior is in [CI](ci.md)):

- **Matrix / Hermes.** Both workflows POST a signed JSON body to the Hermes
  `matrix-notify` route (HMAC-SHA256 over the body). A passing PR check stays
  silent; the nightly reports every outcome.
- **Email.** The nightly mails `r3v2@rueb.dev` with the per-machine results and
  the tail of the deploy log, via `msmtp` configured by
  [`ci-alert-mail.nix`](../nix/machines/forgejo-ci-runner-vm/services/ci-alert-mail.nix).
  A cancelled run is not mailed.

## See also

- [CI](ci.md) — the two workflows and how they deploy.
- [`docs/secrets.md`](secrets.md) — how secrets are actually installed, and why
  the `sops-install-secrets` unit is not a health signal.
- [`docs/fleet-keys.md`](fleet-keys.md) — the credentials and rotation procedures
  whose failures these guards catch.
