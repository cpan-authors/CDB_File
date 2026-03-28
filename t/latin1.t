#!perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;    # Local helper routines used by the test suite.

use Test::More;

plan tests => 6;

use CDB_File;

my $good = join( q<>, map { chr } 0 .. 255 );

my %a = qw(one Hello two Goodbye);
$a{'good'} = $good;

$a{'good2'} = $good;
utf8::upgrade($a{'good2'});

{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    eval { CDB_File::create( %a, $db->filename, $db_tmp->filename, string_mode => 'latin1' ) or die "Failed to create cdb: $!" };
    is( "$@", '', "Create cdb OK when contents are all bytes" );
}

my $bad = chr( 256 );
$a{'bad'} = $bad;

{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    eval { CDB_File::create( %a, $db->filename, $db_tmp->filename, string_mode => 'latin1' ) or die "Failed to create cdb: $!" };
    my $err = $@;
    isnt( $err, q<>, 'An error happens if we try to store a >255 code point.' );
}

{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    CDB_File::create( my %a, $db->filename, $db_tmp->filename );

    my %h;

    # Test that good file works.
    ok(
        tie( %h, "CDB_File", $db->filename, string_mode => 'latin1' ),
        'tie() succeeds',
    );

    eval { $h{'bad'} = $bad };
    my $err = $@;

    isnt( $err, q<>, 'An error happens if we try to store a >255 code point in a tied hash.' );

    eval { my $foo = $h{$bad} };
    $err = $@;

    isnt( $err, q<>, 'An error happens if we try to look up a value whose key contains a >255 code point.' );

    eval { exists $h{$bad} };
    $err = $@;

    isnt( $err, q<>, 'An error happens if we try to existence-check a key contains a >255 code point.' );
}

1;
