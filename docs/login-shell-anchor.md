# Login shell anchoring (`homeserver`)

`rueb.loginShellAnchor` keeps the login shell reachable when a data pool is
suspended. It exists because of [rueb/notes#1023](https://code.rueb.dev/rueb/notes/issues/1023):
on 2026-11-19 `tank` suspended for 19 hours and, from outside, the outage looked
like "SSH is down" — the host answered ping, `sshd` was running, and every
session hung after the `Last login` banner.

Two units, both defined in
[`nix/machines/_common/services/login-shell-anchor/default.nix`](../nix/machines/_common/services/login-shell-anchor/default.nix):

| Unit | Role |
| --- | --- |
| `login-shell-anchor-migrate.service` | One-shot: moves the checkout the dotfiles come from off the pool onto `zroot`. Self-limiting via `ConditionPathIsSymlink`, so it is a no-op once the flip has happened. |
| `login-shell-anchor-check.service` + `.timer` | Proves the invariant every 10 minutes and pages through [`rueb.failureMail`](alerting.md) when it breaks. |

## 1. Why a suspended pool kills SSH

fish reads `~/.config/fish/conf.d/*.fish` and `~/.config/fish/config.fish` on
**every** startup — [the docs](https://fishshell.com/docs/current/index.html) are
explicit that this happens "whether interactive and/or if they're login shells" —
so `ssh host 'somecommand'` runs them too. On top of that,
[`fish_add_path`](https://fishshell.com/docs/current/cmds/fish_add_path.html)
normalises its arguments with `realpath`, and `config.fish` calls
`fish_add_path ~/bin`.

On `homeserver` both of those paths led onto `tank`:

```text
~/.config/fish -> ~/code/systems/dotfiles/.config/fish/
~/bin          -> ~/code/systems/dotfiles/bin/
~/code         -> /tank/Shares/rueb/code/        # the Samba share
```

When a ZFS pool suspends, in-kernel operations on it wait indefinitely — there is
no timeout and no `EIO` to fail on. So `open()` on `config.fish` and `realpath()`
on `~/bin` sat in **uninterruptible sleep (D state)**, which means they survived
`SIGKILL` and could not be interrupted by anything short of the pool coming back.
Every shell `sshd` spawned died the same way, which is why the box looked
unreachable rather than unhealthy.

The fix is not to make fish resilient; it is to make sure the login shell never
touches the pool in the first place.

## 2. What the migration does

`~/code` stops being one symlink onto the share and becomes a real directory on
`zroot` holding **one symlink per entry** in the share — except `systems`, which
becomes a real copy:

```text
before                                   after
~/code  -> /tank/Shares/rueb/code/       ~/code/            (real, on zroot)
  ~/.config/fish -> ~/code/systems/...     ~/code/ansible    -> /tank/.../ansible
  ~/bin          -> ~/code/systems/...     ~/code/systems    (real, on zroot)
                                           ~/.config/fish -> ~/code/systems/...  (unchanged)
```

No path anyone types changes, and every other repo in the share keeps the path
it already has. The dotfile symlinks are not touched at all — they keep pointing
at `~/code/systems/...`, which now resolves inside `zroot`.

Properties worth knowing:

- **Nothing is deleted.** The pool keeps its copy of the checkout; it just stops
  being the one the home directory points at. The old `~/code` symlink is parked
  at `~/code.pre-anchor` as the undo.
- The copy is `cp -a`, so `.git`, `.jj` and any uncommitted work come along.
- The flip is two `mv -T` renames inside one dataset, so the window where
  `~/code` does not exist is a couple of syscalls rather than a copy.
- The unit runs **as the account**, not root: `~/.config` is `0700`, and
  everything it writes should already be owned by the person who owns it.
- If the post-move check fails, the migration rolls itself back and fails the
  unit, so a half-done flip cannot go unnoticed.

## 3. Why the check cannot hang

The check is the part that has to be careful: a naive `realpath ~/.config/fish`
or `test -e ~/bin` would follow the intermediate symlinks into the suspended pool
and block in D state — the exact failure it is looking for.

So it walks the path **one component at a time**, and only ever calls `readlink`
on a prefix whose own ancestors were already proven to sit outside the pool. Each
prefix is compared to the pool mountpoints *lexically*, before anything touches
it. The moment a link target lands inside a pool the walk stops and reports; it
never resolves a path inside the pool.

That makes the check safe to run during the outage it is designed to detect,
which is when its output actually matters.

It catches more than a direct symlink: an indirection anywhere along the path
(`~/.config/fish` → `~/code/...` → `~/code` → `/tank/...`) is followed, relative
link targets are resolved, and a symlink cycle terminates and fails closed.

## 4. Options

Set in [`nix/machines/homeserver/configuration.nix`](../nix/machines/homeserver/configuration.nix):

| Option | Value here | Notes |
| --- | --- | --- |
| `poolRoots` | `[ "/tank" ]` | Mountpoints that must never appear in a login-critical path. |
| `paths` | `.config/fish`, `bin` | Relative to the account's home. Add anything else the login shell resolves. |
| `anchorDir` | `/home/rramirez/code` | Must live under the home: the swap is two renames and only stays atomic inside one dataset. |
| `poolDir` | `/tank/Shares/rueb/code` | The share directory `anchorDir` points at. |
| `entry` | `systems` | The checkout inside `poolDir`. |
| `migrate` | `true` | Set `false` to keep only the check on a machine fixed by hand. |

`login-shell-anchor-check.service` is in `rueb.failureMail.units` in
[`srv/alerting.nix`](../nix/machines/homeserver/srv/alerting.nix), so a
regression mails instead of waiting for the next outage to discover it.

## 5. Verifying

On the host:

```console
$ systemctl status login-shell-anchor-check.service
$ systemctl list-timers login-shell-anchor-check.timer
```

The fixture runner exercises both scripts against a rebuilt copy of the broken
layout — including the cases that are easy to get wrong (an unreadable pool, a
relative symlink, a cycle, a re-run after the migration):

```console
$ scripts/test-login-shell-anchor.sh
```

It is also a CI step in [`.forgejo/workflows/pr-check.yaml`](../.forgejo/workflows/pr-check.yaml).

## 6. Related, still open

Anchoring the login shell removes one symptom. The outage's actual cause — six
enclosures behind two daisy-chained Realtek hubs, one shared failure domain for
all three "mirrors" — is a hardware change, tracked in
[rueb/notes#1023](https://code.rueb.dev/rueb/notes/issues/1023).
[`rueb.zpoolRescue`](../nix/machines/_common/services/zpool-rescue/default.nix)
is the software mitigation: it resumes a suspended pool within ~30 s, which is
what would have turned this into a 30-second blip rather than a power-cycle.
