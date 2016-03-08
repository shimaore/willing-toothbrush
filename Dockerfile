FROM shimaore/debian:2.0.6
MAINTAINER Stéphane Alnet <stephane@shimaore.net>
ENV NODE_ENV production

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  make \
  python-pkg-resources \
  supervisor \
  &&

# Install Node.js using `n`.
  git clone https://github.com/tj/n.git n.git && \
  cd n  && \
  make install  && \
  cd ..  && \
  rm -rf n.git/  && \
  n 4.3.2  && \
  mkdir -p /opt/willing-toothbrush/log

COPY . /opt/willing-toothbrush
WORKDIR /opt/willing-toothbrush
RUN npm install && \
    npm cache clean

CMD ["/usr/bin/supervisord","-n"]
