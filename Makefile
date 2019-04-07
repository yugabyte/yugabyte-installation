# Copyright (c) YugaByte, Inc.

.PHONY: test

test: pycodestyle
	test/test.sh

pycodestyle:
	pycodestyle --config=pycodestyle.conf bin/yb-ctl
