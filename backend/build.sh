#!/usr/bin/env bash
set -o errexit

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"

pip install -r requirements/production.txt

python manage.py collectstatic --noinput

python manage.py migrate