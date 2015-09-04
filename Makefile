NAME=shimaore/`jq -r .name package.json`
TAG=`jq -r .version package.json`

image: Dockerfile
	docker build --rm=true -t ${NAME}:${TAG} .
	docker tag -f ${NAME}:${TAG} ${REGISTRY}/${NAME}:${TAG}

tests:
	npm test

push: image tests
	docker push ${REGISTRY}/${NAME}:${TAG}
	docker push ${NAME}:${TAG}
