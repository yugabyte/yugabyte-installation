# Copyright (c) YugaByte, Inc.

.PHONY: test

test: pycodestyle
	test/test.sh

pycodestyle:
	pycodestyle --config=pycodstyle.conf bin/yb-ctl
