ARG COMPOSER_VERSION=2.2

FROM composer:$COMPOSER_VERSION AS composer

FROM golang:alpine AS builder

# envsubst from gettext can not replace env vars with default values
# this package is not available for ARM32 and we have to build it from source code
# flag -ldflags "-s -w" produces a smaller executable
RUN go install -ldflags "-s -w" -v github.com/a8m/envsubst/cmd/envsubst@v1.4.3

FROM node:20-alpine AS assets

WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY webpack.config.js postcss.config.js ./
COPY assets/ assets/
COPY templates/ templates/
RUN yarn build:prod

FROM alpine:3.24

COPY --from=builder /go/bin/envsubst /usr/bin/envsubst

RUN set -ex \
 && apk add --no-cache \
      curl \
      libwebp \
      nginx \
      pcre \
      php84 \
      php84-bcmath \
      php84-ctype \
      php84-curl \
      php84-dom \
      php84-fpm \
      php84-gd \
      php84-gettext \
      php84-iconv \
      php84-json \
      php84-mbstring \
      php84-opcache \
      php84-openssl \
      php84-pecl-amqp \
      php84-pecl-imagick \
      php84-pdo_mysql \
      php84-pdo_pgsql \
      php84-pdo_sqlite \
      php84-phar \
      php84-session \
      php84-simplexml \
      php84-tokenizer \
      php84-xml \
      php84-zlib \
      php84-sockets \
      php84-xmlreader \
      php84-tidy \
      php84-intl \
      php84-sodium \
      mariadb-client \
      postgresql17-client \
      rabbitmq-c \
      s6 \
      tar \
      tzdata \
 && ln -sf /usr/bin/php84 /usr/bin/php \
 && ln -sf /usr/sbin/php-fpm84 /usr/sbin/php-fpm \
 && rm -rf /var/cache/apk/* \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

# Copy the root overlay (entrypoint, nginx, php-fpm, s6 configs)
# Sourced from wallabag-docker repo
COPY docker/root /

# Copy source code from this branch
RUN mkdir -p /var/www/wallabag
COPY . /var/www/wallabag/

# Copy built frontend assets
COPY --from=assets /app/web/build /var/www/wallabag/web/build

RUN set -ex \
 && cd /var/www/wallabag \
 && mkdir -p data/assets \
 && envsubst < /etc/wallabag/parameters.template.yml > app/config/parameters.yml \
 && SYMFONY_ENV=prod composer install --no-dev -o --prefer-dist --no-progress \
 && rm -rf /root/.composer/* /var/www/wallabag/var/cache/* /var/www/wallabag/var/logs/* /var/www/wallabag/var/sessions/* \
 && chown -R nobody:nobody /var/www/wallabag

ENV PATH="${PATH}:/var/www/wallabag/bin"

WORKDIR /var/www/wallabag

HEALTHCHECK CMD curl --fail --silent --show-error --user-agent healthcheck http://localhost/api/info || exit 1

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
CMD ["wallabag"]
