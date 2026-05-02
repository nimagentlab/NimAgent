# nimagent public release checklist

Before pushing the repository publicly:

- [ ] `nimble test` passes locally.
- [ ] `nimble examples` compiles locally.
- [ ] No compiled binaries are staged.
- [ ] No `.env`, keys, tokens, local config, logs, DB files, or private notes are staged.
- [ ] README quick start matches the real public API.
- [ ] License owner is correct.
- [ ] Git history starts from a clean initial commit.
- [ ] GitHub topics are added after push.
- [ ] First release tag is `v0.1.0` only after CI passes.
