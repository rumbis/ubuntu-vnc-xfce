# docker build -t accetto/ubuntu-vnc-xfce .
# docker build -t accetto/ubuntu-vnc-xfce:dev .
# docker build --target stage-ubuntu -t dev/ubuntu-vnc-xfce:stage-ubuntu .
# docker build --target stage-xfce -t dev/ubuntu-vnc-xfce:stage-xfce .
# docker build --target stage-vnc -t dev/ubuntu-vnc-xfce:stage-vnc .
# docker build --target stage-novnc -t dev/ubuntu-vnc-xfce:stage-novnc .
# docker build --target stage-wrapper -t dev/ubuntu-vnc-xfce:stage-wrapper .
# docker build --target stage-final -t dev/ubuntu-vnc-xfce:stage-final .
# docker build -t dev/ubuntu-vnc-xfce .
# docker build --build-arg ARG_VNC_RESOLUTION=1360x768 -t accetto/ubuntu-vnc-xfce .
# docker build --build-arg BASETAG=rolling -t accetto/ubuntu-vnc-xfce:rolling .

ARG BASETAG=latest

FROM ubuntu:${BASETAG} as stage-ubuntu

LABEL \
    maintainer="https://github.com/accetto" \
    vendor="accetto"

### 'apt-get clean' runs automatically
RUN apt-get update && apt-get install -y \
        inetutils-ping \
        lsb-release \
        net-tools \
        vim \
    && rm -rf /var/lib/apt/lists/*

### next ENTRYPOINT command supports development and should be overriden or disabled
### it allows running detached containers created from intermediate images, for example:
### docker build --target stage-vnc -t dev/ubuntu-vnc-xfce:stage-vnc .
### docker run -d --name test-stage-vnc dev/ubuntu-vnc-xfce:stage-vnc
### docker exec -it test-stage-vnc bash
# ENTRYPOINT ["tail", "-f", "/dev/null"]

FROM stage-ubuntu as stage-xfce

ENV \
    DEBIAN_FRONTEND=noninteractive \
    LANG='en_US.UTF-8' \
    LANGUAGE='en_US:en' \
    LC_ALL='en_US.UTF-8'

### 'apt-get clean' runs automatically
RUN apt-get update && apt-get install -y \
        mousepad \
        locales \
        supervisor \
        xfce4 \
        xfce4-terminal \
    && locale-gen en_US.UTF-8 \
    && apt-get purge -y \
        pm-utils \
        xscreensaver* \
    && rm -rf /var/lib/apt/lists/*

FROM stage-xfce as stage-vnc

### 'apt-get clean' runs automatically
### installed into '/usr/share/usr/local/share/vnc'
RUN apt-get update && apt-get install -y \
        wget \
    && wget -qO- https://dl.bintray.com/tigervnc/stable/tigervnc-1.9.0.x86_64.tar.gz | tar xz --strip 1 -C / \
    && rm -rf /var/lib/apt/lists/*

FROM stage-vnc as stage-novnc

### same parent path as VNC
ENV NO_VNC_HOME=/usr/share/usr/local/share/noVNCdim

### 'apt-get clean' runs automatically
### 'python-numpy' used for websockify/novnc
### ## Use the older version of websockify to prevent hanging connections on offline containers, 
### see https://github.com/ConSol/docker-headless-vnc-container/issues/50
### installed into '/usr/share/usr/local/share/noVNCdim'
RUN apt-get update && apt-get install -y \
        python-numpy \
    && mkdir -p ${NO_VNC_HOME}/utils/websockify \
    && wget -qO- https://github.com/novnc/noVNC/archive/v1.1.0.tar.gz | tar xz --strip 1 -C ${NO_VNC_HOME} \
    && wget -qO- https://github.com/novnc/websockify/archive/v0.8.0.tar.gz | tar xz --strip 1 -C ${NO_VNC_HOME}/utils/websockify \
    && chmod +x -v ${NO_VNC_HOME}/utils/*.sh \
    && rm -rf /var/lib/apt/lists/*

### add 'index.html' for choosing noVNC client
RUN echo \
"<!DOCTYPE html>\n" \
"<html>\n" \
"    <head>\n" \
"        <title>noVNC</title>\n" \
"        <meta charset=\"utf-8\"/>\n" \
"    </head>\n" \
"    <body>\n" \
"        <p><a href=\"vnc_lite.html\">noVNC Lite Client</a></p>\n" \
"        <p><a href=\"vnc.html\">noVNC Full Client</a></p>\n" \
"    </body>\n" \
"</html>" \
> ${NO_VNC_HOME}/index.html

FROM stage-novnc as stage-wrapper

### 'apt-get clean' runs automatically
### Install nss-wrapper to be able to execute image as non-root user
RUN apt-get update && apt-get install -y \
        gettext \
        libnss-wrapper \
    && rm -rf /var/lib/apt/lists/*

FROM stage-wrapper as stage-final

LABEL \
    any.accetto.description="Headless Ubuntu VNC/noVNC container with Xfce desktop" \
    any.accetto.display-name="Headless Ubuntu/Xfce VNC/noVNC container" \
    any.accetto.expose-services="6901:http,5901:xvnc" \
    any.accetto.tags="ubuntu, xfce, vnc, novnc"

### Arguments can be provided during build
ARG ARG_HOME
ARG ARG_VNC_BLACKLIST_THRESHOLD
ARG ARG_VNC_BLACKLIST_TIMEOUT
ARG ARG_VNC_PW
ARG ARG_VNC_RESOLUTION

ENV \
    DISPLAY=:1 \
    HOME=${ARG_HOME:-/home/headless} \
    NO_VNC_PORT="6901" \
    STARTUPDIR=/dockerstartup \
    VNC_BLACKLIST_THRESHOLD=${ARG_VNC_BLACKLIST_THRESHOLD:-20} \
    VNC_BLACKLIST_TIMEOUT=${ARG_VNC_BLACKLIST_TIMEOUT:-0} \
    VNC_COL_DEPTH=24 \
    VNC_PORT="5901" \
    VNC_PW=${ARG_VNC_PW:-headless} \
    VNC_RESOLUTION=${ARG_VNC_RESOLUTION:-1024x768} \
    VNC_VIEW_ONLY=false

### Creates home folder
WORKDIR ${HOME}

COPY [ "./src/startup", "${STARTUPDIR}/" ]

### Preconfigure Xfce
COPY [ "./src/home/Desktop", "./Desktop/" ]
COPY [ "./src/home/config/xfce4/panel", "./.config/xfce4/panel/" ]
COPY [ "./src/home/config/xfce4/xfconf/xfce-perchannel-xml", "./.config/xfce4/xfconf/xfce-perchannel-xml/" ]

### 'generate_container_user' has to be sourced to hold all env vars correctly
RUN echo 'source $STARTUPDIR/generate_container_user' >> ${HOME}/.bashrc

RUN chmod +x ${STARTUPDIR}/set_user_permissions.sh \
    && ${STARTUPDIR}/set_user_permissions.sh $STARTUPDIR $HOME \
    && gtk-update-icon-cache -f /usr/share/icons/hicolor

EXPOSE ${VNC_PORT} ${NO_VNC_PORT}

ENV REFRESHED_AT 2019-06-20

### Issue #7: Mitigating problems with foreground mode
WORKDIR ${STARTUPDIR}
ENTRYPOINT ["./vnc_startup.sh"]
CMD [ "--wait" ]
