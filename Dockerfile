# ========================================================
# Stage: Frontend (Vite)
# ========================================================
FROM --platform=$BUILDPLATFORM node:22-alpine AS frontend
WORKDIR /src/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
COPY internal/web/translation /src/internal/web/translation
RUN npm run build

# ========================================================
# Stage: Builder
# ========================================================
FROM golang:1.27-alpine AS builder
WORKDIR /app
ARG TARGETARCH

RUN apk --no-cache --update add \
  build-base \
  gcc \
  curl \
  unzip \
  git

COPY . .
COPY --from=frontend /src/internal/web/dist ./internal/web/dist

# دانلود و کامپایل دقیق فایل اجرایی سایفون
RUN CGO_ENABLED=0 go install github.com/Psiphon-Labs/psiphon-tunnel-core/ConsoleClient@latest && \
    mv /go/bin/ConsoleClient /go/bin/psiphon

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"
RUN go build -ldflags "-w -s" -o build/x-ui main.go
RUN ./DockerInit.sh "$TARGETARCH"

# ========================================================
# Stage: Final Image of 3x-ui (Tor + Psiphon)
# ========================================================
FROM alpine
ENV TZ=Asia/Tehran
WORKDIR /app

# نصب پیش‌نیازها
RUN apk add --no-cache --update \
  ca-certificates \
  tzdata \
  fail2ban \
  bash \
  curl \
  openssl \
  tor \
  jq \
  sudo \
  socat

# ساخت پوشه‌های کاری Tor و Psiphon
RUN mkdir -p /etc/tor/t_sin_nodes /var/lib/tor/t_sin_nodes /etc/psiphon /var/lib/psiphon && \
    chown -R tor:tor /var/lib/tor/t_sin_nodes /etc/tor/t_sin_nodes

COPY --from=builder /app/build/ /app/
COPY --from=builder /app/DockerEntrypoint.sh /app/
COPY --from=builder /app/x-ui.sh /usr/bin/x-ui
COPY --from=builder /app/internal/web/translation /app/internal/web/translation

# کپی کردن فایل اجرایی سایفون اصلاح‌شده
COPY --from=builder /go/bin/psiphon /usr/bin/psiphon-tunnel-core

# کپی کردن اسکریپت راه‌انداز
COPY entrypoint.sh /app/entrypoint.sh

# Configure fail2ban
RUN rm -f /etc/fail2ban/jail.d/alpine-ssh.conf \
  && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local \
  && sed -i "s/^\[ssh\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/^\[sshd\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/#allowipv6 = auto/allowipv6 = auto/g" /etc/fail2ban/fail2ban.conf

RUN chmod +x \
  /app/DockerEntrypoint.sh \
  /app/entrypoint.sh \
  /app/x-ui \
  /usr/bin/x-ui \
  /usr/bin/psiphon-tunnel-core

ENV XUI_IN_DOCKER="true"
ENV XUI_MAIN_FOLDER="/app"
ENV XUI_ENABLE_FAIL2BAN="true"
ENV XUI_DB_TYPE=""
ENV XUI_DB_DSN=""
EXPOSE 2053
CMD [ "./x-ui" ]
ENTRYPOINT [ "/app/entrypoint.sh" ]
