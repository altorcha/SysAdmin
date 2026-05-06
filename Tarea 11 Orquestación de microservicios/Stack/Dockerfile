FROM nginx:1.27-alpine

RUN sed -i 's/listen       80;/listen       8080;/' /etc/nginx/conf.d/default.conf \
    && sed -i 's/listen  \\[::\\]:80;/listen  [::]:8080;/' /etc/nginx/conf.d/default.conf \
    && sed -i 's/server_tokens on;/server_tokens off;/' /etc/nginx/nginx.conf || true

EXPOSE 8080
