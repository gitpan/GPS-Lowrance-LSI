package GPS::Lowrance::LSI;

use 5.006;
use strict;
use warnings;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
  lsi_query
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
  lsi_query
);

our $VERSION = '0.01';

use Carp::Assert;

BEGIN {

  my $OS_win = ($^O eq "MSWin32") ? 1 : 0;

  if ($OS_win) {
    eval "use Win32::SerialPort;";
  } else {
    eval "use Device::SerialPort;";
  }

}

use constant LSI_PREAMBLE    => 0x8155;
use constant DEFAULT_TIMEOUT => 30;

sub _str2hex {
  my $str = shift;
  return sprintf('%02x 'x (length($str)), unpack("C"x(length($str)), $str));
}

sub _checksum {
  my $str   = shift;
  my $chksum = 0;
  foreach my $chr (unpack("C"x(length($str)), $str)) {
    $chksum = ($chksum + $chr) & 0xff;
  }
  $chksum = 1 + ($chksum ^ 0xff);
  return $chksum;
}

sub lsi_query {
  my ($port, $cmd, $send_data, $id, $debug, $timeout) = @_;

  my $size = length($send_data);

  assert( ($cmd & 0x80) == 0 ),          if DEBUG;
  assert( $size <= 0xffff ),             if DEBUG;
  assert( ($id >= 0) && ($id <= 0xff) ), if DEBUG;

  my $xmit = pack("vvvC", LSI_PREAMBLE, $cmd, $size, $id);

     $xmit .= pack("C", _checksum($xmit)) . $send_data;

  if ($debug) {
    print STDERR _str2hex($xmit), "\n";
  }

  $port->write( $xmit );

  $timeout ||= DEFAULT_TIMEOUT;

  my $end_time = $timeout + time;

  my $rcvd     = "";
  my $expected = 8;
  my $ack      = 0;

  do {
    my $in = $port->input;

    if ($in ne "") {

      if ($debug) {
	print STDERR _str2hex($in), "\n";
      }

      $expected -= length($in);
      if ($ack) {
	$rcvd .= $in;
      } else {
	my ($magic, $cmd_ack, $rcvd_size, $rcvd_id, $chk) =
	  unpack("vvvCC", $in);

	if ( ($magic == LSI_PREAMBLE) && ($cmd_ack == ($cmd | 0x80)) ) {

	  if ($chk != _checksum( substr($in, 0, -1) )) {
	    warn "response header checksum mismatch"; }

	  $expected = 1+$rcvd_size, if ($rcvd_size);
	  $ack      = 1;
	  $rcvd    .= $in;
	} else {
	  warn "ignoring unrecognized response";
	}
      }
    }

    assert( $expected >= 0 ), if DEBUG;

  } while ($expected && (time < $end_time));

  # if there is a time out, return undef
  if (time >= $end_time) {
    warn "no response";
    return;
  }

  return $rcvd;
}


1;
__END__

=head1 NAME

GPS::Lowrance::LSI - Lowrance Serial Interface Protocol module in Perl

=head1 REQUIREMENTS

The following modules are required to use this module:

  Carp::Assert
  Win32::SerialPort or Device::SerialPort

This module should work with Perl 5.6.x. It has been tested on Perl 5.8.2.

=head1 SYNOPSIS

  use Win32::SerialPort;                # or Device::SerialPort (?)
  use GPS::Lowrance::LSI 'lsi_query';

  my $port = new Win32::SerialPort( 'com1' );

  my $data = lsi_query( $port, 0x30e, "", 0 );

=head1 DESCRIPTION

This module provides I<very> low-level support for the LSI 100
protocol used to communicate with Lowrance GPS devices.

(Higher-level functions and wrappers for specific commands will be
provided in other modules.)

=head2 FUNCTIONS

=over

=item lsi_query

  $data_out = lsi_query( $port, $cmd, $data_in, $id, $debug, $timeout );

This method submits an LSI query sentence (with the command and input
data) to a GPS connected to the device specified by serial port at
C<$port>.  (See the LSI specification on the Lowrance web site for the
specific command codes.)

It then waits C<$timeout> seconds (defaults to 30) for a response.  If
there is no response, it returns C<undef>.

Otherwise, it verifies that the response is well-formed and returns the data.
(The first 8-bytes of the returned data is the response header.)

The format of the rest of the data depends on the command.

If C<$debug> is true, then debugging information is shown.

=back

=head1 CAVEATS

This is an early release of the module, so likely there are bugs.

This module has not (yet) been tested with Device::SerialPort.
Feedback on this would be appreciated.

Win32::SerialPort unfortunately has not been updated since 1999.

=head1 SEE ALSO

The Lowrance Serial Interface (LSI) Protocol is described in a document
available on the Lowrance web site at L<http://www.lowrance.com>.

=head1 AUTHOR

Robert Rothenberg <rrwo at cpan.org>

Please report any bugs using the CPAN Request Tracker at
L<http://rt.cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Robert Rothenberg <rrwo at cpan.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
