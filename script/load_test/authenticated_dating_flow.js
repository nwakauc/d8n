import http from "k6/http";
import { check, group, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const BASE_URL = __ENV.D8N_LOAD_TEST_BASE_URL || "https://staging-api.d8n.tech";
const PASSWORD = __ENV.D8N_LOAD_TEST_PASSWORD;
const USER_COUNT = requiredInteger("D8N_LOAD_TEST_USERS", 3000, 1, 5000);
const MAX_VUS = requiredInteger("D8N_LOAD_TEST_MAX_VUS", 500, 1, 5000);
const RAMP_DURATION = __ENV.D8N_LOAD_TEST_RAMP_DURATION || "1m";
const HOLD_DURATION = __ENV.D8N_LOAD_TEST_HOLD_DURATION || "2m";

const loginFailures = new Rate("d8n_login_failures");
const discoveryFailures = new Rate("d8n_discovery_failures");
const interactionConflicts = new Rate("d8n_interaction_conflicts");
const loginDuration = new Trend("d8n_login_duration", true);
const discoveryDuration = new Trend("d8n_discovery_duration", true);

export const options = {
  scenarios: {
    dating_flow: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: stagesFor(MAX_VUS),
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: "rate<0.05", abortOnFail: true, delayAbortEval: "45s" }],
    http_req_duration: ["p(95)<2000", "p(99)<5000"],
    d8n_login_failures: [{ threshold: "rate<0.02", abortOnFail: true, delayAbortEval: "45s" }],
    d8n_discovery_failures: [{ threshold: "rate<0.05", abortOnFail: true, delayAbortEval: "45s" }],
    d8n_login_duration: ["p(95)<2000"],
    d8n_discovery_duration: ["p(95)<2500"],
  },
  userAgent: "D8N-staging-k6/1.0",
};

let token;
let accountNumber;

export function setup() {
  if (!PASSWORD) {
    throw new Error("D8N_LOAD_TEST_PASSWORD is required");
  }

  const health = http.get(`${BASE_URL}/up`, { tags: { endpoint: "health" } });
  if (health.status !== 200) {
    throw new Error(`staging health check failed with HTTP ${health.status}`);
  }

  return { ready: true };
}

export default function () {
  accountNumber ||= ((__VU - 1) % USER_COUNT) + 1;
  token ||= login(accountNumber);
  if (!token) {
    sleep(2);
    return;
  }

  if (!isPublishedAccount(accountNumber)) {
    browseOwnProfile(token);
    sleep(randomThinkTime());
    return;
  }

  const profiles = discover(token);
  if (profiles.length > 0) {
    const candidate = profiles[Math.floor(Math.random() * profiles.length)];
    const action = Math.random();

    if (action < 0.08) {
      like(token, candidate.id);
    } else if (action < 0.20) {
      pass(token, candidate.id);
    } else if (action < 0.30) {
      browseMatches(token);
    } else if (action < 0.40) {
      browseOwnProfile(token);
    }
  }

  sleep(randomThinkTime());
}

function login(number) {
  return group("password login", () => {
    const response = http.post(
      `${BASE_URL}/api/v1/auth/password/login`,
      JSON.stringify({
        identifier: syntheticEmail(number),
        password: PASSWORD,
        device_name: `k6-vu-${__VU}`,
      }),
      requestOptions("password_login"),
    );

    loginDuration.add(response.timings.duration);
    const valid = check(response, {
      "login returns 201": (result) => result.status === 201,
      "login returns a bearer token": (result) => Boolean(result.json("token")),
    });
    loginFailures.add(!valid);
    return valid ? response.json("token") : null;
  });
}

function discover(sessionToken) {
  return group("discovery", () => {
    const response = http.get(
      `${BASE_URL}/api/v1/discovery?limit=20`,
      requestOptions("discovery", sessionToken),
    );
    discoveryDuration.add(response.timings.duration);
    const valid = check(response, {
      "discovery returns 200": (result) => result.status === 200,
      "discovery returns profiles": (result) => Array.isArray(result.json("profiles")),
    });
    discoveryFailures.add(!valid);
    return valid ? response.json("profiles") : [];
  });
}

function like(sessionToken, profileId) {
  const response = http.post(
    `${BASE_URL}/api/v1/profiles/${profileId}/likes`,
    null,
    requestOptions("like", sessionToken),
  );
  interactionConflicts.add(![200, 201].includes(response.status));
  check(response, { "like is accepted or safely conflicts": (result) => [200, 201, 404, 409].includes(result.status) });
}

function pass(sessionToken, profileId) {
  const response = http.post(
    `${BASE_URL}/api/v1/profiles/${profileId}/pass`,
    null,
    requestOptions("pass", sessionToken),
  );
  interactionConflicts.add(![200, 201].includes(response.status));
  check(response, { "pass is accepted or safely conflicts": (result) => [200, 201, 404, 409].includes(result.status) });
}

function browseOwnProfile(sessionToken) {
  const response = http.get(`${BASE_URL}/api/v1/profile`, requestOptions("own_profile", sessionToken));
  check(response, { "own profile returns 200": (result) => result.status === 200 });
}

function browseMatches(sessionToken) {
  const response = http.get(`${BASE_URL}/api/v1/matches?limit=20`, requestOptions("matches", sessionToken));
  check(response, { "matches return 200": (result) => result.status === 200 });
}

function requestOptions(endpoint, sessionToken = null) {
  const headers = { "Content-Type": "application/json", Accept: "application/json" };
  if (sessionToken) headers.Authorization = `Bearer ${sessionToken}`;

  return { headers, tags: { endpoint } };
}

function syntheticEmail(number) {
  return `loadtest-user-${String(number).padStart(6, "0")}@example.invalid`;
}

function isPublishedAccount(number) {
  return number % 20 >= 3;
}

function randomThinkTime() {
  return 1.5 + Math.random() * 2.5;
}

function stagesFor(maxVus) {
  const candidates = [100, 250, 500, 1000, 2000, 3000, 5000];
  const targets = candidates.filter((target) => target < maxVus);
  targets.push(maxVus);

  const stages = [];
  for (const target of [...new Set(targets)]) {
    stages.push({ duration: RAMP_DURATION, target });
    stages.push({ duration: HOLD_DURATION, target });
  }
  stages.push({ duration: RAMP_DURATION, target: 0 });
  return stages;
}

function requiredInteger(name, fallback, minimum, maximum) {
  const value = Number.parseInt(__ENV[name] || String(fallback), 10);
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer between ${minimum} and ${maximum}`);
  }
  return value;
}
