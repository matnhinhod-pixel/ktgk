#!/usr/bin/env bash
set -euo pipefail

adc_file="${HOME}/.config/gcloud/application_default_credentials.json"
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
  echo "Ignoring missing GOOGLE_APPLICATION_CREDENTIALS file: $GOOGLE_APPLICATION_CREDENTIALS" >&2
  unset GOOGLE_APPLICATION_CREDENTIALS
fi
if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -f "$adc_file" ]]; then
  export GOOGLE_APPLICATION_CREDENTIALS="$adc_file"
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/DOMINHNHAT.WebAPI"
exec dotnet run --no-restore --project DOMINHNHAT.WebAPI.csproj --launch-profile http
