# private/

Template for the master build. Copy it once:

    cp -r private.example private

`private/` is ignored by git, so nothing in it reaches GitHub.

| path | what it does |
|---|---|
| `profiles/master.conf` | the master profile, `./build.sh -p master` |
| `env` | secrets (ntfy topic), sourced after the profile |
| `components.list` | extra components or overrides by name |
| `recipes/` | recipes for those, same API as `recipes/` |
| `patches/<name>/` | patches applied on top of a component's source |
| `module/` | copied over `module/` when packaging, e.g. your own `libexec/fb-*.sh` |

A private `libexec/fb-<name>.sh` becomes `fb <name>` on the phone as long as
`<name>` is in the profile's `FEATURES`.
