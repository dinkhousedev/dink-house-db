FROM postgres:15-alpine

# Install additional extensions if needed
RUN apk add --no-cache --virtual .build-deps \
    build-base \
    postgresql-dev \
    && apk del .build-deps

# Copy initialization scripts
COPY ./sql/init.sh /docker-entrypoint-initdb.d/00-init.sh
COPY ./sql/modules/*.sql /docker-entrypoint-initdb.d/
COPY ./sql/seeds/*.sql /docker-entrypoint-initdb.d/

# Make init script executable
RUN chmod +x /docker-entrypoint-initdb.d/00-init.sh

# Set proper permissions
RUN chown -R postgres:postgres /docker-entrypoint-initdb.d

USER postgres