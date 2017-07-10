.PHONY: all client server compute client_only
all: client server compute

server: bin/server compute
client: bin/client compute

# install libraries, only needed for server right now.
lib/: shard.yml shard.lock
	shards install

bin/server: src/server.cr src/word-square/word-square-packet.cr src/word-square/version.cr lib/
	crystal build $< -o $@
bin/client: src/client.cr src/word-square/word-square-packet.cr
	crystal build $< -o $@
bin/compute-o%: src/word-square-compute.cr
	crystal build $< -D square_size_$* -o $@

compute: bin/compute-o3 bin/compute-o4 bin/compute-o5 bin/compute-o6 bin/compute-o7 bin/compute-o8 bin/compute-o9 bin/compute-o10 bin/compute-o11
