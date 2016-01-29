#!/bin/bash

exec &> ~ubuntu/startup-log

set -e
set -x

apt-get update
apt-get install -y git

# Livegrep
apt-get install -y libgflags-dev libgit2-dev libjson0-dev libboost-system-dev libboost-filesystem-dev libsparsehash-dev cmake golang g++ mercurial

# Other
apt-get install -y parallel realpath unzip

# Nginx
apt-get install -y nginx
mkdir -p /etc/nginx/sites-enabled
rm /etc/nginx/sites-enabled/default
cat >/etc/nginx/sites-enabled/mozsearch.conf <<"THEEND"
server {
  listen 80 default_server;
  sendfile off;

  location /static {
    root /home/ubuntu/mozsearch;
  }

  location /mozilla-central/source {
    root /home/ubuntu/docroot;
    try_files /file/$uri /dir/$uri/index.html =404;
    types { }
    default_type text/html;
    expires 1d;
    add_header Cache-Control "public";
  }

  location /mozilla-central/search {
    proxy_pass http://localhost:8000;
  }

  location /mozilla-central/define {
    proxy_pass http://localhost:8000;
  }

  location = / {
    root /home/ubuntu/docroot;
    try_files $uri/help.html =404;
    expires 1d;
    add_header Cache-Control "public";
  }
}
THEEND
chmod 0644 /etc/nginx/sites-enabled/mozsearch.conf

/etc/init.d/nginx reload

while true
do
    COUNT=$(lsblk | grep xvdf | wc -l)
    if [ $COUNT -eq 1 ]
    then break
    fi
done

echo "Volume detected"

mkdir ~ubuntu/index
mount /dev/xvdf ~ubuntu/index

echo "Finished installation"

cat > ~ubuntu/web-server <<"THEEND"
#!/bin/bash

set -e
set -x

cd $HOME

exec &> $HOME/web-server-log

wget https://index.taskcluster.net/v1/task/gecko.v2.mozilla-central.nightly.latest.firefox.linux64-opt/artifacts/public/build/jsshell-linux-x86_64.zip
mkdir js
pushd js
unzip ../jsshell-linux-x86_64.zip
popd

export LD_LIBRARY_PATH=\$HOME/js
export JS=\$HOME/js/js

git clone https://github.com/livegrep/livegrep
pushd livegrep
make
popd
export CODESEARCH=\$HOME/livegrep/bin/codesearch

git clone https://github.com/bill-mccloskey/mozsearch

mkdir -p docroot/file/mozilla-central
mkdir -p docroot/dir/mozilla-central
ln -s $HOME/index/file docroot/file/mozilla-central/source
ln -s $HOME/index/dir docroot/dir/mozilla-central/source
ln -s $HOME/index/help.html docroot

cd mozsearch
nohup python router/router.py $HOME/mozsearch $HOME/index > $HOME/router.log 2> $HOME/router.err < /dev/null &
THEEND

chmod +x ~ubuntu/web-server
su - -c ~ubuntu/web-server ubuntu

echo "Finished"