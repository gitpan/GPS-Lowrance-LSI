
# Usage: perl getinfo.pl device baudrate
# e.g.   perl getinfo.pl com1 9600

use strict;
use warnings;

my ($OS_win, $SerialModule);

BEGIN{
  $OS_win = ($^O eq "MSWin32") ? 1 : 0;

  $SerialModule = ($OS_win)? "Win32::SerialPort" : "Device::SerialPort";

  eval "use $SerialModule;";
}

use GPS::Lowrance::LSI 0.20 'lsi_query';

my $PortName = shift || 'com1';
my $BaudRate = shift || 9600;

my $Quiet    = 0;

my $Debug    = 1;
my $Timeout  = 5;
my $RetryCnt = 3;


my $PortObj = new $SerialModule( $PortName, $Quiet )
  or die "Unable to open port $PortName";

$PortObj->baudrate($BaudRate);
$PortObj->parity("none");
$PortObj->databits(8);
$PortObj->stopbits(1);

$PortObj->binary('T');

$PortObj->write_settings;

unless ($PortObj) { die "Unable to configure device at $PortName"; }

use Data::Dumper;
use Parse::Binary::FixedFormat;

my $InfoRec = new Parse::Binary::FixedFormat [
 qw( Reserved:C ProductID:v ProtocolVersion:v
     ScreenType:v ScreenWidth:v ScreenHeight:v
     NumOfWaypoints:v NumOfIcons:v NumOfRoutes:v NumOfWaypointsPerRoute:v
     NumOfPlotTrails:C NumOfIconSym:C ScreenRotateAngle:C
     RunTime:V Checksum:C )];

my $Buff = lsi_query($PortObj, 0x30e, "", 0, $Debug, $Timeout, $RetryCnt);

my $Info = $InfoRec->unformat( substr($Buff, 8) );

print Data::Dumper->Dump([$Info],['Info']);

$PortObj->close;

exit 0;

__END__
