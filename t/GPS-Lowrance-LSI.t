# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl GPS-Lowrance-LSI.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 1;
BEGIN { use_ok('GPS::Lowrance::LSI') };

#########################

# At the moment no test cases are specified, since most of the code
# would require connecting to a Lowrance or compatible GPS.

# Eventually tests for checksum and header-building functions will be
# added.


