
filesort : ../vostok/result/o7c
	$< FileSort.mod FileSort.c ../vostok/singularity/definition
	$(CC) -O2 -I ../vostok/singularity/implementation FileSort.c ../vostok/singularity/implementation/*.c -o $@
	echo && ./$@

../vostok/result/o7c :
	cd .. && make

clean :
	rm filesort FileSort.c

./PHONY: clean
