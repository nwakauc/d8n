#!/usr/bin/env bash
set -euo pipefail
set -a
source .env
set +a
ssh -i ~/.ssh/d8n_production d8nadmin@164.68.106.97 "
export PGPASSWORD='$D8N_DATABASE_PASSWORD'
psql -h 127.0.0.1 -p 5432 -U d8n_app -d d8n_production -f ~/cleanup_broken_photos.sql
"
