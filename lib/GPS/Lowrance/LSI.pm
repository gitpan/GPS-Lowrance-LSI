package GPS::Lowrance::LSI;

use 5.006;
use strict;
use warnings;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
  lsi_query lsi_checksum
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
  lsi_query
);

our $VERSION = '0.10';

use Carp::Assert;
use Parse::Binary::FixedFormat;

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

# _str2hex is a really simple routine to output hex dumps of data;
# it's not worthwhile using Data::Hexdumper or family just for this.

sub _str2hex {
  my $str = shift;
  return sprintf('%02x 'x (length($str)), unpack("C"x(length($str)), $str));
}

# calculate twos-compliment checksum

sub lsi_checksum {
  my $str    = shift;
  my $chksum = 0;
  foreach my $chr (unpack("C"x(length($str)), $str)) {
    $chksum = ($chksum + $chr) & 0xff;
  }
  $chksum = (1 + ($chksum ^ 0xff)) & 0xff;
  return $chksum;
}

my $LsiSentence = undef;

INIT {
  $LsiSentence = new Parse::Binary::FixedFormat  [
   qw( Header:v Cmd:v Cnt:v ID:C Chksum:C ) ];

  assert( UNIVERSAL::isa( $LsiSentence, 'Parse::Binary::FixedFormat' ) ),
    if DEBUG;

}

sub lsi_query {
  my ($port, $cmd, $send_data, $id, $debug, $timeout) = @_;

  $send_data = "", unless (defined $send_data);
  my $size   = length($send_data);

  $id      ||= 0;

  assert( ($cmd & 0x80) == 0 ),          if DEBUG;
  assert( $size <= 0xffff ),             if DEBUG;
  assert( ($id >= 0) && ($id <= 0xff) ), if DEBUG;

  my $hdr = {
	     Header => LSI_PREAMBLE,         # magic number 
             Cmd    => $cmd,                 # command
             Cnt    => $size,                # size of extra data
             ID     => $id,                  # Reserved field (always 0)
             Chksum => 0,
            };

  my $xmit = $LsiSentence->format( $hdr );   # build structure w/out checksum
  $hdr->{Chksum} = lsi_checksum( $xmit );    # update checksum and rebuild

  $xmit = $LsiSentence->format( $hdr ) . $send_data;

  if ($debug) {
    print STDERR _str2hex($xmit), "\n";
  }

  $port->write( $xmit );

  $timeout ||= DEFAULT_TIMEOUT;

  my $end_time = $timeout + time;            # when to timeout

  my $rcvd     = "";                         # receive buffer
  my $expected = 8;                          # bytes expected
  my $ack      = 0;                          # was an ack received?

  do {

    # My GlobalMap 100 seems to return data in 8-byte blocks. So we
    # have to input in drips and drabs.

    my $in = $port->input;

    if ($in ne "") {

      if ($debug) {
	print STDERR _str2hex($in), "\n";
      }

      if ($ack) {
	$expected -= length($in);
	$rcvd .= $in;
      } else {

	my $hdr = $LsiSentence->unformat( $in );

	if ( ($hdr->{Header} == LSI_PREAMBLE) &&
	     ($hdr->{Cmd} == ($cmd | 0x80)) ) {

	  if ($hdr->{Chksum} != lsi_checksum( substr($in, 0, -1) )) {
	    warn "response header checksum mismatch"; }

	  $expected = 1+$hdr->{Cnt}, if ($hdr->{Cnt});
	  $ack      = 1;
	  $rcvd    .= $in;
	} else {
	  warn "ignoring unrecognized response";
	}
      }
    }

    assert( $expected >= 0 ), if DEBUG;

  } while ($expected && (time < $end_time));

  if (length($rcvd) > 8) {
    my $chk_calc = lsi_checksum( substr($rcvd, 8, -1) );
    my $chk_rcvd = unpack( "C", substr($rcvd, -1) );
    if ($chk_calc != $chk_rcvd) {
      warn "data checksum mismatch";
    }
  }

  # if there is a time out, return undef; should we use a timeout flag
  # instead?

  if (time >= $end_time) {
    warn "timed out";
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
  Parse::Binary::FixedFormat
  Win32::SerialPort or Device::SerialPort

This module should work with Perl 5.6.x. It has been tested on Perl 5.8.2.

=head2 Installation

Installation is standard:

  perl Makefile.PL
  make
  make test
  make install

For Windows playforms, you may need to use C<nmake> instead.

=head1 SYNOPSIS

  use Win32::SerialPort;                # or Device::SerialPort (?)
  use GPS::Lowrance::LSI 'lsi_query';

  my $port = new Win32::SerialPort( 'com1' );

  my $data = lsi_query( $port, 0x30e, "", 0 );

=head1 DESCRIPTION

This module provides I<very> low-level support for the LSI (Lowrance
Serial Interface) 100 protocol used to communicate with Lowrance GPS
devices.

(Higher-level functions and wrappers for specific commands will be
provided in other modules.  This module is intentionally kept simple.)

=head2 Functions

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

=item lsi_checksum

  $chksum = lsi_checksum( $data );

Used to calculate 8-bit checksums in data.  This is generally an
internal routine, but since L</lsi_query> makes raw data available,
this is useful.

=back

=head1 EXAMPLES

An example of using this module to query product information is below:

  use GPS::Lowrance::LSI;
  use Parse::Binary::FixedFormat;

  my $inforec = new Parse::Binary::FixedFormat [
   qw( Reserved:C ProductID:v ProtocolVersion:v
       ScreenType:v ScreenWidth:v ScreenHeight:v
       NumOfWaypoints:v NumOfIcons:v NumOfRoutes:v
       NumOfWaypointsPerRoute:v
       NumOfPlotTrails:C NumOfIconSym:C ScreenRotateAngle:C
       RunTime:V Checksum:C )];

  # We assume that $port is already initialized to a serial port using
  # Win32::SerialPort or Device::SerialPort

  my $buff = lsi_query($port, 0x30e);

  my $info = $inforec->unformat( substr($buff, 8) );

=head1 TODO

A separate C<GPS::Lowrance> module will be written that will function
as a wrapper for the various commands.

Add more test cases, where appropriate.

=head1 CAVEATS

This is an early release of the module, so likely there are bugs.

This module has not (yet) been tested with Device::SerialPort.
Feedback on this would be appreciated.

Win32::SerialPort unfortunately has not been updated since 1999.

=head1 SEE ALSO

C<Win32::SerialPort> and C<Device::SerialPort> explain how to create
serial port connection objects for use with this module.

C<Parse::Binary::FixedFormat> is useful for flexible parsing binary
structures used by this protocol.

The Lowrance Serial Interface (LSI) Protocol is described in a document
available on the L<Lowrance|http://www.lowrance.com> web site at
L<http://www.lowrance.com/Software/CyberCom_LSI100/cybercom_lsi100.asp>.

=head1 AUTHOR

Robert Rothenberg <rrwo at cpan.org>

=head2 Suggestions and Bug Reporting

Feedback is always welcome.  Please report any bugs using the CPAN
Request Tracker at L<http://rt.cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Robert Rothenberg <rrwo at cpan.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
