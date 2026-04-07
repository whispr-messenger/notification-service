#!/bin/bash
set -e

cd /app

exec env MIX_ENV=dev mix phx.server
