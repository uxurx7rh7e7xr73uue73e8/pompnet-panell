# PompNet Panel — Railway build
# Builds the official Sanaei/3X-UI source with PompNet branding.
ARG XUI_REF=main

FROM node:22-alpine AS frontend
ARG XUI_REF
RUN apk add --no-cache git
RUN git clone --depth 1 --branch "${XUI_REF}" https://github.com/MHSanaei/3x-ui.git /src/3x-ui
WORKDIR /src/3x-ui/frontend
RUN npm ci

# PompNet branding + requested Persian login greeting.
RUN sed -i 's#<span className="brand-name">3X-UI</span>#<span className="brand-name">پمپ نت</span>#g' src/pages/login/LoginPage.tsx
RUN sed -i 's/"hello": "سلام"/"hello": "سلام به پنل اختصاصی خوش آمدید"/g; s/"title": "خوش‌آمدید"/"title": "پمپ نت"/g; s/این عملیات 3X-UI را/این عملیات پنل پمپ نت را/g' ../internal/web/translation/fa-IR.json

RUN npm run build

FROM golang:1.27-alpine AS builder
ARG XUI_REF
RUN apk add --no-cache --update build-base gcc curl unzip git
WORKDIR /app
RUN git clone --depth 1 --branch "${XUI_REF}" https://github.com/MHSanaei/3x-ui.git /app/src
WORKDIR /app/src

COPY --from=frontend /src/3x-ui/internal/web/translation ./internal/web/translation
COPY --from=frontend /src/3x-ui/frontend/dist ./internal/web/dist

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"

RUN go build -ldflags "-w -s" -o build/x-ui main.go
RUN ./DockerInit.sh "amd64"

FROM alpine:latest
ENV TZ=Asia/Tehran
WORKDIR /app

RUN apk add --no-cache --update ca-certificates tzdata fail2ban bash curl openssl

COPY --from=builder /app/src/build/ /app/
COPY --from=builder /app/src/DockerEntrypoint.sh /app/
COPY --from=builder /app/src/x-ui.sh /usr/bin/x-ui
COPY --from=builder /app/src/internal/web/translation /app/internal/web/translation

RUN rm -f /etc/fail2ban/jail.d/alpine-ssh.conf \
 && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local \
 && sed -i "s/^\[ssh\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
 && sed -i "s/^\[sshd\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
 && sed -i "s/#allowipv6 = auto/allowipv6 = auto/g" /etc/fail2ban/fail2ban.conf

RUN chmod +x /app/DockerEntrypoint.sh /app/x-ui /usr/bin/x-ui

ENV XUI_IN_DOCKER="true"
ENV XUI_MAIN_FOLDER="/app"
ENV XUI_ENABLE_FAIL2BAN="false"
ENV XUI_DB_TYPE=""
ENV XUI_DB_DSN=""
ENV XUI_PORT="2053"

EXPOSE 2053

# Railway supplies PORT; otherwise the normal 2053 port is used.
CMD ["sh", "-c", "export XUI_PORT=${PORT:-2053}; exec ./x-ui"]

ENTRYPOINT ["/app/DockerEntrypoint.sh"]
