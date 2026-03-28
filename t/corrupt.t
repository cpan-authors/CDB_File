use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;

use Test::More;
use CDB_File;
use File::Temp;

# Helper: create a valid CDB file with known content, return its binary data
sub make_valid_cdb {
    my ( $db, $db_tmp ) = get_db_file_pair(1);
    my $db_file  = $db->filename;
    my $tmp_file = $db_tmp->filename;

    my %data = ( hello => 'world', foo => 'bar', key => 'value' );
    CDB_File::create( %data, $db_file, $tmp_file )
        or die "Failed to create test CDB: $!";

    open my $fh, '<:raw', $db_file or die "Can't read $db_file: $!";
    my $bytes = do { local $/; <$fh> };
    close $fh;

    return $bytes;
}

# Helper: write binary data to a temp file and return the filename
sub write_corrupt_file {
    my ($data) = @_;
    my $tmp = File::Temp->new( UNLINK => 1, SUFFIX => '.cdb' );
    binmode $tmp;
    print $tmp $data;
    close $tmp;
    return $tmp;    # keep object alive for UNLINK
}

my $valid_cdb = make_valid_cdb();

# ---------- Truncated files ----------

# 1. File truncated to 0 bytes (empty)
{
    my $fobj = write_corrupt_file('');
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie to empty file succeeds (deferred failure)" );

    eval { my $v = $h{'hello'} };
    like( $@, qr/Read of CDB_File failed/,
        "FETCH on empty file croaks" );
    untie %h if tied %h;
}

# 2. File truncated to 100 bytes (partial header)
{
    my $fobj = write_corrupt_file( substr( $valid_cdb, 0, 100 ) );
    my %h;
    my $tied = tie %h, 'CDB_File', $fobj->filename;

    if ($tied) {
        # FETCH should fail: hash table lookup reads from header region
        eval { my $v = $h{'hello'} };
        like( $@, qr/Read of CDB_File failed/,
            "FETCH on truncated header croaks" );
        undef $tied;
        untie %h if tied %h;
    }
    else {
        pass("Tie to truncated header file correctly failed");
    }
}

# 3. File with complete header but truncated data section
{
    # Keep just the 2048-byte header, chop all data
    my $fobj = write_corrupt_file( substr( $valid_cdb, 0, 2048 ) );
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie to header-only file succeeds" );

    # FETCH should fail when trying to read key/value data
    eval { my $v = $h{'hello'} };
    like( $@, qr/Read of CDB_File failed/,
        "FETCH on header-only file croaks" );
    untie %h if tied %h;
}

# 4. File truncated mid-record (header + partial data)
{
    # Keep header plus only 4 bytes of data (partial record header)
    my $fobj = write_corrupt_file( substr( $valid_cdb, 0, 2052 ) );
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie to mid-record truncated file succeeds" );

    eval { my $v = $h{'hello'} };
    like( $@, qr/Read of CDB_File failed/,
        "FETCH on mid-record truncated file croaks" );
    untie %h if tied %h;
}

# ---------- Corrupted header pointers ----------

# 5. ALL hash table pointers beyond EOF
{
    my $corrupt = $valid_cdb;

    # Corrupt ALL 256 hash table entries: set position far past EOF
    my $bad_pos = pack( 'V', 0xFFFFFF00 );    # position way beyond file
    for my $i ( 0 .. 255 ) {
        substr( $corrupt, $i * 8, 4, $bad_pos );
    }

    my $fobj = write_corrupt_file($corrupt);
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie to file with corrupt hash pointers succeeds" );

    # Any key lookup should fail since all hash pointers are corrupt
    eval { my $v = $h{'hello'} };
    like( $@, qr/Read of CDB_File failed/,
        "Corrupt hash pointers trigger read error on FETCH" );
    untie %h if tied %h;
}

# 6. ALL hash tables with impossibly large slot counts
{
    my $corrupt = $valid_cdb;

    # Set the slot count of ALL 256 hash entries to a huge number
    my $bad_slots = pack( 'V', 0x7FFFFFFF );
    for my $i ( 0 .. 255 ) {
        substr( $corrupt, $i * 8 + 4, 4, $bad_slots );
    }

    my $fobj = write_corrupt_file($corrupt);
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie to file with huge slot counts succeeds" );

    eval { my $v = $h{'hello'} };
    like( $@, qr/Read of CDB_File failed/,
        "Huge slot count triggers read error" );
    untie %h if tied %h;
}

# ---------- Corrupted record lengths ----------

# 7. Key length set to enormous value in a record
{
    my $corrupt = $valid_cdb;

    # Find the first data record (at offset 2048) and corrupt the key length
    my $bad_klen = pack( 'V', 0x7FFFFFFF );    # ~2GB key
    substr( $corrupt, 2048, 4, $bad_klen );

    my $fobj = write_corrupt_file($corrupt);
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie to file with corrupt key length succeeds" );

    # Iteration (FIRSTKEY) reads key length from the data section
    eval { my @k = keys %h };
    like( $@, qr/Read of CDB_File failed|Out of memory/,
        "Corrupt key length triggers error on iteration" );
    untie %h if tied %h;
}

