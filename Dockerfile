FROM debian:bullseye-slim

WORKDIR /opt

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
       perl make \
       libmodule-build-perl libparams-util-perl libparams-validate-perl libmoosex-app-cmd-perl libdbi-perl libyaml-libyaml-perl libjson-perl \
    && rm -rf /var/lib/apt/lists/*

ADD http://xrl.us/cpanm cpanm
COPY cpanfile cpanfile

RUN perl cpanm --installdeps .

COPY lib lib
COPY share share
COPY bin bin


