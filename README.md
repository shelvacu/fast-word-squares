# Word Square Finder

This is a program that, given a wordlist, finds every possible [word square](https://en.wikipedia.org/wiki/Word_square) of a given order. Using the terminology in the wikipedia article, this program finds both double word squares and normal word squares.

This project requires the [Crystal](https://crystal-lang.org/) programming language. See [here](https://crystal-lang.org/docs/installation/) for how to install Crystal.

----

## Quickstart

Some weird guy asked you to please run this program on your computer so that he can find word squares.

Do this:

    git clone https://github.com/shelvacu/fast-word-squares.git
	cd fast-word-squares
	make client

Then run the client, giving the server address as the first argument. No other arguments are required.

	bin/client <server addr>

----

This program is split into three pieces:

## word-finder-main.cr

This is where the actual juicy (single-threaded) computation happens. There are lots of compiler flags available, but the only one you need is one of the square\_size\_*N* flags. Yes, the order of squares computed is determined at compile-time, for ***SPEED***. All the binaries you'd need are compiled by the Makefile, but if you want to compile it manually, an example compile would look like:

    crystal build word-finder-main.cr -D square_size_5 -o build/word-finder-o5

Which makes a program to find squares of order 5, and placed the compiled ELF file in `build/word-finder-o5`. You can then see what options are available with:

	./build/word-finder-o5 -h

## Client

The client is responsible for spinning up multiple instances of the computation binary to take full advantage of multi-core systems, and to collect results and send them to the server. Run like:

	make client
	bin/client <server addr>

The number of processes used defaults to number of virtual cores times 2. This can be changed with `-t` or `--threads` (somewhat of a misnomer, actually processes).

The compute binary (word-finder) binary is located automatically, or can be specified explicitly with `-c` or `--compute-exec`.

A real invocation of the client might look like:

	nice -n 1 bin/client 127.0.0.1

Note the use of `nice` so that the intense computation is a lower priority, therefor not slowing down other things running on the same machine.

## Server

The server is responsible for distributing work among many clients, and collecting the results from all the clients. Note that currently there is no security/verification, and a malicious or buggy client could upload bogus results.

### Server Init

To setup the server, first you must initialize the database:

	make init-db
	bin/initialize-db <wordlist file name> <word size> [ <start length> <compute binary location> ]
	
The `initialize-db` command takes either 2 or 4 arguments. It will create a file named `db.sqlite` in the current directory.

You must provide these arguments:

1. `wordlist file name` Wordlists are not in this source tree, you must provide your own. The wordlist will automatically be filtered to have only words of the correct length, and only words with nothing besides letters a-z. Duplicates are removed.
2. `word size` (eg `5`). Also known as the "order" of the word square.

You must provide both or neither of these options:

03. `start length` This determines how many cells to fill in each word square to start off each work piece. This number should be tuned such that each worker process takes about a minute to finish, but things will still work just fine if they take a second or an hour. As this value gets smaller, each worker process will take longer to do each piece of work, and the database will be smaller and take a shorter amount of time to generate. As this number gets bigger, each worker process will take less time, and the database will be larger, and take longer to initialize.

    This defaults to the same size as the words, the order of the squares to find. In that case no compute binary is needed, since the set of work pieces is exactly the same as the set of words.

04. `compute binary location` Path to the compute binary, needed to correctly populate the work_pieces table when using a start length that is not the same as the word size. The compute binary you want will start with `compute-o` and end with the word size, and be in the `bin` directory. For example, if you are using a word size of 6, you will want `compute-o6`, which can be compiled with `make bin/compute-o6`.

### Server Run

Running the server requires no arguments:

	bin/server

However, the `db.sqlite` must be present in the data directory, which defaults to the working directory.

The server will also create a logfile and results file automatically. I reccomend creating a dedicated data directory and using it like so:

    mkdir word-square-data
	mv db.sqlite word-square-data #move the sqlite file made by initialize-db into the data dir
	bin/server --data-folder word-square-data

That way things are a little less cluttered.
