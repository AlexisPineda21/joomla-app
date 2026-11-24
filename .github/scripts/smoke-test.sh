#!/bin/bash
# Smoke test del sitio publicado: /health.php debe responder 200 con el commit
# esperado (la version nueva es la que atiende) y la portada debe responder 200.
set -euo pipefail
url="${1:?Uso: smoke-test.sh <url> <commit>}"
expected="${2:?Uso: smoke-test.sh <url> <commit>}"

for attempt in $(seq 1 18); do
  body=$(curl -fsS --max-time 10 "$url/health.php" 2>/dev/null || true)
  home=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url/" 2>/dev/null || true)

  if grep -q "\"commit\":\"$expected\"" <<< "$body" && [ "$home" = "200" ]; then
    echo "Smoke test correcto (intento $attempt): $body"
    exit 0
  fi

  echo "Intento $attempt: portada=${home:-sin respuesta} health=${body:-sin respuesta}"
  sleep 10
done

echo "::error::Smoke test fallido: $url no sirve el commit $expected"
exit 1
