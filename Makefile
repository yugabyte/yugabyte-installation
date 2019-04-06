# Copyright (c) YugaByte, Inc.

.PHONY: test

test: pycodestyle
	test/test.sh

pycodestyle:
	pycodestyle bin/yb-ctl
