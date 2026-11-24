#!/bin/bash
# Hace que el tag "latest" de ECR apunte a otra imagen (por digest o por tag).
# Lo usan el rollback automatico del pipeline y el workflow app-rollback.
set -euo pipefail
ref="${1:?Uso: ecr-retag.sh <sha256:digest | tag>}"
: "${ECR_REPOSITORY:?Falta ECR_REPOSITORY}"

if [[ $ref == sha256:* ]]; then
  image_id="imageDigest=$ref"
else
  image_id="imageTag=$ref"
fi

get_field() {
  aws ecr batch-get-image \
    --repository-name "$ECR_REPOSITORY" \
    --image-ids "$image_id" \
    --query "images[0].$1" \
    --output text
}

manifest=$(get_field imageManifest)
media=$(get_field imageManifestMediaType)

if [ -z "${manifest:-}" ] || [ "$manifest" = "None" ]; then
  echo "::error::No existe la imagen $ref en el repositorio $ECR_REPOSITORY"
  exit 1
fi

errors=$(mktemp)
if ! aws ecr put-image \
  --repository-name "$ECR_REPOSITORY" \
  --image-tag latest \
  --image-manifest "$manifest" \
  --image-manifest-media-type "$media" > /dev/null 2> "$errors"; then
  if ! grep -q ImageAlreadyExistsException "$errors"; then
    cat "$errors" >&2
    exit 1
  fi
fi

echo "El tag latest apunta ahora a $ref"
