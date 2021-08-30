FROM jrei/systemd-ubuntu:18.04

LABEL maintainer="devops@carbyne911.com"

ARG WGW_SERVICE_GIT_BRANCH=develop
ARG GSTREAMER_VERSION=1.18.4


#environment variables
ENV JANUS_CERT_PATH=/opt/janus/share/janus/certs
ENV CERT_PATH=/opt/janus/share/janus/certs/cert.pem
ENV KEY_PATH=/opt/janus/share/janus/certs/key.pem
ENV RTP_CERT_PATH=/opt/janus/share/janus/certs/rtpcert.pem
ENV RTP_KEY_PATH=/opt/janus/share/janus/certs/rtpkey.pem
ENV TRANSPORT_HTTP_CFG_PATH=/opt/janus/etc/janus/janus.transport.http.jcfg

ENV JANUS_ENV=dev
ENV JANUS_CERT_FILENAME=wgw_carbyneapi-dev_com_cert.pem
ENV JANUS_KEY_FILENAME=wgw_carbyneapi-dev_com_key.pem
ENV SGW_URL=sgw-eu-central-1-dev.sgw.carbyneapi-dev.com
ENV WGW_URL=-1
ENV WGW_MACHINE_IP=-1
ENV JANUS_DIR=WGWService
ENV MIN_PORT=20000
ENV MAX_PORT=40000
ENV SGW_APPLICATION=ClientVideo
ENV AWS_S3_BUCKET_PATH_UPDATE_FOLDER=s3://carbyne-deployment-conf/wgw-service/$JANUS_ENV/
ENV DEPLOYMENT_CONF_VERSION=1
ENV WGW_LOG_FILE_PATH=/home/ubuntu/logs/wgw.logs
ENV EC2_ID=instance_id
ENV SGW_PORT=1935
ENV AWS_CREDENTIALS_ACCESS_KEY_ID=-1
ENV AWS_CREDENTIALS_SECRET_ACCESS_KEY=-1
ENV AWS_CREDENTIALS_PROFILE_NAME=default
ENV AWS_CREDENTIALS_FILE_PATH=/root/.aws/credentials
# ENV AWS_S3_UPLOAD_BUCKET=carbyne-media-platform-dev





# create working directory
RUN mkdir -p /home/ubuntu

# install essential tools
RUN apt-get update \
 && apt-get install wget unzip zip -y 

# install python and meson
RUN apt-get update && apt-get install -y python3-pip \
&& pip3 install meson && export PATH=$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH

# install dev dependencies
RUN apt-get update && apt-get -y --no-install-recommends install \
    build-essential \
    pkg-config \
    git \
    cmake \
    autoconf \
    autopoint \
    libssl1.0-dev \
    curl \
    libconfig-dev \
    aptitude \
    gdb \
    coturn \
    jq \ 
    awscli \
    lsof \
    logrotate

# install ninja
RUN apt install -y python3 git ninja-build python3-pip && pip3 install --user meson
#install gstreamer dev dependencies
RUN apt-get -y install \
    m4 \
    libmicrohttpd-dev \
    libjansson-dev  \
    libssl-dev \
    libsrtp-dev \
    libsofia-sip-ua-dev \
    libglib2.0-dev \
    libopus-dev \
    libogg-dev \
    libcurl4-openssl-dev \
    liblua5.3-dev \
    libconfig-dev  \
    pkg-config \
    gengetopt \
    libtool \
    automake \
    gtk-doc-tools \
    glib-2.0 \
    bison \
    flex \
    libglib2.0-dev \
    libunwind-dev \
    libdw-dev \
    libgtk-3-dev \
	libcairo-dev \
	libspeex-dev \
	libdv-dev \
	libsoup2.4-dev \
	qtdeclarative5-dev \
	libwavpack-dev \
    libvo-aacenc-dev \
    libvpx-dev \
    libgstreamer1.0-dev 
