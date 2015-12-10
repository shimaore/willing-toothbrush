FROM shimaore/debian:2.0.4
MAINTAINER Stéphane Alnet <stephane@shimaore.net>

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  make \
  python-pkg-resources \
  supervisor

# Install Node.js using `n`.
RUN git clone https://github.com/tj/n.git
WORKDIR n
RUN make install
WORKDIR ..
RUN n 4.2.1
ENV NODE_ENV production

COPY . /opt/willing-toothbrush
WORKDIR /opt/willing-toothbrush
RUN mkdir -p log
RUN npm install

CMD ["/usr/bin/supervisord","-n"]
