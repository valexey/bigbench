V := ../../../vostok

sort : $(V)/result/o7c FileSort.mod
	$< FileSort.mod FileSort.c $(V)/singularity/definition
	$(CC) -O2 -I $(V)/singularity/implementation FileSort.c $(V)/singularity/implementation/*.c -o sort
	-rm FileSort.c

clean :
	-rm sort FileSort.c

./PHONY: clean
