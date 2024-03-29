FROM ubuntu:14.04
MAINTAINER danb@renci.org

RUN apt-get update
RUN apt-get upgrade -y

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server supervisor postgresql-9.3 wget dpkg sudo libcurl4-gnutls-dev

RUN mkdir -p /var/run/sshd

#set up supervisor
RUN mkdir -p /var/log/supervisor
ADD ./common/supervisord.conf.etc /etc/supervisor/supervisord.conf
ADD ./common/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# set up an admin user
RUN useradd admin
RUN echo 'admin:admin' | chpasswd
RUN mkdir /home/admin
RUN chown admin:admin /home/admin
RUN chsh -s /bin/bash admin

#install iRODS
RUN wget -P /home/admin ftp://ftp.renci.org/pub/irods/releases/4.0.3/irods-database-plugin-postgres-1.3.deb
RUN wget -P /home/admin ftp://ftp.renci.org/pub/irods/releases/4.0.3/irods-icat-4.0.3-64bit.deb

# install package dependencies to prevent Docker build from erring out
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y `dpkg -I /home/admin/irods-icat-4.0.3-64bit.deb | sed -n 's/^ Depends: //p' | sed 's/,//g'`
RUN dpkg -i /home/admin/irods-icat-4.0.3-64bit.deb

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y `dpkg -I /home/admin/irods-database-plugin-postgres-1.3.deb | sed -n 's/^ Depends: //p' | sed 's/,//g'`
RUN dpkg -i /home/admin/irods-database-plugin-postgres-1.3.deb

# set up the iCAT database
RUN service postgresql start && \
  sudo -u postgres createdb -O postgres 'ICAT' -E UTF8 -l en_US.UTF-8 -T template0 && \
  sudo -u postgres psql -U postgres -d postgres -c "CREATE USER irods WITH PASSWORD 'testpassword'" && \
  sudo -u postgres psql -U postgres -d postgres -c 'GRANT ALL PRIVILEGES ON DATABASE "ICAT" TO irods'

ADD ./icat/server.sh /home/admin/server.sh
RUN chmod a+x /home/admin/server.sh

#irods setup_database
ADD ./icat/dbresp /home/admin/dbresp
RUN service postgresql start && \ 
  sudo su -c "/var/lib/irods/packaging/setup_irods.sh </home/admin/dbresp"

# irods needs to be part of admin to execute supervisorctl
RUN usermod -G admin -a irods

#change irods user's irodsEnv file to point to localhost, since it was configured with a transient Docker container's hostname
RUN sed -i 's/^irodsHost.*/irodsHost localhost/' /var/lib/irods/.irods/.irodsEnv
# change the default zone to be 'ssUppnexZone'
RUN sed -i 's/tempZone/ssUppnexZone/' /var/lib/irods/.irods/.irodsEnv

ADD ./icat/runAll.sh /home/admin/runAll.sh
RUN chmod a+x /home/admin/runAll.sh

EXPOSE 22 1247
ENTRYPOINT /usr/bin/supervisord "-n"

