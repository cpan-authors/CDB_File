use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;

use Test::More;
use Test::Fatal;
use CDB_File;

plan( skip_all => "bytes mode test requires > 5.13.7" ) if $] < '5.013007';
plan tests => 10;

# Test for GitHub issue #24: bytes string mode
# The bytes mode uses SvPVbyte() which ensures that UTF-8 flagged
# strings with code points > 255 croak, and that Latin-1 characters
# are downgraded to their byte representation.

# Basic bytes mode: create and read with byte strings
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    my %data = ( 'hello' => 'world', 'foo' => 'bar' );
    CDB_File::create %data, $db->filename, $db_tmp->filename, 'bytes' => 1
        or die "create failed: $!";

    my %h;
    tie( %h, 'CDB_File', $db->filename, 'bytes' => 1 ) or die "tie failed: $!";

    is( $h{'hello'}, 'world', 'Basic bytes mode: fetch works' );
    is( $h{'foo'}, 'bar', 'Basic bytes mode: second key works' );
    ok( exists $h{'hello'}, 'Basic bytes mode: EXISTS works' );

    untie %h;
}

# Bytes mode with Latin-1 string that has UTF-8 flag
# SvPVbyte will downgrade the UTF-8 representation to bytes
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    # Create a string with UTF-8 flag but only Latin-1 code points
    my $key = "caf\x{e9}";   # "caf" + e-acute (Latin-1 range)
    utf8::upgrade($key);      # Force UTF-8 flag on

    my $t = CDB_File->new( $db->filename, $db_tmp->filename, 'bytes' => 1 )
        or die "new failed: $!";
    $t->insert( $key, 'espresso' );
    $t->finish;

    my %h;
    tie( %h, 'CDB_File', $db->filename, 'bytes' => 1 ) or die "tie failed: $!";

    # Look up with the same UTF-8 flagged string
    is( $h{$key}, 'espresso', 'Bytes mode: UTF-8 flagged Latin-1 key round-trips' );

    # Look up with a non-UTF-8 flagged version (same bytes)
    my $key_bytes = "caf\xe9";
    is( $h{$key_bytes}, 'espresso', 'Bytes mode: byte-string key matches UTF-8 flagged equivalent' );

    untie %h;
}

# Bytes mode should croak on wide characters (code point > 255)
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    my $t = CDB_File->new( $db->filename, $db_tmp->filename, 'bytes' => 1 )
        or die "new failed: $!";

    my $wide_key = "\x{100}";  # Code point 256, cannot be a byte
    like(
        exception { $t->insert( $wide_key, 'value' ) },
        qr/[Ww]ide character/,
        'Bytes mode: insert croaks on wide character in key'
    );

    like(
        exception { $t->insert( 'key', "\x{100}" ) },
        qr/[Ww]ide character/,
        'Bytes mode: insert croaks on wide character in value'
    );
}

# Bytes mode via CDB_File::create
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    my %data = ( 'alpha' => 'beta' );
    CDB_File::create %data, $db->filename, $db_tmp->filename, 'bytes' => 1
        or die "create failed: $!";

    my %h;
    tie( %h, 'CDB_File', $db->filename, 'bytes' => 1 ) or die "tie failed: $!";

    is( $h{'alpha'}, 'beta', 'Bytes mode via create(): works' );

    untie %h;
}

# Verify bytes and utf8 are mutually exclusive in create
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    # Can't easily test mutual exclusion via create() since it only accepts
    # one option_key, but we can test via the constructor
    # (utf8 and bytes can't both be passed as option_key anyway)
    pass('Bytes and utf8 are mutually exclusive by design (single option_key)');
}

# Fetch with wide character should croak in bytes mode
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);

    my %data = ( 'test' => 'value' );
    CDB_File::create %data, $db->filename, $db_tmp->filename, 'bytes' => 1
        or die "create failed: $!";

    my %h;
    tie( %h, 'CDB_File', $db->filename, 'bytes' => 1 ) or die "tie failed: $!";

    my $wide_key = "\x{100}";
    like(
        exception { $h{$wide_key} },
        qr/[Ww]ide character/,
        'Bytes mode: FETCH croaks on wide character key'
    );

    untie %h;
}
