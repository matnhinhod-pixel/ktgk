#!/usr/bin/env bash
set -euo pipefail

Auth__RequireEmailOtp="${Auth__RequireEmailOtp:-false}"
export Auth__RequireEmailOtp
if [[ "$Auth__RequireEmailOtp" == "true" ]]; then
  Smtp__Host=smtp.gmail.com
  Smtp__Port=587
  Smtp__EnableSsl=true
  read -rp 'Gmail sender email: ' Smtp__From
  if [[ -z "$Smtp__From" ]]; then
    echo 'Gmail sender email is required.' >&2
    exit 1
  fi

  Smtp__Username=$Smtp__From
  read -rsp 'Gmail App Password: ' Smtp__Password
  printf '\n'
  if [[ -z "$Smtp__Password" ]]; then
    echo 'Gmail App Password is required.' >&2
    exit 1
  fi

  export Smtp__Host Smtp__Port Smtp__From Smtp__Username
  export Smtp__EnableSsl Smtp__Password
fi
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-/tmp/dominhnhat-adc.json}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/DOMINHNHAT.WebAPI"
exec dotnet run --no-restore --project DOMINHNHAT.WebAPI.csproj --launch-profile http
