#!perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;    # Local helper routines used by the test suite.

use Test::More;

plan( skip_all => "utf8 macro support requires > 5.13.7" ) if $] < '5.013007';
plan tests => 3;

use CDB_File;

my ( $db, $db_tmp ) = get_db_file_pair(1);

my %data = ( nonutf8 => "\xff\xfe" );

CDB_File::create( %data, $db->filename, $db_tmp->filename, string_mode => 'latin1' );

{
    my %h;
    tie %h, "CDB_File", $db->filename, string_mode => 'utf8';

    eval { my $foo = $h{'nonutf8'} };
    my $err = $@;

    like $err, qr<utf-?8>i, '“utf8” mode rejects invalid UTF-8.';
}

{
    my %h;
    tie %h, "CDB_File", $db->filename, string_mode => 'utf8_naive';

    my $foo;
    eval { $foo = $h{'nonutf8'} };
    my $err = $@;

    is( $err, q<>, '“utf8_naive” mode accepts invalid UTF-8.' );
    ok( !utf8::valid($foo), '.. and SV is invalid' );
}
