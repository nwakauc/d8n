#!/usr/bin/env bash
set -euo pipefail
set -a
source .env
set +a

echo "=== Step 2: brand_memberships + profiles (manual, ID-remapped fix) ==="
timeout 60 ssh -o BatchMode=yes -i ~/.ssh/d8n_production d8nadmin@164.68.106.97 "
export PGPASSWORD='$D8N_DATABASE_PASSWORD'
psql -h 127.0.0.1 -p 5432 -U d8n_app -d d8n_production -f ~/fix_brand_memberships.sql
"

echo
echo "=== Step 3: everything else (preferences, likes, matches, messages, trust, etc.) ==="
timeout 60 ssh -o BatchMode=yes -i ~/.ssh/d8n_production d8nadmin@164.68.106.97 "
export PGPASSWORD='$D8N_DATABASE_PASSWORD'
SOURCE_CONN='-h 127.0.0.1 -p 25432 -U uchechinwaka -d d8n_date9ja_rehearsal_cutover' \
DEST_CONN='-h 127.0.0.1 -p 5432 -U d8n_app -d d8n_production' \
bash ~/promote_step3_remaining.sh
"

echo
echo "=== Verify ==="
timeout 20 ssh -o BatchMode=yes -i ~/.ssh/d8n_production d8nadmin@164.68.106.97 "
export PGPASSWORD='$D8N_DATABASE_PASSWORD'
psql -h 127.0.0.1 -p 5432 -U d8n_app -d d8n_production -c \"select 'profiles' t, count(*) from profiles where user_id in (950,951) union all select 'dateza_unchanged', count(*) from profiles where brand_id=1;\"
"
