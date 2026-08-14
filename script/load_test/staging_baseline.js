import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "20s", target: 10 },
    { duration: "40s", target: 10 },

    { duration: "20s", target: 25 },
    { duration: "40s", target: 25 },

    { duration: "20s", target: 50 },
    { duration: "40s", target: 50 },

    { duration: "20s", target: 100 },
    { duration: "40s", target: 100 },

    { duration: "20s", target: 0 },
  ],

  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<1000"],
  },
};

export default function () {
  const res = http.get("https://staging-api.d8n.tech/");

  check(res, {
    "status is 200": (r) => r.status === 200,
  });

  sleep(1);
}
