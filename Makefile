build:
	docker login
	docker buildx build --platform linux/amd64 -t phyzical/cs2-modded-sever --push   .