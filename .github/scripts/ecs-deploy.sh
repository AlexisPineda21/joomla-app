#!/bin/bash
# Fuerza un despliegue nuevo del servicio de ECS y espera a que quede estable.
# La definicion de tarea usa la imagen :latest; ECS la resuelve a un digest en cada
# despliegue, asi que basta con reiniciar el servicio (rolling update, sin caida).
set -euo pipefail
: "${ECS_CLUSTER:?Falta ECS_CLUSTER}" "${ECS_SERVICE:?Falta ECS_SERVICE}"

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --force-new-deployment \
  --query 'service.deployments[0].{despliegue:id,estado:rolloutState}' \
  --output table

echo "Esperando a que el servicio quede estable (maximo 10 minutos)..."
aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"

aws ecs describe-services \
  --cluster "$ECS_CLUSTER" \
  --services "$ECS_SERVICE" \
  --query 'services[0].{deseadas:desiredCount,corriendo:runningCount,despliegues:length(deployments)}' \
  --output table
