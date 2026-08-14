# D8N staging load tests

These scripts target synthetic accounts only. Never point them at production or
use real credentials.

`staging_baseline.js` measures the proxy/Rails baseline with no database-heavy
user flow. `authenticated_dating_flow.js` logs each virtual user in once, then
exercises discovery, own-profile reads, match lists, likes, and passes with human
think time.

The authenticated scenario deliberately ramps through plateaus. Do not begin at
5,000 virtual users: find the first saturation point and stop increasing load
when errors, latency, swapping, or database connection pressure becomes unsafe.

## Required environment

```sh
export D8N_LOAD_TEST_PASSWORD='set-this-outside-the-repository'
export D8N_LOAD_TEST_USERS=3000
export D8N_LOAD_TEST_MAX_VUS=500
```

## Run

```sh
k6 run --summary-export=tmp/k6-staging-summary.json \
  script/load_test/authenticated_dating_flow.js
```

For short verification before a measured run:

```sh
D8N_LOAD_TEST_MAX_VUS=25 \
D8N_LOAD_TEST_RAMP_DURATION=20s \
D8N_LOAD_TEST_HOLD_DURATION=40s \
k6 run script/load_test/authenticated_dating_flow.js
```

Increase `D8N_LOAD_TEST_MAX_VUS` only after reviewing the previous plateau. A
5,000-VU run should use a 5,000-account dataset so sessions and profile locks are
not artificially shared between virtual users.

Capture server CPU, memory, swapping, container usage, PostgreSQL connections,
slow queries, request latency, and error logs throughout the run. Client-side k6
latency alone is not enough to choose production hardware.
