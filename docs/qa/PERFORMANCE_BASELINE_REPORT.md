# Performance Baseline Report

Phase 3C bounded smoke validation for load and responsiveness.

## Scope

- Keep the check local and non-production.
- Verify the platform can process a small staged load without failure.
- Do not claim production load-test readiness from this smoke alone.

## Environment

- Local backend started on `http://127.0.0.1:3000`
- QA environment variables loaded from `.env.test`
- Writes were skipped for the smoke run
- Load matrix step size capped at 20

## Results

| Stage | Concurrency | Total requests | Failed requests | Fail rate | Duration |
|---|---|---:|---:|---:|---:|
| 10 | 4 | 105 | 0 | 0.00 | 1.21s |
| 20 | 9 | 205 | 0 | 0.00 | 1.71s |

## Aggregate

- Total requests: `310`
- Failed requests: `0`
- Overall fail rate: `0.00`
- Total smoke duration: `2.92s`
- Aborted: `false`

## Conclusion

- The bounded local load smoke passed.
- This is a baseline only, not a production load verdict.
- Larger staged load testing still belongs in the dedicated QA/staging environment.
