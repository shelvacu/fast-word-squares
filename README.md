# Word Square Finder

This is a program that, given a wordlist, finds every possible [word square](https://en.wikipedia.org/wiki/Word_square) of a given order. Using the terminology in the wikipedia article, this program finds both double word squares and normal word squares.

This project requires both the Ruby programming language (available in all sensible package managers) and the [Crystal](https://crystal-lang.org/) programming language. See [here](https://crystal-lang.org/docs/installation/) for how to install crystal.

This program is split into three pieces:

## work-finder-main.cr

This is where the actual juicy (single-threaded) computation happens. There are lots of compiler flags available, but the only one you need is one of the square\_size\_*N* flags. Yes, the order of squares computed is determined at compile-time, for ***SPEED***. An example compile would look like:

    crystal build word-finder-main.cr -D square_size_5 -o build/word-finder-o5

Which makes a program to find squares of order 5, and placed the compiled ELF file in `build/word-finder-o5`. You can then see what options are available with:

	./build/word-finder-o5 -h

## Client

The client is responsible for spinning up multiple instances of the computation binary to take full advantage of multi-core systems, and to collect results and send them to the server. Run like:

	ruby client/main.rb <server name/ip> <path to compute exec> <number of threads to use>

I reccomend that you take the number of threads available on your system and then double that number to get the number of threads to use.

A real invocation of the client might look like:

	nice -n 1 ruby client/main.rb 127.0.0.1 build/word-finder-o5 16

Note the use of `nice` so that the intense computation is a lower priority, therefor not slowing down other things running on the same machine.

## Server

The server is responsible for distributing work among many clients, and collecting the results from all the clients. Note that currently there is no security, and a malicious client could upload bogus results.

To setup the server, first you must initialize the database:

	cd server
	bundle install
	ruby initialize-db.rb <wordlist file name> <word size AKA word square order>

No wordlists are in this source tree, you must provide your own. Make sure the word size you pick here matches what compiler flag used when compiling the client.

Running the server requires no arguments:

	cd server
	ruby work-split-server.rb

Currently there is no built-in way to extract the results into a text file, however they are stored in the main.db sqlite3 file in the table "results".
