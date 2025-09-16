FROM docker.io/library/php:8-apache

LABEL org.opencontainers.image.source=https://github.com/digininja/DVWA
LABEL org.opencontainers.image.description="DVWA pre-built image."
LABEL org.opencontainers.image.licenses="gpl-3.0"

WORKDIR /var/www/html

# https://www.php.net/manual/en/image.installation.php
RUN apt-get update \
 && export DEBIAN_FRONTEND=noninteractive \
 && apt-get install -y zlib1g-dev libpng-dev libjpeg-dev libfreetype6-dev iputils-ping git curl \
 && apt-get clean -y && rm -rf /var/lib/apt/lists/* \
 && docker-php-ext-configure gd --with-jpeg --with-freetype \
 && a2enmod rewrite \
 # Use pdo_sqlite instead of pdo_mysql if you want to use sqlite
 && docker-php-ext-install gd mysqli pdo pdo_mysql

# Install MySQL client and server for DVWA database
RUN apt-get update && apt-get install -y \
    default-mysql-server \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY --chown=www-data:www-data . .
COPY --chown=www-data:www-data config/config.inc.php.dist config/config.inc.php

# Configure DVWA database settings
RUN sed -i "s/\$_DVWA\['db_server'\] = '127.0.0.1';/\$_DVWA\['db_server'\] = 'localhost';/" config/config.inc.php && \
    sed -i "s/\$_DVWA\['db_database'\] = 'dvwa';/\$_DVWA\['db_database'\] = 'dvwa';/" config/config.inc.php && \
    sed -i "s/\$_DVWA\['db_user'\] = 'dvwa';/\$_DVWA\['db_user'\] = 'root';/" config/config.inc.php && \
    sed -i "s/\$_DVWA\['db_password'\] = 'p@ssw0rd';/\$_DVWA\['db_password'\] = '';/" config/config.inc.php

# This is configuring the stuff for the API
RUN cd /var/www/html/vulnerabilities/api \
 && composer install

# Expose ports 80 and 443 for Apache
EXPOSE 80 443

# Configure Apache with security hardening
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf && \
    # Hide Apache version information
    echo "ServerTokens Prod" >> /etc/apache2/apache2.conf && \
    echo "ServerSignature Off" >> /etc/apache2/apache2.conf && \
    # Hide PHP version from X-Powered-By header
    echo "expose_php = Off" >> /usr/local/etc/php/conf.d/security.ini && \
    # Enable security headers module
    a2enmod headers && \
    # Configure security headers
    echo '<Directory "/var/www/html">' >> /etc/apache2/apache2.conf && \
    echo '    # Content Security Policy' >> /etc/apache2/apache2.conf && \
    echo '    Header always set Content-Security-Policy "default-src '\''self'\''; script-src '\''self'\'' '\''unsafe-inline'\''; style-src '\''self'\'' '\''unsafe-inline'\''; img-src '\''self'\'' data:; font-src '\''self'\''"' >> /etc/apache2/apache2.conf && \
    echo '    # Permissions Policy' >> /etc/apache2/apache2.conf && \
    echo '    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"' >> /etc/apache2/apache2.conf && \
    echo '    # Security headers for Spectre protection' >> /etc/apache2/apache2.conf && \
    echo '    Header always set Cross-Origin-Embedder-Policy "require-corp"' >> /etc/apache2/apache2.conf && \
    echo '    Header always set Cross-Origin-Opener-Policy "same-origin"' >> /etc/apache2/apache2.conf && \
    echo '</Directory>' >> /etc/apache2/apache2.conf

# Create startup script for MySQL and Apache
RUN echo '#!/bin/bash\n\
service mysql start\n\
mysql -e "CREATE DATABASE IF NOT EXISTS dvwa;"\n\
mysql -e "CREATE USER IF NOT EXISTS '\''root'\''@'\''localhost'\'' IDENTIFIED BY '\''\'\'';"\n\
mysql -e "GRANT ALL PRIVILEGES ON dvwa.* TO '\''root'\''@'\''localhost'\'';"\n\
mysql -e "FLUSH PRIVILEGES;"\n\
exec apache2-foreground' > /usr/local/bin/start-services.sh && \
chmod +x /usr/local/bin/start-services.sh

# Add health check that verifies both Apache and MySQL
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD curl -f http://localhost/ && mysqladmin ping -h localhost || exit 1

# Start both MySQL and Apache
CMD ["/usr/local/bin/start-services.sh"]
