#!/usr/bin/env bash
# Installs dependencies and deploys TWLight to a single Debian host.

# Ensure the docker repo will be usable.
apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
# Add the apt key
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
# Add the apt repo
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
# Update
apt update && apt upgrade -y

# Install docker
apt install -y docker-ce docker-ce-cli containerd.io
curl -L "https://github.com/docker/compose/releases/download/1.25.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Add twlight user
adduser twlight --disabled-password --quiet ||:
usermod -a -G docker twlight

# Pull TWLight code and make twlight user the owner
cd /srv
git clone https://github.com/WikipediaLibrary/TWLight.git ||:
cd /srv/TWLight
# Get on correct branch
echo "Enter git branch: (eg. staging \| production):"
read TWLIGHT_GIT_BRANCH
git checkout "${TWLIGHT_GIT_BRANCH}" && git pull

echo "Enter DJANGO_DB_NAME:"
read DJANGO_DB_NAME
echo "Enter DJANGO_DB_USER:"
read DJANGO_DB_USER
echo "Enter DJANGO_DB_PASSWORD:"
read DJANGO_DB_PASSWORD
echo "Enter MYSQL_ROOT_PASSWORD:"
read MYSQL_ROOT_PASSWORD
echo "Enter SECRET_KEY:"
read SECRET_KEY
echo "Enter TWLIGHT_OAUTH_CONSUMER_KEY:"
read TWLIGHT_OAUTH_CONSUMER_KEY
echo "Enter TWLIGHT_OAUTH_CONSUMER_SECRET:"
read TWLIGHT_OAUTH_CONSUMER_SECRET
echo "Enter TWLIGHT_EZPROXY_SECRET:"
read TWLIGHT_EZPROXY_SECRET

chown -R twlight:twlight /srv/TWLight

read -r -d '' TWLIGHT <<- EOF

docker swarm init
# drop any existing services
docker service ls -q | xargs docker service rm
# drop any existing secrets
docker secret ls -q | xargs docker secret rm

cd /srv/TWLight
printf "${DJANGO_DB_NAME}" | docker secret create DJANGO_DB_NAME -
printf "${DJANGO_DB_USER}" | docker secret create DJANGO_DB_USER -
printf "${DJANGO_DB_PASSWORD}" | docker secret create DJANGO_DB_PASSWORD -
printf "${MYSQL_ROOT_PASSWORD}" | docker secret create MYSQL_ROOT_PASSWORD -
printf "${SECRET_KEY}" | docker secret create SECRET_KEY -
printf "${TWLIGHT_OAUTH_CONSUMER_KEY}" | docker secret create TWLIGHT_OAUTH_CONSUMER_KEY -
printf "${TWLIGHT_OAUTH_CONSUMER_SECRET}" | docker secret create TWLIGHT_OAUTH_CONSUMER_SECRET -
printf "${TWLIGHT_EZPROXY_SECRET}" | docker secret create TWLIGHT_EZPROXY_SECRET -

docker stack deploy -c "docker-compose.yml" -c "docker-compose.${TWLIGHT_GIT_BRANCH}.yml" "${TWLIGHT_GIT_BRANCH}"

echo 'Setting up crontab. *WARNING* This will create duplicate jobs if run repeatedly.'
(crontab -l 2>/dev/null; echo '# Reclaim disk space previously used by docker.') | crontab -
(crontab -l 2>/dev/null; echo '0 5 * * * docker system prune -a -f; docker volume rm $(docker volume ls -qf dangling=true)') | crontab -
(crontab -l 2>/dev/null; echo '# Run django_cron tasks.') | crontab -
(crontab -l 2>/dev/null; echo '*/5 * * * *  docker exec -t $(docker ps -q -f name="\${TWLIGHT_GIT_BRANCH}_twlight") /app/bin/twlight_docker_entrypoint.sh python manage.py runcrons') | crontab -
(crontab -l 2>/dev/null; echo '# Update the running stack if there is a new image.') | crontab -
(crontab -l 2>/dev/null; echo '*/5 * * * *  /srv/TWLight/bin/./twlight_docker_deploy.sh') | crontab -

EOF
sudo su --login twlight /usr/bin/env bash -c "${TWLIGHT}"