# 8. Data length set to enormous value
{
    my $corrupt = $valid_cdb;

    # Corrupt the data length at offset 2052 (second U32 in first record)
    my $bad_dlen = pack( 'V', 0x7FFFFFFF );
    substr( $corrupt, 2052, 4, $bad_dlen );

    my $fobj = write_corrupt_file($corrupt);
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie to file with corrupt data length succeeds" );

    # Iteration should detect the corrupt length when advancing
    eval { my @k = each %h; my @k2 = each %h };
    like( $@, qr/Read of CDB_File failed|Out of memory/,
        "Corrupt data length triggers error on iteration advance" );
    untie %h if tied %h;
}

# ---------- Iteration on corrupt files ----------

# 9. FIRSTKEY/NEXTKEY on truncated file
{
    # File has header but data ends too early for iter_key to read
    my $fobj = write_corrupt_file( substr( $valid_cdb, 0, 2050 ) );
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie for iteration test succeeds" );

    eval { my @k = keys %h };
    like( $@, qr/Read of CDB_File failed/,
        "Iteration on truncated data croaks" );
    untie %h if tied %h;
}

# 10. The header end pointer (first 4 bytes at offset 0) points to
#     a position before 2048, which would make curpos >= end immediately
{
    my $corrupt = $valid_cdb;

    # Set the first hash table pointer (slot 0) to position 1024
    # This affects iter_start which reads bytes 0-3 to set 'end'
    # Actually iter_start reads cdb_read(c, buf, 4, 0) - the first 4 bytes
    # In a valid CDB, bytes 0-3 are the position of hash table 0
    # If this is < 2048, iteration sees curpos (2048) >= end, so no records
    my $small_end = pack( 'V', 1024 );
    substr( $corrupt, 0, 4, $small_end );

    my $fobj = write_corrupt_file($corrupt);
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Tie for small-end-pointer test succeeds" );

    # This should either return no keys or croak, but not crash
    my @k;
    eval { @k = keys %h };
    ok( !$@ || $@ =~ /Read of CDB_File failed/,
        "Small end pointer handled gracefully (got " . scalar(@k) . " keys)" );
    untie %h if tied %h;
}

# ---------- multi_get on corrupt file ----------

# 11. multi_get with data pointing past EOF
{
    my $corrupt = $valid_cdb;

    # Corrupt all data positions in hash tables by adding a huge offset
    # This is harder to target, so instead truncate the file just past header+hash tables
    # but keep the hash tables intact so lookup "succeeds" but data read fails
    # Simpler: use a valid file but truncate just enough to break data reads
    my $trunc_len = length($valid_cdb) - 5;    # chop last 5 bytes
    my $fobj = write_corrupt_file( substr( $valid_cdb, 0, $trunc_len ) );
    my %h;
    my $t = tie %h, 'CDB_File', $fobj->filename;

    if ($t) {
        # Some keys may still work, others may fail depending on position
        my $any_error = 0;
        for my $key (qw(hello foo key nonexistent)) {
            eval {
                my $v = $t->multi_get($key);
            };
            $any_error = 1 if $@;
        }
        # At minimum, the slightly truncated file should not crash
        pass("multi_get on slightly truncated file did not crash");
        undef $t;
        untie %h;
    }
    else {
        pass("Tie to slightly truncated file correctly failed");
    }
}

# ---------- Random garbage file ----------

# 12. File of random bytes
{
    # 4KB of pseudo-random data (deterministic seed for reproducibility)
    srand(42);
    my $garbage = join '', map { chr( int( rand(256) ) ) } 1 .. 4096;

    my $fobj = write_corrupt_file($garbage);
    my %h;
    my $tied = tie %h, 'CDB_File', $fobj->filename;

    if ($tied) {
        # Try various operations - they should error, not crash
        eval { my $v = $h{'test'} };
        my $err1 = $@;

        eval { my @k = keys %h };
        my $err2 = $@;

        eval { exists $h{'test'} };
        my $err3 = $@;

        ok( 1, "Operations on garbage file did not crash" );
        undef $tied;
        untie %h if tied %h;
    }
    else {
        pass("Tie to garbage file correctly failed");
    }
}

# ---------- Verify valid file still works after all corruption tests ----------

# 13. Sanity check: the valid CDB we've been corrupting still works
{
    my $fobj = write_corrupt_file($valid_cdb);
    my %h;
    ok( ( tie %h, 'CDB_File', $fobj->filename ),
        "Sanity: valid CDB still ties" );
    is( $h{'hello'}, 'world', "Sanity: valid CDB returns correct value" );
    untie %h;
}

done_testing();
