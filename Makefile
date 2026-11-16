HARE = hare

dsh-hare: cmd/dsh/*.ha cmd/dsh/*.s
	$(HARE) build -lc -o $@ cmd/dsh/

test: dsh-hare
	./tests/run.sh

bench: dsh-hare
	./bench.sh

install: dsh-hare
	install -Dm755 dsh-hare $(HOME)/.local/bin/dsh-hare

clean:
	rm -f dsh-hare

.PHONY: test bench install clean
