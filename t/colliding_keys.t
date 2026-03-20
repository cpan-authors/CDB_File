use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;

use Test::More tests => 8;
use CDB_File;

# Test for GitHub issue #26: Cannot read colliding keys
# R8Y and SYY have the same djb2 hash value.
# Prior to the fix, looking up one of the colliding keys could return
# undef because cdb_findnext() stopped probing on a key-length match
# with different content.

{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    my $t = CDB_File->new( $db->filename, $db_tmp->filename ) or die "new failed: $!";
    $t->insert( 'R8Y', 'val_r8y' );
    $t->insert( 'SYY', 'val_syy' );
    $t->finish;

    my %h;
    tie( %h, 'CDB_File', $db->filename ) or die "tie failed: $!";

    is( $h{'R8Y'}, 'val_r8y', 'Fetch first colliding key (R8Y)' );
    is( $h{'SYY'}, 'val_syy', 'Fetch second colliding key (SYY)' );

    ok( exists $h{'R8Y'}, 'EXISTS for first colliding key' );
    ok( exists $h{'SYY'}, 'EXISTS for second colliding key' );

    untie %h;
}

# Second reproducer from the issue: sorted keys iteration + fetch
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    my %data = map { $_ => 1 } qw/Q5M QCX QK3 TPM QN5/;
    CDB_File::create %data, $db->filename, $db_tmp->filename
        or die "create failed: $!";

    my %h;
    tie( %h, 'CDB_File', $db->filename ) or die "tie failed: $!";

    my $all_defined = 1;
    for my $key ( sort keys %h ) {
        if ( !defined $h{$key} ) {
            $all_defined = 0;
            diag("Key '$key' returned undef after sorted iteration");
        }
    }
    ok( $all_defined, 'All keys defined after sorted keys iteration + fetch' );

    untie %h;
}

# Test with multi_get on colliding keys
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    my $t = CDB_File->new( $db->filename, $db_tmp->filename ) or die "new failed: $!";
    $t->insert( 'R8Y', 'a' );
    $t->insert( 'SYY', 'b' );
    $t->insert( 'R8Y', 'c' );
    $t->finish;

    my %h;
    my $cdb = tie( %h, 'CDB_File', $db->filename ) or die "tie failed: $!";

    my $r8y_vals = $cdb->multi_get('R8Y');
    is_deeply( $r8y_vals, [ 'a', 'c' ], 'multi_get returns all values for colliding key R8Y' );

    my $syy_vals = $cdb->multi_get('SYY');
    is_deeply( $syy_vals, ['b'], 'multi_get returns value for colliding key SYY' );

    is( $h{'SYY'}, 'b', 'FETCH works for SYY with repeated R8Y entries' );

    undef $cdb;
    untie %h;
}
