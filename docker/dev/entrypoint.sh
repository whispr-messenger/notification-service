#!/bin/bash
set -e

cd /app

MIX_ENV=dev mix ecto.migrate
exec env MIX_ENV=dev mix phx.server
