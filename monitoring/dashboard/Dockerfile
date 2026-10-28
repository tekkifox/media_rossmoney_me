FROM nginx:1.31-alpine

# The dashboard config is baked into the image rather than supplied as a Compose
# `configs` mount. Compose materialises those as a root-owned file, which the
# non-root master (uid 1001) cannot read: "open() /etc/nginx/conf.d/default.conf
# failed (13: Permission denied)".
#
# Copying it in the build gives mode 644 regardless of the host's file ownership.
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN chmod 644 /etc/nginx/conf.d/default.conf

# Scratch space for the non-root master: the upstream image runs as root and
# expects to own these paths, so the compose service mounts tmpfs over them.
RUN mkdir -p /var/cache/nginx /var/run && \
    chown -R 1001:1001 /var/cache/nginx /var/run

# The report volume is mounted at /reports, not at /usr/share/nginx/html, so
# Docker cannot seed it with nginx's stock index.html. Serving from a path the
# image does not populate removes the need to delete anything at startup.
#
# The dashboard serves from /reports, which must be chowned to 1001:1001 before
# the dashboard reads it. That one-shot job is baked into this image so no
# separate alpine image is needed:
#   docker compose run --rm reports-init
COPY reports-init.sh /reports-init.sh
RUN chmod 755 /reports-init.sh