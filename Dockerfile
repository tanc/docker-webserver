FROM ubuntu:12.04

MAINTAINER Agile Collective <info@agile.coop>

# Set timezone and locale.
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# multiverse repository required to install libapache2-mod-fastcgi
RUN echo "deb http://archive.ubuntu.com/ubuntu precise multiverse" >> /etc/apt/sources.list

# Prevent services autoload (http://jpetazzo.github.io/2013/10/06/policy-rc-d-do-not-start-services-automatically/)
RUN echo '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

RUN \
    # Update system
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y && \
    # Install packages
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install php5-fpm php5-mysql php5-imagick imagemagick \
    php5-mcrypt php5-curl php5-gd php5-sqlite php5-common php-apc \
    php-pear php5-json php5-memcache php5-xdebug php5-intl \
    mysql-client supervisor \
    vim curl wget openssh-server ssmtp \
    apache2-mpm-worker libapache2-mod-fastcgi && \
    # Cleanup
    DEBIAN_FRONTEND=noninteractive apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN a2enmod actions alias fastcgi rewrite ssl && \
    a2ensite default-ssl

# Configuration
ADD ./config/apache2/sites-available/default /etc/apache2/sites-available/default
ADD ./config/apache2/sites-available/default-ssl /etc/apache2/sites-available/default-ssl
ADD ./config/apache2/sites-available/host.conf /etc/apache2/sites-available/includes/host.conf
ADD ./config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD ./config/apache2/mods-enabled/fastcgi.conf /etc/apache2/mods-enabled/fastcgi.conf
ADD ./config/php5/conf.d/xdebug.ini /etc/php5/fpm/conf.d/xdebug.ini

# Generate SSL certificate and key
RUN openssl req -batch -nodes -newkey rsa:2048 -keyout /etc/ssl/private/server.key -out /tmp/server.csr && \
    openssl x509 -req -days 365 -in /tmp/server.csr -signkey /etc/ssl/private/server.key -out /etc/ssl/certs/server.crt;rm /tmp/server.csr

RUN \
    # PHP settings changes
    sed -i 's/memory_limit = .*/memory_limit = 196M/' /etc/php5/fpm/php.ini && \
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php5/fpm/php.ini && \
    sed -i 's/cgi.fix_pathinfo = .*/cgi.fix_pathinfo = 0/' /etc/php5/fpm/php.ini && \
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 500M/' /etc/php5/fpm/php.ini && \
    sed -i 's/post_max_size = .*/post_max_size = 500M/' /etc/php5/fpm/php.ini && \
    # PHP FPM config changes
    sed -i 's/listen = .*/listen = \/var\/run\/php5-fpm\.sock/' /etc/php5/fpm/pool.d/www.conf && \
    sed -i "/;listen.owner = www-data/c\listen.owner = www-data" /etc/php5/fpm/pool.d/www.conf && \
    sed -i "/;listen.group = www-data/c\listen.group = www-data" /etc/php5/fpm/pool.d/www.conf && \
    sed -i "/;listen.mode = 0666/c\listen.mode = 0666" /etc/php5/fpm/pool.d/www.conf && \
    sed -i "/;daemonize = yes/c\daemonize = no" /etc/php5/fpm/php-fpm.conf && \
    # PHP Xdebug settings
    printf "\nxdebug.remote_enable=on\nxdebug.remote_port=9000\nxdebug.remote_connect_back=On" >> /etc/php5/conf.d/20-xdebug.ini && \
    touch /etc/php5/conf.d/zz_phpconfig.ini

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php
RUN mv composer.phar /usr/local/bin/composer

# Install Drush 7.
RUN composer global require drush/drush:7.*
RUN composer global update

# Unfortunately, adding the composer vendor dir to the PATH doesn't seem to work. So:
RUN ln -s /root/.composer/vendor/bin/drush /usr/local/bin/drush

# Mail set up
RUN sed -i 's/\;sendmail_path =/sendmail_path = \/usr\/sbin\/ssmtp \-t/' /etc/php5/fpm/php.ini
RUN sed -i 's/\;sendmail_path =/sendmail_path = \/usr\/sbin\/ssmtp \-t/' /etc/php5/cli/php.ini
RUN sed -i 's/mailhub=mail/mailhub=mailhog\:1025/' /etc/ssmtp/ssmtp.conf

# Setup SSH.
RUN echo 'root:root' | chpasswd
RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN mkdir /var/run/sshd && chmod 0755 /var/run/sshd
RUN mkdir -p /root/.ssh/ && touch /root/.ssh/authorized_keys
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Startup script
# This startup script will configure apache
ADD ./startup.sh /opt/startup.sh
RUN chmod +x /opt/startup.sh

ADD ./config/index.php /var/www/docroot/index.php

RUN usermod -u 1000 www-data && \
    mkdir -p /var/run/apache2/fastcgi/dynamic && \
    chown -R www-data:www-data /var/run/apache2 && \
    chown -R www-data:www-data /var/www

# Default docroot folder name (/var/www/<docroot>)
ENV DOCROOT docroot

EXPOSE 80 443 22

WORKDIR /var/www

CMD /opt/startup.sh; /usr/bin/supervisord -n
