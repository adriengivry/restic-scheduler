FROM alpine:3.22

RUN apk add --no-cache lua5.4 lua5.4-socket && \
    ln -sf /usr/bin/lua5.4 /usr/local/bin/lua

COPY ping_server.lua /app/ping_server.lua

CMD ["lua", "/app/ping_server.lua"]
