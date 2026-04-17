#!/bin/sh
set -e

# Postgres readiness est garantie par `depends_on: condition: service_healthy`
# dans docker-compose.prod.yml.

echo "[entrypoint] running migrations"
/app/bin/whispr_notification eval "WhisprNotifications.Release.migrate()"

echo "[entrypoint] starting Phoenix"
exec /app/bin/whispr_notification start
