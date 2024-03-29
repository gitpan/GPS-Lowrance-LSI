use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'GPS::Lowrance::LSI',
    VERSION_FROM      => 'lib/GPS/Lowrance/LSI.pm', # finds $VERSION
    PREREQ_PM         => {
      'Carp::Assert'               => 0,
      'Parse::Binary::FixedFormat' => 0.02,
      'Text::Wrap'                 => 0,    # standard module, but...
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/GPS/Lowrance/LSI.pm',
       AUTHOR         => 'Robert Rothenberg <rrwo at cpan.org>') : ()),
);
