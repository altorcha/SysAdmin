#!/usr/bin/env bash
set -euo pipefail

OWNER_USER="${SUDO_USER:-$USER}"
OWNER_HOME="$(getent passwd "${OWNER_USER}" | cut -d: -f6)"
PROJECT_DIR="${OWNER_HOME}/contenedores"
HOST_IP="${HOST_IP:-192.168.10.10}"

echo "Verificando Docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker no esta instalado. Instala Docker antes de ejecutar este script."
  exit 1
fi

docker compose version >/dev/null

echo "Creando estructura en ${PROJECT_DIR}..."
mkdir -p "${PROJECT_DIR}/web/html/uploads" "${PROJECT_DIR}/db/backups"
cd "${PROJECT_DIR}"

echo "Generando docker-compose.yml..."
cat > docker-compose.yml <<EOF
services:
  web:
    build: ./web
    container_name: web_principal
    ports:
      - "8080:8080"
    volumes:
      - web_content:/usr/share/nginx/html
    networks:
      infra_red:
        ipv4_address: 172.20.0.10
    mem_limit: 512m
    cpus: "0.50"
    pids_limit: 100
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_RAW
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: postgres_db
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: AdminPractica10
      POSTGRES_DB: usuarios
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      infra_red:
        ipv4_address: 172.20.0.20
    mem_limit: 512m
    cpus: "0.75"
    restart: unless-stopped

  backup:
    image: postgres:16-alpine
    container_name: postgres_backup
    depends_on:
      - db
    environment:
      PGPASSWORD: AdminPractica10
    volumes:
      - ./db/backups:/backups:Z
    networks:
      infra_red:
        ipv4_address: 172.20.0.40
    command: >
      sh -c 'while true; do
      pg_dumpall -h db -U admin > /backups/backup_\$$(date +%F_%H-%M-%S).sql;
      sleep 300;
      done'
    mem_limit: 256m
    cpus: "0.25"
    restart: unless-stopped

  ftp:
    image: delfer/alpine-ftp-server
    container_name: ftp_archivos
    environment:
      USERS: "webuser|FtpPractica10|/ftp/ftp"
      ADDRESS: "${HOST_IP}"
      MIN_PORT: "21000"
      MAX_PORT: "21010"
    ports:
      - "21:21"
      - "21000-21010:21000-21010"
    volumes:
      - web_content:/ftp/ftp
    networks:
      infra_red:
        ipv4_address: 172.20.0.30
    mem_limit: 256m
    cpus: "0.25"
    restart: unless-stopped

volumes:
  db_data:
    name: db_data
  web_content:
    name: web_content

networks:
  infra_red:
    name: infra_red
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

echo "Generando Dockerfile del servidor web..."
cat > web/Dockerfile <<'EOF'
FROM nginx:alpine

RUN apk add --no-cache iputils shadow \
    && addgroup -S webgroup \
    && adduser -S -D -H -G webgroup webuser \
    && mkdir -p /var/cache/nginx/client_temp \
              /var/cache/nginx/proxy_temp \
              /var/cache/nginx/fastcgi_temp \
              /var/cache/nginx/uwsgi_temp \
              /var/cache/nginx/scgi_temp \
              /usr/share/nginx/html/uploads \
    && chown -R webuser:webgroup /var/cache/nginx /usr/share/nginx/html \
    && chmod 777 /usr/share/nginx/html/uploads

COPY nginx.conf /etc/nginx/nginx.conf
COPY html/ /usr/share/nginx/html/

RUN chown -R webuser:webgroup /usr/share/nginx/html \
    && chmod 777 /usr/share/nginx/html/uploads

USER webuser

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
EOF

echo "Generando configuracion segura de Nginx..."
cat > web/nginx.conf <<'EOF'
worker_processes auto;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server_tokens off;
    sendfile on;

    access_log /dev/stdout;
    error_log /dev/stderr warn;

    client_body_temp_path /var/cache/nginx/client_temp;
    proxy_temp_path /var/cache/nginx/proxy_temp;
    fastcgi_temp_path /var/cache/nginx/fastcgi_temp;
    uwsgi_temp_path /var/cache/nginx/uwsgi_temp;
    scgi_temp_path /var/cache/nginx/scgi_temp;

    server {
        listen 8080;
        server_name _;

        root /usr/share/nginx/html;
        index index.html;

        location / {
            try_files $uri $uri/ =404;
        }

        location /uploads/ {
            autoindex on;
        }
    }
}
EOF

echo "Generando pagina web personalizada..."
cat > web/html/index.html <<'EOF'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Practica 10 - Contenedores</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main>
    <img src="logo-practica10.svg" alt="Logo Practica 10" class="logo">
    <h1>Practica 10: Servicios en Contenedores</h1>
    <p>Servidor web personalizado con Nginx Alpine, usuario no administrativo, red bridge, volumen persistente y contenido compartido por FTP.</p>
    <a href="/uploads/">Ver archivos subidos por FTP</a>
  </main>
</body>
</html>
EOF

cat > web/html/styles.css <<'EOF'
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  font-family: Arial, sans-serif;
  background: #101820;
  color: #f4f7fb;
}

main {
  width: min(720px, 90vw);
  padding: 32px;
  border: 1px solid #2f4858;
  background: #182733;
}

.logo {
  width: 120px;
}

h1 {
  color: #56cfe1;
}

a {
  color: #80ffdb;
  font-weight: bold;
}
EOF

cat > web/html/logo-practica10.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="220" height="160" viewBox="0 0 220 160">
  <rect width="220" height="160" fill="#56cfe1"/>
  <rect x="30" y="40" width="160" height="80" rx="8" fill="#101820"/>
  <circle cx="70" cy="80" r="18" fill="#80ffdb"/>
  <circle cx="110" cy="80" r="18" fill="#f4f7fb"/>
  <circle cx="150" cy="80" r="18" fill="#ffdd57"/>
  <text x="110" y="145" text-anchor="middle" font-family="Arial" font-size="18" fill="#101820">P10 Docker</text>
</svg>
EOF

echo "Abriendo puertos en firewalld si esta disponible..."
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
  sudo firewall-cmd --add-port=8080/tcp --permanent
  sudo firewall-cmd --add-port=21/tcp --permanent
  sudo firewall-cmd --add-port=21000-21010/tcp --permanent
  sudo firewall-cmd --reload
else
  echo "firewalld no esta activo; se omite configuracion de firewall."
fi

echo "Construyendo y levantando servicios..."
docker compose up -d --build

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  chown -R "${SUDO_USER}:${SUDO_USER}" "${PROJECT_DIR}"
fi

echo
echo "Despliegue terminado."
echo "Web: http://${HOST_IP}:8080"
echo "FTP: ${HOST_IP}:21 | usuario webuser | password FtpPractica10 | modo pasivo"
echo "Proyecto generado en: ${PROJECT_DIR}"
