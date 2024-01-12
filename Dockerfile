# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-alpine:3.18 as buildstage
LABEL maintainer="lnogworth"

# build variables
ARG SYNCTHING_RELEASE
ARG NORDVPN_CLIENT_VERSION=3.16.9
ARG DEBIAN_FRONTEND=noninteractive 

RUN \
 echo "**** install build packages ****" && \
  apk add --no-cache \
    build-base \
    go

RUN \
  echo "**** fetch source code ****" && \
  if [ -z ${SYNCTHING_RELEASE+x} ]; then \
    SYNCTHING_RELEASE=$(curl -sX GET "https://api.github.com/repos/syncthing/syncthing/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  mkdir -p \
    /tmp/sync && \
  curl -o \
  /tmp/syncthing-src.tar.gz -L \
    "https://github.com/syncthing/syncthing/archive/${SYNCTHING_RELEASE}.tar.gz" && \
  tar xf \
  /tmp/syncthing-src.tar.gz -C \
    /tmp/sync --strip-components=1 && \
  echo "**** compile syncthing  ****" && \
  cd /tmp/sync && \
  go clean -modcache && \
  CGO_ENABLED=0 go run build.go \
    -no-upgrade \
    -version=${SYNCTHING_RELEASE} \
    build syncthing

# Install dependencies, get the NordVPN Repo, install NordVPN client, cleanup and set executables
RUN echo "**** Get NordVPN Repo ****" && \
    curl https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb --output /tmp/nordvpnrepo.deb && \
    apt-get install -y /tmp/nordvpnrepo.deb && \
    apt-get update -y && \
    echo "**** Install NordVPN client ****" && \
    apt-get install -y nordvpn${NORDVPN_CLIENT_VERSION:+=$NORDVPN_CLIENT_VERSION} && \
    apt-get update && \
    echo "**** Cleanup ****" && \
    apt-get remove -y nordvpn-release && \
    apt-get autoremove -y && \
    apt-get autoclean -y && \
    rm -rf \
		/tmp/* \
		/var/cache/apt/archives/* \
		/var/lib/apt/lists/* \
		/var/tmp/* \
    echo "**** Finished software setup ****"

# Copy all the files we need in the container
COPY /fs /

############## runtime stage ##############
FROM ghcr.io/linuxserver/baseimage-alpine:3.18

# set version label
ARG BUILD_DATE
ARG VERSION

# environment settings
ENV HOME="/config"

RUN \
  echo "**** create var lib folder ****" && \
  install -d -o abc -g abc \
    /var/lib/syncthing

# copy files from build stage and local files
COPY --from=buildstage /tmp/sync/syncthing /usr/bin/
COPY root/ /

# ports and volumes
EXPOSE 8384 22000/tcp 22000/udp 21027/UDP
VOLUME /config

# Make sure NordVPN service is running before logging in and launching Meshnet
ENV S6_CMD_WAIT_FOR_SERVICES=1
CMD nordvpn_login && meshnet_config && meshnet_watch
