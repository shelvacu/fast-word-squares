.PHONY: all client server compute client_only init-db
all: client server compute init-db stats

server: bin/server compute
client: bin/client compute
stats: bin/stats
init-db: bin/initialize-db

# install libraries, only needed for server & init right now.
lib/: shard.yml shard.lock
	shards install
	touch $@

bin/server: src/server.cr src/word-square/word-square-packet.cr src/word-square/version.cr lib/
	crystal build $< -o $@
bin/client: src/client.cr src/word-square/word-square-packet.cr
	crystal build $< -o $@
bin/stats: src/stats.cr lib/
	crystal build $< -o $@
bin/initialize-db: src/initialize-db.cr lib/
	crystal build $< -o $@
bin/compute-o%: src/word-square-compute.cr src/square_size.cr src/filter_wordlist.cr
	crystal build $< --release -D square_size_$* -D disable_gc -o $@

compute: bin/compute-o3 bin/compute-o4 bin/compute-o5 bin/compute-o6 bin/compute-o7 bin/compute-o8 bin/compute-o9 bin/compute-o10 bin/compute-o11
