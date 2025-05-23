-e TZ=America/Maceio

docker run -ti --detach --name restreamer --privileged -e TZ=America/Maceio --volume ${HOME}/confs/montagem_docker/restreamer/core/config:/core/config --volume ${HOME}/confs/montagem_docker/restreamer/core/data:/core/data --volume ${HOME}/confs/montagem_docker/restreamer/core/config/etc/timezone:/etc/timezone:rw --volume ${HOME}/confs/montagem_docker/restreamer/core/config/etc/localtime:/etc/localtime:rw --publish 8080:8080 --publish 8181:8181 --publish 1935:1935 --publish 1936:1936 --publish 6000:6000/udp --add-host=host.docker.internal:host-gateway --network=redeswag --restart unless-stopped  datarhei/restreamer:latest

sudo docker run -d -ti --restart=always --name restreamer \
   -e TZ=America/Maceio \
   -v ${HOME}/workspace/docker_compose/restreamer/core/config:/core/config \
   -v ${HOME}/workspace/docker_compose/restreamer/core/data:/core/data \
   -v ${HOME}/workspace/docker_compose/restreamer/core/config/etc/timezone:/etc/timezone:ro \
   -v ${HOME}/workspace/docker_compose/restreamer/core/config/etc/localtime:/etc/localtime:ro \
   --add-host=host.docker.internal:host-gateway \
   --network=redeswag \
   --runtime=nvidia --privileged \
   -p 8080:8080 -p 8181:8181 \
   -p 1935:1935 -p 1936:1936 \
   -p 6000:6000/udp \
   datarhei/restreamer:cuda-latest