# compile and install the latest gstreamer
RUN cd /home/ubuntu \
    && git clone -b "${GSTREAMER_VERSION}" https://gitlab.freedesktop.org/gstreamer/gst-build.git \  
    && cd gst-build \
    && meson build \
    && ninja -C build \
    && ninja -C build install \
    && cd /home/ubuntu \
    && rm -rf gst-build 

  




RUN apt-get install cron

# copy admin script


RUN mkdir /home/ubuntu/logs/ \
    && touch $WGW_LOG_FILE_PATH \
    && chmod 777 $WGW_LOG_FILE_PATH
# test and change the premissions of systemctl







RUN wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
    && dpkg -i amazon-cloudwatch-agent.deb \
    && rm amazon-cloudwatch-agent.deb



# install additional libs
RUN cd /home/ubuntu/ \ 
 && aptitude install libmicrohttpd-dev libjansson-dev  \
	libssl-dev libsrtp-dev libsofia-sip-ua-dev libglib2.0-dev \
	libopus-dev libogg-dev libcurl4-openssl-dev liblua5.3-dev libconfig-dev  pkg-config gengetopt \
	libtool automake -y

# install libnice-dev
RUN apt remove libnice-dev -y \ 
    && apt remove  libnice10  -y  \ 
    && git clone -b 0.1.17 https://gitlab.freedesktop.org/libnice/libnice.git \
    && apt-get install libtool m4 automake 

# install libnice
RUN cd libnice/ \
    && libtoolize \
    && aclocal \ 
    && ./autogen.sh \ 
    && ./configure \
    && automake --add-missing && autoconf \
    && make &&  make install \
    && cd ../ \
    && rm -rf ./libnice

# install libsrtp
RUN cd /home/ubuntu \ 
    && apt remove libsrtp0 -y \ 
    && wget https://github.com/cisco/libsrtp/archive/v2.2.0.tar.gz \ 
    && tar xfv v2.2.0.tar.gz \ 
    && cd libsrtp-2.2.0/ \ 
	&& ./configure --prefix=/usr --enable-openssl --disable-aes-gcm \ 
	&& make shared_library &&  make install  \
    && cd ../ \
    && rm -rf ./libsrtp-2.2.0

# install usrsctp
RUN cd /home/ubuntu/ \    
	&& git clone https://github.com/sctplab/usrsctp   \ 
	&& cd /home/ubuntu/usrsctp   \ 
	&& ./bootstrap  \ 
	&& ./configure --prefix=/usr && make &&  make install \ 
	&& cd /home/ubuntu \
    && rm -rf ./usrsctp


# install libwebsockets
RUN git clone git://git.libwebsockets.org/libwebsockets  ||  \ 
	git clone https://github.com/warmcat/libwebsockets.git \ 
    && cd libwebsockets \ 
	# If you want the stable version of libwebsockets, uncomment the next line
	&& git checkout v2.4-stable \ 
	&& mkdir build \ 
	&& cd build \ 
	# See https://github.com/meetecho/janus-gateway/issues/732 re: LWS_MAX_SMP
	&& cmake -DLWS_MAX_SMP=1 -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_C_FLAGS="-fpic" .. \ 
	&& make &&  make install \ 
	&& cd /home/ubuntu  \
    && rm -rf ./libwebsockets

# install pahp mqtt
RUN cd /home/ubuntu/ \ 
	&& git clone https://github.com/eclipse/paho.mqtt.c.git \ 
	&& cd paho.mqtt.c \ 
	&& make &&  make install \ 
	&& cd /home/ubuntu/  \
    && rm -rf ./paho.mqtt.c


# COPY ../ /home/ubuntu/WGWService

# clone wgw code
# 
COPY /ci/deployment/scripts/deploy-scripts/wgw_version /home/ubuntu/wgw_version
COPY /plugins/janus_videoroom.c /home/ubuntu/janus_videoroom.c

