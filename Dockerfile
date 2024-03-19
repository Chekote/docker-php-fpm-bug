FROM chekote/ubuntu:latest

ENV PHP_VERSION=8.3

RUN set -eu; \
    #
    apt-get update; \
    #
    # Configure ondrej PPA
    apt-get install -y software-properties-common; \
    add-apt-repository ppa:ondrej/php; \
    apt-get update; \
    #
    # Install dependencies
    apt-get install --no-install-recommends --no-install-suggests -y \
      ca-certificates \
      curl \
      php${PHP_VERSION}-fpm \
      nginx \
      supervisor; \
    #
    # Cleanup
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    rm -rf /var/cache/apt/*; \
    #
    # Fix "Unable to create the PID file (/run/php/php5.6-fpm.pid).: No such file or directory (2)"
    mkdir -p /run/php; \
    #
    # Configure PHP-FPM
    sed -i "s!display_startup_errors = Off!display_startup_errors = On!g" /etc/php/${PHP_VERSION}/fpm/php.ini; \
    sed -i "s!;error_log = php_errors.log!error_log = /proc/self/fd/2!g" /etc/php/${PHP_VERSION}/fpm/php.ini; \
    #
    sed -i "s!;daemonize = yes!daemonize = no!g" /etc/php/${PHP_VERSION}/fpm/php-fpm.conf; \
    sed -i "s!error_log = /var/log/php${PHP_VERSION}-fpm.log!error_log = /proc/self/fd/2!g" /etc/php/${PHP_VERSION}/fpm/php-fpm.conf; \
    #
    sed -i "s!;catch_workers_output = yes!catch_workers_output = yes!g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf; \
    sed -i "s!listen = /run/php/php${PHP_VERSION}-fpm.sock!listen = 0.0.0.0:9000!g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf; \
    #
    # Configure Nginx
    #
    # Route nginx logs to syslog socket (will show in Docker logs)
    sed -i 's!/var/log/nginx/access.log!syslog:server=unix:/proc/self/fd/1!g' /etc/nginx/nginx.conf; \
    sed -i 's!/var/log/nginx/error.log!syslog:server=unix:/proc/self/fd/2!g' /etc/nginx/nginx.conf; \
    # Pass shell environment variable to php-fpm
    sed -i 's/;clear_env = no/clear_env = no/g' /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf; \
    # Enable slow log
    sed -i 's!;request_slowlog_timeout = 0!request_slowlog_timeout = 5!g' /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf; \
    sed -i 's!;slowlog = log/\$pool.log.slow!slowlog = /proc/self/fd/2!g' /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf; \
    #
    # Blackfire CLI
    # Note: We need to temporarily disable set -e, since the Blackfire installer will complain because it can't start
    # the agent. This is because this environment was not booted with systemd as init system. But we don't care. \
    # We don't actually need the agent to be running, we just want the CLI so we can install the Probe
    set +e; \
    bash -c "$(curl -L https://installer.blackfire.io/installer.sh)"; \
    set -e; \
    #
    # Blackfire Probe
    blackfire php:install; \
    printf "blackfire.agent_socket=tcp://blackfire:8707\n" >> /etc/php/${PHP_VERSION}/fpm/conf.d/99-blackfire.ini; \
    #
    # Make sure everything works \
    blackfire -V; \
    curl --version; \
    nginx -v; \
    php -v; \
    php-fpm${PHP_VERSION} -v; \
    supervisord --version;

COPY supervisor/php-fpm.conf /etc/supervisor/conf.d/php-fpm.conf
COPY supervisor/nginx.conf /etc/supervisor/conf.d/nginx.conf
COPY nginx.conf /etc/nginx/sites-available/default
COPY phpinfo.php /var/www/public/phpinfo.php
