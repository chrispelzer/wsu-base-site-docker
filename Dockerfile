FROM bitnami/laravel:6
ENV DEBIAN_FRONTEND noninteractive
ENV PHPBREW_SET_PROMPT 1
ENV PHPBREW_RC_ENABLE 1
ENV PHPBREW_ROOT /opt/phpbrew

VOLUME /opt/phpbrew

USER root

# Get basic system utilities
RUN apt-get update && apt-get install -y -qq curl wget make git

# Get packages so phpbrew can compile php from source
# https://php.watch/articles/compile-php-ubuntu
# https://github.com/phpbrew/phpbrew/wiki/Troubleshooting/#compiling-php74-with-the-openssl-extension-error-in-ubuntu-2204
RUN apt-get update && apt-get install -y -qq curl \
    wget \
    make \
    git \
    gcc \
    lbzip2 \
    m4 \
    build-essential \
    autoconf \
    libtool \
    bison \
    re2c \
    pkg-config \
    bzip2 \
    libxml2-dev \
    libssl-dev \
    libbz2-dev \
    zlib1g-dev \
    libmcrypt-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libreadline-dev \
    libjpeg-dev \
    libpng-dev \
    libxpm-dev \
    libpq-dev \
    libicu-dev \
    libfreetype6-dev \
    libldap2-dev \
    libxslt-dev \
    libldb-dev \
    libzip-dev \
    libsystemd-dev

# Install phpbrew so we can get whatever funky version of php we need
# https://phpbrew.github.io/phpbrew/
WORKDIR /tmp
RUN curl -L -O https://github.com/phpbrew/phpbrew/raw/1.28.0/phpbrew \
    && chmod +x phpbrew \
    && mv phpbrew /usr/bin/phpbrew

# Only copy in the phpbrewrc so that phpbrew doesn't reinstall php every time something in the app folder changes
COPY ./base-site/.phpbrewrc /var/www/html/.phpbrewrc

# Install php based on the .phpbrewrc
# https://github.com/phpbrew/phpbrew#known-issues
RUN PHPVERSION=$(awk '{print $3}' /var/www/html/.phpbrewrc) \
    && mkdir -p /opt/phpbrew \
    && phpbrew init --root=/opt/phpbrew \
    && phpbrew install ${PHPVERSION} \
        +default \
        +pdo \
        +mysql \
        +fpm \
        -- \
        --with-gd=shared \
        --enable-gd-natf \
        --with-jpeg-dir=/usr \
        --with-png-dir=/usr \
    && chown -R bitnami:bitnami /opt/phpbrew

# Use a real shell that has features like 'source' because it's 2023 and not 1970
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Load custom php.ini files
COPY ./php-configs /tmp/php-configs/

RUN export PHPVERSION=$(awk '{print $3}' /var/www/html/.phpbrewrc) \
    && echo ${PHPVERSION} \
    && chown -R bitnami:bitnami /tmp/php-configs/

# Back to the bitnami user
USER 1000

# Run the base-site setup steps ensuring that we're on the version of php we expect
RUN wget https://raw.githubusercontent.com/phpbrew/phpbrew/master/shell/bashrc -O /tmp/bashrc \
    && sudo mkdir -p /root/.phpbrew \
    && sudo cp /tmp/bashrc /root/.phpbrew/ \
    && echo 'source /root/.phpbrew/bashrc' | sudo tee -a /root/.bashrc \
    && mkdir -p ~/.phpbrew \
    && cp /tmp/bashrc ~/.phpbrew/ \
    && echo 'source ~/.phpbrew/bashrc' >> ~/.bashrc \
    && chown -R 1000:1000 ${HOME}/.phpbrew \
    && source ~/.phpbrew/bashrc \
    && phpbrew use $(awk '{print $3}' /var/www/html/.phpbrewrc) \
    && sudo cp /tmp/php-configs/php.ini ${PHPBREW_ROOT}/php/${PHPBREW_PHP}/etc/fpm/php.ini \
    && sudo cp /tmp/php-configs/php.ini ${PHPBREW_ROOT}/php/${PHPBREW_PHP}/etc/cli/php.ini

# Install php extensions specific to the required version of PHP.
# Keep in mind these extensions may need to be enabled in the
# appropriate php.ini file too.
RUN source ${HOME}/.phpbrew/bashrc \
    && phpbrew use $(awk '{print $3}' /var/www/html/.phpbrewrc) \
    && phpbrew ext install gd \
    && phpbrew ext enable gd \
    && phpbrew ext install redis \
    && phpbrew ext enable redis

COPY ./docker-scripts/launch.sh /opt/

# Change directories inside the container so that we're "in" the application's folder
WORKDIR /var/www/html

CMD ["/opt/launch.sh"]
