# Tracked test environment remediation

Affected path:

- `backend/.env.test`

Known history in this repository:

- first known commit in path history: `a9f47b90e732310341f7b2f03e5b7fa6f7ed7131`
- latest known commit in path history: `757db30556e1068eac8978f043046142318d7ce8`

Affected refs at the time of remediation:

- `feat/merchant-review-contract-closure`
- `closure/full-application-closure`
- `main`
- `origin/feat/merchant-review-contract-closure`
- `origin/closure/full-application-closure`

Rotation status:

- values rotated: no verified repo-side rotation performed
- exposure status: treat matching secrets in `backend/.env.test` as exposed

Current-tree remediation:

- tracked file removed from the index
- exact ignore rule added at `/backend/.env.test`
- example file added at `backend/.env.test.example`

Recommended controlled purge procedure:

1. Confirm any matching JWT secret, Super Admin PIN, database password, access token, refresh token, Cloudflare token, Railway token, or Firebase private key has been rotated outside the repository.
2. Confirm any production or shared Railway variable does not reuse the same value.
3. Use `git filter-repo` to purge `backend/.env.test` from all reachable history after a backup is taken.
4. Force-push only the intended rewritten refs after review.
5. Recreate any required local test env from `backend/.env.test.example`.

Impact on worktrees and commit SHAs:

- local worktrees may need to rebase or re-point after a history rewrite
- feature branch tip at remediation time: `ddcde3ddea6fbbc6d75fc8828e1a9beb014dcb8e`
- closure branch tip restored to: `7a73125e4eb0253995dbe63535440f42af7a8823`

Notes:

- no secret values are recorded here
- no automatic history rewrite was performed in this step
