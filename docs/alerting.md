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
certificate expires. `sops-install-secrets` is watched because a oneshot that
fails silently leaves a host without credentials until reboot.

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

## Known weakness: alert mail from `ssdnodes-1` fails SPF/DKIM/DMARC

Diagnosis, so nobody re-derives it or "fixes" the wrong thing:

- `rueb.dev` SPF is `v=spf1 ip4:172.93.51.14 -all` — the VPS's public address is
  already authorized.
- Postfix on `ssdnodes-1` relays to Stalwart **over the tailnet**, so Stalwart
  evaluates the connecting IP as `100.64.0.4`, which is not in the record — hence
  `smtp.spf-ehlo-fail` / `smtp.spf-from-fail` / `dkim-fail` / `dmarc-fail` on a
  legitimate local message. It is still delivered (`message-ingest.ham`) because
  DMARC is `p=quarantine` with relaxed alignment.

The mail is not unauthenticated; it is authenticated against an address Stalwart
is not looking at. Options, in increasing order of correctness:

1. Add `ip4:100.64.0.4` to the SPF record — works, but puts carrier-NAT space in a
   public SPF record where it means nothing to every other receiver.
2. Mark `100.64.0.0/10` as a trusted relay in Stalwart so mail from it skips
   authentication checks. Correct semantics; needs the right key for the installed
   version.
3. Submit alerts over authenticated SMTP, so identity comes from auth, not IP.

Deliberately **not** done: alerts are delivered today, and changing public SPF or
the mail server's trust model to silence a warning on a working path is the same
class of low-value risk that caused an outage during that session. If it is
picked up, start from the cause above rather than the symptom.

## See also

- [`docs/secrets.md`](secrets.md) — why `sops-install-secrets` being a oneshot
  matters when triaging a missing secret.
- [`docs/fleet-keys.md`](fleet-keys.md) — the credentials and rotation procedures
  whose failures these guards catch.
