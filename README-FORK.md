# joomla-app: fork de Joomla

Fork manual de la release **Joomla 5.4.10** (paquete *Full Package* oficial). Se despliega en Amazon ECS Fargate sobre la infraestructura del repositorio `iac-joomla-aws`.

Lo propio del fork:

| Archivo | Para qué |
|---|---|
| `Dockerfile` | Parte de `joomla:5.4.10-php8.3-apache` y cambia su código por el de este repositorio |
| `docker/start-joomla.sh` | Arranque del contenedor: instala Joomla la primera vez y en cada arranque copia el código de la imagen al webroot |
| `docker/configure-joomla.php` | Ajusta `configuration.php` con las variables de entorno (RDS y Valkey) |
| `health.php` | Salud del sitio (MySQL y Valkey) y commit desplegado |
| `media/templates/site/cassiopeia/css/user.css` | Personalización visual del sitio |
| `compose.yaml` | Prueba local con MySQL 8.4 y Valkey 8.0 |
| `.github/workflows/` | Pipelines de CI/CD y rollback |

El resto de archivos son los de Joomla sin modificar.

## Código y datos

El código vive en la imagen. Solo `configuration.php` e `images/` viven en Amazon EFS (montado en `/mnt/joomla-data`) y se enlazan al webroot. Por eso un cambio en el repositorio llega al sitio con solo publicar una imagen nueva, y durante un despliegue la versión vieja y la nueva pueden atender a la vez.

Las extensiones se agregan al repositorio, no desde el panel de administración: lo que se instale desde el panel se pierde cuando la tarea se reemplaza.

## CI/CD (GitHub Actions)

| Workflow | Evento | Qué hace |
|---|---|---|
| `app-ci-cd` | PR a `main` | `php -l`, ShellCheck, build de la imagen y prueba con `compose.yaml` (instala Joomla contra MySQL y Valkey y consulta `/health.php`). No publica nada |
| `app-ci-cd` | push a `main` | Lo mismo y, después, push a ECR con los tags `<sha>` y `latest`, despliegue en ECS (rolling update) y smoke test contra el ALB. **Si falla, vuelve a publicar la imagen anterior** |
| `app-rollback` | manual | Publica una imagen anterior de ECR indicando el SHA del commit |

La autenticación con AWS es por OIDC: no hay llaves de acceso guardadas en GitHub.

## Probar en local

```bash
cp .env.example .env
docker compose up -d --build --wait
curl http://localhost:8080/health.php
```

## Actualizar Joomla

Descargar el *Full Package* de la versión nueva, reemplazar los archivos de Joomla en una rama, cambiar el `FROM` del `Dockerfile` y abrir un PR. El pipeline valida que la imagen instala y arranca antes del merge. Después del despliegue, revisar en *Sistema → Base de datos* que el esquema quede al día.
