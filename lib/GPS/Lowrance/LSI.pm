package GPS::Lowrance::LSI;

use 5.006;
use strict;
use warnings;

require Exporter;
use AutoLoader qw(AUTOLOAD);

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
  lsi_query lsi_checksum verify_checksum
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
  lsi_query
);

our $VERSION = '0.20';

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
use constant DEFAULT_TIMEOUT => 5;

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

# verify the checksum at the end of a data structure

sub verify_checksum {
  my $str    = shift;
  my $chksum = unpack("C", substr($str, -1));
  return ( $chksum == lsi_checksum( substr($str, 0, -1) ) );
}

my $LsiSentence = undef;

INIT {
  $LsiSentence = new Parse::Binary::FixedFormat  [
   qw( Header:v Cmd:v Cnt:v ID:C Chksum:C ) ];

  assert( UNIVERSAL::isa( $LsiSentence, 'Parse::Binary::FixedFormat' ) ),
    if DEBUG;

}

sub lsi_query {
  my ($port, $cmd, $send_data, $id, $debug, $timeout, $retry) = @_;

  $send_data = "", unless (defined $send_data);
  my $size   = length($send_data);

  $id      ||= 0;
  $timeout ||= DEFAULT_TIMEOUT;              # set to default timeout
  $retry   ||= 0;                            # retry defaults to 0

  assert( ($cmd & 0x80) == 0 ),          if DEBUG;
  assert( $size <= 0xffff ),             if DEBUG;
  assert( ($id >= 0) && ($id <= 0xff) ), if DEBUG;
  assert( $timeout >= 0 ),               if DEBUG;
  assert( $retry >= -1 ),                if DEBUG;

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

  my $end_time     = $timeout + time;        # when to timeout
  my $no_timed_out = 1;                      # not timed out?

  my $bad_chksum   = 0;                      # was checksum bad?

  my $rcvd         = "";	             # receive buffer

  do {
    if ($debug) {
      print STDERR "XMIT => ", _str2hex($xmit), "\n"; }

    $port->write( $xmit );

    my $expected     = 8;	             # bytes expected (header size)
    my $ack          = 0;	             # was an ack received?

    do {

      # My GlobalMap 100 seems to return data in 8-byte blocks. So we
      # have to input in drips and drabs.

      my $in = $port->input;

      if ($in ne "") {

	if ($debug) {
	  print STDERR "RCVD => ", _str2hex($in), "\n"; }

	if ($ack) {
	  $expected -= length($in);
	  $rcvd .= $in;
	} else {

	  my $hdr = $LsiSentence->unformat( $in );

	  if ( ($hdr->{Header} == LSI_PREAMBLE) &&
	       ($hdr->{Cmd}    == ($cmd | 0x80)) ) {

	    unless (verify_checksum( $in )) {
	      warn "response header checksum mismatch";
	      $bad_chksum = 1;
	    }

	    $expected = 1+$hdr->{Cnt}, if ($hdr->{Cnt});
	    $ack      = 1;
	    $rcvd    .= $in;
	  } else {
	    warn "ignoring unrecognized response";
	  }
	}
      }

      assert( $expected >= 0 ), if DEBUG;

      $no_timed_out = (time < $end_time);

    } while ($expected && $no_timed_out);

    if (length($rcvd) > 8) {
      unless (verify_checksum( substr($rcvd, 8) )) {
	warn "data checksum mismatch";	
	$bad_chksum = 1;
      }
    }
    if ($retry<0) { $bad_chksum = 0; } # ignore bad checksum
  } while ($retry-- && $bad_chksum);

  if ($bad_chksum) {
    return;
  }

  unless ($no_timed_out) {
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
Serial Interface) 100 protocol used to communicate with Lowrance and
Eagle GPS devices.

(Higher-level functions and wrappers for specific commands will be
provided in other modules.  This module is intentionally kept simple.)

=head2 Functions

=over

=item lsi_query

  $data_out = lsi_query( $port, $cmd, $data_in, $id, $debug,
			 $timeout, $retry );

This method submits an LSI query sentence (with the command and input
data) to a GPS connected to the device specified by serial port at
C<$port>.  (See the LSI specification on the Lowrance or Eagle web
sites for the specific command codes.)

It then waits C<$timeout> seconds (defaults to 5) for a response.  If
there is no response, it returns C<undef>.

Otherwise, it verifies that the response is well-formed and returns
the data.  If C<$retry> is greater than zero, then it will retry the
query C<$retry> times if there is a bad checksum or if there is a
timeout.  (If the checksum keeps failing or responses time out, it
will return C<undef>.)

A value of C<-1> for C<$retry> causes bad checksums to be ignored.

The C<$id> value is "reserved" and should be set to 0.

The first 8-bytes of the returned data is the response header.

The format of the rest of the data depends on the command.

If C<$debug> is true, then debugging information is shown.

=item verify_checksum

  if (verify_checksum( $data )) { ... }

Used to verify the checksum in the data.  The last byte of data
returned is the checksum of the data.

Note that L</lsi_query> returns the initial 8-byte acknowledgement
header along with any data.  So to verify data returned by that
function:

  if (verify_checksum( substr( $data, 8 ) )) { ... }

The query function already verifies data returned by the query. So
there is usually no need to re-check the data.

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

  $InfoRec = new Parse::Binary::FixedFormat [
   qw( Reserved:C ProductID:v ProtocolVersion:v
       ScreenType:v ScreenWidth:v ScreenHeight:v
       NumOfWaypoints:v NumOfIcons:v NumOfRoutes:v
       NumOfWaypointsPerRoute:v
       NumOfPlotTrails:C NumOfIconSym:C ScreenRotateAngle:C
       RunTime:V Checksum:C )];

  # We assume that $Port is already initialized to a serial port using
  # Win32::SerialPort or Device::SerialPort

  $Buff = lsi_query($Port, 0x30e);

  $Info = $InfoRec->unformat( substr($Buff, 8) );

A working implementation of this example can be found in the file
C<eg/getinfo.pl> included with this distrubtion.

=head1 TODO

A separate C<GPS::Lowrance> module will be written that will function
as a wrapper for the various commands.

Add more test cases, where appropriate.

=head1 CAVEATS

This is an early release of the module, so likely there are bugs.

This module has not (yet) been tested with Device::SerialPort.
Feedback on this would be appreciated.

C<Win32::SerialPort> unfortunately has not been updated since 1999.

=head1 SEE ALSO

C<Win32::SerialPort> and C<Device::SerialPort> explain how to create
serial port connection objects for use with this module.

C<Parse::Binary::FixedFormat> is useful for flexible parsing binary
structures used by this protocol.

The Lowrance Serial Interface (LSI) Protocol is described in a
document available on the L<Lowrance|http://www.lowrance.com> or
L<Eagle|http://www.eaglegps.com> web sites, such as at
L<http://www.lowrance.com/Software/CyberCom_LSI100/cybercom_lsi100.asp>
or L<http://www.eaglegps.com/Downloads/Software/CyberCom/default.htm>.
(Note that the specific URLs are subject to change.)

=head2 Other Implementations

There is a Python module by Gene Cash for handling the LSI 100 protocol at
L<http://home.cfl.rr.com/genecash/eagle.html>.

=head2 Other GPS Vendors

There are other Perl modules to communicate with different GPS brands:

  GPS::Garmin
  GPS::Magellen

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
