#!/bin/bash

ENV_CONF=/etc/php5/fpm/pool.d/env.conf

echo "Configuring Apache2 and PHP5-FPM with environment variables"

# Update php5-fpm with access to Docker environment variables
echo '[www]' > $ENV_CONF
for var in $(env | awk -F= '{print $1}'); do
	# Skip empty/bad variables as this will blow up PHP FPM.
	if [[ ${!var} == '' || ${var} == '_' ]]; then
		echo "Skipping empty/bad variable: ${var}"
	else
		echo "Adding variable: ${var} = ${!var}"
		echo "env[${var}] = ${!var}" >> $ENV_CONF
	fi
done

# Set ServerName of created container
if [ -f /etc/apache2/apache2.conf ]; then
	echo "ServerName $(cat /etc/hostname)" >> /etc/apache2/apache2.conf
fi
