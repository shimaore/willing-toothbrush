NAME=shimaore/`jq -r .name package.json`
TAG=`jq -r .version package.json`

image: Dockerfile
	docker build -t ${NAME}:${TAG} .
	docker tag -f ${NAME}:${TAG} ${REGISTRY}/${NAME}:${TAG}

tests:
	npm test

push: image tests
	docker push ${REGISTRY}/${NAME}:${TAG}
	docker push ${NAME}:${TAG}
	docker rmi ${REGISTRY}/${NAME}:${TAG}
	docker rmi ${NAME}:${TAG}
