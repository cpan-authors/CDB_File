#!perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;

use Test::More tests => 4;
use Test::Warnings;

use CDB_File;

# Test that fetching from a truncated/corrupted CDB file does not segfault.
# When using mmap, cdb_map_addr() returns NULL for out-of-bounds access.
# Before the fix, match() passed this NULL directly to cdb_key_eq(), causing
# a segfault.

{
    # Create a valid CDB file first, then truncate it to corrupt it.
    my ( $db_file, $tmp_file ) = get_db_file_pair(1);
    my $db_path  = $db_file->filename;
    my $tmp_path = $tmp_file->filename;

    my $cdb = CDB_File::new CDB_File( $db_path, $tmp_path ) or die "create: $!";
    $cdb->insert( "longkey" x 10, "value1" );
    $cdb->insert( "anotherkey",   "value2" );
    $cdb->finish or die "finish: $!";

    # Truncate the file to corrupt it — keep the header but chop the data area.
    # The 2048-byte header will be intact, so tie() and hash lookups will proceed,
    # but key data will be beyond the truncated file boundary.
    my $size = -s $db_path;
    truncate( $db_path, 2100 ) or die "truncate: $!";
    ok( -s $db_path < $size, "file was truncated to simulate corruption" );

    my %h;
    ok( tie( %h, "CDB_File", $db_path ), "tie to truncated file succeeds (header is intact)" );

    # This fetch should not segfault. On mmap systems, cdb_map_addr() will return
    # NULL for the out-of-bounds key data. The fix returns -1, which propagates
    # as a read error rather than a crash.
    eval { my $v = $h{"longkey" x 10}; };

    # We don't care whether it returned undef or croaked — just that we didn't segfault.
    pass("fetch on corrupted file did not segfault");

    untie %h;
    unlink $db_path;
}

note "exit";
exit;
