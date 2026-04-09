---
name: Sequential EnKF feature branches
description: Branch names used for sequential EnKF work across 5 repos, for switching back from develop
type: project
---

To switch back to sequential EnKF work, checkout `feature/sequential_enkf` on these repos:

```bash
cd /home/tsluka/work/jedi/bundle
for repo in oops ioda ufo soca pyiri-jedi; do git -C "$repo" checkout feature/sequential_enkf; done
```

Repos and branches (as of 2026-04-03):
- oops: `feature/sequential_enkf`
- ioda: `feature/sequential_enkf`
- ufo: `feature/sequential_enkf`
- soca: `feature/sequential_enkf`
- pyiri-jedi: `feature/sequential_enkf`

All other repos were already on `develop`. Note: `mpas` was on detached HEAD at `b566fc8a959390d838aba08fd03c81edae986f6a`.

**Why:** User switched to develop for other work; needs to be able to return to sequential EnKF branches later.
**How to apply:** When user asks to switch back to sequential EnKF, run the checkout loop above.