RUN cd /home/ubuntu/  \  
   && echo $(cat /home/ubuntu/wgw_version) \
   && git clone -b "${WGW_SERVICE_GIT_BRANCH}" --single-branch https://github.com/reporty/WGWService.git \
   && cp /home/ubuntu/janus_videoroom.c /home/ubuntu/WGWService/plugins/janus_videoroom.c \
   && cd /home/ubuntu/WGWService \   
   && sh autogen.sh \   
   && ./configure --prefix=/opt/janus \   
   && make &&  make install  \   
   && make configs 

#update before installation
RUN apt-get update && apt-get upgrade -y

# install node-dev
RUN apt-get install -y nodejs-dev node-gyp libssl1.0-dev 
# install node
RUN apt-get install -y nodejs npm  \
    && apt-get install npm


# link library
RUN export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib

# remove uneeded libraries
RUN apt-get remove -y \
    cmake \
    m4 \
    libmicrohttpd-dev \
    libjansson-dev  \
    libssl-dev \
    libsrtp-dev \
    libsofia-sip-ua-dev \
    libglib2.0-dev \
    libopus-dev \
    libogg-dev \
    libcurl4-openssl-dev \
    liblua5.3-dev \
    libconfig-dev  \
    pkg-config \
    gengetopt \
    libtool \
    automake \
    gtk-doc-tools \
    glib-2.0 \
    bison \
    flex \
    libglib2.0-dev \
    libunwind-dev \
    libdw-dev \
    libgtk-3-dev \
	libcairo-dev \
	libspeex-dev \
	libdv-dev \
	libsoup2.4-dev \
	qtdeclarative5-dev \
	libwavpack-dev \
    libgstreamer1.0-0 \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-doc \
    gstreamer1.0-tools \
    gstreamer1.0-x \
    gstreamer1.0-alsa \
    gstreamer1.0-gl \
    gstreamer1.0-gtk3 \
    gstreamer1.0-qt5 \
    gstreamer1.0-pulseaudio \
    gstreamer1.0-rtsp \
    libnice-dev \
    gstreamer1.0-nice \
    libgstreamer-plugins-base1.0-0 \
    libgstreamer1.0-0 \
    libgstreamer1.0-dev 



# expose ports
EXPOSE 8188
EXPOSE 7088
EXPOSE 7889
EXPOSE 7188
EXPOSE 8088
EXPOSE 8089
EXPOSE 1937
EXPOSE 443
EXPOSE 20000-40000                                                                                                  
EXPOSE 20000-40000/udp


COPY ./ci/scripts/is_health.sh /home/ubuntu
RUN chmod 777 /home/ubuntu/is_health.sh 

# copy all of the needed files
COPY ./ci/aws/admin_clean_room.zip /home/ubuntu
COPY ./ci/config/janus.jcfg /home/ubuntu
COPY ./ci/config/janus.transport.http.jcfg /home/ubuntu
COPY ./ci/config/janus.transport.websockets.jcfg /home/ubuntu
COPY ./ci/config/janus.plugin.videoroom.jcfg /home/ubuntu
COPY ./ci/scripts/systemctl3.py /usr/bin/systemctl
COPY ./ci/entrypoint.sh  /home/ubuntu
COPY ./ci/config/amazon-cloudwatch-agent.json /home/ubuntu
COPY ./ci/scripts/admin_clean_room.sh /home/ubuntu
# change the premissions of entrypoint
RUN chmod +x /home/ubuntu/entrypoint.sh \
    && sed -i -e 's/\r$//' /home/ubuntu/entrypoint.sh
# run admin script
RUN chmod 777 /home/ubuntu/admin_clean_room.sh
RUN test -L /bin/systemctl || ln -sf /usr/bin/systemctl /bin/systemctl
RUN chmod +x /usr/bin/systemctl
# install admin zip
RUN  cd /home/ubuntu/ \ 
    && unzip admin_clean_room.zip \ 
    && cd admin_clean_room \ 
    && npm i ws




ENTRYPOINT ["/home/ubuntu/entrypoint.sh"]