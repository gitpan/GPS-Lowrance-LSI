# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl GPS-Lowrance-LSI.t'

#########################

use Test::More tests => 2562;
BEGIN { use_ok('GPS::Lowrance::LSI') };

#########################

ok('GPS::Lowrance::LSI::VERSION' ge '0.20');

# At the moment no test cases are specified, since most of the code
# would require connecting to a Lowrance or compatible GPS.

# Eventually tests for checksum and header-building functions will be
# added.

sub chksum {
  return GPS::Lowrance::LSI::lsi_checksum( @_ );
}

sub verify {
  return GPS::Lowrance::LSI::verify_checksum( @_ );
}

# Test the checksum algorithm.  This is probably good enough.

for my $simple (0..255) {
  my $chk = (($simple ^ 0xff) + 1) & 0xff;
  ok( chksum( pack( "C", $simple) ) == $chk );

  for my $detail (qw(1 2 4 8 16 32 64 128 255)) {
    $chk = (((($simple + $detail) & 0xff) ^ 0xff) + 1) & 0xff;
    my $str = pack( "vC", ($simple*256)+$detail, $chk );
    ok( verify( $str ) );    
  }
}

# We assume that Parse::Binary::FixedFormat works, so we don't need
# to test the header formats.

# Likewise, it's difficult to test connection with GPS...

