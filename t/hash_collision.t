use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;

use Test::More tests => 8;
use CDB_File;

# Test for GitHub issue #26: keys with the same djb2 hash could not be
# read back via the tied hash interface.  The bug was introduced in v1.04
# when the match() return value handling in cdb_findnext() was inverted:
# a hash-collision mismatch (match returns 0) incorrectly caused "not found"
# instead of continuing to probe the next hash slot.

# R8Y and SYY have the same djb2 hash.
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);
    my $db_name  = $db->filename;
    my $tmp_name = $db_tmp->filename;

    my $t = CDB_File->new( $db_name, $tmp_name ) or die "CDB_File->new failed: $!";
    $t->insert( 'R8Y', 'val_R8Y' );
    $t->insert( 'SYY', 'val_SYY' );
    $t->finish;

    my %h;
    ok( tie( %h, 'CDB_File', $db_name ), "tie colliding-keys CDB" );
    is( $h{'R8Y'}, 'val_R8Y', "FETCH first colliding key" );
    is( $h{'SYY'}, 'val_SYY', "FETCH second colliding key (was undef before fix)" );
    ok( exists $h{'SYY'}, "EXISTS on second colliding key" );
    untie %h;
}

# Second reproducer from issue #26: sorted keys causing FETCH failures
# after iteration.
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);
    my $db_name  = $db->filename;
    my $tmp_name = $db_tmp->filename;

    my %data = map { $_ => 1 } qw/Q5M QCX QK3 TPM QN5/;
    CDB_File::create %data, $db_name, $tmp_name or die "create failed: $!";

    my %h;
    ok( tie( %h, 'CDB_File', $db_name ), "tie multi-key CDB" );

    my @sorted_keys = sort keys %h;
    my $all_defined = 1;
    for my $k (@sorted_keys) {
        unless ( defined $h{$k} ) {
            $all_defined = 0;
            diag("FETCH returned undef for key '$k' after sorted iteration");
        }
    }
    ok( $all_defined, "all keys defined after sorted-keys iteration" );

    # Also test multi_get on colliding keys
    untie %h;

    ok( tie( %h, 'CDB_File', $db_name ), "re-tie for multi_get test" );
    my $vals = ( tied %h )->multi_get('Q5M');
    is( scalar @$vals, 1, "multi_get returns correct count for non-duplicate key" );
    untie %h;
}
