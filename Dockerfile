FROM alpine:3.22

RUN apk add --no-cache ca-certificates curl lua5.4 restic tzdata && \
    ln -sf /usr/bin/lua5.4 /usr/local/bin/lua

COPY restic-scheduler.lua /usr/local/bin/restic-scheduler

ENTRYPOINT ["lua", "/usr/local/bin/restic-scheduler"]
