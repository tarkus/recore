build:
	mkdir -p lib && ./node_modules/.bin/coffee -c -o lib src

test:
	./node_modules/.bin/_mocha --compilers coffee:coffee-script/register --reporter spec

clean:
	rm -rf lib

dev:
	coffee -wc --bare -o lib src

.PHONY: test
