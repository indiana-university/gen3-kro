#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lambda_dir="$repo_root/argocd/csoc/kro/aws-rgds/gen3/lambda"
build_dir="${BUILD_DIR:-$repo_root/.build/lambda}"
zip_path="${ZIP_PATH:-$build_dir/rds_master_secret_mirror.zip}"
b64_path="${B64_PATH:-$zip_path.b64}"

mkdir -p "$build_dir"
rm -f "$zip_path"
rm -f "$b64_path"

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required to build the Lambda deployment package." >&2
  exit 1
fi

(
  cd "$lambda_dir"
  zip -q -X "$zip_path" rds_master_secret_mirror.py
)

base64 -w0 "$zip_path" > "$b64_path"

echo "Created $zip_path"
echo "Created $b64_path"

if [[ -n "${S3_BUCKET:-}" ]]; then
  s3_key="${S3_KEY:-lambda/rds_master_secret_mirror.zip}"
  aws s3 cp "$zip_path" "s3://$S3_BUCKET/$s3_key"
  echo "Uploaded s3://$S3_BUCKET/$s3_key"
fi
