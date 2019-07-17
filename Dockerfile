FROM node:alpine
RUN apk add --no-cache tini
COPY . /src/app
WORKDIR /src/app
RUN npm install && \
    npm install && \
    npm run build && \
    npm cache clean -f
USER root
ENTRYPOINT ["/sbin/tini","--","node","server.js"]
