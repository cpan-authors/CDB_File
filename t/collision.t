use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;    # Local helper routines used by the test suite.

use Test::More tests => 8;
use CDB_File;

my @keys = qw/Q5M QCX QK3 TPM QN5/;

my ( $db, $db_tmp ) = get_db_file_pair(1);

my $c = CDB_File->new( $db->filename, $db_tmp->filename );
isa_ok( $c, 'CDB_File::Maker' );

for my $k (@keys) {
	$c->insert($k, 1);
};
is( $c->finish, 1, "Finish writes out" );

my %h;
tie( %h, "CDB_File", $db->filename );
isa_ok( tied(%h), 'CDB_File' );

for my $k (sort @keys) {
   is( $h{$k}, 1, "$k matches" );
}

exit;
