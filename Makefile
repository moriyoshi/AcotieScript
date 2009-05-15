all:
	yacc -b parser -dv parser.y
	lex -o lex.c lex.l
	g++ $(subst -O2,,$(shell llvm-config --cflags --ldflags --libs)) -o acotiescript parser.tab.c lex.c
clean:
	rm parser.tab.[ch] lex.c parser.output acotiescript
